# Traefik's LoadBalancer Service → flexible OCI NLB. Read its assigned public IP
# once the release is up and feed it to the app DNS records.
data "kubernetes_service" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "traefik"
  }

  depends_on = [helm_release.traefik]
}

locals {
  nlb_ip = data.kubernetes_service.traefik.status[0].load_balancer[0].ingress[0].ip

  app_records = {
    for d in var.domains : d.domain => {
      zone_id = var.cloudflare_zones[d.zone]
      proxied = d.proxied
    }
  }

  # Optional per-node direct records. Keys come from static inputs (node_count +
  # node_hostnames) so for_each is known at plan; the IP is resolved per index.
  node_direct_dns = {
    for i in range(var.node_count) : var.node_hostnames[i] => i
  }
}

# App domains → the NLB public IP (Cloudflare-proxied).
resource "cloudflare_dns_record" "app" {
  for_each = local.app_records

  zone_id = each.value.zone_id
  name    = each.key
  type    = "A"
  content = local.nlb_ip
  ttl     = 1 # automatic (required when proxied)
  proxied = each.value.proxied
}

# Optional direct-to-node records (DNS-only). Node-pool nodes can recycle, so
# these IPs are best-effort and may change on a node replacement.
resource "cloudflare_dns_record" "node" {
  for_each = local.node_direct_dns

  zone_id = var.cloudflare_zones[var.node_dns_zone]
  name    = each.key
  type    = "A"
  content = oci_containerengine_node_pool.workers.nodes[each.value].public_ip
  ttl     = 1
  proxied = false
}
