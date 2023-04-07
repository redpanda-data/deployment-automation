# Ansible Collection for Redpanda

Redpanda Ansible Collection that enables provisioning and managing a [Redpanda](https://www.redpanda.com/) cluster.

## Usage

### Required Steps: Deploying Redpanda

> Note: This playbook is designed to be run repeatedly against a running cluster however be aware that it will cause a
> rolling restart of the cluster to occur. If you do not want the cluster to restart you can
> specify `restart_node=false`
> either globally (as --extra-vars, or on a host-by-host basis in the `hosts.ini` file). If you make changes to the node
> config and do not perform a restart then you may leave your `rpk` config (and this may inhibit subsequent executions
> of
> the playbook). If you re-run the playbook it will overwrite any configurations with those specified in the playbook,
> so
> care should be taken to ensure that the playbook contains any desired configuration (for example, if you have enabled
> TLS on your cluster, any subsequent runs of `provision-node` should be made with `-e tls=true` otherwise the playbook
> will disable TLS).

Before running these steps, verify that the `hosts.ini` file contains the correct information for your infrastructure.
This will be automatically populated if using the terraform steps above.

1. `ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/provision-node.yml`

Available Ansible variables:

You can pass the following variables as `-e var=value`:

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

You can also specify any available Redpanda configuration value (or set of values) by passing a JSON dictionary as an
Ansible extra-var. These values will be spliced with the calculated configuration and only override those values that
you specify.

There are two sub-dictionaries that you can specify, `redpanda.cluster` and `redpanda.node`. Check the Redpanda docs for
the available [Cluster configuration properties](https://docs.redpanda.com/docs/platform/reference/cluster-properties/)
and [Node configuration properties](https://docs.redpanda.com/docs/platform/reference/node-properties/).

An example overriding specific properties would be as follows:

```commandline
ansible-playbook ansible/provision-node.yml -i hosts.ini --extra-vars '{
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

2. Use `rpk` & standard Kafka tools to produce/consume from the Redpanda cluster & access the Grafana installation on
   the monitor host.

* The Grafana URL is http://&lt;grafana host&gt;:3000/login

## Configure Grafana

To deploy a grafana node, ensure that you have a [monitor] section in your hosts file. You should then be able to run
the deploy-prometheus-grafana.yml playbook

```shell
ansible-playbook cluster/playbooks/deploy-prometheus-grafana.yml \
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
ansible-playbook cluster/playbooks/provision-tls-cluster.yml \
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
ansible-playbook ansible/provision-tls-cluster.yml \
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
ansible-playbook --private-key ~/.ssh/id_rsa cluster/playbooks/provision-node.yml -i hosts.ini -e redpanda_version=22.3.10-1 
```

2. By default the playbook will select the latest version of the Redpanda packages, but an upgrade will only be enacted
   if the `redpanda_install_status` variable is set to `latest`:

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa cluster/playbooks/provision-node.yml -i hosts.ini -e redpanda_install_status=latest 
```

It is also possible to upgrade clusters where SASL authentication has been turned on. For this, you will need to
additionally specify the `redpanda_rpk_opts` variable to include to username and password or a superuser or
appropriately privileged user. An example follows:

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa cluster/playbooks/provision-node.yml -i hosts.ini --extra-vars=redpanda_install_status=latest --extra-vars "{
\"redpanda_rpk_opts\": \"--user ${MY_USER} --password ${MY_USER_PASSWORD}\"
}"
```

Similarly, you can put the `redpanda_rpk_opts` into a yaml
file [protected with Ansible vault](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html#creating-encrypted-files).

```commandline
ansible-playbook --private-key ~/.ssh/id_rsa cluster/playbooks/provision-node.yml -i hosts.ini --extra-vars=redpanda_install_status=latest --extra-vars @vault-file.yml --ask-vault-pass
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
