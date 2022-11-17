# Terraform and Ansible Deployment for Redpanda

Terraform and Ansible configuration to easily provision a [Redpanda](https://vectorized.io) cluster on AWS, GCP, Azure, or IBM .

## Installation Prerequisites

* Install Terraform in your preferred way: https://www.terraform.io/downloads.html
* Install Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
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

To use existing infrastructure, update the `hosts.ini` file with the appropriate information. Otherwise see the READMEs for the following cloud providers:

* [AWS](aws/readme.md)
* [GCP](gcp/readme.md)
* [Azure](azure/README.md)
* [IBM Cloud](ibm/README.md)

### Required Steps: Deploying Redpanda

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

You can also specify any available Redpanda configuration value (or set of values) by passing a JSON dictionary as an Ansible extra-var. These values will be spliced with the calculated configuration and only override those values that you specify.
There are two sub-dictionaries that you can specify, `redpanda.cluster` and `redpanda.node`. Check the Redpanda docs for the available [Cluster configuration properties](https://docs.redpanda.com/docs/platform/reference/cluster-properties/) and [Node configuration properties](https://docs.redpanda.com/docs/platform/reference/node-properties/).

An example overriding specific properties would be as follows:

```commandline
ansible-playbook ansible/playbooks/provision-node.yml -i hosts.ini  --extra-vars '{ "redpanda": 
 {"cluster":
   { "auto_create_topics_enabled": "true"
   },
  "node":
   { "developer_mode": "false"
   }
 }
}'
```

2. Use `rpk` & standard Kafka tools to produce/consume from the Redpanda cluster & access the Grafana installation on the monitor host.
* The Grafana URL is http://&lt;grafana host&gt;:3000/login

## Configure TLS

### Optional: Create a Local Certificate Authority

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/create-ca.yml`

This creates a CA, with data in `ansible/playbook/tls/ca`. This only needs to be done once on your local machine (unless you blow the CA directory away).

### Generate keypairs and CSRs

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/generate-csrs.yml`

This will generate a keypair and a Certificate Signing Request, and collect the CSRs in the `ansible/playbook/tls/certs` directory. You can use your own CA to issue certificates, or use the local CA that we created in the first step.

### Optional: Issue certificates with the local CA

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/issue-certs.yml`

This will put issued certificates in `ansible/playbook/tls/certs`.

### Install certificates, configure RedPanda, and restart

`ansible-playbook --private-key <your_private_key> -i hosts.ini -v ansible/playbooks/install-certs.yml`

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

