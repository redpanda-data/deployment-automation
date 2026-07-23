#!/usr/bin/env bash
# Upgrade fixture: manufacture the first-fingerprint-collision case so the assert
# can prove the candidate collection refreshes a keyring that a naive
# fingerprint-presence gate would wrongly skip. Run between phase 1 (baseline
# converge) and phase 2 (candidate converge):
#   ansible redpanda -b -m script -a scripts/upgrade/sabotage-deb-keyring.sh
#
# The keyring is rewritten to: the CURRENTLY-SERVED key, followed by whatever the
# phase-1 (baseline) collection already installed. That is a realistic overlap
# bundle, and it satisfies three constraints simultaneously:
#   - the baseline key is retained, so the phase-2 `apt update` that
#     system_setup runs BEFORE the repo is reconfigured still verifies the
#     still-configured baseline repo (no premature NO_PUBKEY);
#   - the served key's fingerprint is present, so a gate that only checks
#     "is the served fingerprint in the keyring?" skips the refresh and leaves
#     the extra baseline key in place — which the assert then catches;
#   - the bytes differ from the served key alone, so a whole-keyring comparison
#     correctly refreshes it down to exactly the served material.
#
# No-op on RPM hosts. Fingerprint sets are recorded to /var/tmp for the log.
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "rpm host: DEB keyring sabotage not applicable"
  exit 0
fi

KEYRING=/usr/share/keyrings/redpanda-redpanda-archive-keyring.gpg
KEY_URL=https://linux.pkg.redpanda.com/redpanda-deb-signing-public.gpg

list_fprs() {
  gpg --no-default-keyring --keyring "$1" --list-keys --with-colons 2>/dev/null \
    | awk -F: '/^fpr:/{print $10}'
}

echo "=== DEB keyring sabotage on $(hostname) (manufacturing the fpr-collision case) ==="
if [ ! -s "$KEYRING" ]; then
  echo "no baseline keyring at $KEYRING — phase-1 collection did not install one; nothing to sabotage"
  exit 0
fi
cp "$KEYRING" /tmp/rp-baseline-keyring
list_fprs /tmp/rp-baseline-keyring > /var/tmp/upgrade_keyring_baseline || true
echo "baseline keyring fprs (installed by the phase-1 collection):"
sed 's/^/  /' /var/tmp/upgrade_keyring_baseline

curl -fsSL "$KEY_URL" -o /tmp/rp-served.key
gpg --dearmor --yes -o /tmp/rp-served.gpg /tmp/rp-served.key
# served key first (its fpr is present, so a presence-gate skips), then the
# retained baseline key (so intermediate apt-get update still verifies)
cat /tmp/rp-served.gpg /tmp/rp-baseline-keyring > "$KEYRING"
chmod 0644 "$KEYRING"

list_fprs "$KEYRING" > /var/tmp/upgrade_keyring_sabotaged
echo "sabotaged keyring fprs (served key + retained baseline key):"
sed 's/^/  /' /var/tmp/upgrade_keyring_sabotaged
