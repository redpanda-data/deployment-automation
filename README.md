# Terraform and Ansible Deployment for Redpanda

[![Build status](https://badge.buildkite.com/b4528cf1604a18231c935663db15739e56d202dde6d7a2ec2a.svg)](https://buildkite.com/redpanda/deployment-automation)

Terraform and Ansible configuration to easily provision a [Redpanda](https://www.redpanda.com/) cluster on AWS, GCP,
Azure, or IBM.

## Installation Prerequisites

Here are some prerequisites you'll need to install to run the content in this repo. You can also choose to use our
Dockerfile_FEDORA or Dockerfile_UBUNTU dockerfiles to build a local client if you'd rather not install terraform and
ansible on your machine.

* Install Terraform: https://www.terraform.io/downloads.html
* Install Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* Depending on your system, you might need to install some python packages (e.g. `selinux` or `jmespath`). Ansible will
  throw an error with the expected python packages, both on local and remote machines.

### On Mac OS X:

You can use brew to install the prerequisites. You will also need to install gnu-tar:

```commandline
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install ansible
brew install gnu-tar
```

## Basic Usage:

```shell
# Set required ansible variables
export CLOUD_PROVIDER=aws
export ANSIBLE_COLLECTIONS_PATHS=${PWD}/artifacts/collections
export ANSIBLE_ROLES_PATH=${PWD}/artifacts/roles
export ANSIBLE_INVENTORY=${PWD}/${CLOUD_PROVIDER}/hosts.ini

# Assumes default private and public key names, if these aren't correct for you set them to the correct values

# Deploy VM
# ASSUMES YOU HAVE A DEFAULT VPC, if you don't, create one and set vpc_id and subnet_id
cd $CLOUD_PROVIDER
terraform init
terraform apply --auto-approve -var='public_key_path=~/.ssh/id_rsa.pub' -var='deployment_prefix=go-rp'
cd ..


# Install collections and roles
export $ANSIBLE_COLLECTIONS_PATH=$PWD/artifacts/collections
export $ANSIBLE_ROLES_PATH=$PWD/artifacts/roles
ansible-galaxy collection install -r $PWD/requirements.yml --force -p $ANSIBLE_COLLECTIONS_PATH
ansible-galaxy role install -r $PWD/requirements.yml --force -p $ANSIBLE_ROLES_PATH

# Run a Playbook
# You need to pick the correct playbook for you, in this case we picked provision-cluster
ansible-playbook ansible/provision-cluster.yml --private-key ~/.ssh/id_rsa

# If you want Redpanda Console and our implementation of Prometheus and Grafana you will need to run the following
ansible-playbook ansible/deploy-monitor.yml --private-key ~/.ssh/id_rsa
ansible-playbook ansible/deploy-client.yml --private-key ~/.ssh/id_rsa
```

The playbooks can all be run in any order. However they are designed with the assumption that you will run only either the TLS or non TLS playbooks, not both. Currently we do not support converting a cluster from non-TLS to TLS or vice versa.

## Additional Documentation

More information on consuming this collection
is [available here](https://docs.redpanda.com/docs/deploy/deployment-option/self-hosted/manual/production/production-deployment-automation/)
in our official documentation.

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

### Ansible Collection Caching Issues

If you're experiencing issues where Ansible is using outdated versions of collections (e.g., local changes to the `redpanda-ansible-collection` are not being picked up), this is likely due to multiple cached versions of collections in different locations.

**Symptoms:**
- Local changes to collection roles/tasks are not reflected in playbook execution
- Debug tasks or modifications don't appear in ansible-playbook output
- Role behavior doesn't match your local code changes

**Root Cause:**
Ansible searches for collections in this priority order:
1. Playbook-adjacent `collections/` directory
2. `ANSIBLE_COLLECTIONS_PATH` (your local artifacts)
3. `~/.ansible/collections/` (user cache) ⚠️ **Common problem source**
4. System paths (`/usr/share/ansible/collections`)

**Solutions:**

**Option 1: Clear Caches and Set Environment Variables (Recommended)**
```bash
# Clear old cached versions
rm -rf ~/.ansible/collections/ansible_collections/redpanda
rm -rf ./gcp/artifacts/collections
rm -rf ./*/artifacts/collections  # Clear any cloud-specific caches

# Set environment variables (add to ~/.bashrc for persistence)
export ANSIBLE_COLLECTIONS_PATH=${PWD}/artifacts/collections
export ANSIBLE_ROLES_PATH=${PWD}/artifacts/roles

# Reinstall collections
ansible-galaxy collection install -r requirements.yml --force -p ./artifacts/collections

# Run playbooks
ansible-playbook ansible/operation-configure-logging.yml
```

**Option 2: Use Inline Environment Variables**
```bash
ANSIBLE_COLLECTIONS_PATH=${PWD}/artifacts/collections ANSIBLE_ROLES_PATH=${PWD}/artifacts/roles ansible-playbook ansible/operation-configure-logging.yml
```

**Option 3: Create a Cleanup Script**
```bash
#!/bin/bash
# cleanup-ansible-cache.sh
echo "Cleaning ansible caches..."
rm -rf ~/.ansible/collections/ansible_collections/redpanda
rm -rf ./gcp/artifacts/collections
rm -rf ./aws/artifacts/collections
rm -rf ./azure/artifacts/collections
rm -rf ./ibm/artifacts/collections
echo "Caches cleared!"
```

**Option 4: Use ansible.cfg Configuration**
Modify your `ansible.cfg` to prioritize local collections:
```ini
[defaults]
collections_paths = ./artifacts/collections:~/.ansible/collections:/usr/share/ansible/collections
roles_path = ./artifacts/roles:~/.ansible/roles:/usr/share/ansible/roles
```

**Prevention:**
- Always set `ANSIBLE_COLLECTIONS_PATH` and `ANSIBLE_ROLES_PATH` environment variables before development
- Use `--force` flag when installing collections during development
- Clear caches when switching between different versions of collections

## Contribution Guide

### testing with a specific branch of redpanda-ansible-collection

Change the redpanda.cluster entry in your requirements.yml file to the following:

```yaml
  - name: https://github.com/redpanda-data/redpanda-ansible-collection.git
    type: git
    version: <<<YOUR BRANCH NAME>>>
```

### pre-commit

We use pre-commit to ensure good code health on this repo. To install
pre-commit [check the docs here](https://pre-commit.com/#install). The basic idea is that you'll have a fairly
comprehensive checkup happen on each commit, guaranteeing that everything will be properly formatted and validated. You
may also need to install some pre-requisite tools for pre-commit to work correctly. At the time of writing this
includes:

* [ansible-lint](https://ansible-lint.readthedocs.io/installing/#installing-from-source-code)
* [tflint](https://github.com/terraform-linters/tflint#installation)

## Ansible Linter Skip List Whys and Wherefores

A lot of effort to bring the linter and IDE into alignment without meaningful improvement in readability, outcomes or
correctness.

- jinja[spacing]
- yaml[brackets]
- yaml[line-length]

Breaks the play because intermediate commands in the pipe return nonzero (but irrelevant) error codes

- risky-shell-pipe 
