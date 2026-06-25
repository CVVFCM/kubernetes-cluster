# Cluster SSH keypair generated at apply time. Public key is set as the OKE node
# pool's ssh_public_key (oke.tf) for optional operator SSH into workers; the private
# key is published as an org secret. Rotate with `-replace` (then recycle the pool).
resource "tls_private_key" "cluster" {
  algorithm = "ED25519"
}

resource "github_actions_organization_secret" "cluster_ssh_key" {
  secret_name = "CLUSTER_SSH_PRIVATE_KEY"
  visibility  = "private" # cluster root key — keep off public repos
  value       = tls_private_key.cluster.private_key_openssh
}
