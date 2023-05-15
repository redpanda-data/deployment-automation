#!/bin/bash

cleanup() {
  exit_code=$?
  echo "trapped exit, cleaning up"
  DEPLOYMENT_ID=rp-devex-tls  task destroy
  exit $exit_code
}
trap cleanup EXIT INT TERM

echo "beginning tls cluster testing"
task keygen
if [ $error_code -ne 0 ]; then
  echo "error in keygen"
  exit 1
fi

DEPLOYMENT_ID=rp-devex-tls task apply -- -var='tags={
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

DEPLOYMENT_ID=rp-devex-tls task create-tls-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ansible standup"
  exit 1
fi


DEPLOYMENT_ID=rp-devex-tls task test-tls-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test-tls-cluster"
  exit 1
fi
DEPLOYMENT_ID=rp-devex-tls task destroy -- '-var=tags={
  "VantaOwner" : "devex@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
