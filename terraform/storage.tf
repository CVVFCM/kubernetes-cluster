# Dedicated block volume per node for Longhorn replica data, mounted at
# /var/lib/longhorn by cloud-init. Kept off the boot disk so Longhorn can't
# trigger DiskPressure on the OS/k3s volume. Must share the node's AD.
resource "oci_core_volume" "longhorn" {
  for_each = local.nodes

  availability_domain = local.ad
  compartment_id      = var.compartment_id
  display_name        = "longhorn-${each.key}"
  size_in_gbs         = var.longhorn_volume_size_gb
}

resource "oci_core_volume_attachment" "longhorn" {
  for_each = local.nodes

  # Paravirtualized presents a stable /dev/oracleoci/oraclevdb (oci-utils udev)
  # and avoids tangling OCI's own iSCSI attach flow with Longhorn's iSCSI.
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.nodes[each.key].id
  volume_id       = oci_core_volume.longhorn[each.key].id
  device          = "/dev/oracleoci/oraclevdb"
}
