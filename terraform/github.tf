# OKE kubeconfig published as an org Actions secret for CI in other repos.
# Note: this kubeconfig uses an exec credential (`oci ce cluster generate-token`),
# so consumers need the OCI CLI + OCI auth available.
resource "github_actions_organization_secret" "kubeconfig" {
  secret_name = var.kubeconfig_secret_name
  visibility  = "all"
  value       = data.oci_containerengine_cluster_kube_config.main.content
}

resource "github_actions_organization_secret" "oci_tenancy" {
  secret_name = "OCI_TENANCY_OCID"
  visibility  = "all"
  value       = var.tenancy_id
}

resource "github_actions_organization_secret" "oci_user" {
  secret_name = "OCI_USER_OCID"
  visibility  = "all"
  value       = var.user_id
}

resource "github_actions_organization_secret" "oci_fingerprint" {
  secret_name = "OCI_FINGERPRINT"
  visibility  = "all"
  value       = var.fingerprint
}

resource "github_actions_organization_secret" "oci_region" {
  secret_name = "OCI_REGION"
  visibility  = "all"
  value       = var.region
}

resource "github_actions_organization_secret" "oci_api_key" {
  secret_name = "OCI_API_KEY"
  visibility  = "all"
  value       = base64encode(file(var.private_key_path))
}
