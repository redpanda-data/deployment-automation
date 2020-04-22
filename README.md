# Redpanda

Ansible role for installing and configuring [Redpanda](https://vectorized.io).

## Installation

Add the following to a `requirements.yml` file:

```yaml
- src: computology.packagecloud
- src: mrlesmithjr.mdadm
- src: git+https://github.com/vectorizedio/redpanda-ansible
```

Then execute:

```bash
ansible-galaxy install -r requirements.yml
```

## Recommended hardware

The role assumes that the hosts where Redpanda is running are 
provisioned with SSD devices, and available as `/dev/nvme0n1`, 
`/dev/nvme0n2`, etc. In the case of AWS, it is recommended to use 
instance type `i3.8xlarge` and enable the `redpanda_with_raid` 
variable (see [Role Variables](#-role-variables) below).

## Requirements

  * Ansible >= 2.9
  * Ubuntu 18.04 on hosts.

## Role Variables

  * `redpanda_vectorizedio_packagecloud_token` **Required** The master 
    token provided by VectorizedIO to <https://packagecloud.io>.
  * `redpanda_with_raid`. Whether to aggregate the local SSD devices 
    in RAID0 configuration (**default**: `true`).
  * `redpanda_cluster_id`. ID of the cluster being deployed 
    (**default**: `redpanda`).
  * `redpanda_cluster_org_id`. ID of the organization that the cluster 
    belongs to (**default**: `vectorized-customer`).

## Inventory Requirements

The role expects each host in the inventory have the following 
variables associated to them:

  * `private_ip`. Denotes the internal network IP address assigned to 
  them.
  * `id`. The ID of the host in the redpanda cluster (1-index).

For example:

```ini
[redpanda]
54.186.78.36 private_ip=172.31.18.83 id=1 ansible_user=myuser ansible_become=True
54.186.78.37 private_ip=172.31.18.84 id=2 ansible_user=myuser ansible_become=True
54.186.78.38 private_ip=172.31.18.85 id=3 ansible_user=myuser ansible_become=True
```

## Dependencies

  * [`computology.packagecloud`](https://github.com/computology/packagecloud-ansible-role). 
    Installs packages from [Packagecloud](https://packagecloud.io).
  * [`mrlesmithjr.mdadm`](https://github.com/mrlesmithjr/ansible-mdadm/). Configures RAID.

## Example Playbook

```yaml
- hosts: redpanda
  roles:
  - { role: redpanda, redpanda_with_raid: true }
```

## Author Information

VectorizedIO dev team

## LICENSE

[Apache-2.0](./LICENSE)
