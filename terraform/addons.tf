# In-cluster add-ons, installed via Terraform now that OKE gives a stable,
# managed API endpoint. All depend (directly or transitively) on the node pool
# being up. See provider.tf for how the k8s/helm/kubectl providers authenticate.

# --- Longhorn (default StorageClass, replicas on node boot disks) ---

resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = var.longhorn_version
  namespace        = "longhorn-system"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    defaultSettings = {
      defaultReplicaCount = 2 # one per node = node-level HA
      defaultDataLocality = "best-effort"
    }
    persistence = {
      defaultClass             = true # make longhorn the default StorageClass
      defaultClassReplicaCount = 2
    }
  })]

  depends_on = [oci_containerengine_node_pool.workers]
}

# Demote OKE's built-in oci-bv so a class-less PVC can't silently provision a
# paid block volume (the 200GB free budget is fully used by the boot disks).
resource "kubernetes_annotations" "oci_bv_nondefault" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = true

  metadata {
    name = "oci-bv"
  }

  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  depends_on = [helm_release.longhorn]
}

# --- Gateway API CRDs (must precede Traefik's Gateway provider) ---

# Standard channel. Must match the Traefik version: Traefik v3.7's
# kubernetesGateway provider unconditionally watches TLSRoute + BackendTLSPolicy
# (both graduated to standard in Gateway API v1.5). With older CRDs those v1
# watches 404, the provider's caches never sync, and it silently reconciles
# nothing (Gateway/HTTPRoute stay "Waiting for controller"). Keep this version in
# lockstep with the Traefik chart.
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each          = data.kubectl_file_documents.gateway_api.manifests
  yaml_body         = each.value
  server_side_apply = true

  depends_on = [oci_containerengine_node_pool.workers]
}

# --- Traefik v3 (Gateway API provider) fronted by a flexible OCI NLB ---

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version != "" ? var.traefik_chart_version : null
  namespace        = "traefik"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    deployment = { replicas = 2 }
    # With required pod anti-affinity (one Traefik per host) and replicas == node
    # count, a surge pod can never schedule. Roll by freeing a host first instead.
    updateStrategy = {
      type          = "RollingUpdate"
      rollingUpdate = { maxSurge = 0, maxUnavailable = 1 }
    }
    providers = {
      kubernetesGateway = {
        enabled = true
      }
    }
    # We define our own GatewayClass + Gateway (below) for explicit 80/443 + TLS.
    gateway      = { enabled = false }
    gatewayClass = { enabled = false }
    service = {
      type = "LoadBalancer"

      spec = {
        externalTrafficPolicy = "Local"
      }

      annotations = {
        "oci.oraclecloud.com/load-balancer-type"                                  = "nlb"
        "oci-network-load-balancer.oraclecloud.com/is-preserve-source"            = "true"
        "oci-network-load-balancer.oraclecloud.com/security-list-management-mode" = "None"
      }
    }
    affinity = {
      podAntiAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = [{
          labelSelector = { matchLabels = { "app.kubernetes.io/name" = "traefik" } }
          topologyKey   = "kubernetes.io/hostname"
        }]
      }
    }
  })]

  depends_on = [kubectl_manifest.gateway_api_crds]
}

resource "kubectl_manifest" "gateway_class" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata   = { name = "traefik" }
    spec       = { controllerName = "traefik.io/gateway-controller" }
  })

  depends_on = [helm_release.traefik]
}

# Listener ports must equal Traefik's entryPoint ports, not the public ports:
# the kubernetesGateway provider matches listeners to entryPoints by port number.
# The chart's default entryPoints are web=8000 / websecure=8443, and its Service
# already maps public 80->8000 and 443->8443 (exposedPort). Using 8000/8443 here
# avoids binding privileged ports in the (non-root, no-NET_BIND_SERVICE) pod.
resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata   = { name = "main", namespace = "traefik" }
    spec = {
      gatewayClassName = "traefik"
      listeners = [
        {
          name          = "web"
          protocol      = "HTTP"
          port          = 8000
          allowedRoutes = { namespaces = { from = "All" } }
        },
        {
          name     = "websecure"
          protocol = "HTTPS"
          port     = 8443
          tls = {
            mode            = "Terminate"
            certificateRefs = [{ kind = "Secret", name = "wildcard-tls" }]
          }
          allowedRoutes = { namespaces = { from = "All" } }
        },
      ]
    }
  })

  depends_on = [kubectl_manifest.gateway_class]
}

# --- cert-manager + Let's Encrypt DNS-01 (Cloudflare) ---

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    crds = { enabled = true }
  })]

  depends_on = [oci_containerengine_node_pool.workers]
}

resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }

  data = {
    api-token = var.cloudflare_dns_api_token
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "cluster_issuers" {
  for_each = {
    staging = "https://acme-staging-v02.api.letsencrypt.org/directory"
    prod    = "https://acme-v02.api.letsencrypt.org/directory"
  }

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = "letsencrypt-${each.key}" }
    spec = {
      acme = {
        server              = each.value
        email               = var.acme_email
        privateKeySecretRef = { name = "letsencrypt-${each.key}-account" }
        solvers = [{
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = { name = "cloudflare-api-token", key = "api-token" }
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager, kubernetes_secret.cloudflare_api_token]
}

# Wildcard cert for every managed zone, terminated at the Gateway's websecure listener.
resource "kubectl_manifest" "wildcard_cert" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata   = { name = "wildcard", namespace = "traefik" }
    spec = {
      secretName = "wildcard-tls"
      issuerRef  = { name = var.default_cluster_issuer, kind = "ClusterIssuer" }
      dnsNames   = flatten([for z in keys(var.cloudflare_zones) : [z, "*.${z}"]])
    }
  })

  depends_on = [kubectl_manifest.cluster_issuers, helm_release.traefik]
}

# --- Traefik dashboard (IngressRoute on websecure, BasicAuth-protected) ---
# The dashboard API is already enabled in the chart (--api.dashboard=true) but
# unexposed. We surface it via a Traefik IngressRoute (the kubernetesGateway
# provider can't target the internal api@internal service). All gated on
# credentials being supplied, so the dashboard stays private until then.

resource "kubernetes_secret" "dashboard_auth" {
  count = var.traefik_dashboard_users != "" ? 1 : 0

  metadata {
    name      = "dashboard-auth"
    namespace = "traefik"
  }

  data = {
    users = var.traefik_dashboard_users
  }

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "dashboard_middleware" {
  count = var.traefik_dashboard_users != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata   = { name = "dashboard-auth", namespace = "traefik" }
    spec = {
      basicAuth = { secret = "dashboard-auth" }
    }
  })

  depends_on = [helm_release.traefik, kubernetes_secret.dashboard_auth]
}

resource "kubectl_manifest" "dashboard_ingressroute" {
  count = var.traefik_dashboard_users != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata   = { name = "dashboard", namespace = "traefik" }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind        = "Rule"
        match       = "Host(`${var.traefik_dashboard_host}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
        services    = [{ name = "api@internal", kind = "TraefikService" }]
        middlewares = [{ name = "dashboard-auth" }]
      }]
      tls = { secretName = "wildcard-tls" }
    }
  })

  depends_on = [
    helm_release.traefik,
    kubectl_manifest.dashboard_middleware,
    kubectl_manifest.wildcard_cert,
  ]
}

# --- Grafana Alloy (logs + metrics + traces → Grafana Cloud) ---
# Cluster telemetry collector. Runs as a DaemonSet (one pod per node) so it can
# tail each node's pod logs and scrape node-local kubelet/cAdvisor. Endpoints +
# the write token are injected as env vars; the .alloy config reads them via
# sys.env(). Whole stack gated on the token so nothing deploys without creds.

resource "kubernetes_namespace" "alloy" {
  count = var.grafana_cloud_token != "" ? 1 : 0

  metadata {
    name = "alloy"
  }
}

resource "kubernetes_secret" "grafana_cloud" {
  count = var.grafana_cloud_token != "" ? 1 : 0

  metadata {
    name      = "grafana-cloud"
    namespace = "alloy"
  }

  data = {
    token = var.grafana_cloud_token
  }

  depends_on = [kubernetes_namespace.alloy]
}

resource "helm_release" "alloy" {
  count = var.grafana_cloud_token != "" ? 1 : 0

  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_version
  namespace  = "alloy"
  timeout    = 600

  values = [yamlencode({
    controller = { type = "daemonset" }
    alloy = {
      configMap = { content = file("${path.module}/alloy/config.alloy") }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
      extraEnv = [
        { name = "PROM_URL", value = var.grafana_cloud_prometheus_url },
        { name = "PROM_USER", value = var.grafana_cloud_prometheus_user },
        { name = "LOKI_URL", value = var.grafana_cloud_loki_url },
        { name = "LOKI_USER", value = var.grafana_cloud_loki_user },
        {
          name = "GCLOUD_TOKEN"
          valueFrom = {
            secretKeyRef = { name = "grafana-cloud", key = "token" }
          }
        },
      ]
    }
  })]

  depends_on = [
    oci_containerengine_node_pool.workers,
    kubernetes_namespace.alloy,
    kubernetes_secret.grafana_cloud,
  ]
}
