output "public_ips" {
  value = { for k, v in oci_core_instance.nodes : k => v.public_ip }
}

output "private_ips" {
  value = { for k, v in oci_core_instance.nodes : k => v.private_ip }
}

output "server_public_ip" {
  value = oci_core_instance.nodes["server"].public_ip
}

output "ssh_connections" {
  value = { for k, v in oci_core_instance.nodes : k => "ssh ubuntu@${v.public_ip}" }
}

output "availability_domain" {
  value = local.ad
}

# Fetch the kubeconfig and rewrite its loopback address to the server's public IP.
output "kubeconfig_cmd" {
  value = "ssh ubuntu@${oci_core_instance.nodes["server"].public_ip} sudo cat /etc/rancher/k3s/k3s.yaml | sed 's/127.0.0.1/${oci_core_instance.nodes["server"].public_ip}/' > kubeconfig.yaml"
}

# --- Autonomous Database ---

output "db_id" {
  value = oci_database_autonomous_database.main.id
}

output "db_connection_strings" {
  value     = oci_database_autonomous_database.main.connection_strings
  sensitive = true
}

output "db_admin_password" {
  value     = random_password.db_admin.result
  sensitive = true
}

output "db_wallet_password" {
  value     = random_password.db_wallet.result
  sensitive = true
}

# base64 zip; recover with: tofu output -raw db_wallet_base64 | base64 -d > wallet.zip
output "db_wallet_base64" {
  value     = oci_database_autonomous_database_wallet.main.content
  sensitive = true
}

# --- GitHub export ---

output "kubeconfig_secret_name" {
  value       = github_actions_organization_secret.kubeconfig.secret_name
  description = "Org Actions secret holding the cluster kubeconfig."
}
