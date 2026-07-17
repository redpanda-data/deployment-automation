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
#   5. RPM: repo_gpgcheck=1 is configured and a fresh `dnf makecache` verifies the
#      Artifact-Registry-signed repomd.xml against the imported AR signer key — signed
#      metadata verification survives (and is exercised by) the upgrade.
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

  echo "--- signed repo metadata verification (repo_gpgcheck) ---"
  # The candidate collection must write repo_gpgcheck=1 on the redpanda repos: AR
  # signs repomd.xml with Google's Artifact Registry repository-signer key, and
  # disabling the check would silently accept forged/replayed metadata.
  grep -rEq "repo_gpgcheck[[:space:]]*=[[:space:]]*1" /etc/yum.repos.d/*redpanda*.repo \
    || fail "repo_gpgcheck=1 not set on the redpanda repos after re-converge (metadata verification disabled)"
  # Force a fresh metadata fetch so the repomd.xml signature is actually verified
  # right now, on this upgraded host, with the keys the candidate imported.
  # -y auto-confirms the AR signer key import into dnf's per-repo keyring.
  dnf -q clean metadata >/dev/null 2>&1
  out=$(dnf -y makecache 2>&1) || { echo "$out"; fail "dnf makecache failed with repo_gpgcheck=1 — AR metadata signature did not verify"; }
  echo "OK: repomd.xml signature verified with repo_gpgcheck=1"
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
