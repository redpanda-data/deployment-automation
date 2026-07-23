# Terraform and Ansible Deployment for Redpanda

[![Build status](https://badge.buildkite.com/b4528cf1604a18231c935663db15739e56d202dde6d7a2ec2a.svg)](https://buildkite.com/redpanda/deployment-automation)

Terraform and Ansible configuration to easily provision a [Redpanda](https://www.redpanda.com/) cluster on AWS, GCP,
Azure, or IBM.

## Installation Prerequisites

Here are some prerequisites you'll need to install to run the content in this repo. You can also choose to use our
Dockerfile_UBUNTU dockerfile to build a local client if you'd rather not install terraform and
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
export ANSIBLE_COLLECTIONS_PATH=${PWD}/artifacts/collections
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
ansible-galaxy collection install -r $PWD/requirements.yml --force -p $ANSIBLE_COLLECTIONS_PATH
ansible-galaxy role install -r $PWD/requirements.yml --force -p $ANSIBLE_ROLES_PATH

# Run a Playbook
# You need to pick the correct playbook for you, in this case we picked provision-cluster
ansible-playbook ansible/provision-cluster.yml --private-key ~/.ssh/id_rsa

# If you want Redpanda Console and our implementation of Prometheus and Grafana you will need to run the following
ansible-playbook ansible/deploy-monitor.yml --private-key ~/.ssh/id_rsa
ansible-playbook ansible/deploy-console.yml --private-key ~/.ssh/id_rsa
```

The playbooks can all be run in any order. However they are designed with the assumption that you will run only either the TLS or non TLS playbooks, not both. Currently we do not support converting a cluster from non-TLS to TLS or vice versa.

## Running tests with Task

CI workflows are driven by [Task](https://taskfile.dev). Each `ci:*` task runs a full
deployment end-to-end — provision, converge, assert, tear down:

```shell
task ci:aws:rp            # basic AWS cluster upgrade test
task ci:aws:rp:tiered     # tiered storage over TLS (needs REDPANDA_LICENSE)
```

Test against a collection branch or version without editing requirements.yml:

```shell
CANDIDATE_COLLECTION_REF="git+https://github.com/redpanda-data/redpanda-ansible-collection.git,my-branch" task ci:aws:rp
```

Run `task --list` to see the rest. See [`docs/COLLECTION_UPGRADE_TEST.md`](docs/COLLECTION_UPGRADE_TEST.md) for what the upgrade lanes do.

## Additional Documentation

More information on consuming this collection
is [available here](https://docs.redpanda.com/docs/deploy/deployment-option/self-hosted/manual/production/production-deployment-automation/)
in our official documentation. See also [`docs/COLLECTION_UPGRADE_TEST.md`](docs/COLLECTION_UPGRADE_TEST.md) (upgrade-test harness) and [`docs/CONNECT.md`](docs/CONNECT.md) (Redpanda Connect).

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

For `task` runs, set `CANDIDATE_COLLECTION_REF` instead of editing requirements.yml (see [Running tests with Task](#running-tests-with-task)). It takes a git branch (`git+<url>,<branch>`) or a Galaxy version (`redpanda.cluster:0.12.0`).

For a manual `ansible-galaxy` run, change the redpanda.cluster entry in your requirements.yml to:

```yaml
  - name: https://github.com/redpanda-data/redpanda-ansible-collection.git
    type: git
    version: <<<YOUR BRANCH NAME>>>
```

### linting

CI enforces `ansible-lint` and `terraform fmt` on PRs (GitHub Actions). Run
`ansible-lint -c .ansible-lint` locally before pushing.

## Ansible Linter Skip List Whys and Wherefores

A lot of effort to bring the linter and IDE into alignment without meaningful improvement in readability, outcomes or
correctness.

- jinja[spacing]
- yaml[brackets]
- yaml[line-length]

Breaks the play because intermediate commands in the pipe return nonzero (but irrelevant) error codes

- risky-shell-pipe 
