resource "random_password" "k3s_token" {
  length  = 48
  special = false # shell-safe in cloud-init
}

resource "oci_core_instance" "nodes" {
  for_each = local.nodes

  availability_domain = local.ad
  compartment_id      = var.compartment_id
  display_name        = "k3s-${each.key}"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.main.id
    assign_public_ip = true
    private_ip       = each.value.private_ip
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = local.ssh_keys
    user_data = base64encode(templatefile(
      "${path.module}/cloud-init/k3s-${each.value.role}.yaml.tftpl",
      {
        k3s_token   = random_password.k3s_token.result
        k3s_version = var.k3s_version
        server_url  = local.server_url
        node_ip     = each.value.private_ip
      }
    ))
  }
}
