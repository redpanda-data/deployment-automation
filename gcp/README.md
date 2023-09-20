# GCP Deployment

This Terraform module will deploy VMs on GCP Compute Engine.

**Prerequisites:**

- An existing subnet to deploy the VMs into. The subnet's attached firewall should allow inbound traffic on ports `22`, `3000`, `8888`, `8889`, `9090`, `9092`, `9100`, `9644` and `33145`. This module adds the `rp-cluster` tag to the deployed VMs, which can be used as the target tag for the firewall rule.

- Set the desired GCP project by executing `gcloud projects list` and then `gcloud config set project <PROJECT_ID>`.

- The module assumes credentials for GCP have been configured using 
  [User Application Default Credentials](https://cloud.google.com/sdk/gcloud/reference/auth/application-default). This can be done by executing `gcloud auth application-default login`, after which a JSON file is generated that the Terraform GCP provider can automatically find. Consult the [GCP provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference) for other alternatives.

After completing these steps, please follow the required steps in the [project readme](../README.md) to deploy Redpanda to the new VMs.

1. `terraform init`
2. `terraform apply` to create the resources on AWS.
    - Supported configuration variables (See `vars.tf`):
        - `project_name` (required): The name of the project on GCP to use.
        - `subnet` (required): The name of an existing subnet to deploy the infrastructure on.
        - `region` (default: `us-west2`): The region to deploy the infrastructure on.
        - `zone` (default: `a`): The region's zone to deploy the infrastructure on.
        - `nodes` (default: `3`): The number of nodes to base the cluster on (Note that one additional node is added as a monitoring node).
        - `client_nodes` (default: `1`): The number of client nodes
        - `disks` (default: `1`): The number of **local** disks to deploy on each machine
        - `image` (default: `ubuntu-os-cloud/ubuntu-2004-lts`): The OS image running on the VMs.
        - `machine_type` (default: `n2-standard-2`): The machine type.
        - `public_key_path`: Provide the path to the public key of the keypair used to access the nodes.
        - `ssh_user`: The ssh user. Must match the one in the public ssh key's comments.
        - `ha`: Enable high availability mode. In this mode (which supports up to 8 nodes), instances will be deployed into a Compute Resource Policy with an availability domain for each node. N.B. GCP does not currently have a mode which allows you to knowingly co-locate specific nodes into a smaller number of availability domains (see [Google Issue 256993209](https://issuetracker.google.com/issues/256993209)). 

  We recommend putting all the variables you'd like to set as key=value pairs in a file named [redpanda.auto.tfvars](https://developer.hashicorp.com/terraform/language/values/variables#variable-definitions-tfvars-files) in this directory for convenience. However you can also set them at runtime using command line flags. 
  Example: `terraform apply -var nodes=3 -var project_name=myproject -var subnet=redpanda-cluster-subnet -var public_key_path=~/.ssh/id_rsa.pub -var ssh_user=$USER`
