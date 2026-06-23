locals {
  # Cross every requested domain with every cluster node → one A record each
  # (DNS round-robin). Keyed "<domain>-<node>" for stable for_each addressing.
  dns_records = merge([
    for d in var.domains : {
      for node_key, node in oci_core_instance.nodes :
      "${d.domain}-${node_key}" => {
        domain  = d.domain
        proxied = d.proxied
        ip      = node.public_ip
      }
    }
  ]...)
}

# k3s Traefik/ServiceLB listens on 80/443 of each node.
resource "cloudflare_dns_record" "app" {
  for_each = local.dns_records

  zone_id = var.cloudflare_zone_id
  name    = each.value.domain
  type    = "A"
  content = each.value.ip
  ttl     = 1 # 1 = automatic (required when proxied)
  proxied = each.value.proxied
}
