#!/bin/bash

cleanup() {
  echo "trapped exit, cleaning up"
  task destroy
  exit $?
}
trap cleanup EXIT INT TERM
task ci-standup TF_CLI_ARGS='-var=tags={
  "vanta-owner" : "devex"
  "vanta-non-prod" : "true"
  "vanta-description" : "cicd-instance-for-devex"
  "vanta-contains-user-data" : "false"
  "vanta-user-data-stored" : "none"
  "vanta-no-alert" : "this-is-a-testing-instance-with-no-stored-data"
}'
task test-tls-cluster
task destroy -- '-var=tags={
  "vanta-owner" : "devex"
  "vanta-non-prod" : "true"
  "vanta-description" : "cicd-instance-for-devex"
  "vanta-contains-user-data" : "false"
  "vanta-user-data-stored" : "none"
  "vanta-no-alert" : "this-is-a-testing-instance-with-no-stored-data"
}'
