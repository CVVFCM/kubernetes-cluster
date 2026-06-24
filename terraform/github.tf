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
