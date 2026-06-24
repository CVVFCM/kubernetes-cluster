data "external" "kubeconfig" {
  count      = var.export_kubeconfig ? 1 : 0
  depends_on = [oci_core_instance.nodes]
  program    = ["bash", "${path.module}/scripts/fetch-kubeconfig.sh"]

  query = {
    host    = oci_core_instance.nodes["server"].public_ip
    key_pem = tls_private_key.cluster.private_key_openssh
  }
}

resource "github_actions_organization_secret" "kubeconfig" {
  count       = var.export_kubeconfig ? 1 : 0
  secret_name = var.kubeconfig_secret_name
  visibility  = "all"
  value       = data.external.kubeconfig[0].result.kubeconfig
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

# mTLS wallet (base64 ZIP from OCI: cwallet.sso, sqlnet.ora, tnsnames.ora, ...).
# The app workflow base64-decodes this, unzips, and mounts it as TNS_ADMIN so the
# oci8 client resolves the tnsnames alias and authenticates via cwallet.sso (no
# runtime password). cwallet.sso is auto-login — treat this secret as credential-grade.
resource "github_actions_environment_secret" "oracle_wallet" {
  repository  = var.database_url_repo
  environment = var.database_url_environment
  secret_name = "ORACLE_WALLET_B64"
  value       = oci_database_autonomous_database_wallet.main.content
}
