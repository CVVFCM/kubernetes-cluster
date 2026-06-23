data "external" "kubeconfig" {
  depends_on = [oci_core_instance.nodes]
  program    = ["bash", "${path.module}/scripts/fetch-kubeconfig.sh"]

  query = {
    host = oci_core_instance.nodes["server"].public_ip
    key  = var.ssh_private_key_path
  }
}

resource "github_actions_organization_secret" "kubeconfig" {
  secret_name     = var.kubeconfig_secret_name
  visibility      = "all"
  plaintext_value = data.external.kubeconfig.result.kubeconfig
}
