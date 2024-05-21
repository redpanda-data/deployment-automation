## LIMITED ALPHA RELEASE - CAN NOT BE USED WITHOUT CONTACTING REDPANDA

* Have an existing, ready to go Redpanda cluster using the standard documentation 
* Have at least one instance for a Connect cluster to install on
  * our Redpanda Terraform AWS Module can create connect instances when enable_connect is set to true

* Add the connect group to your hosts file as in this example (the Redpanda AWS terraform module does this automatically)

***NOTE: You MUST use Fedora -- or a close equivalent -- as the OS for the Connect cluster***

```yaml
[redpanda]
54.218.89.220 ansible_user=fedora ansible_become=True private_ip=172.31.37.199
35.92.237.241 ansible_user=fedora ansible_become=True private_ip=172.31.45.22
52.42.0.22 ansible_user=fedora ansible_become=True private_ip=172.31.35.172

[monitor]
34.213.129.31 ansible_user=fedora ansible_become=True private_ip=172.31.5.102

[client]
54.189.99.201 ansible_user=fedora ansible_become=True private_ip=172.31.5.5 id=0

[connect]
18.237.200.129 ansible_user=fedora ansible_become=True private_ip=172.31.12.72 id=0
35.92.20.137 ansible_user=fedora ansible_become=True private_ip=172.31.8.120 id=1
54.191.10.62 ansible_user=fedora ansible_become=True private_ip=172.31.8.167 id=2
```
* Acquire the RPM from Redpanda by contacting Customer Success
* Place it into a temporary directory -- by default the role assumes the following

```yaml
redpanda_connect_rpm: "redpanda-connect.x86_64.rpm"
redpanda_connect_rpm_dir: "/tmp"
```

but you can change these by adding the values in your playbook and setting it accordingly

* Depending on whether you are looking for a TLS or non TLS implementation you will need to adjust things accordingly. 
  * See the role in the ansible collection for [more details](https://github.com/redpanda-data/redpanda-ansible-collection/tree/main/roles) 

```yaml
---
- hosts: connect
  vars:
    redpanda_connect_rpm: "redpanda-connect.x86_64.rpm"
    redpanda_connect_rpm_dir: "/tmp"
  tasks:
    - name: install connect
      ansible.builtin.include_role:
        name: redpanda.cluster.redpanda_connect
```

You will most likely need to customize at least some of these values, especially if you are setting up TLS.

* Run the playbook and you should have a working Connect cluster. There is an example tls playbook as well.

This command is relative to the root of the repository. Private key should be the path to the ssh key file with access to the hosts. Ansible inventory should be the ansible inventory with the connect group defined.
```shell
ansible-playbook ansible/deploy-connect.yml --private-key $PRIVATE_KEY --inventory $ANSIBLE_INVENTORY
```

## TLS

Currently we do not support transitioning a non TLS cluster to TLS. 

To enable TLS across your RP and Connect clusters you will need to make sure that
* the Connect cluster has the necessary keystore and truststore to access the RP clusters
* the JMX Exporter has the necessary keystore and truststore
* Console has the necessary certs to access the Connect cluster
* Prometheus has the necessary certs to access the JMX Exporter

The Connect, Console and Demo Certs roles have all the necessary elements to demonstrate how this process works. 

For the Monitoring configuration you will need to check the TLS playbook to see how it uses the demo certs role to generate and deploy certs, keystores and truststores as needed. 

Once the cert side of the process is set up you can use the deploy-connect-tls playbook to deploy the Connect cluster with TLS enabled.

```shell
ansible-playbook ansible/deploy-connect-tls.yml --private-key $PRIVATE_KEY --inventory $ANSIBLE_INVENTORY
```
