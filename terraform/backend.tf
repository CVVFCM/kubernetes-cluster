variable "backend_profile" {
  type    = string
  default = "default"
}

terraform {
  backend "s3" {
    bucket  = "cvvfcm-terraform-state"
    key     = "kubernetes-cluster/terraform.tfstate"
    region  = "fr-par"
    profile = var.backend_profile

    # Scaleway Object Storage is S3-compatible, not AWS.
    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
