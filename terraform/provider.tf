terraform {
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_id
  user_ocid        = var.user_id
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

provider "github" {
  owner = var.github_org

  # Authenticates as the org-owned GitHub App (Organization > Secrets: read &
  # write). Wired through variables (default null) rather than a bare
  # `app_auth {}` so `tofu validate` passes without credentials in env; null
  # leaves the provider falling back to GITHUB_APP_ID,
  # GITHUB_APP_INSTALLATION_ID and GITHUB_APP_PEM_FILE (PEM content, not a path).
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_pem
  }
}

provider "cloudflare" {
  # api_token from CLOUDFLARE_API_TOKEN env
}

# The kubernetes/helm/kubectl providers talk to the OKE API via the cluster's
# public endpoint, authenticating with a short-lived exec token from the OCI CLI
# (`oci ce cluster generate-token`). The CLI must be present on the runner, and
# the cluster must exist before these connect — hence the two-phase first apply
# (-target the cluster + node pool, then a full apply). See locals.tf for the
# parsed host/CA.
provider "kubernetes" {
  host                   = local.kube_host
  cluster_ca_certificate = local.kube_ca

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args        = ["ce", "cluster", "generate-token", "--cluster-id", local.kube_cluster_id, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = local.kube_host
    cluster_ca_certificate = local.kube_ca

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "oci"
      args        = ["ce", "cluster", "generate-token", "--cluster-id", local.kube_cluster_id, "--region", var.region]
    }
  }
}

provider "kubectl" {
  host                   = local.kube_host
  cluster_ca_certificate = local.kube_ca
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args        = ["ce", "cluster", "generate-token", "--cluster-id", local.kube_cluster_id, "--region", var.region]
  }
}
