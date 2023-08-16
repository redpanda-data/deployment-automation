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
ansible-galaxy install -r ./requirements.yml

# Run a Playbook
# You need to pick the correct playbook for you, in this case we picked provision-basic-cluster
ansible-playbook ansible/provision-basic-cluster.yml --private-key ~/.ssh/id_rsa
```

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
