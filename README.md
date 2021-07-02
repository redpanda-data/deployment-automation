# Terraform and Ansible Deployment for Redpanda

Terraform and Ansible Scripts to easily provision a [Redpanda](https://vectorized.io)
cluster on AWS or GCP.

## Installation Requirements

* Install terraform in your preferred way https://www.terraform.io/downloads.html
** On Mac OS X: `brew tap hashicorp/tap ; brew install hashicorp/tap/terraform`
* Install Ansible https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
** On Mac OS X: `brew install ansible`
* Depending on your system, you might need to install some python packages (e.g. `selinux` or `jmespath`). Ansible will throw an error with the expected python packages, both on local and remote machines.
** On Mac OS X, you need to install gnu-tar: `brew install gnu-tar`

### Gather Ansible requirements 
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
* `grafana_admin_pass=<password_here>`: Configure Grafana's admin user's password

2. Use rpk & standard Kafka tool to produce/consume from the Redpanda cluster
& access the Grafana installation on the monitor host.


## Troubleshooting

### On Mac OS X, Python unable to fork workers

If you see something like this:
> ok: [34.209.26.177] => {“changed”: false, “stat”: {“exists”: false}}
> objc[57889]: +[__NSCFConstantString initialize] may have been in progress in another thread when fork() was called.
> objc[57889]: +[__NSCFConstantString initialize] may have been in progress in another thread when fork() was called. We cannot safely call it or ignore it in the fork() child process. Crashing instead. Set a breakpoint on objc_initializeAfterForkError to debug.
> ERROR! A worker was found in a dead state
You might try resolving by setting an environment variable:
> export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
See:
https://stackoverflow.com/questions/50168647/multiprocessing-causes-python-to-crash-and-gives-an-error-may-have-been-in-progr

