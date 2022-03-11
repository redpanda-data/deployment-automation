variable "ssh_key" {}
variable "number_of_instances" {
    description = "Number of VMs, IPs, and associated volume attachements"
    type = number
    default  = 3
}
variable "resource_group" {
    description = "Associated Resource Group"
    type = string
    default = "2ad3843ca84b4295bd6ef46c47b3ff6f"
}

locals {
    BASENAME = "sk-redpanda-v2"
    ZONE = "ca-tor-1"
}

resource "ibm_is_vpc" "vpc" {
    name = "${local.BASENAME}-vpc"
    resource_group = var.resource_group
}

resource "ibm_is_security_group" "sg1" {
    name = "${local.BASENAME}-sg1"
    vpc = ibm_is_vpc.vpc.id
    resource_group = var.resource_group

}

# allow all incoming network traffic on port 22
resource "ibm_is_security_group_rule" "ingress_ssh_all" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"

    tcp {
      port_min = 22
      port_max = 22
    }
}

resource "ibm_is_security_group_rule" "internet_access_out" {
    group     = ibm_is_security_group.sg1.id
    direction = "outbound"
    remote    = "0.0.0.0/0"

}

resource "ibm_is_security_group_rule" "internet_access_in" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"

}

resource "ibm_is_security_group_rule" "ingress_node_exporter" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9100
        port_max = 9100
    }
}

resource "ibm_is_security_group_rule" "ingress_http" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9092
        port_max = 9092
    }
}

resource "ibm_is_security_group_rule" "ingress_http_rpc" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 33145
        port_max = 33145
    }
}

resource "ibm_is_security_group_rule" "ingress_http_admin" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9644
        port_max = 9644
    }
}

resource "ibm_is_security_group_rule" "ingress_redpanda_proxy" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 8082
        port_max = 8082
    }
}

resource "ibm_is_security_group_rule" "ingress_grafana" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 3000
        port_max = 3000
    }
}

resource "ibm_is_security_group_rule" "ingress_prometheus" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9090
        port_max = 9090
    }
}

resource "ibm_is_security_group_rule" "ingress_kfk_broker" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 9091
        port_max = 9091
    }
}

resource "ibm_is_security_group_rule" "ingress_zk_client_port" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 2181
        port_max = 2181
    }
}

resource "ibm_is_security_group_rule" "ingress_zk_leader_port" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 3888
        port_max = 3888
    }
}

resource "ibm_is_security_group_rule" "ingress_zk_peer_port" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 2888
        port_max = 2888
    }
}

resource "ibm_is_security_group_rule" "ingress_kfk_sr" {
    group     = ibm_is_security_group.sg1.id
    direction = "inbound"
    remote    = "0.0.0.0/0"
    
    tcp {
        port_min = 8081
        port_max = 8081
    }
}


resource "ibm_is_public_gateway" "pgw1" {
  name  = "${local.BASENAME}-pgw1"
  vpc   = ibm_is_vpc.vpc.id
  resource_group = var.resource_group
  zone  = local.ZONE
}

resource "ibm_is_subnet" "subnet1" {
    name                     = "${local.BASENAME}-subnet1"
    vpc                      = ibm_is_vpc.vpc.id
    zone                     = local.ZONE
    total_ipv4_address_count = 256
    resource_group = var.resource_group
    public_gateway = ibm_is_public_gateway.pgw1.id
}

data "ibm_is_image" "ubuntu" {
    name = "ibm-ubuntu-20-04-3-minimal-amd64-1"
}

data "ibm_is_ssh_key" "ssh_key_id" {
    name = var.ssh_key
}

resource "ibm_is_instance" "vsi" {
    count   = var.number_of_instances
    name    = "${local.BASENAME}-rp-node-${count.index}"
    vpc     = ibm_is_vpc.vpc.id
    zone    = local.ZONE
    resource_group = var.resource_group
    keys    = [data.ibm_is_ssh_key.ssh_key_id.id]
    image   = data.ibm_is_image.ubuntu.id
    profile = "bx2d-4x16"
    

    primary_network_interface {
        subnet          = ibm_is_subnet.subnet1.id
        security_groups = [ibm_is_security_group.sg1.id]
    }
}

resource "ibm_is_instance_volume_attachment" "vol_attachment" {
  instance = ibm_is_instance.vsi[count.index].id
  count    = var.number_of_instances

  name                                = "data-vol-rp-node-${count.index}-att"
  capacity                            = 150
  delete_volume_on_attachment_delete  = true
  delete_volume_on_instance_delete    = true
  volume_name                         = "rp-node-${count.index}-vol"

  //User can configure timeouts
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

resource "ibm_is_floating_ip" "fip" {
    count = var.number_of_instances
    name   = "${local.BASENAME}-fip-${count.index}"
    target = ibm_is_instance.vsi[count.index].primary_network_interface[0].id
}

resource "ibm_is_instance" "vsi_monitoring" {
    count   = var.enable_monitoring ? 1 : 0
    name    = "${local.BASENAME}-monitoring-node"
    vpc     = ibm_is_vpc.vpc.id
    zone    = local.ZONE
    resource_group = var.resource_group
    keys    = [data.ibm_is_ssh_key.ssh_key_id.id]
    image   = data.ibm_is_image.ubuntu.id
    profile = "bx2d-4x16"
    

    primary_network_interface {
        subnet          = ibm_is_subnet.subnet1.id
        security_groups = [ibm_is_security_group.sg1.id]
    }
}

resource "ibm_is_instance_volume_attachment" "vol_attachment_monitoring" {
    count   = var.enable_monitoring ? 1 : 0
    instance = ibm_is_instance.vsi_monitoring[count.index].id
    name                                = "data-vol-monitoring-node-att"
    capacity                            = 150
    delete_volume_on_attachment_delete  = true
    delete_volume_on_instance_delete    = true
    volume_name                         = "monitoring-node-vol"

    //User can configure timeouts
    timeouts {
        create = "30m"
        update = "30m"
        delete = "30m"
    }
}

resource "ibm_is_floating_ip" "fip_monitoring" {
    name   = "${local.BASENAME}-fip-monitoring"
    target = ibm_is_instance.vsi_monitoring[0].primary_network_interface[0].id
    }

output "redpanda-ips" {
    value = ibm_is_floating_ip.fip.*.address
}

output "monitoring-ips" {
    value = ibm_is_floating_ip.fip_monitoring.*.address
}

resource "local_file" "hosts_ini" {
    content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips   = ibm_is_floating_ip.fip.*.address
      redpanda_private_ips  = ibm_is_instance.vsi[*].primary_network_interface[0].primary_ipv4_address
      monitor_public_ip     = var.enable_monitoring ? ibm_is_floating_ip.fip_monitoring.*.address[0] : ""
      monitor_private_ip    = var.enable_monitoring ? tolist(ibm_is_instance.vsi_monitoring[*].primary_network_interface[0].primary_ipv4_address)[0] : ""
      ssh_user              = var.ssh_username
      enable_monitoring     = var.enable_monitoring
      client_public_ips     = [""]
      client_private_ips     = [""]
    }
  )
  filename = "${path.module}/../hosts.ini"
}
