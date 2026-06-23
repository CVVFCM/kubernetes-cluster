data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_id
}

data "http" "github_keys" {
  url = "https://api.github.com/users/${var.github_username}/keys"
}

locals {
  ad = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.ads.availability_domains[0].name
  ssh_keys = join("\n", concat(
    [for k in jsondecode(data.http.github_keys.response_body) : k.key],
    [tls_private_key.cluster.public_key_openssh],
  ))

  server_url = "https://${var.server_private_ip}:6443"

  # role drives which cloud-init template the node receives.
  nodes = {
    server = { role = "server", private_ip = var.server_private_ip }
    agent  = { role = "agent", private_ip = var.agent_private_ip }
  }
}
