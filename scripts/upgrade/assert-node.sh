#!/usr/bin/env bash
# Per-broker assertions for the COLLECTION upgrade test, run after the candidate collection
# re-converges a cluster originally built by the last released collection. Run via:
#   ansible redpanda -b -m script -a scripts/upgrade/assert-node.sh
#
# Redpanda is PINNED to the same version in both phases, so this proves the COLLECTION change
# re-converged the host safely, on each node:
#   1. The package source is cut over to the Artifact Registry (linux.pkg.redpanda.com).
#   2. No stale legacy (dl.redpanda.com) source file was left behind to mask/conflict.
#   3. Repo metadata refresh succeeds with NO GPG/signature error. On Debian this is the
#      load-bearing check: if the keyring still holds only the old signing key (e.g. a
#      `creates:`-guarded import that never re-ran), `apt-get update` fails here.
#   4. The redpanda package is installed, the service is active, and the broker version is
#      UNCHANGED from the baseline phase (a collection re-converge must not move the broker).
#
# NOTE: on GCP, install-rp-deb.yml sets allow_unauthenticated=true, which makes apt ignore a
# bad signature. The Debian signature assertion is therefore only trustworthy on AWS/non-GCP.
set -uo pipefail

fail() { echo "ASSERT FAIL on $(hostname): $*" >&2; exit 1; }
echo "=== collection re-converge assert on $(hostname) ==="

if command -v apt-get >/dev/null 2>&1; then
  grep -rq "linux.pkg.redpanda.com" /etc/apt/sources.list.d/ \
    || fail "Artifact Registry apt repo is not configured"
  if grep -rq "dl.redpanda.com" /etc/apt/sources.list.d/; then
    fail "stale dl.redpanda.com apt source still present after re-converge"
  fi

  echo "--- apt-get update (signature / keyring check) ---"
  out=$(apt-get update 2>&1) || { echo "$out"; fail "apt-get update returned non-zero"; }
  echo "$out"
  if echo "$out" | grep -iqE "NO_PUBKEY|GPG error|is not signed|not signed"; then
    fail "apt GPG/signature error against AR repo — stale keyring (key cutover not applied)?"
  fi
  cur=$(dpkg-query -W -f='${Version}' redpanda) || fail "redpanda package not installed"
else
  grep -rq "linux.pkg.redpanda.com" /etc/yum.repos.d/ \
    || fail "Artifact Registry yum repo is not configured"
  if grep -rq "dl.redpanda.com" /etc/yum.repos.d/; then
    fail "stale dl.redpanda.com yum repo still present after re-converge"
  fi

  echo "--- dnf makecache (AR metadata reachable; repo_gpgcheck=false) ---"
  dnf -q makecache >/dev/null 2>&1 || fail "dnf makecache failed against AR repo"
  cur=$(rpm -q --qf '%{VERSION}-%{RELEASE}' redpanda) || fail "redpanda package not installed"
fi

[ -n "$cur" ] || fail "could not determine current redpanda version"
base="UNKNOWN"
[ -f /tmp/upgrade_baseline_version ] && base=$(cat /tmp/upgrade_baseline_version)
echo "baseline=$base current=$cur"

# RP is pinned across both phases: the version must not move during a collection re-converge.
if [ "$base" != "UNKNOWN" ] && [ "$base" != "$cur" ]; then
  fail "broker version changed during collection re-converge: $base -> $cur (RP should be pinned)"
fi

systemctl is-active --quiet redpanda || fail "redpanda service is not active after re-converge"
echo "PASS on $(hostname) (version stable at $cur, service active)"
