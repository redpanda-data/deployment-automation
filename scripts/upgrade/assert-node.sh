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
#   4. Debian: the installed keyring is byte-identical to the key material the
#      repository URL currently serves. sabotage-deb-keyring.sh doubled the keyring
#      between phases (first fingerprint still present!), so a fingerprint-presence
#      gate skips the refresh and fails this assert; only a whole-keyring comparison
#      passes. Before/sabotaged/after fingerprint sets are printed for the log.
#   5. RPM: repo_gpgcheck matches the dnf backend — 0 on dnf5 (which cannot verify
#      AR's repomd.xml signature) and 1 on dnf4, where a fresh `dnf makecache`
#      verifies the AR-signed repomd.xml. Either way makecache must succeed.
#   6. The redpanda package is installed, the service is active, and the broker version is
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

  echo "--- keyring refreshed across the upgrade (key-rotation path) ---"
  KEYRING=/usr/share/keyrings/redpanda-redpanda-archive-keyring.gpg
  KEY_URL=https://linux.pkg.redpanda.com/redpanda-deb-signing-public.gpg
  curl -fsSL "$KEY_URL" -o /tmp/assert-served.key || fail "could not fetch served DEB signing key"
  gpg --dearmor --yes -o /tmp/assert-served.gpg /tmp/assert-served.key \
    || fail "could not dearmor served DEB signing key"
  for f in baseline sabotaged; do
    if [ -f "/var/tmp/upgrade_keyring_$f" ]; then
      echo "$f keyring fprs:"; sed 's/^/  /' "/var/tmp/upgrade_keyring_$f"
    fi
  done
  echo "post-upgrade keyring fprs:"
  gpg --no-default-keyring --keyring "$KEYRING" --list-keys --with-colons 2>/dev/null \
    | awk -F: '/^fpr:/{print "  "$10}'
  # The sabotaged keyring contained the served key's fingerprint but extra bytes;
  # only a whole-keyring refresh restores exact served material. A fingerprint
  # gate would have skipped the refresh and this cmp fails.
  cmp -s /tmp/assert-served.gpg "$KEYRING" \
    || fail "keyring is not byte-identical to the served signing key — rotation refresh did not run (fpr-gated skip?)"
  echo "OK: keyring refreshed to exactly the served key material across the upgrade"
  cur=$(dpkg-query -W -f='${Version}' redpanda) || fail "redpanda package not installed"
else
  grep -rq "linux.pkg.redpanda.com" /etc/yum.repos.d/ \
    || fail "Artifact Registry yum repo is not configured"
  if grep -rq "dl.redpanda.com" /etc/yum.repos.d/; then
    fail "stale dl.redpanda.com yum repo still present after re-converge"
  fi

  echo "--- repo metadata verification (repo_gpgcheck), gated on the dnf backend ---"
  # dnf5 cannot verify AR's repomd.xml signature, so the collection sets
  # repo_gpgcheck=0 on dnf5 and =1 on dnf4. Assert the value matches the backend,
  # and where verification is on, prove it actually verifies now.
  if [ -x /usr/bin/dnf5 ]; then
    grep -rEq "repo_gpgcheck[[:space:]]*=[[:space:]]*0" /etc/yum.repos.d/*redpanda*.repo \
      || fail "repo_gpgcheck should be 0 on dnf5 (AR repomd signature is not verifiable by dnf5) but is not"
    dnf -q clean metadata >/dev/null 2>&1
    dnf makecache >/dev/null 2>&1 || fail "dnf makecache failed on the redpanda AR repo"
    echo "OK: dnf5 host, repo_gpgcheck=0 as expected, makecache succeeds"
  else
    grep -rEq "repo_gpgcheck[[:space:]]*=[[:space:]]*1" /etc/yum.repos.d/*redpanda*.repo \
      || fail "repo_gpgcheck should be 1 on dnf4 but is not (metadata verification disabled)"
    dnf -q clean metadata >/dev/null 2>&1
    out=$(dnf -y makecache 2>&1) || { echo "$out"; fail "dnf makecache failed with repo_gpgcheck=1 — AR metadata signature did not verify"; }
    echo "OK: dnf4 host, repomd.xml signature verified with repo_gpgcheck=1"
  fi
  cur=$(rpm -q --qf '%{VERSION}-%{RELEASE}' redpanda) || fail "redpanda package not installed"
fi

[ -n "$cur" ] || fail "could not determine current redpanda version"
# A missing baseline is a FAILURE, not a skip: silently passing here would let a
# version-moving candidate collection go green (the exact regression this checks for).
# capture-baseline.sh writes to /var/tmp so a reboot can't wipe it (Fedora /tmp is tmpfs).
[ -f /var/tmp/upgrade_baseline_version ] \
  || fail "baseline version file missing — capture-baseline.sh did not run on this node?"
base=$(cat /var/tmp/upgrade_baseline_version)
[ -n "$base" ] || fail "baseline version file is empty"
echo "baseline=$base current=$cur"

# RP is pinned across both phases: the version must not move during a collection re-converge.
if [ "$base" != "$cur" ]; then
  fail "broker version changed during collection re-converge: $base -> $cur (RP should be pinned)"
fi

systemctl is-active --quiet redpanda || fail "redpanda service is not active after re-converge"
echo "PASS on $(hostname) (version stable at $cur, service active)"
