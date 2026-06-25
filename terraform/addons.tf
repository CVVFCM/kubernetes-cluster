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
    providers = {
      kubernetesGateway = { enabled = true }
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
          port          = 80
          allowedRoutes = { namespaces = { from = "All" } }
        },
        {
          name     = "websecure"
          protocol = "HTTPS"
          port     = 443
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
