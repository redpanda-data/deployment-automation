#!/bin/bash


# Parse the named arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix=*)
      PREFIX="${1#*=}"
      ;;
    --distro=*)
      DISTRO="${1#*=}"
      ;;
    --unstable=*)
      UNSTABLE="${1#*=}"
      ;;
    --tiered=*)
      TIERED="${1#*=}"
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ -z "$PREFIX" ] || [ -z "$DISTRO" ] || [ -z "$UNSTABLE" ] || [ -z "$TIERED" ]; then
  echo ""
  echo "ERROR: invalid input"
  echo ""
  echo "Usage: ./standup-tiered-storage.sh.sh --prefix=PREFIX --distro=DISTRO --unstable=[true/false] --tiered=[true/false]"
  echo "prefix   : a short prefix for identifying resources"
  echo "distro   : name of an image distro, must match the lookup in vars.tf"
  echo "unstable : whether to use the latest development version"
  echo "tiered   : whether to use tiered storage"
  exit 1
fi

cleanup() {
  exit_code=$?
  echo "trapped exit, cleaning up"
  DEPLOYMENT_ID=$PREFIX TIERED_STORAGE_ENABLED=true task destroy
  exit $exit_code
}
trap cleanup EXIT INT TERM

echo "beginning ${PREFIX} cluster testing"
task keygen
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in keygen"
  exit 1
fi

task_to_create="create-tls-cluster"
task_to_test="test-tls-cluster"
is_tiered="false"
if [ "$TIERED" == "true" ]; then
  task_to_create="create-tiered-storage-cluster"
  task_to_test="test-tiered-storage-cluster"
  is_tiered="true"
fi

DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO TIERED_STORAGE_ENABLED=$is_tiered task apply -- -var='tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'

error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in {$PREFIX} apply"
  exit 1
fi

echo "building cluster"
DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO IS_USING_UNSTABLE=$UNSTABLE task $task_to_create
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ansible standup"
  exit 1
fi

echo "testing cluster"
DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO task $task_to_test
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test-tls-cluster"
  exit 1
fi

DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO TIERED_STORAGE_ENABLED=$is_tiered  task destroy -- '-var=tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
