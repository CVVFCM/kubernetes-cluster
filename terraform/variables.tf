# --- OCI authentication (no defaults: set in terraform.tfvars) ---

variable "tenancy_id" {
  type        = string
  description = "Tenancy OCID."
}

variable "user_id" {
  type        = string
  description = "User OCID for the API key."
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the API signing key."
}

variable "private_key_path" {
  type        = string
  description = "Path to the API private key (PEM)."
  default     = "~/oracle-private.pem"
}

variable "region" {
  type    = string
  default = "eu-paris-1"
}

variable "compartment_id" {
  type        = string
  description = "Compartment OCID where resources are created."
}

# --- OKE cluster + node pool ---

variable "kubernetes_version" {
  type        = string
  description = "OKE Kubernetes version (e.g. v1.31.1). Empty = latest supported."
  default     = ""
}

variable "availability_domain" {
  type        = string
  description = "AD name; empty selects the first AD in the region."
  default     = ""
}

variable "node_count" {
  type        = number
  description = "Worker node count."
  default     = 2
}

variable "ocpus" {
  type        = number
  description = "OCPUs per worker. 2 nodes x 2 = 4 = A1 Always-Free cap."
  default     = 2
}

variable "memory_in_gbs" {
  type        = number
  description = "Memory per worker. 2 nodes x 12 = 24 = A1 Always-Free cap."
  default     = 12
}

variable "node_boot_volume_gb" {
  type        = number
  description = "Worker boot volume size (also backs Longhorn /var/lib/longhorn). 2 x 100 = 200 = block Always-Free cap."
  default     = 100
}

# --- Networking ---

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "api_subnet_cidr" {
  type        = string
  description = "Subnet for the OKE Kubernetes API endpoint."
  default     = "10.0.0.0/28"
}

variable "worker_subnet_cidr" {
  type        = string
  description = "Subnet for worker nodes (public)."
  default     = "10.0.1.0/24"
}

variable "lb_subnet_cidr" {
  type        = string
  description = "Subnet for LoadBalancer/NLB frontends (public)."
  default     = "10.0.2.0/24"
}

variable "pods_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.96.0.0/16"
}

variable "kube_api_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach the OKE API endpoint (6443)."
  default     = "0.0.0.0/0"
}

variable "http_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach the NLB on 80/443. 0.0.0.0/0 = open; lock to Cloudflare ranges to force traffic through the CF proxy."
  default     = "0.0.0.0/0"
}

# --- Cloudflare DNS ---

variable "cloudflare_zones" {
  type        = map(string) # zone name => zone ID (not secret)
  description = "Cloudflare zone IDs keyed by zone name."
  default = {
    "cvvfcm.fr" = "3fa2035c4239d02756471c8a0f51f247"
  }
}

variable "domains" {
  type = list(object({
    domain  = string # record name, relative to the zone
    zone    = string # zone name, key into cloudflare_zones
    proxied = bool   # Cloudflare proxy (orange cloud)
  }))
  description = "App hostnames pointed at the NLB."
  default = [
    { domain = "meteoprint", zone = "cvvfcm.fr", proxied = true },
    { domain = "healthcheck", zone = "cvvfcm.fr", proxied = false },
    { domain = "traefik", zone = "cvvfcm.fr", proxied = false },
  ]
}

variable "node_hostnames" {
  type        = list(string)
  description = "Optional per-node direct DNS names, assigned in node order. Must hold at least node_count names."
  default     = ["optimist", "laser", "europe", "declic", "vaurien", "caravelle"]
}

variable "node_dns_zone" {
  type        = string
  description = "Zone (key into cloudflare_zones) for the per-node direct records."
  default     = "cvvfcm.fr"
}

# --- Add-on versions / TLS ---

variable "longhorn_version" {
  type        = string
  description = "Longhorn Helm chart version (arm64-published). Verify latest at charts.longhorn.io."
  default     = "1.12.0"
}

variable "traefik_chart_version" {
  type        = string
  description = "Traefik Helm chart version. Empty = latest."
  default     = ""
}

variable "gateway_api_version" {
  type        = string
  description = "Kubernetes Gateway API release tag for the standard-channel CRDs. Keep in lockstep with the Traefik version (v3.7 → v1.5.x)."
  default     = "v1.5.1"
}

variable "cert_manager_version" {
  type        = string
  description = "cert-manager Helm chart version. Verify latest at charts.jetstack.io."
  default     = "v1.20.2"
}

variable "acme_email" {
  type        = string
  description = "Contact email for the Let's Encrypt ACME account."
  default     = "yohan@les-tilleuls.coop"
}

variable "default_cluster_issuer" {
  type        = string
  description = "ClusterIssuer for the wildcard Gateway cert. Use letsencrypt-staging while testing, then letsencrypt-prod."
  default     = "letsencrypt-prod"
}

variable "cloudflare_dns_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token for cert-manager DNS-01 (Zone.DNS:Edit + Zone:Read). Written into a k8s Secret; lands in TF state."
  default     = ""
}

# --- Traefik dashboard ---

variable "traefik_dashboard_users" {
  type        = string
  sensitive   = true
  description = "htpasswd lines for the Traefik dashboard BasicAuth (e.g. output of `htpasswd -nbB admin '<pw>'`). Empty = dashboard not exposed. Lands in a k8s Secret + TF state."
  default     = ""
}

variable "traefik_dashboard_host" {
  type        = string
  description = "Hostname the Traefik dashboard IngressRoute matches. Must resolve to the NLB (add it to var.domains)."
  default     = "traefik.cvvfcm.fr"
}

# --- GitHub export ---

variable "github_org" {
  type        = string
  description = "GitHub organization that owns the exported secret."
}

variable "kubeconfig_secret_name" {
  type        = string
  description = "Name of the GitHub org Actions secret holding the kubeconfig."
  default     = "OKE_KUBECONFIG"
}
