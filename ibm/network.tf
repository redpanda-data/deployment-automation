resource "ibm_is_public_gateway" "pgw" {
  name  = "${local.BASENAME}-pgw"
  vpc   = ibm_is_vpc.vpc.id
  resource_group = var.resource_group
  zone  = local.ZONE
}

resource "ibm_is_subnet" "subnet" {
    name                     = "${local.BASENAME}-subnet"
    vpc                      = ibm_is_vpc.vpc.id
    zone                     = local.ZONE
    total_ipv4_address_count = 256
    resource_group = var.resource_group
    public_gateway = ibm_is_public_gateway.pgw.id
}

resource "ibm_is_security_group" "sg" {
    name = "${local.BASENAME}-sg"
    vpc = ibm_is_vpc.vpc.id
    resource_group = var.resource_group

}

# allow all incoming network traffic on port 22
resource "ibm_is_security_group_rule" "ingress_ssh_all" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"

    tcp {
      port_min = 22
      port_max = 22
    }
}

resource "ibm_is_security_group_rule" "internet_access_out" {
    group     = ibm_is_security_group.sg.id
    direction = "outbound"
    remote    = "0.0.0.0/0"

}

resource "ibm_is_security_group_rule" "internet_access_in" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"

}

resource "ibm_is_security_group_rule" "ingress_node_exporter" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9100
        port_max = 9100
    }
}

resource "ibm_is_security_group_rule" "ingress_http" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9092
        port_max = 9092
    }
}

resource "ibm_is_security_group_rule" "ingress_http_rpc" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 33145
        port_max = 33145
    }
}

resource "ibm_is_security_group_rule" "ingress_http_admin" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9644
        port_max = 9644
    }
}

resource "ibm_is_security_group_rule" "ingress_redpanda_proxy" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 8082
        port_max = 8082
    }
}

resource "ibm_is_security_group_rule" "ingress_grafana" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 3000
        port_max = 3000
    }
}

resource "ibm_is_security_group_rule" "ingress_prometheus" {
    group     = ibm_is_security_group.sg.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9090
        port_max = 9090
    }
}