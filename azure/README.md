# Microsoft Azure Deployment

This Terraform module will deploy VMs on Microsoft Azure, with a security group that allows inbound traffic on ports used by Redpanda and monitoring tools.

## Prerequisites

1. Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
2. Login to obtain subscription and tenant information: `az login`

## Create cluster

1. `terraform init` to setup the working directory
2. `terraform apply` to create the Azure resources

## Supported configuration varibles

See `vars.tf` for a complete list:
- `region`: Azure Region where the Resource Group will exist (default: `Central US`)
- `vm_sku`: Azure VM SKU to use for the Redpanda nodes (default: `Standard_L8s_v3`)
- `vm_instances`: Number of Redpanda nodes to create (default: `3`)
- `vm_add_data_disk`: Attach a Premium_LRS data disk to each node? (default `false`)
- `vm_data_disk_gb`: Size of the Premium_LRS data disk in GiB (default `2048` P40)
- `client_vm_sku`: Azure VM SKU to use for the client node (default: `Standard_D2ds_v5`)
- `client_vm_instances`: Number of client nodes to create (default: `1`)
- `enable_monitoring`: Setup a Prometheus/Grafana instance? (default: `true`)
- `vm_image`: Source image reference for the VMs (default: `Canonical.0001-com-ubuntu-server-focal.20_04-lts.latest`)
- `admin_username`: Username for the local administrator on each VM (default: `adminpanda`)
- `public_key`: Public Key file used for authentication (default: `~/.ssh/id_rsa.pub`)
- `ha`: Whether to use a scale set to enable rack awareness (default: `false`). N.B. By default the Azure module uses an Azure Availability set to ensure that nodes do not have common failure points. Unfortunately with this approach you cannot introspect the fault domain for each instance and therefore we cannot enable rack awareness on Redpanda. By setting we can enable rack awareness in Redpanda (and this option will populate a rack attribute in the `hosts.ini`). 
- `zone`: Availability zone for instances to be deployed into (default: `null`).

Examples:
- `terraform apply -var vm_sku=Standard_L8s_v2 -var vm_instances=3 -var client_vm_instances=2 -auto-approve`
- `terraform apply -var vm_sku=Standard_F8s_v2 -var vm_add_data_disk=true -auto-approve`

Note that `terraform apply` will automatically generate an Ansible inventory file `../hosts.ini`.

## Recommended VM SKUs

Azure’s storage optimised [Lsv3-series](https://learn.microsoft.com/en-us/azure/virtual-machines/lsv3-series) VMs are recommended for maximum performance. These VMs include directly mapped local NVMe disks that provide high throughput, low latency IO for Redpanda and can be part of Flexible Scale Sets for High Availability configuration (note: [Lsv3-series](https://learn.microsoft.com/en-us/azure/virtual-machines/lsv3-series) can also be used, but not in a high availability configuration). 

There are some drawbacks to using Lsv2/LSv3; the NVMe disks are ephemeral so data stored in Redpanda is lost when the VM is stopped, and for Lsv2 the expected network bandwidth is relatively low for such highly spec'd machines. This may force the use of larger sizes for the additional network bandwidth rather than for the vCPU or memory.

For a persistent storage option consider using the compute optimised [Fsv2-series](https://docs.microsoft.com/en-us/azure/virtual-machines/fsv2-series) VMs with Premium SSD storage. These VMs have a higher than expected network bandwidth per vCPU than Lsv2, but the downside is that the SSDs are remote to the VM so performance will suffer from lower throughput and higher latency. This series also supports Flexible Scale Sets so can be used in an HA configuration.
