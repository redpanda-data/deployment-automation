#!/bin/bash

# Parse the named arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --hosts=*)
      PATH_TO_HOSTS_FILE="${1#*=}"
      ;;
    --cert=*)
      PATH_TO_CA_CRT="${1#*=}"
      ;;
    --bucket=*)
      BUCKET_NAME="${1#*=}"
      ;;
    --sshkey=*)
      SSHKEY="${1#*=}"
      ;;
    --cloud=*)
      CLOUD_PROVIDER="${1#*=}"
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ -z "$PATH_TO_HOSTS_FILE" ] || [ -z "$PATH_TO_CA_CRT" ]; then
  echo ""
  echo "ERROR: invalid input"
  echo ""
  echo "Usage    : ./testcluster.sh --hosts=PATH_TO_HOSTS_FILE --cert=PATH_TO_CA_CRT"
  echo "hosts    : the fully qualified path to the hosts file"
  echo "cert     : the fully qualified path to the CA cert used to sign the cluster certs"
  echo "bucket   : name of the bucket"
  echo "sshkey   : path to ssh key"
  exit 1
fi


## assemble the redpanda brokers by chopping up the hosts file
# shellcheck disable=SC2155
export REDPANDA_BROKERS=$(sed -n '/^\[redpanda\]/,/^$/p' "${PATH_TO_HOSTS_FILE}" | \
grep 'private_ip=' | \
cut -d' ' -f1 |  \
sed 's/$/:9092/' | \
tr '\n' ',' | \
sed 's/,$/\n/')

## get ansible user
# shellcheck disable=SC2155
export CLIENT_SSH_USER=$(sed -n '/\[redpanda\]/,/\[/p' "${PATH_TO_HOSTS_FILE}" | grep ansible_user | head -n1 | tr ' ' '\n' | grep ansible_user | cut -d'=' -f2
)

# shellcheck disable=SC2155
export CLIENT_PUBLIC_IP=$(sed -n '/^\[client\]/,/^$/p' "${PATH_TO_HOSTS_FILE}" | grep 'private_ip=' | cut -f1 -d' ')

## test that we can check status, create a topic and produce to the topic
echo "checking cluster status"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $SSHKEY $CLIENT_SSH_USER@$CLIENT_PUBLIC_IP 'rpk cluster status --brokers '"$REDPANDA_BROKERS"' --tls-truststore '"$PATH_TO_CA_CRT"' -v' || exit 1

echo "creating topic"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $SSHKEY $CLIENT_SSH_USER@$CLIENT_PUBLIC_IP 'rpk topic create testtopic --brokers '"$REDPANDA_BROKERS"' --tls-truststore '"$PATH_TO_CA_CRT"' -v' || exit 1

echo "producing to topic"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $SSHKEY $CLIENT_SSH_USER@$CLIENT_PUBLIC_IP 'echo squirrels | rpk topic produce testtopic --brokers '"$REDPANDA_BROKERS"' --tls-truststore '"$PATH_TO_CA_CRT"' -v' || exit 1

sleep 30

echo "consuming from topic"
testoutput=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $SSHKEY $CLIENT_SSH_USER@$CLIENT_PUBLIC_IP 'rpk topic consume testtopic --brokers '"$REDPANDA_BROKERS"' --tls-truststore '"$PATH_TO_CA_CRT"' -v -o :end')
echo $testoutput | grep squirrels || exit 1

if [ "$CLOUD_PROVIDER" == "gcp" ]; then
  echo "checking that gcp bucket is not empty"
  echo "$DEVEX_GCP_CREDS_BASE64" | base64 -d > /tmp/gcp_creds.json
  export GOOGLE_APPLICATION_CREDENTIALS="/tmp/gcp_creds.json"
  export CLOUDSDK_CORE_PROJECT=hallowed-ray-376320
  gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS
  echo $BUCKET_NAME
  if [ $(gcloud storage ls $(gcloud storage ls | grep ${BUCKET_NAME%-bucket}) | wc -l) -gt 1 ]; then
    echo "success"
    exit 0
  fi
else
  echo "checking that aws bucket is not empty"
  # Check if the bucket is empty
  object_count=$(aws s3api list-objects --bucket "${BUCKET_NAME}" --region us-west-2 --output json | jq '.Contents | length')
  echo "success"
  exit 0
fi

echo "fail"
exit 1
