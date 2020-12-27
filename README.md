# Terraform and Ansible Deployment for Redpanda

Terraform and Ansible Scripts to easily provision a [Redpanda](https://vectorized.io)
cluster on AWS or GCP.

## Installation Requirements

* Install terraform in your preferred way https://www.terraform.io/downloads.html
* Install Ansible https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* `ansible-galaxy install -r ansible/requirements.yml` to gather ansible requirements

## Usage

### Optional Steps: Deploying the VMs

To use existing infrastructure, update the `hosts.ini` file with the appropriate 
information. Otherwise see the READMEs for the following cloud providers:

* [AWS](aws/readme.md)
* [GCP](gcp/readme.md)

### Required Steps: Deploying Redpanda

Before running these steps, verify that the `hosts.ini` file contains the
correct information for your infrastructure. This will be automatically
populated if using the terraform steps above.

1. `ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/provision-node.yml`

  Available Ansible variables:

  You can pass the following variables as `-e var=value`:

* `advertise_public_ips=false|true`: Configure Redpanda to advertise the
node's public IPs for client communication instead of private IPs.
This allows for using the cluster from outside its subnet.
**Note**: This is not recommended for production deployments, because it
means that your nodes will be public. Use it for testing only. Default `false`

2. Use rpk & standard Kafka tool to produce/consume from the Redpanda cluster
& access the Grafana installation on the monitor host.
