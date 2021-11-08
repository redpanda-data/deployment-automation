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
- `vm_image`: Source image reference for the VMs (default: `Canonical.UbuntuServer.18.04-LTS.latest`)
- `admin_username`: Username for the local administrator on each VM (default: `adminpanda`)
- `public_key`: Public Key file used for authentication (default: `~/.ssh/id_rsa.pub`)

Examples:
- `terraform apply -var vm_sku=Standard_L8s_v2 -var vm_instances=3 -var client_vm_instances=2`
- `terraform apply -var vm_sku=Standard_D8ds_v4 -var vm_add_data_disk=true`

## Recommended VM SKUs

- Best overall performance: [Lsv2-series](https://docs.microsoft.com/en-us/azure/virtual-machines/lsv2-series). Storage optimized with directly mapped local NVMe drives
- Best persistent storage: [Ddsv4-series](https://docs.microsoft.com/en-us/azure/virtual-machines/ddv4-ddsv4-series#ddsv4-series). General purpose with support for [Ultra SSD storage](https://docs.microsoft.com/en-us/azure/virtual-machines/disks-types#ultra-disks)
- Cost effective persistent storage: [M-series](https://docs.microsoft.com/en-us/azure/virtual-machines/m-series). Supports [Write Accelerator](https://docs.microsoft.com/en-us/azure/virtual-machines/how-to-enable-write-accelerator) on Premium SSD storage

## Format and mount data disks

The Redpanda VMs are created with a managed disk for better performance. Azure attaches the managed disk to the VM, but it isn't formatted and mounted. When the resources have been created the following steps needs to be run on each Redpanda VM:

```shell
# SSH into the VM
ssh -i ~/.ssh/id_rsa adminpanda@<public IP address>
# Find the disk (e.g. `sdb`)
lsblk -o NAME,HCTL,SIZE,MOUNTPOINT | grep -i "sd"
# Format the disk using XFS
sudo parted /dev/sdc --script mklabel gpt mkpart xfspart xfs 0% 100%
sudo mkfs.xfs /dev/sdc1
sudo partprobe /dev/sdc1
# Mount the disk
sudo mkdir /mnt/vectorized
sudo mount /dev/sdc1 /mnt/vectorized

# (Optional) Persist the mount
# Find the UUID of the drive
sudo blkid
# Add the drive to /etc/fstab
sudo vim /etc/fstab
UUID=8a63cd02-acab-4f5f-aacb-3f9839181873    /mnt/vectorized    xfs    defaults,nofail    1    2
```

Reference: [Add a disk to a Linux VM](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/add-disk)
