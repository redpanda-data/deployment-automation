# AWS Deployment

This Terraform module will deploy VMs on AWS EC2, with a security group which allows inbound traffic on ports used by Redpanda and monitoring tools.

After completing these steps, please follow the required steps in the [project readme](../README.md) to deploy Redpanda to the new VMs.

1. Create AWS secret keys and provide them to terraform https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables
2. `terraform init`
3. `terraform apply` to create the resources on AWS.
    * Supported configuration variables (See `vars.tf`):
        * `aws_region`: The AWS region to deploy the infrastructure on. Default: `us-west-2`.
        * `nodes`: The number of nodes to base the cluster on. Default: `1`.
        * `enable_monitoring`: Will create a prometheus/grafana instance to be used for monitoring the cluster. Default: `true`.
        * `instance_type`: The instance to run redpanda on. Default: `i3.8xlarge`.
        * `public_key_path`: Provide the path to the public key of the keypair used to access the nodes. Default: `~/.ssh/id_rsa.pub`
        * `distro`: Linux distribution to install (this settings affects the below variables). Default: `ubuntu-focal`
        * `distro_ami`: AWS AMI to use for each available distribution.
        These have to be changed with according to the chosen AWS region.
        * `distro_ssh_user`: User used to ssh into the created EC2 instances.

  Example: `terraform apply -var instance_type i3.large -var nodes 3`
