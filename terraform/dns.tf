locals {
  # Cross every requested domain with every cluster node → one A record each
  # (DNS round-robin). Keyed "<domain>-<node>" for stable for_each addressing.
  dns_records = merge([
    for d in var.domains : {
      for node_key, node in oci_core_instance.nodes :
      "${d.domain}-${node_key}" => {
        domain  = d.domain
        zone_id = var.cloudflare_zones[d.zone]
        proxied = d.proxied
        ip      = node.public_ip
      }
    }
  ]...)
}

# k3s Traefik/ServiceLB listens on 80/443 of each node.
resource "cloudflare_dns_record" "app" {
  for_each = local.dns_records

  zone_id = each.value.zone_id
  name    = each.value.domain
  type    = "A"
  content = each.value.ip
  ttl     = 1 # 1 = automatic (required when proxied)
  proxied = each.value.proxied
}

locals {
  # One direct (non-proxied) hostname per node, names drawn from the pool in
  # sorted-node-key order so each node keeps a stable name.
  node_direct_dns = {
    for idx, k in sort(keys(oci_core_instance.nodes)) :
    k => {
      hostname = var.node_hostnames[idx]
      ip       = oci_core_instance.nodes[k].public_ip
    }
  }
}

# Direct A record per node (SSH / API access). DNS-only — node IP exposed.
resource "cloudflare_dns_record" "node" {
  for_each = local.node_direct_dns

  zone_id = var.cloudflare_zones[var.node_dns_zone]
  name    = each.value.hostname
  type    = "A"
  content = each.value.ip
  ttl     = 1
  proxied = false
}
