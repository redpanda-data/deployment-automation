#!/usr/bin/env bash
# Checks that a CI image built from Dockerfile_UBUNTU carries the tool
# versions the Buildkite lanes depend on.
#
# usage: scripts/check-ci-image.sh <image> [platform]
#   platform defaults to linux/amd64, the architecture of the Buildkite agents.
#
# Exits non-zero if any check fails. Expected versions match the pins in
# Dockerfile_UBUNTU; update both together.
set -euo pipefail

image=${1:?usage: $0 <image> [platform]}
platform=${2:-linux/amd64}

ANSIBLE_CORE_SERIES=2.20.
TERRAFORM_VERSION=1.7.4
TASK_VERSION=3.21.0
GO_VERSION=1.23.5

failures=0
run() { docker run --rm --platform "$platform" "$image" bash -c "$1" 2>&1; }

check() {
  local name=$1 cmd=$2 want=$3 out
  out=$(run "$cmd") || true
  if [[ $out == *"$want"* ]]; then
    printf 'PASS  %-34s %s\n' "$name" "$(head -1 <<<"$out")"
  else
    printf 'FAIL  %-34s want %q, got: %s\n' "$name" "$want" "$(head -1 <<<"$out")"
    failures=$((failures + 1))
  fi
}

echo "checking $image ($platform)"
# The Python interpreter Ansible itself runs on, read from its shebang.
ansible_py='"$(sed -n "1s/^#!//p" "$(command -v ansible)")"'

check 'ansible-core 2.20.x'            'ansible --version | head -1'              "[core $ANSIBLE_CORE_SERIES"
check 'controller python >= 3.12'      "$ansible_py"' -c "import sys; print(\"py-ok\" if sys.version_info >= (3, 12) else sys.version)"' 'py-ok'
# jmespath: json_query in ansible/deploy-monitor*.yml. cryptography: controller-side crypto modules.
check 'controller jmespath, cryptography' "$ansible_py"' -c "import jmespath, cryptography; print(\"libs-ok\")"' 'libs-ok'
check 'bundled community.general'      'ansible-galaxy collection list community.general 2>/dev/null' 'community.general'
check 'terraform'                      'terraform version | head -1'              "Terraform v$TERRAFORM_VERSION"
check 'task'                           'task --version'                           "v$TASK_VERSION"
check 'go'                             'go version'                               "go$GO_VERSION"
check 'aws cli v2'                     'aws --version'                            'aws-cli/2.'
check 'gcloud'                         'gcloud --version | head -1'               'Google Cloud SDK'
check 'keytool'                        'command -v keytool'                       '/keytool'
# ssh and scp: Ansible's connection to the hosts. ssh-keygen: tools:keygen.
# sshpass: password-based Ansible connections.
check 'ssh tools'                      'm=; for t in ssh scp ssh-keygen sshpass; do command -v $t >/dev/null || m="$m $t"; done; [ -z "$m" ] && echo tools-ok || echo "missing:$m"' 'tools-ok'
check 'jq git make unzip wget curl openssl' 'm=; for t in jq git make unzip wget curl openssl; do command -v $t >/dev/null || m="$m $t"; done; [ -z "$m" ] && echo tools-ok || echo "missing:$m"' 'tools-ok'

if ((failures)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
