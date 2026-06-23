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

  is_mtls_connection_required = true
  whitelisted_ips = concat(
    [for n in oci_core_instance.nodes : n.public_ip],
    var.db_acl_extra_cidrs,
  )
}

resource "oci_database_autonomous_database_wallet" "main" {
  autonomous_database_id = oci_database_autonomous_database.main.id
  password               = random_password.db_wallet.result
  generate_type          = "SINGLE"
  base64_encode_content  = true
}
