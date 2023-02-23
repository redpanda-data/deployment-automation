cd ../aws || exit

## get these from AWS directly or provide your own auth method for terraform
export AWS_ACCESS_KEY_ID=KEY
export AWS_SECRET_ACCESS_KEY=KEY
export AWS_SESSION_TOKEN=KEY

## path to the ssh private key you are using to log into nodes
export SSH_KEY_LOC=KEY

echo "start tf work"
terraform destroy --auto-approve && terraform apply --auto-approve || exit

cd ..

# spin up nodes
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
ansible-playbook --private-key $SSH_KEY_LOC -i hosts.ini -v ansible/playbooks/provision-node.yml

echo "REDPANDA_BROKERS=$(awk '/\[redpanda\]/{a=1;next}/\[monitor\]/{a=0}a{if($1~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $1}' < hosts.ini | sed 's/$/:9092/' | tr '\n' ',' | sed 's/,$/\n/')"
echo "REDPANDA_BROKERS=$(sed -n '/^\[redpanda\]/, /^\[monitor\]/p' hosts.ini | grep 'private_ip=' | cut -d= -f4 | sed 's/$/:9092/' | tr '\n' ',' | sed 's/,$/\n/')"

# generate ssh commands for testing (assumes we are using us-west-2)
awk '/\[redpanda\]/{a=1;next}/\[monitor\]/{a=0}a{if($1~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $1}' < hosts.ini | while read -r ip_address; do tmp_ip=$(echo "$ip_address" | tr '.' '-'); echo "ssh -i ${SSH_KEY_LOC} ubuntu@ec2-${tmp_ip}.us-west-2.compute.amazonaws.com"; done
