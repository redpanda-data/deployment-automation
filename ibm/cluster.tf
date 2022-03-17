locals {
    BASENAME = var.base_name
    ZONE =  var.zone
}

resource "ibm_is_vpc" "vpc" {
    name = "${local.BASENAME}-vpc"
    resource_group = var.resource_group
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
        subnet          = ibm_is_subnet.subnet.id
        security_groups = [ibm_is_security_group.sg.id]
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
        subnet          = ibm_is_subnet.subnet.id
        security_groups = [ibm_is_security_group.sg.id]
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