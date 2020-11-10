# GCP Deployment

This Terraform module will deploy VMs on GCP Compute Engine.

**Prerequisites:**
- An existing subnet to deploy the VMs into. The subnet's attached firewall should allow inbound traffic on ports 22, 3000, 8888, 8889, 9090, 9092, 9644 and 33145. This module adds the `rp-node` tag to the deployed VMs, which can be used as the target tag for the firewall rule.

After completing these steps, please follow the required steps in the [project readme](../README.md) to deploy Redpanda to the new VMs.

1. `terraform init`
2. `terraform apply` to create the resources on AWS.
    - Supported configuration variables (See `vars.tf`):
        - `region` (default: `us-west-1`): The region to deploy the infrastructure on.
        - `zone` (default: `a`): The region's zone to deploy the infrastructure on.
        - `subnet`: The name of an existing subnet to deploy the infrastructure on.
        - `nodes` (default: `1`): The number of nodes to base the cluster on. Keep in mind that one node is used as a monitoring node.
        - `disks` (default: `1`): The number of **local** disks to deploy on each machine
        - `image` (default: `ubuntu-os-cloud/ubuntu-1804-lts`): The OS image running on the VMs.
        - `machine_type` (default: `n2-standard-2`): The machine type.
        - `public_key_path`: Provide the path to the public key of the keypair used to access the nodes.
        - `ssh_user`: The ssh user. Must match the one in the public ssh key's comments.

  Example: `terraform apply -var nodes=3 -var subnet=redpanda-cluster-subnet -var public_key_path=~/.ssh/id_rsa.pub -var ssh_user=$USER`
