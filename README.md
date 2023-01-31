# Terraform and Ansible Deployment for Redpanda

Terraform and Ansible configuration to easily provision a [Redpanda](https://www.redpanda.com/) cluster on AWS, GCP, Azure, or IBM.

# Goal of this project

1 command to a production cluster

## Installation Prerequisites

* Install Terraform in your preferred way: https://www.terraform.io/downloads.html
* Install Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* Depending on your system, you might need to install some python packages (e.g. `selinux` or `jmespath`). Ansible will throw an error with the expected python packages, both on local and remote machines.
* `ansible-galaxy install -r ansible/requirements.yml` to gather ansible requirements

### On Mac OS X:
You can use brew to install the prerequisites. You will also need to install gnu-tar:
```commandline
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install ansible
brew install gnu-tar
ansible-galaxy install -r ansible/requirements.yml
```

## Usage

### Optional Steps: Deploying the VMs

To use existing infrastructure, update the `hosts.ini` file with the appropriate information. Otherwise see the READMEs for the following cloud providers:

* [AWS](aws/readme.md)
* [GCP](gcp/readme.md)
* [Azure](azure/README.md)
* [IBM Cloud](ibm/README.md)

### Required Steps: Deploying Redpanda

> Note: This playbook is designed to be run repeatedly against a running cluster however be aware that it will cause a rolling restart of the cluster to occur. If you do not want the cluster to restart you can specify `restart_node=false`either globally (as --extra-vars, or on a host-by-host basis in the `hosts.ini` file). If you make changes to the node config and do not perform a restart then you may leave your `rpk` config (and this may inhibit subsequent executions of the playbook). If you re-run the playbook it will overwrite any configurations with those specified in the playbook, so care should be taken to ensure that the playbook contains any desired configuration (for example, if you have enabled TLS on your cluster, any subsequent runs of `provision-node` should be made with `-e tls=true` otherwise the playbook will disable TLS).

Before running these steps, verify that the `hosts.ini` file contains the correct information for your infrastructure. This will be automatically populated if using the terraform steps above.


1. `ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/provision-node.yml`

Available Ansible variables:

You can pass the following variables as `-e var=value`:

| Property                    | Default value                      | Description                                                                                                                                                                                                                                                                                               |
|-----------------------------|------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
 | `redpanda_organization`     | redpanda-test                      | Set this to identify your organization in the asset management system.                                                                                                                                                                                                                                    |
| `redpanda_cluster_id`       | redpanda                           | Helps identify the cluster.                                                                                                                                                                                                                                                                               |
| `advertise_public_ips`      | `false`                            | Configure Redpanda to advertise the node's public IPs for client communication instead of private IPs. This allows for using the cluster from outside its subnet. **Note**: This is not recommended for production deployments, because it means that your nodes will be public. Use it for testing only. |
| `grafana_admin_pass`        | enter_your_secure_password         | Configure Grafana's admin user's password                                                                                                                                                                                                                                                                 |
| `ephemeral_disk`            | `false`                            | Enable filesystem check for attached disk, useful when using attached disks in instances with ephemeral OS disks (i.e Azure L Series). This allows a filesystem repair at boot time and ensures that the drive is remounted automatically after a reboot.                                                 |
| `redpanda_mode`             | production                         | [Enables hardware optimization](https://docs.redpanda.com/docs/platform/deployment/production-deployment/#set-redpanda-production-mode)                                                                                                                                                                   |                                                                                                                                                                  |                                                                                                            
| `redpanda_admin_api_port`   | 9644                               |                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                                                                                                                                                          |                                                                                                                  
| `redpanda_kafka_port`       | 9092                               |                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                  |                                                                                                                  
| `redpanda_rpc_port`         | 33145                              |                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                |                                                                                                                 
| `redpanda_use_staging_repo` | `false`                            | Enables access to unstable builds                                                                                                                                                                                                                                                                         |                                                                                                                                                                                                                                                                        | False                                                                                                                                                                                                                                                                                                     
| `redpanda_version`          | latest                             | For example 22.2.2-1 or 22.3.1~rc1-1. If this value is set then the package will be upgraded if the installed version is lower than what has been specified.                                                                                                                                              |
| `redpanda_install_status`   | present                            | If redpanda_version is set to latest, changing redpanda_install_status to latest will effect an upgrade, otherwise the currently installed version will remain                                                                                                                                            |
| `redpanda_data_directory`   | /var/lib/redpanda/data             | Path where Redpanda will keep its data                                                                                                                                                                                                                                                                    |
| `redpanda_key_file`         | /etc/redpanda/certs/node.key       | TLS: path to private key                                                                                                                                                                                                                                                                                  |
| `redpanda_cert_file`        | /etc/redpanda/certs/node.crt       | TLS: path to signed certificate                                                                                                                                                                                                                                                                           |
| `redpanda_truststore_file`  | /etc/redpanda/certs/truststore.pem | TLS: path to truststore                                                                                                                                                                                                                                                                                   |
| `tls`                       | false                              | Set to true to configure Redpanda to use TLS. This can be set on a per-node basis, although this may lead to errors configuring `rpk`                                                                                                                                                                     |
| `skip_node`                 | false                              | Per-node config to prevent the Redpanda_broker role being applied to this specific node. Use carefully when adding new nodes to avoid existing nodes from being reconfigured.                                                                                                                             |
| `restart_node`              | false                              | Per-node config to prevent Redpanda brokers from being restarted after updating. Use with care because this can cause `rpk` to be reconfigured but the node not be restarted and therefore be in an inconsistent state.                                                                                   |
| `rack`                      | `undefined`                        | Per-node config to enable rack awareness. N.B. Rack awareness will be enabled cluster-wide if at least one node has the `rack` variable set.                                                                                                                                                              |
| `tiered_storage_bucket_name`|                                    | Set bucket name to enable tiered storage
| `aws_region`                |                                    | The region to be used if tiered storage is enabled

You can also specify any available Redpanda configuration value (or set of values) by passing a JSON dictionary as an Ansible extra-var. These values will be spliced with the calculated configuration and only override those values that you specify.
There are two sub-dictionaries that you can specify, `redpanda.cluster` and `redpanda.node`. Check the Redpanda docs for the available [Cluster configuration properties](https://docs.redpanda.com/docs/platform/reference/cluster-properties/) and [Node configuration properties](https://docs.redpanda.com/docs/platform/reference/node-properties/).

An example overriding specific properties would be as follows:

```commandline
ansible-playbook ansible/playbooks/provision-node.yml -i hosts.ini --extra-vars '{
  "redpanda": {
    "cluster": {
      "auto_create_topics_enabled": "true"
    },
    "node": {
      "developer_mode": "false"
    }
  }
}'
```

2. Use `rpk` & standard Kafka tools to produce/consume from the Redpanda cluster & access the Grafana installation on the monitor host.
* The Grafana URL is http://&lt;grafana host&gt;:3000/login

## Configure TLS

There are two options for configuring TLS. The first option would be to use externally provided and signed certificates (possibly via a corporately provided Certmonger) and re-run the `provision_node` playbook but specifying the relevant locations and `tls=true`. For example:

```commandline
ansible-playbook ansible/playbooks/provision-node.yml -i hosts.ini --extra-vars redpanda_key_file='<path to key file>' --extra-vars redpanda_cert_file='<path to cert file>' --extra-vars redpanda_truststore_file='<path to truststore file>' --extra-vars tls=true
```

The second option is to deploy a private certificate authority using the playbooks provided below and generating private keys and signed certificates. For this approach, follow the steps below.

### Optional: Create a Local Certificate Authority

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/create-ca.yml`

This creates a CA, with data in `ansible/playbook/tls/ca`. This only needs to be done once on your local machine (unless you blow the CA directory away).

### Generate keypairs and CSRs

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/generate-csrs.yml`

This will generate a keypair and a Certificate Signing Request, and collect the CSRs in the `ansible/playbook/tls/certs` directory. You can use your own CA to issue certificates, or use the local CA that we created in the first step.

### Optional: Issue certificates with the local CA

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/issue-certs.yml`

This will put issued certificates in `ansible/playbook/tls/certs`.

If you need to re-issue certificates (perhaps because the original certificates expired) you can use the per-host (or global) flag `overwrite_certs=true`.

### Install certificates, configure RedPanda, and restart

If you need to re-issue certificates (perhaps because the original certificates expired) you can use the per-host (or global) flag `overwrite_certs=true`.

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/install-certs.yml`

## Adding Nodes to an existing cluster

The playbooks can be used to add nodes to an existing cluster however care is required to make sure that they playbooks are executed in the correct order. To add new nodes execute the playbooks in the following order:

1. Add the new host(s) to the `hosts.ini` file. You may add `skip_node=true` to the existing hosts to avoid the playbooks being re-run on those nodes.
2. `install-node-deps.yml` - this will set up the Prometheus node_exporter and install package dependencies.
3. `prepare-data-dir.yml` - this will create any RAID devices required and format devices as XFS. Note: This playbook looks for devices presented to the operating system as NVMe devices (which can include EBS volumes built on the Nitro System). You may replace this playbook with your own method of formatting devices and presenting disks.
4. If managing TLS with the Redpanda playbooks:
  1. `generate-csrs.yml` - will create private key and CSR and bring the CSR back to the Ansible host.
  2. If using the Redpanda provided CA: `issue-certs.yml` - signs the CSR and issues a certificate.
  3. `install-certs.yml` - Installs the certificate and also applies the `redpanda_broker` role to the cluster nodes. Note: This will install and start Redpanda (and restart any brokers that do not have `skip_node=true` set)
5. If `install-certs.yml` was not run in step iii above, you will need to run `provision-node.yml` which will install the `redpanda_broker` role onto any nodes without `skip_node=true` set. **Note: If TLS is enabled on the cluster, make sure that `-e tls=true` is set, otherwise this playbook will disable TLS across any nodes that don't have `skip_nodes=true` set.**

## Building a cluster with TLS enabled in one execution

A similar process can be used to build a cluster with TLS in one execution as to adding TLS nodes to an existing cluster:

1. Add the new host(s) to the `hosts.ini` file.
2. `install-node-deps.yml` - this will set up the Prometheus node_exporter and install package dependencies.
3. `prepare-data-dir.yml` - this will create any RAID devices required and format devices as XFS. Note: This playbook looks for devices presented to the operating system as NVMe devices (which can include EBS volumes built on the Nitro System). You may replace this playbook with your own method of formatting devices and presenting disks.
4. If managing TLS with the Redpanda playbooks run the following steps. If you're using externally provided certificates, skip to step 5 remembering to set `tls=true`: 
  1. `generate-csrs.yml` - will create private key and CSR and bring the CSR back to the Ansible host.
  2. If using the Redpanda provided CA: `issue-certs.yml` - signs the CSR and issues a certificate.
  3. `install-certs.yml` - Installs the certificate and also applies the `redpanda_broker` role to the cluster nodes. Note: This will install and start Redpanda (and restart any brokers that do not have `skip_node=true` set)
5. If `install-certs.yml` was not run in step iii above, you will need to run `provision-node.yml` which will install the `redpanda_broker` role. **Note: If TLS is enabled on the cluster, make sure that `-e tls=true` is set, otherwise this playbook will disable TLS across any nodes that don't have `skip_nodes=true` set.**


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
