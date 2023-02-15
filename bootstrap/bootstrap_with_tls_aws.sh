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

# node pre-install work
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
echo "install node deps"
ansible-playbook --private-key $SSH_KEY_LOC -i hosts.ini -v ansible/playbooks/install-node-deps.yml || exit
echo "prepare data dir"
ansible-playbook --private-key $SSH_KEY_LOC -i hosts.ini -v ansible/playbooks/prepare-data-dir.yml || exit

# populate hosts.ini with relevant global variables
echo "copy host file"
cat <(echo '[all:vars]
tls=true
advertise_public_ips=true

'
) hosts.ini > tmp.ini

rm hosts.ini
mv tmp.ini hosts.ini

# prep for ansible apply
export CA_PATH="ansible/playbooks/tls/ca"
echo "generate csrs"
ansible-playbook --private-key $SSH_KEY_LOC -i hosts.ini -v ansible/playbooks/generate-csrs.yml || exit
echo "issue certs"
ansible-playbook --private-key $SSH_KEY_LOC -i hosts.ini -v ansible/playbooks/issue-certs.yml || exit
echo "install certs"
ansible-playbook --private-key $SSH_KEY_LOC -i hosts.ini -v ansible/playbooks/install-certs.yml || exit
echo "done"

# parse hosts.ini public ips into a redpanda_brokers compatible format for public and private ips for testing
echo "REDPANDA_BROKERS=$(awk '/\[redpanda\]/{a=1;next}/\[monitor\]/{a=0}a{if($1~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $1}' < hosts.ini | sed 's/$/:9093/' | tr '\n' ',' | sed 's/,$/\n/')"
echo "REDPANDA_BROKERS=$(sed -n '/^\[redpanda\]/, /^\[monitor\]/p' hosts.ini | grep 'private_ip=' | cut -d= -f4 | sed 's/$/:9092/' | tr '\n' ',' | sed 's/,$/\n/')"

# export the brokers for use in automated test
REDPANDA_BROKERS=$(awk '/\[redpanda\]/{a=1;next}/\[monitor\]/{a=0}a{if($1~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $1}' < hosts.ini | sed 's/$/:9093/' | tr '\n' ',' | sed 's/,$/\n/')
export REDPANDA_BROKERS

# generate ssh commands for testing (assumes we are using us-west-2)
awk '/\[redpanda\]/{a=1;next}/\[monitor\]/{a=0}a{if($1~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $1}' < hosts.ini | while read -r ip_address; do tmp_ip=$(echo "$ip_address" | tr '.' '-'); echo "ssh -i ${SSH_KEY_LOC} ubuntu@ec2-${tmp_ip}.us-west-2.compute.amazonaws.com"; done

# you will need the ca.crt to use these commands on the client inside the VPC and from your workstation, but not on the nodes
rpk cluster status \
--brokers "${REDPANDA_BROKERS}" \
--tls-truststore ansible/playbooks/tls/ca/ca.crt \
-v || exit

rpk topic create testtopic2      \
--brokers "${REDPANDA_BROKERS}" \
--tls-truststore ansible/playbooks/tls/ca/ca.crt \
-v

