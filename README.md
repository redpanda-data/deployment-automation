# Terraform and Ansible Deployment for Redpanda

Terraform and Ansible Scripts to easily provision a [Redpanda](https://vectorized.io)
cluster on AWS or GCP.

## Installation Pre-Requisites

* Install terraform in your preferred way https://www.terraform.io/downloads.html
* Install Ansible https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* Depending on your system, you might need to install some python packages (e.g. `selinux` or `jmespath`). Ansible will throw an error with the expected python packages, both on local and remote machines.
* `ansible-galaxy install -r ansible/requirements.yml` to gather ansible requirements

### On Mac OS X:
You can use brew to install the prerequisites. You will also need to install gnu-tar:
```
 brew tap hashicorp/tap
 brew install hashicorp/tap/terraform
 brew install ansible
 brew install gnu-tar
 ansible-galaxy install -r ansible/requirements.yml
```


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
* The Grafana URL is http://<grafana host>:3000/login


## Configure TLS

### Optional: Create a Local Certificate Authority

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/tls/create-ca.yml`

This creates a CA, with data in `ansible/playbook/tls/ca`. This only needs to be done once on your local machine (unless you blow the CA directory away).

### Generate keypairs and CSRs

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/tls/generate-csrs.yml`

This will generate a keypair and a Certificate Signing Request, and collect the CSRs in the `ansible/playbook/tls/certs` directory. You can
use your own CA to issue certificates, or use the local CA that we created in the first step.

### Optional: Issue certificates with the local CA

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/tls/issue-certs.yml`

This will put issued certificates in `ansible/playbook/tls/certs`.

### Install certificates, configure RedPanda, and restart

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/tls/install-certs.yml`

## Troubleshooting

### On Mac OS X, Python unable to fork workers

If you see something like this:
```
ok: [34.209.26.177] => {“changed”: false, “stat”: {“exists”: false}}
objc[57889]: +[__NSCFConstantString initialize] may have been in progress in another thread when fork() was called.
objc[57889]: +[__NSCFConstantString initialize] may have been in progress in another thread when fork() was called. We cannot safely call it or ignore it in the fork() child process. Crashing instead. Set a breakpoint on objc_initializeAfterForkError to debug.
ERROR! A worker was found in a dead state
```

You might try resolving by setting an environment variable:
`export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`

See: https://stackoverflow.com/questions/50168647/multiprocessing-causes-python-to-crash-and-gives-an-error-may-have-been-in-progr

