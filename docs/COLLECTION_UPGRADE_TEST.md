# Collection upgrade testing

Every Redpanda CI lane in this repo runs as a **collection upgrade test**: it builds a cluster with
the **last released** `redpanda.cluster` collection, seeds data, then re-converges the *same* cluster
with the **candidate** collection (whatever `requirements.yml` pins) and asserts the re-converge was
safe and lossless. Redpanda itself is **pinned to one version across both phases**, so the only thing
that changes is the collection — which makes a red lane an unambiguous "this collection change breaks
re-convergence of an existing cluster."

This replaced the earlier standalone `ci:*:rp:upgrade` lanes (and the `AR_URL_UPGRADE_TEST.md`
runbook): rather than a separate upgrade job, the upgrade flow is now the default shape of every lane.

## What each lane does

```
prereqs (install candidate collection + roles)
─ Phase 1: the "existing cluster" ────────────────────────────
  override collection → LAST RELEASED (Galaxy)
  provision @ REDPANDA_VERSION (install_status=present)
  capture baseline broker version
  seed SEED_COUNT records + verify all readable
─ Phase 2: apply the candidate ───────────────────────────────
  restore collection → CANDIDATE (requirements.yml)
  re-provision @ the SAME REDPANDA_VERSION (install_status=present)
  deploy monitor + console (also re-converged on the candidate)
  profile tests (test:cluster[:tls], storage, …)
  upgrade:assert
─ destroy
```

`upgrade:assert` requires, on every broker: the package source is cut over to the Artifact Registry
(`linux.pkg.redpanda.com`) with **no stale `dl.redpanda.com` source**, `apt-get update` / `dnf
makecache` succeed with **no GPG/signature error**, the broker version is **unchanged** from phase 1
(RP is pinned), the service is **active**, and **all `SEED_COUNT` seeded records survive** (full count
+ tail record, so partial loss fails too).

## Why this shape

- **Evergreen.** "Last released → candidate" is a moving baseline that rolls forward every release —
  a permanent guard that the collection re-converges an existing cluster without disturbing it.
- **Pinning RP isolates the variable.** No Redpanda upgrade-path rules (no feature-version skips), so
  a failure points squarely at the collection change, not at Redpanda.
- **It still catches repo/key migrations.** When the released and candidate collections differ in repo
  URLs or signing keys, phase 2 exercises the cutover — e.g. it is exactly what caught the
  `NO_PUBKEY` failure during the dl.redpanda.com → Artifact Registry migration.

## Knobs (env)

| Var | Default | Meaning |
|-----|---------|---------|
| `REDPANDA_VERSION` | `26.1.11-1` | broker version, pinned across both phases. Must resolve in **both** the released collection's repo era and the candidate's. |
| `BASELINE_COLLECTION_REF` | `redpanda.cluster` | the "last released" collection; Galaxy latest by default. Override to pin a specific prior release. |
| `CANDIDATE_COLLECTION_REF` | _(unset → `requirements.yml`)_ | the collection under test. Unset installs whatever `requirements.yml` pins; or set it to a git branch (`git+<url>,<branch>`) or a released Galaxy version (`redpanda.cluster:0.12.0`). |
| `SEED_COUNT` | `500` | records seeded pre-converge and required intact after. |

`REDPANDA_VERSION` is the single pin knob; set it once at the Buildkite pipeline `env:` level.

## Coverage note
Because RP is pinned `present`, phase 2 does **not** pull a redpanda package from the candidate's repo
(it's already satisfied) — so a *fresh package install from AR* isn't exercised by these lanes while
the released baseline still predates the AR migration. That self-closes once an AR-based collection is
the released baseline (phase 1 then installs from AR), and fresh-install-from-AR is covered separately
by building the branch directly.

## Excluded
Unstable lanes (`IS_USING_UNSTABLE=true`) stay single-phase fresh installs — there's no sensible
"last stable release → nightly build" pairing.

## Running one locally
```bash
# candidate defaults to whatever requirements.yml pins; override it with CANDIDATE_COLLECTION_REF:
#   a git branch:       git+https://github.com/redpanda-data/redpanda-ansible-collection.git,my-branch
#   a released version: redpanda.cluster:0.12.0
DEPLOYMENT_ID=cu-ub-$RANDOM DISTRO=ubuntu-focal \
  CANDIDATE_COLLECTION_REF="git+https://github.com/redpanda-data/redpanda-ansible-collection.git,my-branch" \
  task ci:aws:rp
```
A green run prints `PASS on <host> (version stable …)` per broker and
`all <N> seeded records survived the collection re-converge (head..tail intact)`.

## Implementation notes
- `cluster:provision` / `cluster:tiered` take `RP_VERSION` + `RP_INSTALL_STATUS` and **do not** install
  collections themselves (no `:ansible:prereqs` dep) — the workflow controls which collection is active
  before each converge. Call `:ansible:prereqs` first if invoking them directly.
- Phase-1 baseline is set with `:ansible:collection:override` (force-installs `BASELINE_COLLECTION_REF`);
  phase-2 candidate is installed with `:ansible:collection:candidate` (force-installs `CANDIDATE_COLLECTION_REF`
  when set — a git branch or Galaxy version — otherwise from `requirements.yml`).
- TLS lanes pass `RPK_EXTRA='-X tls.ca={{.CA_CRT}}'` to `test:upgrade:seed` / `test:upgrade:assert`.
