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

variable "node_hostnames" {
  type        = list(string)
  description = "Per-node direct DNS names, assigned in sorted-node-key order. Must hold at least as many names as nodes."
  default     = ["optimist", "laser", "europe", "declic", "vaurien", "caravelle"]
}

variable "node_dns_zone" {
  type        = string
  description = "Zone (key into cloudflare_zones) for the per-node direct records."
  default     = "cvvfcm.fr"
}

variable "longhorn_volume_size_gb" {
  type        = number
  description = "Size of the per-node OCI block volume backing Longhorn (/var/lib/longhorn). 2 x 50 + 2 boot vols stays under the 200 GB Always-Free cap."
  default     = 50
}

variable "longhorn_version" {
  type        = string
  description = "Longhorn Helm chart version (arm64-published). Pin explicitly; verify latest at charts.longhorn.io before bumping."
  default     = "1.11.2"
}

variable "k9s_version" {
  type        = string
  description = "k9s release tag installed on the nodes (arm64 binary from GitHub releases)."
  default     = "v0.51.0"
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
