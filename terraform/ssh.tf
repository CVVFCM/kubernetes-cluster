# Cluster SSH keypair generated at apply time.
# Public key is injected into every node's authorized_keys (see locals.tf);
# the private key is used directly by the kubeconfig fetch (see github.tf) and
# published as an org secret for operators. Rotate with `-replace` on this resource
# (also recreate the nodes so the new public key lands in authorized_keys).
resource "tls_private_key" "cluster" {
  algorithm = "ED25519"
}

resource "github_actions_organization_secret" "cluster_ssh_key" {
  secret_name = "CLUSTER_SSH_PRIVATE_KEY"
  visibility  = "private" # cluster root key — keep off public repos
  value       = tls_private_key.cluster.private_key_openssh
}
