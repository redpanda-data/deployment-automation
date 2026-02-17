#!/bin/bash
set -euo pipefail

# check-idempotency.sh — Run ansible-playbook and fail if any tasks report changes
# Usage: check-idempotency.sh ansible-playbook [args...]

LOGFILE=$(mktemp)
trap 'rm -f "$LOGFILE"' EXIT

echo "=== Idempotency check — running playbook again ==="

set +e
"$@" 2>&1 | tee "$LOGFILE"
RC=${PIPESTATUS[0]}
set -e

if [ "$RC" -ne 0 ]; then
  echo "FAIL: ansible-playbook exited with code $RC"
  exit "$RC"
fi

if grep -qE 'changed=[1-9]' "$LOGFILE"; then
  echo ""
  echo "FAIL: Idempotency check failed — second run had changes:"
  grep -E 'changed=' "$LOGFILE"
  exit 1
fi

echo "PASS: Idempotency check passed — no changes on second run"
