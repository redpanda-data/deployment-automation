# Redpanda

Ansible role for installing and configuring [Redpanda](https://vectorized.io).

## Installation

Recommended:

```bash
ansible-galaxy install \
  computology.packagecloud \
  mrlesmithjr.mdadm \
  git+https://github.com/vectorizedio/redpanda-ansible
```

## Requirements

  * Ansible >= 2.9

## Role Variables

  * redpanda_vectorizedio_packagecloud_token
  * redpanda_with_raid

In addition, the role expects hosts in the inventory to be tagged with 
a `private_ip` variable that denotes the internal network IP address 
assigned to them.

## Dependencies

  * [computology.packagecloud](https://github.com/computology/packagecloud-ansible-role)
  * [mrlesmithjr.mdadm](https://github.com/mrlesmithjr/ansible-mdadm/)

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
