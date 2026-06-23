data "external" "kubeconfig" {
  depends_on = [oci_core_instance.nodes]
  program    = ["bash", "${path.module}/scripts/fetch-kubeconfig.sh"]

  query = {
    host = oci_core_instance.nodes["server"].public_ip
    key  = var.ssh_private_key_path
  }
}

resource "github_actions_organization_secret" "kubeconfig" {
  secret_name = var.kubeconfig_secret_name
  visibility  = "all"
  value       = data.external.kubeconfig.result.kubeconfig
}

# Symfony DATABASE_URL → repo "prod" environment secret.
# The environment must already exist. If it does not, uncomment the resource below
# (note: managing it here can reset the environment's protection rules).
# resource "github_repository_environment" "database_url" {
#   repository  = var.database_url_repo
#   environment = var.database_url_environment
# }

resource "github_actions_environment_secret" "database_url" {
  repository  = var.database_url_repo
  environment = var.database_url_environment
  secret_name = "DATABASE_URL"
  value       = local.database_url
}
