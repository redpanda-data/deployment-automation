# CLAUDE.md

Terraform + Ansible automation to provision Redpanda on AWS / GCP / Azure / IBM.
This covers the non-obvious bits; see `README.md` for install and basic usage.

## Run things with Task

CI is driven by [Task](https://taskfile.dev). `Taskfile.yml` includes the modules
in `.tasks/` (namespaces: `infra ansible cluster monitor connect test ops ci cert
tools dev cleanup`). `task --list` shows everything.

The `ci:*` lanes run a full deployment end-to-end (provision → converge → assert →
tear down; each `defer`s its own teardown):

```shell
task ci:aws:rp                  # basic AWS upgrade test
task ci:aws:rp:tiered           # tiered storage over TLS (needs REDPANDA_LICENSE)
task ci:aws:rp:tiered:unstable  # fresh install from the unstable repo
task ci:gcp:rp                  # GCP equivalent
```

`.buildkite/pipeline.yml` just invokes these `ci:*` tasks. Task auto-loads `.env`
(dotenv) — handy for local knobs like `REDPANDA_LICENSE`; keep secrets out of git.

## Collection under test: `CANDIDATE_COLLECTION_REF`

`redpanda.cluster` installs from `requirements.yml` (Galaxy latest) by default. To
test a branch/tag/version without editing that file, set the env var — a git ref
(`git+<url>,<ref>`) or a Galaxy version (`redpanda.cluster:0.12.0`):

```shell
CANDIDATE_COLLECTION_REF="git+https://github.com/redpanda-data/redpanda-ansible-collection.git,my-branch" task ci:aws:rp
```

`:ansible:collection:pin` (run via `:ansible:prereqs`, `run: once`) force-installs
it in every workflow. Full detail: `docs/COLLECTION_UPGRADE_TEST.md`.

## Upgrade-test model

The `ci:*:rp*` lanes (except `:unstable`) are two-phase COLLECTION UPGRADE tests:
build with the last released collection (`BASELINE_COLLECTION_REF`, Galaxy) at a
pinned RP version and seed data, then re-converge with the candidate at the SAME
version and assert a safe re-converge + data survival. `:unstable` is single-phase
(fresh install at latest unstable). Helpers live in `scripts/upgrade/`.

## Layout

- `aws/ gcp/ azure/ ibm/` — Terraform per cloud
- `ansible/` — `provision-cluster*`, `deploy-{monitor,console,connect}*`, `operation-*`
- `docs/` — `COLLECTION_UPGRADE_TEST.md`, `CONNECT.md`

## Lint

GitHub Actions enforce `ansible-lint` and terraform `fmt` / `validate`
(the terraform checks are **AWS-only**) on PRs. Run `ansible-lint -c .ansible-lint`
locally (profile `production`).

- `.ansible-lint` excludes the cloud dirs, `templates/`, `artifacts/`; its skip
  list drops `jinja[spacing]`, `yaml[line-length]`, `yaml[trailing-spaces]`,
  `risky-shell-pipe`.
