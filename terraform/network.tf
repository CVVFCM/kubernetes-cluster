resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "oke-vcn"
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# --- Security lists (one per subnet role) ---
# Intra-VCN traffic is fully open so the control plane <-> workers <-> LB paths
# (6443/12250/10250, flannel, NLB health checks, nodeports) all work without
# enumerating every OKE port. Public entrypoints are narrow: API on 6443, the
# load balancer on 80/443, and ICMP 3/4 for path-MTU discovery.

resource "oci_core_security_list" "api" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-api"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }

  ingress_security_rules {
    protocol = "6" # kube API for operators / CI
    source   = var.kube_api_ingress_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "1" # ICMP path-MTU
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_security_list" "workers" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-workers"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }

  ingress_security_rules {
    protocol = "1" # ICMP path-MTU
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  # The OCI NLB forwards to worker NodePorts with the client's source IP
  # preserved (is-preserve-source=true + externalTrafficPolicy=Local, addons.tf).
  # The health check rides the vcn_cidr rule above, but data-plane packets carry
  # the real client IP, so the NodePort range must be reachable from the same
  # CIDR that fronts the NLB — otherwise traffic is dropped and connections time
  # out. Lock http_ingress_cidr to Cloudflare ranges to force traffic via the CF
  # proxy. 30000-32767 is the default K8s NodePort range (covers the web/
  # websecure nodePorts and the healthCheckNodePort).
  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.http_ingress_cidr
    tcp_options {
      min = 30000
      max = 32767
    }
  }
}

resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-lb"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.http_ingress_cidr
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.http_ingress_cidr
    tcp_options {
      min = 443
      max = 443
    }
  }
}

# --- Subnets (all public, regional) ---

resource "oci_core_subnet" "api" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.api_subnet_cidr
  display_name               = "oke-api"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.api.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "workers" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.worker_subnet_cidr
  display_name               = "oke-workers"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.workers.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "lb" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.lb_subnet_cidr
  display_name               = "oke-lb"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.lb.id]
  prohibit_public_ip_on_vnic = false
}
