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
    --tfdir=*)
      TF_DIR="${1#*=}"
      ;;
    --taskname=*)
      TASK_NAME="${1#*=}"
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ -z "$PREFIX" ] || [ -z "$DISTRO" ] || [ -z "$UNSTABLE" ] || [ -z "$TIERED" ] || [ -z "$TASK_NAME" ]; then
  echo ""
  echo "ERROR: invalid input"
  echo ""
  echo "Usage: ./standup-tiered-storage.sh.sh --prefix=PREFIX --distro=DISTRO --unstable=[true/false] --tiered=[true/false] --tfdir=TF_DIR --taskname=ANSIBLE_TASK_NAME"
  echo "prefix   : a short prefix for identifying resources"
  echo "distro   : name of an image distro, must match the lookup in vars.tf"
  echo "unstable : whether to use the latest development version"
  echo "tiered   : whether to use tiered storage"
  echo "tfdir    : directory for Terraform"
  echo "taskname : Ansible task to use minus create- or test-. So for example create-proxy-cluster would be passed as proxy-cluster"
  exit 1
fi

cleanup() {
  exit_code=$?
  echo "trapped exit, cleaning up"
  DEPLOYMENT_ID=$PREFIX TIERED_STORAGE_ENABLED=true TF_DIR=$TF_DIR TF_CMD=destroy task build
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

is_tiered="false"
if [ "$TIERED" == "true" ]; then
  is_tiered="true"
fi

DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO TIERED_STORAGE_ENABLED=$is_tiered TF_DIR=$TF_DIR task build -- -var='tags={
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
DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO IS_USING_UNSTABLE=$UNSTABLE task "create-$TASK_NAME"
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ansible standup"
  exit 1
fi

echo "testing cluster"
DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO task "test-$TASK_NAME"
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test-tls-cluster"
  exit 1
fi

DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO TIERED_STORAGE_ENABLED=$is_tiered TF_CMD=destroy task build -- '-var=tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
