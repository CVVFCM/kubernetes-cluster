# --- OKE version + worker image discovery ---

data "oci_containerengine_cluster_option" "main" {
  cluster_option_id = "all"
}

data "oci_containerengine_node_pool_option" "main" {
  node_pool_option_id = "all"
}

locals {
  # Latest supported k8s version (OCI returns the list ascending) unless pinned.
  k8s_version = var.kubernetes_version != "" ? var.kubernetes_version : element(
    data.oci_containerengine_cluster_option.main.kubernetes_versions,
    length(data.oci_containerengine_cluster_option.main.kubernetes_versions) - 1,
  )

  # Oracle Linux OKE worker image matching the k8s version on aarch64 (A1 is ARM).
  node_image_id = [
    for s in data.oci_containerengine_node_pool_option.main.sources :
    s.image_id
    if can(regex("aarch64", s.source_name)) && can(regex(replace(local.k8s_version, "v", ""), s.source_name))
  ][0]
}

# --- Cluster ---

resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  name               = "cvvfcm-oke"
  kubernetes_version = local.k8s_version
  type               = "BASIC_CLUSTER" # free control plane
  vcn_id             = oci_core_vcn.main.id

  endpoint_config {
    subnet_id            = oci_core_subnet.api.id
    is_public_ip_enabled = true
  }

  options {
    # Subnet the cloud-controller-manager places LoadBalancer (incl. flexible NLB) frontends in.
    service_lb_subnet_ids = [oci_core_subnet.lb.id]

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }
  }
}

# --- Worker node pool: 2x A1.Flex, 100GB boot, Oracle Linux ---

resource "oci_containerengine_node_pool" "workers" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_id
  name               = "workers"
  kubernetes_version = local.k8s_version
  node_shape         = "VM.Standard.A1.Flex"

  node_shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  node_config_details {
    size = var.node_count

    placement_configs {
      availability_domain = local.ad
      subnet_id           = oci_core_subnet.workers.id
    }

    node_pool_pod_network_option_details {
      cni_type = "FLANNEL_OVERLAY"
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.node_image_id
    boot_volume_size_in_gbs = var.node_boot_volume_gb
  }

  # Optional operator SSH into worker nodes (key also published as an org secret).
  ssh_public_key = tls_private_key.cluster.public_key_openssh

  # Longhorn prereqs + the mandatory OKE node bootstrap.
  node_metadata = {
    user_data = base64encode(file("${path.module}/cloud-init/oke-worker.yaml.tftpl"))
  }
}

# --- kubeconfig (drives the kubernetes/helm/kubectl providers + the org secret) ---

data "oci_containerengine_cluster_kube_config" "main" {
  cluster_id    = oci_containerengine_cluster.main.id
  token_version = "2.0.0"
}

locals {
  kube_cluster_id = oci_containerengine_cluster.main.id
  kubeconfig_yaml = yamldecode(data.oci_containerengine_cluster_kube_config.main.content)
  kube_host       = local.kubeconfig_yaml["clusters"][0]["cluster"]["server"]
  kube_ca         = base64decode(local.kubeconfig_yaml["clusters"][0]["cluster"]["certificate-authority-data"])
}
