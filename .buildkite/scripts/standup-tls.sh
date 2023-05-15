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
    *)
      echo "Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ -z "$PREFIX" ] || [ -z "$DISTRO" ]; then
  echo ""
  echo "ERROR: invalid input"
  echo ""
  echo "Usage: ./standup-tiered-storage.sh.sh --prefix=PREFIX --distro=DISTRO"
  echo "prefix  : a short prefix for identifying resources"
  echo "distro  : name of an image distro, must match the lookup in vars.tf"
  exit 1
fi


cleanup() {
  exit_code=$?
  echo "trapped exit, cleaning up"
  DEPLOYMENT_ID=rp-devex-tls  task destroy
  exit $exit_code
}
trap cleanup EXIT INT TERM

echo "beginning tls cluster testing"
task keygen
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in keygen"
  exit 1
fi

DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO task apply -- -var='tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'

error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in tls apply"
  exit 1
fi

DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO task create-tls-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ansible standup"
  exit 1
fi


DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO task test-tls-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test-tls-cluster"
  exit 1
fi
DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO task destroy -- '-var=tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
