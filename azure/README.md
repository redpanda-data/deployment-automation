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
- `region`: Azure Region where the Resource Group will exist (default: `North Europe`)
- `vm_sku`: Azure VM SKU to use for the Redpanda nodes (default: `Standard_L8s_v2`)
- `vm_instances`: Number of Redpanda nodes to create (default: `3`)
- `vm_add_data_disk`: Attach a Premium_LRS data disk to each node? (default `false`)
- `vm_data_disk_gb`: Size of the Premium_LRS data disk in GiB (default `512` P20)
- `client_vm_sku`: Azure VM SKU to use for the client node (default: `Standard_D2s_v4`)
- `client_vm_instances`: Number of client nodes to create (default: `1`)
- `enable_monitoring`: Setup a Prometheus/Grafana instance? (default: `true`)
- `vm_image`: Source image reference for the VMs (default: `Canonical.0001-com-ubuntu-server-focal.20_04-lts.latest`)
- `admin_username`: Username for the local administrator on each VM (default: `adminpanda`)
- `public_key`: Public Key file used for authentication (default: `~/.ssh/id_rsa.pub`)

Examples:
- `terraform apply -var vm_sku=Standard_L8s_v2 -var vm_instances=3 -var client_vm_instances=2 -auto-approve`
- `terraform apply -var vm_sku=Standard_F8s_v2 -var vm_add_data_disk=true -auto-approve`

Note that `terraform apply` will automatically generate an Ansible inventory file `../hosts.ini`.

## Recommended VM SKUs

Azure’s storage optimised [Lsv2-series](https://docs.microsoft.com/en-us/azure/virtual-machines/lsv2-series) VMs are recommended for maximum performance. These VMs include directly mapped local NVMe disks that provide high throughput, low latency IO for Redpanda. 

There are some drawbacks to using Lsv2; the NVMe disks are ephemeral so data stored in Redpanda is lost when the VM is stopped, and the expected network bandwidth is relatively low for such highly specced machines. This may force the use of larger sizes for the additional network bandwidth rather than for the vCPU or memory.

For a persistent storage option consider using the compute optimised [Fsv2-series](https://docs.microsoft.com/en-us/azure/virtual-machines/fsv2-series) VMs with Premium SSD storage. These VMs have a higher expected network bandwidth per vCPU than Lsv2, but the downside is that the SSDs are remote to the VM so performance will suffer from lower throughput and higher latency.
