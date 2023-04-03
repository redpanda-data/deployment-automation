#!/bin/bash

cleanup() {
  exit_code=$?
  echo "trapped exit, cleaning up"
  task destroy
  exit $exit_code
}
trap cleanup EXIT INT TERM

echo "beginning tiered storage cluster testing"
task keygen
if [ $error_code -ne 0 ]; then
  echo "error in keygen"
  exit 1
fi

DEPLOYMENT_ID=rp-devex-tiered task apply -- -var='tiered_storage_enabled=true' -var='tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'

error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in apply"
  exit 1
fi

DEPLOYMENT_ID=rp-devex-tiered task create-tiered-storage-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ansible standup"
  exit 1
fi


DEPLOYMENT_ID=rp-devex-tiered task test-tiered-storage-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test-tls-cluster"
  exit 1
fi
DEPLOYMENT_ID=rp-devex-tiered task destroy -- '-var=tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
