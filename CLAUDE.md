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

- `task tools:lint:secrets` (`scripts/check-secret-hygiene.py`, tested by
  `scripts/test_check_secret_hygiene.py`) runs first in the Buildkite pipeline
  and blocks the lanes. Task prints every command after expanding `{{.VAR}}`, so
  a credential goes through the task's `env:` block and the program reads it
  from its environment (`TF_VAR_*`, an Ansible env lookup); never template it
  into a command or put it on a command line. Give the `env:` entry a name that
  is not already in the process environment (`DA_REDPANDA_LICENSE`), because a
  process environment value wins over a task's `env:`. Debug output
  (`REDPANDA_BROKER_NO_LOG=false`, `HTTP_DEBUG=true`, `RPK_DEBUG=true`, `ANSIBLE_VERBOSITY`,
  `TF_LOG`, `-v` on ansible) is for local runs only; CI must not set it.
- `.ansible-lint` excludes the cloud dirs, `templates/`, `artifacts/`; its skip
  list drops `jinja[spacing]`, `yaml[line-length]`, `yaml[trailing-spaces]`,
  `risky-shell-pipe`.
