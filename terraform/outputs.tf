output "cluster_id" {
  value = oci_containerengine_cluster.main.id
}

output "cluster_endpoint" {
  value       = local.kube_host
  description = "OKE public Kubernetes API endpoint."
}

output "kubernetes_version" {
  value = oci_containerengine_cluster.main.kubernetes_version
}

output "node_public_ips" {
  value       = [for n in oci_containerengine_node_pool.workers.nodes : n.public_ip]
  description = "Worker node public IPs (best-effort; nodes recycle)."
}

output "nlb_ip" {
  value       = local.nlb_ip
  description = "Public IP of the flexible NLB fronting Traefik (the app DNS target)."
}

output "kubeconfig_secret_name" {
  value       = github_actions_organization_secret.kubeconfig.secret_name
  description = "GitHub org Actions secret holding the OKE kubeconfig."
}

output "kubeconfig_cmd" {
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.main.id} --region ${var.region} --token-version 2.0.0 --file $HOME/.kube/config"
  description = "Fetch a local kubeconfig for this cluster."
}
