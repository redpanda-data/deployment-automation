#!/bin/bash

# Check if the go-task binary already exists
if command -v artifacts/bin/task >/dev/null 2>&1; then
  echo "go-task is already installed"
  exit 0
fi

# Download the go-task binary from GitHub
TASK_VERSION=v3.21.0

if [[ $(uname -m) == "aarch64" ]]; then
  ARCH="arm64"
else
  ARCH="amd64"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  OS=darwin
else
  OS=linux
fi

mkdir -p artifacts/bin/
curl -sSLf "https://github.com/go-task/task/releases/download/${TASK_VERSION}/task_${OS}_${ARCH}.tar.gz" | tar -xz -C artifacts/bin

# Verify that go-task is installed
if command -v artifacts/bin/task >/dev/null 2>&1; then
  echo "go-task has been installed successfully"
else
  echo "go-task installation failed"
fi
