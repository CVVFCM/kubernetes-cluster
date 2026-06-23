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

# --- Cluster configuration ---

variable "github_username" {
  type        = string
  description = "GitHub user whose public keys authorize SSH access."
  default     = "yohang"
}

variable "availability_domain" {
  type        = string
  description = "AD name; empty selects the first AD in the region."
  default     = ""
}

variable "ocpus" {
  type        = number
  description = "OCPUs per instance. 2 nodes x 2 = 4 = A1 Always-Free cap."
  default     = 2
}

variable "memory_in_gbs" {
  type        = number
  description = "Memory per instance. 2 nodes x 12 = 24 = A1 Always-Free cap."
  default     = 12
}

variable "ssh_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH (22)."
  default     = "0.0.0.0/0"
}

variable "k3s_api_ingress_cidr" {
  type        = string
  description = "CIDR allowed to reach the k3s API (6443)."
  default     = "0.0.0.0/0"
}

variable "k3s_version" {
  type        = string
  description = "k3s version to pin (INSTALL_K3S_VERSION). Empty installs latest stable."
  default     = ""
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "db_name" {
  type        = string
  description = "ADB db_name: alphanumeric, max 14 chars, unique in tenancy."
  default     = "k3sappdb"
}

variable "db_workload" {
  type        = string
  description = "ADB workload type: OLTP (ATP), DW (ADW), or AJD."
  default     = "OLTP"
}

variable "db_acl_extra_cidrs" {
  type        = list(string)
  description = "Extra IPs/CIDRs allowed to reach the DB (e.g. your workstation). Node public IPs are added automatically."
  default     = []
}

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
  description = "Hostnames to point at the cluster (every node)."
  default = [
    { domain = "meteoprint", zone = "cvvfcm.fr", proxied = true },
  ]
}

variable "db_server_version" {
  type        = string
  description = "serverVersion embedded in the Symfony DATABASE_URL. Must match the actual ADB version."
  default     = "19"
}

variable "database_url_repo" {
  type        = string
  description = "Repo (under github_org) receiving the DATABASE_URL environment secret."
  default     = "Meteoprint"
}

variable "database_url_environment" {
  type        = string
  description = "GitHub environment whose secret holds DATABASE_URL."
  default     = "prod"
}

variable "github_org" {
  type        = string
  description = "GitHub organization that owns the exported secret."
}

variable "kubeconfig_secret_name" {
  type        = string
  description = "Name of the GitHub org Actions secret holding the kubeconfig."
  default     = "K3S_KUBECONFIG"
}

variable "export_kubeconfig" {
  type        = bool
  description = "Fetch the kubeconfig over SSH and publish it as the org secret. Enable on apply (cluster up); keep off for plan so planning never depends on SSH reachability."
  default     = false
}

variable "server_private_ip" {
  type        = string
  description = "Static private IP of the k3s server node."
  default     = "10.0.1.10"
}

variable "agent_private_ip" {
  type        = string
  description = "Static private IP of the k3s agent node."
  default     = "10.0.1.11"
}
