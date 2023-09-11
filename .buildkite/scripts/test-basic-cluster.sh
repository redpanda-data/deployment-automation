#!/bin/bash

# Parse the named arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --hosts=*)
      PATH_TO_HOSTS_FILE="${1#*=}"
      ;;
    --rpk=*)
      PATH_TO_RPK_FILE="${1#*=}"
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ -z "$PATH_TO_HOSTS_FILE" ] || [ -z "$PATH_TO_RPK_FILE" ]; then
  echo ""
  echo "ERROR: invalid input"
  echo ""
  echo "Usage: ./testcluster.sh --hosts=PATH_TO_HOSTS_FILE --rpk=PATH_TO_RPK_FILE"
  echo "hosts : the fully qualified path to the hosts file"
  echo "rpk   : the fully qualified path to rpk"
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

export REDPANDA_REGISTRY=$(sed -n '/^\[redpanda\]/,/^$/p' "${PATH_TO_HOSTS_FILE}" | \
grep 'private_ip=' | \
cut -d' ' -f1 |  \
sed 's/$/:8081/' | \
tr '\n' ',' | \
sed 's/,$/\n/')

## test that we can check status, create a topic and produce to the topic
echo "checking cluster status"
"${PATH_TO_RPK_FILE}" cluster status --brokers "$REDPANDA_BROKERS" -v || exit 1

echo "creating topic"
"${PATH_TO_RPK_FILE}" topic create testtopic --brokers "$REDPANDA_BROKERS" -v || exit 1

echo "producing to topic"
echo squirrel | "${PATH_TO_RPK_FILE}" topic produce testtopic --brokers "$REDPANDA_BROKERS" -v || exit 1

echo "consuming from topic"
"${PATH_TO_RPK_FILE}" topic consume testtopic --brokers "$REDPANDA_BROKERS" -v -o :end | grep squirrel || exit 1

echo "testing schema registry"
for ip_port in $(echo $REDPANDA_REGISTRY | tr ',' ' '); do curl $ip_port/subjects ; done 
