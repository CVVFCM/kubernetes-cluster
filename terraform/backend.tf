variable "backend_profile" {
  # Empty = no shared-config profile; the S3 backend falls back to the env
  # credential chain (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY), which is how CI
  # and any host without ~/.aws/credentials authenticate. Locally, set it (e.g.
  # via .yohan/.env -> TF_VAR_backend_profile) to use a named profile instead.
  type    = string
  default = ""
}

terraform {
  backend "s3" {
    bucket  = "cvvfcm-terraform-state"
    key     = "kubernetes-cluster/terraform.tfstate"
    region  = "fr-par"
    profile = var.backend_profile != "" ? var.backend_profile : null

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
