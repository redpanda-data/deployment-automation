#!/usr/bin/env bash
# Records the broker version installed by the BASELINE (released collection / legacy
# dl.redpanda.com repo) phase, so the candidate phase can prove the package actually moved.
# Run on every broker via:  ansible redpanda -b -m script -a scripts/upgrade/capture-baseline.sh
set -euo pipefail

if command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W -f='${Version}\n' redpanda > /tmp/upgrade_baseline_version
else
  rpm -q --qf '%{VERSION}-%{RELEASE}\n' redpanda > /tmp/upgrade_baseline_version
fi

echo "baseline redpanda version on $(hostname): $(cat /tmp/upgrade_baseline_version)"
