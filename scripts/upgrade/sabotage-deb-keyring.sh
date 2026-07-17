#!/usr/bin/env bash
# Upgrade fixture: force the DEB key-rotation refresh path so the assert can
# prove the candidate collection replaces stale keyring material during an
# upgrade — not just on fresh installs. Run between phase 1 (baseline converge)
# and phase 2 (candidate converge):
#   ansible redpanda -b -m script -a scripts/upgrade/sabotage-deb-keyring.sh
#
# The sabotage writes "served-key + served-key" (the currently served keyring
# concatenated with itself) into the redpanda keyring. This is a valid keyring
# whose FIRST fingerprint matches the served key — so a fingerprint-presence
# gate (the pre-fix logic) skips the refresh and leaves the doubled keyring in
# place — but whose bytes differ from the pristine dearmored key, so the
# whole-keyring comparison (the fixed logic) must replace it. assert-node.sh
# then requires the installed keyring to be byte-identical to the served key.
#
# Fingerprint sets are recorded to /var/tmp for before/after visibility:
#   upgrade_keyring_baseline  - keyring as left by the phase-1 (released) collection
#   upgrade_keyring_sabotaged - keyring after this sabotage
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

echo "=== DEB keyring sabotage on $(hostname) (forcing the rotation-refresh path) ==="
list_fprs "$KEYRING" > /var/tmp/upgrade_keyring_baseline || true
echo "baseline keyring fprs (phase-1 collection):"
sed 's/^/  /' /var/tmp/upgrade_keyring_baseline

curl -fsSL "$KEY_URL" -o /tmp/rp-served.key
gpg --dearmor --yes -o /tmp/rp-served.gpg /tmp/rp-served.key
cat /tmp/rp-served.gpg /tmp/rp-served.gpg > "$KEYRING"
chmod 0644 "$KEYRING"

list_fprs "$KEYRING" > /var/tmp/upgrade_keyring_sabotaged
echo "sabotaged keyring fprs (served key doubled — first-fpr gates would skip refresh):"
sed 's/^/  /' /var/tmp/upgrade_keyring_sabotaged
