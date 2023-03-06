#!/bin/bash

cleanup() {
  exit_code=$?
  echo "trapped exit, cleaning up"
  task destroy
  exit $exit_code
}
trap cleanup EXIT INT TERM
task ci-standup TF_CLI_ARGS='-var=tags={
  "VantaOwner" : "gene@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ci-standup"
  exit 1
fi
task test-tls-cluster
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test-tls-cluster"
  exit 1
fi
task destroy -- '-var=tags={
  "VantaOwner" : "gene@redpanda.com"
  "VantaNonProd" : "true"
  "VantaDescription" : "cicd-instance-for-devex"
  "VantaContainsUserData" : "false"
  "VantaUserDataStored" : "none"
  "VantaNoAlert" : "this-is-a-testing-instance-with-no-stored-data"
}'
