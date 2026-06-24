resource "random_password" "db_admin" {
  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 1
  override_special = "_#-" # ADB forbids " and most other specials
}

resource "random_password" "db_wallet" {
  length  = 24
  special = false
}

resource "oci_database_autonomous_database" "main" {
  compartment_id           = var.compartment_id
  db_name                  = var.db_name # alphanumeric, <= 14 chars
  display_name             = var.db_name
  db_workload              = var.db_workload # "OLTP"
  is_free_tier             = true
  cpu_core_count           = 1
  data_storage_size_in_tbs = 1 # free tier capped to 20 GB server-side
  admin_password           = random_password.db_admin.result

  # mTLS optional so a self-contained DATABASE_URL works without a wallet.
  # Disabling mTLS requires an ACL or private endpoint; whitelisted_ips satisfies it.
  is_mtls_connection_required = false
  whitelisted_ips = concat(
    [for n in oci_core_instance.nodes : n.public_ip],
    var.db_acl_extra_cidrs,
  )

  # Always Free ADB has fixed, immutable compute/storage (reported as 0) — any
  # update attempt is rejected with 403. Don't reconcile these after creation.
  lifecycle {
    ignore_changes = [cpu_core_count, data_storage_size_in_tbs]
  }
}

resource "oci_database_autonomous_database_wallet" "main" {
  autonomous_database_id = oci_database_autonomous_database.main.id
  password               = random_password.db_wallet.result
  generate_type          = "SINGLE"
  base64_encode_content  = true
}

locals {
  # Wallet-less TLS connect descriptor for the HIGH consumer group
  # (protocol TCPS, server-only TLS auth). Carries ssl_server_dn_match.
  db_tls_descriptor = one([
    for p in oci_database_autonomous_database.main.connection_strings[0].profiles :
    p.value
    if upper(p.consumer_group) == "HIGH" && upper(p.tls_authentication) == "SERVER"
  ])

  # Symfony/Doctrine oci8 DSN. The full descriptor is URL-encoded and placed as the
  # host segment; Doctrine rawurldecodes it back. serverVersion + charset included.
  # Symfony resolves DATABASE_URL via %env(resolve:...)%, so any literal '%' (from
  # urlencode, e.g. '%25') must be doubled to '%%' or the container param resolver
  # tries to interpret it as a parameter reference and fails.
  database_url = format(
    "oci8://ADMIN:%s@%s?serverVersion=%s&charset=AL32UTF8",
    replace(urlencode(random_password.db_admin.result), "%", "%%"),
    replace(urlencode(local.db_tls_descriptor), "%", "%%"),
    var.db_server_version,
  )
}
