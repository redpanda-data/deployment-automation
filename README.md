# Terraform and Ansible Deployment for Redpanda

[![Build status](https://badge.buildkite.com/b4528cf1604a18231c935663db15739e56d202dde6d7a2ec2a.svg)](https://buildkite.com/redpanda/deployment-automation)

Terraform and Ansible configuration to easily provision a [Redpanda](https://www.redpanda.com/) cluster on AWS, GCP,
Azure, or IBM.

# Goal of this project

1 command to a production cluster

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

## Usage

### Standing up VMs

You are welcome to stand up VMs your own way for running a Redpanda cluster, but if you'd like we support VM standup
with our [AWS Redpanda Cluster module](https://registry.terraform.io/modules/redpanda-data/redpanda-cluster/aws/latest).

Actually running terraform itself is fairly straightforward. For example if you want to create an AWS Redpanda Cluster,
you should review the [default variables](aws/main.tf) and change them to your liking.

Additional documetation for non-AWS terraform code is available here:

* [GCP](gcp/readme.md)
* [Azure](azure/README.md)
* [IBM Cloud](ibm/README.md)

```shell
export AWS_ACCESS_KEY_ID=<<<YOUR KEY ID>>>
export AWS_SECRET_ACCESS_KEY=<<<YOUR SECRET ACCESS KEY>>>

terraform apply --auto-approve
```

### Populating a Hosts File

Our terraform code will automatically supply you a hosts file, but if you aren't using it you'll need to generate one
for your own use.

The general format is

```text
[ redpanda ]
<<<INSTANCE PUBLIC IP>>> ansible_user=<<<SSH USER FOR ANSIBLE TO USE>>> ansible_become=True private_ip=<<<INSTANCE PRIVATE IP>>>
<<<INSTANCE PUBLIC IP>>> ansible_user=<<<SSH USER FOR ANSIBLE TO USE>>> ansible_become=True private_ip=<<<INSTANCE PRIVATE IP>>>
<<<INSTANCE PUBLIC IP>>> ansible_user=<<<SSH USER FOR ANSIBLE TO USE>>> ansible_become=True private_ip=<<<INSTANCE PRIVATE IP>>>

[ client ]
<<<INSTANCE PUBLIC IP>>> ansible_user=<<<SSH USER FOR ANSIBLE TO USE>>> ansible_become=True private_ip=<<<INSTANCE PRIVATE IP>>>

[ monitor ]
<<<INSTANCE PUBLIC IP>>> ansible_user=<<<SSH USER FOR ANSIBLE TO USE>>> ansible_become=True private_ip=<<<INSTANCE PRIVATE IP>>>
```

We also have some additional values that can be set on each instance in the [redpanda] group if you intend to use
features like rack awareness or tiered storage. Here's an example with tiered storage, but you can also set values like
rack or restart_node.

```text 
[redpanda]
<<<INSTANCE PUBLIC IP>>> ansible_user=<<<SSH USER FOR ANSIBLE TO USE>>> ansible_become=True private_ip=<<<INSTANCE PRIVATE IP>>> tiered_storage_bucket_name=<<<AWS BUCKET NAME TO USE FOR TIERED STORAGE>>> cloud_storage_region=<<<AWS REGION TO USE FOR TIERED STORAGE>>>
```

### Running a Playbook

Here is an example for how you can run one of our playbooks. You will want to make sure that ANSIBLE_COLLECTIONS_PATHS
and ANSIBLE_ROLES_PATH are correct for your setup.

Please note that if you use a particular playbook for creating a cluster you should use it for any subsequent
operations, for example upgrades.

```shell
#!/bin/bash
## from content root ##
## if you already have ANSIBLE_COLLECTIONS_PATH and ANSIBLE_ROLES_PATH don't set these
export ANSIBLE_COLLECTIONS_PATHS=${PWD}/artifacts/collections
export ANSIBLE_ROLES_PATH=${PWD}/artifacts/roles

## install collections and roles
ansible-galaxy install -r ./requirements.yml

## set path to a hosts.ini file with at minimum a [redpanda] section. you can also add a [client] and [monitor] section for additional features
export ANSIBLE_INVENTORY=$PWD/hosts.ini

ansible-playbook ansible/<<<PLAYBOOK NAME>>>.yml --private-key <<<YOUR PRIVATE KEY LOCATION>>>
```

### Additional Redpanda Values

You can pass the following variables as `-e var=value` when running ansible :

| Property                     | Default value                      | Description                                                                                                                                                                                                                                                                                               |
|------------------------------|------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `redpanda_organization`      | redpanda-test                      | Set this to identify your organization in the asset management system.                                                                                                                                                                                                                                    |
| `redpanda_cluster_id`        | redpanda                           | Helps identify the cluster.                                                                                                                                                                                                                                                                               |
| `advertise_public_ips`       | `false`                            | Configure Redpanda to advertise the node's public IPs for client communication instead of private IPs. This allows for using the cluster from outside its subnet. **Note**: This is not recommended for production deployments, because it means that your nodes will be public. Use it for testing only. |
| `grafana_admin_pass`         | enter_your_secure_password         | Configure Grafana's admin user's password                                                                                                                                                                                                                                                                 |
| `ephemeral_disk`             | `false`                            | Enable filesystem check for attached disk, useful when using attached disks in instances with ephemeral OS disks (i.e Azure L Series). This allows a filesystem repair at boot time and ensures that the drive is remounted automatically after a reboot.                                                 |
| `redpanda_mode`              | production                         | [Enables hardware optimization](https://docs.redpanda.com/docs/platform/deployment/production-deployment/#set-redpanda-production-mode)                                                                                                                                                                   |                                                                                                                                                                  |                                                                                                            
| `redpanda_admin_api_port`    | 9644                               |                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                                                                                                                                                          |                                                                                                                  
| `redpanda_kafka_port`        | 9092                               |                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                  |                                                                                                                  
| `redpanda_rpc_port`          | 33145                              |                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                |                                                                                                                 
| `redpanda_use_staging_repo`  | `false`                            | Enables access to unstable builds                                                                                                                                                                                                                                                                         |                                                                                                                                                                                                                                                                        | False                                                                                                                                                                                                                                                                                                     
| `redpanda_version`           | latest                             | For example 22.2.2-1 or 22.3.1~rc1-1. If this value is set then the package will be upgraded if the installed version is lower than what has been specified.                                                                                                                                              |
| `redpanda_rpk_opts`          |                                    | Command line options to be passed to instances where `rpk` is used on the playbook, for example superuser credentials may be specified as "--user myuser --password mypassword"                                                                                                                           |
| `redpanda_install_status`    | present                            | If redpanda_version is set to latest, changing redpanda_install_status to latest will effect an upgrade, otherwise the currently installed version will remain                                                                                                                                            |
| `redpanda_data_directory`    | /var/lib/redpanda/data             | Path where Redpanda will keep its data                                                                                                                                                                                                                                                                    |
| `redpanda_key_file`          | /etc/redpanda/certs/node.key       | TLS: path to private key                                                                                                                                                                                                                                                                                  |
| `redpanda_cert_file`         | /etc/redpanda/certs/node.crt       | TLS: path to signed certificate                                                                                                                                                                                                                                                                           |
| `redpanda_truststore_file`   | /etc/redpanda/certs/truststore.pem | TLS: path to truststore                                                                                                                                                                                                                                                                                   |
| `tls`                        | false                              | Set to true to configure Redpanda to use TLS. This can be set on a per-node basis, although this may lead to errors configuring `rpk`                                                                                                                                                                     |
| `skip_node`                  | false                              | Per-node config to prevent the Redpanda_broker role being applied to this specific node. Use carefully when adding new nodes to avoid existing nodes from being reconfigured.                                                                                                                             |
| `restart_node`               | false                              | Per-node config to prevent Redpanda brokers from being restarted after updating. Use with care because this can cause `rpk` to be reconfigured but the node not be restarted and therefore be in an inconsistent state.                                                                                   |
| `rack`                       | `undefined`                        | Per-node config to enable rack awareness. N.B. Rack awareness will be enabled cluster-wide if at least one node has the `rack` variable set.                                                                                                                                                              |
| `tiered_storage_bucket_name` |                                    | Set bucket name to enable tiered storage                                                                                                                                                                                                                                                                  
| `aws_region`                 |                                    | The region to be used if tiered storage is enabled                                                                                                                                                                                                                                                        

### Additional Custom Config

You can also specify any available Redpanda configuration value (or set of values) by passing a JSON dictionary as an
Ansible extra-var. These values will be spliced with the calculated configuration and only override those values that
you specify.
There are two sub-dictionaries that you can specify, `redpanda.cluster` and `redpanda.node`. Check the Redpanda docs for
the available [Cluster configuration properties](https://docs.redpanda.com/docs/platform/reference/cluster-properties/)
and [Node configuration properties](https://docs.redpanda.com/docs/platform/reference/node-properties/).

Example below, note that adding whitespace breaks configuration merging. Please ensure you do not add whitespace!

```shell
export JSONDATA='{"cluster":{"auto_create_topics_enabled":"true"},"node":{"developer_mode":"false"}}'
ansible-playbook ansible/<<<PLAYBOOK NAME>>>.yml --private-key artifacts/testkey -e redpanda="${JSONDATA}"
```

2. Use `rpk` & standard Kafka tools to produce/consume from the Redpanda cluster & access the Grafana installation on
   the monitor host.

* The Grafana URL is http://&lt;grafana host&gt;:3000/login

## Migrate to the AWS Module

We previously had AWS code delivered as simple in place terraform code, but have now converted to a module. If you were
previously using our AWS code and want to migrate you'll need to take the following steps:

* download the new config
* run the following

```shell
terraform state list | while read -r line ; do terraform state mv "$line" "module.redpanda-cluster.$line"; done
```

You can also do the same by hand.

## Configure Grafana

To deploy a grafana node, ensure that you have a [monitor] section in your hosts file. You should then be able to run
the deploy-prometheus-grafana.yml playbook

```shell
ansible-playbook ansible/deploy-prometheus-grafana.yml \
-i hosts.ini \
--private-key '<path to a private key with ssh access to the hosts>'
```

## Building the Cluster with TLS Enabled

There are two options for configuring TLS. The first option would be to use externally provided and signed
certificates (possibly via a corporately provided Certmonger) and run the `provision-tls-cluster` playbook but
specifying the cert locations on new hosts. You can either pass the vars in the command line or edit the file and pass
them there.

You should also consider whether you want public access to the kafka_api and admin_api endpoints.

For example:

```shell
ansible-playbook ansible/provision-tls-cluster.yml \
-i hosts.ini \
--private-key '<path to a private key with ssh access to the hosts>' \
--extra-vars create_demo_certs=false \
--extra-vars advertise_public_ips=false \ 
--extra-vars handle_certs=false \
--extra-vars redpanda_truststore_file='<path to ca.crt file>' 
```

The second option is to deploy a local certificate authority using the playbooks provided below and generating private
keys and signed certificates. For this approach, follow the steps below.

NOTE THAT THIS SHOULD ONLY BE DONE FOR TESTING PURPOSES! Use an actual signed cert from a valid CA for production!

```shell
ansible-playbook ansible/provision-tiered-storage-cluster.yml \
-i hosts.ini \
--private-key '<path to a private key with ssh access to the hosts>'
```

## Adding Nodes to an existing cluster

To add nodes to a cluster you must add them to the hosts file and run the relevant playbook again. You may
add `skip_node=true` to the existing hosts to avoid the playbooks being re-run on existing nodes.

## Upgrading a cluster

The playbook is designed to be idempotent so should be suitable for running as part of a CI/CD pipeline or via Ansible
Tower.
Upgrade support is built in and the playbook is capable of upgrading the packages and then
performing [a rolling upgrade](https://docs.redpanda.com/docs/manage/cluster-maintenance/rolling-upgrade/) across the
cluster.

> Note: Please be aware that any changes that have been made to cluster or node configuration parameters outside of the
> playbook may be overwritten by this procedure, and therefore these settings should be incorporated as part of the
> provided `--extra-vars` (for example `--extra-vars=enable_tls=true`).

There are two ways of enacting an upgrade on a cluster:

1. By running the playbook with a specific target version. If the target version is higher than the currently installed
   version then the cluster will be upgraded and restarted automatically:

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa ansible/<<<PLAYBOOK NAME>>>.yml -i hosts.ini -e redpanda_version=22.3.10-1 
```

2. By default the playbook will select the latest version of the Redpanda packages, but an upgrade will only be enacted
   if the `redpanda_install_status` variable is set to `latest`:

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa ansible/<<<PLAYBOOK NAME>>>.yml -i hosts.ini -e redpanda_install_status=latest 
```

It is also possible to upgrade clusters where SASL authentication has been turned on. For this, you will need to
additionally specify the `redpanda_rpk_opts` variable to include to username and password or a superuser or
appropriately privileged user. An example follows:

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa ansible/<<<PLAYBOOK NAME>>>.yml -i hosts.ini --extra-vars=redpanda_install_status=latest --extra-vars "{
\"redpanda_rpk_opts\": \"--user ${MY_USER} --password ${MY_USER_PASSWORD}\"
}"
```

Similarly, you can put the `redpanda_rpk_opts` into a yaml
file [protected with Ansible vault](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html#creating-encrypted-files).

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa ansible/<<<PLAYBOOK NAME>>>.yml -i hosts.ini --extra-vars=redpanda_install_status=latest --extra-vars @vault-file.yml --ask-vault-pass
```

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
