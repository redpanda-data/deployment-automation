#!/bin/bash
set -x
set -o errexit
set -o pipefail

# test that remote nodes are open
# nc -v -z -w 3 <IP> 33145
# nc -v -z -w 3 <IP> 9092

if [[ $(which ansible) == "" ]]; then
	echo "install ansible";
	exit 1;
fi

echo "installing deps"
ansible-galaxy install -r requirements.yaml

echo "deploying"
ansible-playbook redpanda.yaml -i hosts.yaml
