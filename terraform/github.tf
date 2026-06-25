# OKE kubeconfig published as an org Actions secret for CI in other repos.
# Note: this kubeconfig uses an exec credential (`oci ce cluster generate-token`),
# so consumers need the OCI CLI + OCI auth available.
resource "github_actions_organization_secret" "kubeconfig" {
  secret_name = var.kubeconfig_secret_name
  visibility  = "all"
  value       = data.oci_containerengine_cluster_kube_config.main.content
}
