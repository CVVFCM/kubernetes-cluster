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

variable "db_server_version" {
  type        = string
  description = "serverVersion embedded in the Symfony DATABASE_URL."
  default     = "23"
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

variable "ssh_private_key_path" {
  type        = string
  description = "Private key matching the GitHub public keys authorizing node SSH (used to fetch kubeconfig)."
  default     = "~/.ssh/id_ed25519"
}

variable "kubeconfig_secret_name" {
  type        = string
  description = "Name of the GitHub org Actions secret holding the kubeconfig."
  default     = "K3S_KUBECONFIG"
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
