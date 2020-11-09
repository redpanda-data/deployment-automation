# Redpanda-provision

Utilities to easily provision a [Redpanda](https://vectorized.io) cluster on AWS.

Terraform & Ansible are used to create and manage the nodes and deploy the application.

## Installation Requirements

* Install terraform in your preferred way https://www.terraform.io/downloads.html
* Install Ansible https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* `ansible-galaxy install -r ansible/requirements.yml` to gather ansible requirements

## Usage

### Optional Steps: 1-3

Steps 1-3 are only needed to create new EC2 instances to deploy the redpanda cluster on.
If already created infrastructure is going to be used, they can safely be skipped but you will need to update the `hosts.ini` file with your specific information.

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

### Required Steps: 4-5  

Before running these steps, verify that the `hosts.ini` file contains the correct information for your infrastructure. This will be automatically populated if using the terraform steps above.
        
4. `ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/provision-node.yml -e redpanda_packagecloud_token=<your_token_here>

5. Use rpk & standard kafka tool to produce/consume from the redpanda cluster & access the grafana installation on the monitor host.
