#!/bin/bash

cleanup() {
  echo "trapped exit, cleaning up"
  task destroy
  exit $?
}
trap cleanup EXIT INT TERM
task demo-standup
task test-tls-cluster
task destroy
