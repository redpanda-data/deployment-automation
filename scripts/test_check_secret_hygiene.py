#!/usr/bin/env python3
"""Tests for scripts/check-secret-hygiene.py.

Each test writes a small repository into a temp directory, runs the guard on
it and checks which rules fire. The canary tests need `task` on PATH.

usage: python3 scripts/test_check_secret_hygiene.py
"""

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

GUARD = pathlib.Path(__file__).resolve().parent / "check-secret-hygiene.py"
HAVE_TASK = shutil.which(os.environ.get("TASK_BIN", "task")) is not None


def run_guard(files, *args, env=None):
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        files = dict(files)
        files.setdefault("Taskfile.yml", "version: '3'\ntasks: {}\n")
        for rel, content in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(textwrap.dedent(content))
        proc = subprocess.run(
            [sys.executable, str(GUARD), *args, str(root)],
            capture_output=True,
            text=True,
            env={**os.environ, **(env or {})},
            timeout=300,
        )
        return proc.returncode, proc.stdout + proc.stderr


def taskfile(tasks, extra=""):
    return "version: '3'\n" + extra + "tasks:\n" + textwrap.indent(textwrap.dedent(tasks), "  ")


def pipeline(steps):
    return "steps:\n" + textwrap.indent(textwrap.dedent(steps), "  ")


class GuardTestCase(unittest.TestCase):
    def assertFlags(self, files, rule, *args, env=None):
        rc, out = run_guard(files, "--static", *args, env=env) if "--canary" not in args else run_guard(files, *args, env=env)
        self.assertNotIn("Traceback", out)
        self.assertEqual(rc, 1, out)
        self.assertIn(f"[{rule}]", out, out)
        return out

    def assertClean(self, files, *args, env=None):
        rc, out = run_guard(files, "--static", *args, env=env) if "--canary" not in args else run_guard(files, *args, env=env)
        self.assertNotIn("Traceback", out)
        self.assertEqual(rc, 0, out)
        return out


class TaskFileRules(GuardTestCase):
    def test_templated_credential(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - terraform apply -var='gcp_creds={{.GCP_CREDS}}'
        """)}, "templated-secret")

    def test_index_form_template(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo {{index . "SASL_PASSWORD"}}
        """)}, "templated-secret")

    def test_credential_forwarded_by_pipeline_but_not_declared(self):
        self.assertFlags({
            "Taskfile.yml": taskfile("""
                t:
                  cmds:
                    - 'curl -H "Authorization: Bearer {{.CLOUDSMITH_API_TOKEN}}" https://example.invalid'
            """),
            ".buildkite/pipeline.yml": pipeline("""
                - command: task t
                  plugins:
                    - docker#v5.8.0:
                        image: img
                        environment:
                          - CLOUDSMITH_API_TOKEN
            """),
        }, "templated-secret")

    def test_names_without_the_usual_suffixes(self):
        for name in ("GCP_SA_KEY", "KAFKA_PWD", "BROKER_AUTH"):
            with self.subTest(name=name):
                self.assertFlags({"Taskfile.yml": taskfile(f"""
                    t:
                      vars:
                        {name}: '{{{{.{name} | default ""}}}}'
                      cmds:
                        - rpk topic list -X sasl.password={{{{.{name}}}}}
                """)}, "templated-secret")

    def test_derived_through_deps_vars(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            apply:
              deps:
                - task: write
                  vars: {LIC: '{{.REDPANDA_LICENSE}}'}
            write:
              cmds:
                - echo {{.LIC}}
        """)}, "templated-secret")

    def test_derived_through_defer_vars(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            apply:
              cmds:
                - defer: {task: write, vars: {LIC: '{{.REDPANDA_LICENSE}}'}}
            write:
              cmds:
                - echo {{.LIC}}
        """)}, "templated-secret")

    def test_derived_through_include_vars_and_yaml_extension(self):
        self.assertFlags({
            "Taskfile.yml": "version: '3'\nincludes:\n  x:\n    taskfile: .tasks/x.yaml\n    vars: {PW: '{{.SASL_PASSWORD}}'}\n",
            ".tasks/x.yaml": taskfile("""
                t:
                  cmds:
                    - echo {{.PW}}
            """),
        }, "templated-secret")

    def test_shell_alias_of_a_credential(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - |
                  P="$SASL_PASSWORD"
                  curl -u "admin:$P" https://example.invalid
        """)}, "shell-secret-argv")

    def test_task_shell_options_xtrace(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              set: [xtrace]
              cmds:
                - echo hi
        """)}, "shell-trace")
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo hi
        """, extra="set: [errexit, xtrace]\n")}, "shell-trace")

    def test_conditional_debug_that_is_not_an_opt_in(self):
        for cmd in (
            'ansible-playbook x.yml {{if hasPrefix "ci-" .DEPLOYMENT_ID}}-vvv{{end}}',
            '{{.RPK_PATH}} cluster status {{if ne .RPK_DEBUG "true"}}-v{{end}}',
            'ansible-playbook x.yml --extra-vars redpanda_broker_no_log={{if .CI}}false{{else}}true{{end}}',
        ):
            with self.subTest(cmd=cmd):
                rc, out = run_guard({"Taskfile.yml": taskfile(f"""
                    t:
                      cmds:
                        - '{cmd}'
                """)}, "--static")
                self.assertEqual(rc, 1, out)

    def test_debug_flags_anywhere_on_the_command(self):
        for cmd in (
            "ansible-playbook -vvv x.yml",
            "ansible-playbook --verbose x.yml",
            "{{.RPK_PATH}} -v cluster status",
            '"$RPK" cluster status -v',
            "curl -kv --cert c.crt --key c.key https://example.invalid",
        ):
            with self.subTest(cmd=cmd):
                self.assertFlags({"Taskfile.yml": taskfile(f"""
                    t:
                      cmds:
                        - '{cmd}'
                """)}, "debug-output")

    def test_ansible_display_args_env(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              env:
                ANSIBLE_DISPLAY_ARGS_TO_STDOUT: 'true'
              cmds:
                - ansible-playbook x.yml
        """)}, "debug-output")

    def test_env_entry_that_the_process_environment_overrides(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              env:
                REDPANDA_LICENSE: '{{.REDPANDA_LICENSE}}'
              cmds:
                - ansible-playbook x.yml
        """)}, "env-shadowed")

    def test_fixed_path_write_across_a_line_continuation(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - |
                  printf '%s' "$GCP_CREDS" | base64 -d \\
                    > /tmp/gcp_creds.json
        """)}, "secret-fixed-file")

    def test_artifact_upload_from_a_task(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - buildkite-agent artifact upload "artifacts/logs/*.log"
        """)}, "artifact")


class SafeFormsStayClean(GuardTestCase):
    def test_safe_shell_forms(self):
        for body in (
            'TF_VAR_gcp_creds="$GCP_CREDS" terraform plan',
            'printf \'%s\\n\' "$GCP_CREDS" | base64 -d > "$f"',
            ': "${REDPANDA_LICENSE:?set REDPANDA_LICENSE}"',
            '[ -n "${REDPANDA_LICENSE:-}" ] || exit 1',
            'echo "$CONNECT_RPM_TOKEN" | docker login --password-stdin example.invalid',
            "printf '%s' \"$GCP_CREDS\" \\\n  | base64 -d > \"$f\"",
            "printf '%s' \"$GCP_CREDS\" | gcloud auth activate-service-account --key-file=- >/dev/null",
        ):
            with self.subTest(body=body):
                yml = "version: '3'\ntasks:\n  t:\n    cmds:\n      - |\n" + textwrap.indent(body, " " * 8) + "\n"
                self.assertClean({"Taskfile.yml": yml})

    def test_ordinary_commands(self):
        for cmd in (
            "ansible-playbook x.yml 2>&1 | grep -v WARNING",
            "env TF_IN_AUTOMATION=1 terraform plan",
            "sed -e 's/^token=.*/token=x/' f.conf",
            "ansible-playbook x.yml --extra-vars enable_sasl_token_auth=true",
        ):
            with self.subTest(cmd=cmd):
                self.assertClean({"Taskfile.yml": taskfile(f"""
                    t:
                      cmds:
                        - "{cmd}"
                """)})

    def test_opt_in_debug_and_quiet_knob_values(self):
        self.assertClean({"Taskfile.yml": taskfile("""
            t:
              vars:
                RPK_DEBUG: '{{.RPK_DEBUG}}'
              cmds:
                - '{{.RPK_PATH}} cluster status {{if eq .RPK_DEBUG "true"}}-v{{end}}'
                - task: u
                  vars: {RPK_DEBUG: 'false'}
            u:
              env:
                TF_LOG: ''
              cmds:
                - echo ok
        """, extra="vars:\n  RPK_DEBUG: '{{.RPK_DEBUG | default \"false\"}}'\n")})

    def test_variable_read_by_a_tool_from_its_environment(self):
        self.assertClean({
            ".buildkite/pipeline.yml": pipeline("""
                - command: task t
                  plugins:
                    - docker#v5.8.0:
                        image: img
                        environment:
                          - GOOGLE_CREDENTIALS
            """),
        })


class PipelineRules(GuardTestCase):
    def test_group_steps_are_checked(self):
        self.assertFlags({".buildkite/pipeline.yml": pipeline("""
            - group: lanes
              steps:
                - command: set -x; task ci
        """)}, "shell-trace")

    def test_plugins_in_map_form(self):
        self.assertFlags({".buildkite/pipeline.yml": """
            steps:
              - command: task t
                plugins:
                  docker#v5.8.0:
                    image: img
                    environment:
                      - TF_LOG=debug
        """}, "debug-output")

    def test_artifact_globs(self):
        for art in ("artifacts/**/*", "aws/terraform.tfstat*", "ansible/tls/**/*"):
            with self.subTest(art=art):
                self.assertFlags({".buildkite/pipeline.yml": pipeline(f"""
                    - command: task t
                      artifact_paths: "{art}"
                """)}, "artifact")

    def test_steps_with_depends_on_must_depend_on_the_guard(self):
        self.assertFlags({".buildkite/pipeline.yml": pipeline("""
            - key: secret-hygiene
              command: task tools:lint:secrets
            - wait
            - key: lane
              command: task ci
            - key: cleanup
              command: task cleanup
              depends_on: [lane]
              allow_dependency_failure: true
        """)}, "guard-bypass")
        self.assertFlags({".buildkite/pipeline.yml": pipeline("""
            - key: secret-hygiene
              command: task tools:lint:secrets
            - wait
            - key: lane
              command: task ci
            - key: cleanup
              command: task cleanup
              depends_on: [secret-hygiene, lane]
              allow_dependency_failure: true
        """)}, "guard-bypass")
        self.assertFlags({".buildkite/pipeline.yml": pipeline("""
            - key: secret-hygiene
              command: task tools:lint:secrets
            - wait
            - key: lane
              command: task ci
            - key: cleanup
              command: task cleanup
              depends_on: [lane]
        """)}, "guard-bypass")
        self.assertClean({".buildkite/pipeline.yml": pipeline("""
            - key: secret-hygiene
              command: task tools:lint:secrets
            - wait
            - key: lane
              command: task ci
            - key: cleanup
              command: task cleanup
              depends_on:
                - step: secret-hygiene
                - step: lane
                  allow_failure: true
        """)})


class Robustness(GuardTestCase):
    def test_bad_yaml_is_reported_not_crashed(self):
        out = self.assertFlags({"Taskfile.yml": "version: '3'\n---\ntasks: {}\n"}, "yaml")
        self.assertNotIn("Traceback", out)

    def test_missing_task_binary_is_reported(self):
        rc, out = run_guard({}, "--canary", env={"TASK_BIN": "/nonexistent/task"})
        self.assertEqual(rc, 1, out)
        self.assertIn("[canary]", out)
        self.assertNotIn("Traceback", out)

    def test_line_numbers_use_the_exact_task(self):
        out = self.assertFlags({"Taskfile.yml": taskfile("""
            aws:rp:workflow:
              cmds:
                - echo {{.SASL_PASSWORD}}

            aws:rp:
              cmds:
                - echo {{.SASL_PASSWORD}}
        """)}, "templated-secret")
        self.assertIn("Taskfile.yml:6: [templated-secret] task aws:rp:workflow", out)
        self.assertIn("Taskfile.yml:10: [templated-secret] task aws:rp cmd", out)
        out = self.assertFlags({"Taskfile.yml": taskfile("""
            a:
              cmds:
                - echo ok

            b:
              set: [xtrace]
              cmds:
                - echo ok
        """)}, "shell-trace")
        self.assertIn("Taskfile.yml:9:", out)


@unittest.skipUnless(HAVE_TASK, "task not on PATH")
class CanaryRules(GuardTestCase):
    def test_silent_task_is_still_dry_run(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              silent: true
              vars:
                X: '{{.SASL_PASSWORD}}'
              cmds:
                - echo {{.X}}
        """)}, "canary", "--canary")

    def test_a_task_that_cannot_be_dry_run_fails_closed(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - task: does-not-exist
        """)}, "canary", "--canary")

    def test_canaries_are_passed_as_task_arguments(self):
        out = self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo {{.SASL_PASSWORD}}
        """, extra="vars:\n  SASL_PASSWORD: fixed\n")}, "canary", "--canary")
        self.assertIn("SASL_PASSWORD printed in clear", out)

    def test_labelled_tasks_are_dry_run_by_name(self):
        self.assertClean({"Taskfile.yml": taskfile("""
            lint:all:
              label: 'lint all {{.DISTRO}}'
              cmds:
                - echo ok
        """)}, "--canary")

    def test_guard_output_never_carries_a_real_value(self):
        rc, out = run_guard({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo {{.ZZ_REAL}} {{.SASL_PASSWORD}}
        """, extra="vars:\n  BOOM:\n    sh: 'echo {{.ZZ_REAL}}; exit 3'\n")}, "--canary", env={"ZZ_REAL": "realvalue-0451"})
        self.assertNotIn("realvalue-0451", out)
        self.assertNotIn("Traceback", out)


GUARDED = """
    - key: secret-hygiene
      command: task tools:lint:secrets
    - wait
    - key: lane
      command: task ci
      plugins:
        - seek-oss/aws-sm#v2.3.2:
            json-to-env: [{json-key: ., secret-id: x}]
"""


class GuardOrdering(GuardTestCase):
    def test_guarded_pipeline_is_clean(self):
        self.assertClean({".buildkite/pipeline.yml": pipeline(GUARDED)})

    def test_lanes_that_can_start_before_the_guard_passes(self):
        cases = {
            "step above the wait": GUARDED.replace("    - wait\n", "    - key: early\n      command: task ci\n    - wait\n"),
            "no wait": GUARDED.replace("    - wait\n", ""),
            "soft_fail guard": GUARDED.replace("      command: task tools:lint:secrets\n",
                                               "      command: task tools:lint:secrets\n      soft_fail: true\n"),
            "wait that continues on failure": GUARDED.replace(
                "    - wait\n", "    - wait: ~\n      continue_on_failure: true\n"),
            "guard that cannot fail": GUARDED.replace("command: task tools:lint:secrets", "command: task tools:lint:secrets || true"),
            "guard on some branches": GUARDED.replace("      command: task tools:lint:secrets\n",
                                                      "      command: task tools:lint:secrets\n      branches: main\n"),
            "conditional guard": GUARDED.replace("      command: task tools:lint:secrets\n",
                                                 "      command: task tools:lint:secrets\n      if: build.branch == 'main'\n"),
        }
        for name, steps in cases.items():
            with self.subTest(case=name):
                self.assertFlags({".buildkite/pipeline.yml": pipeline(steps)}, "guard-bypass")


class MoreTaskRules(GuardTestCase):
    def test_decoded_credential_to_stdout(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo "$GCP_CREDS" | base64 -d
        """)}, "secret-to-stdout")

    def test_flow_style_env_knobs(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              env: {TF_LOG: debug, ANSIBLE_VERBOSITY: '4'}
              cmds:
                - terraform plan
        """)}, "debug-output")

    def test_more_safe_forms(self):
        for body in (
            '[ "$GCP_CREDS" = "" ] && exit 0',
            'TF_VAR_gcp_creds="$GCP_CREDS" terraform plan > plan.txt',
        ):
            with self.subTest(body=body):
                yml = "version: '3'\ntasks:\n  t:\n    cmds:\n      - |\n        " + body + "\n"
                self.assertClean({"Taskfile.yml": yml})

    def test_variable_read_by_the_collection(self):
        self.assertClean({".buildkite/pipeline.yml": pipeline("""
            - command: task t
              plugins:
                - docker#v5.8.0:
                    image: img
                    environment:
                      - CLOUDSMITH_API_KEY
        """)})

    def test_malformed_task_files_are_reported(self):
        for doc in ("version: '3'\ntasks: [a, b]\n", "version: '3'\ntasks:\n  t:\n    cmds: echo hi\n    deps: x\n"):
            with self.subTest(doc=doc):
                rc, out = run_guard({"Taskfile.yml": doc}, "--static")
                self.assertNotIn("Traceback", out)


@unittest.skipUnless(HAVE_TASK, "task not on PATH")
class HermeticCanary(GuardTestCase):
    def test_dotenv_is_not_used(self):
        out = self.assertClean({
            ".env": "RPK_DEBUG=true\nZZ_FROM_DOTENV=dotenv-value-0451\n",
            "Taskfile.yml": "version: '3'\ndotenv: ['.env']\nvars:\n  RPK_DEBUG: '{{.RPK_DEBUG | default \"false\"}}'\n"
                            "tasks:\n  t:\n    cmds:\n"
                            "      - 'rpk cluster status {{if eq .RPK_DEBUG \"true\"}}-v{{end}} {{.ZZ_FROM_DOTENV}}'\n",
        }, "--canary")
        self.assertNotIn("dotenv-value-0451", out)

class CoreRulesArePinned(GuardTestCase):
    def test_credential_arguments(self):
        for cmd in (
            "terraform apply -var='gcp_creds=abc'",
            "ansible-playbook x.yml --extra-vars redpanda_license=abc",
            """ansible-playbook x.yml --extra-vars '{"sasl_password": "abc"}'""",
        ):
            with self.subTest(cmd=cmd):
                yml = "version: '3'\ntasks:\n  t:\n    cmds:\n      - |\n        " + cmd + "\n"
                self.assertFlags({"Taskfile.yml": yml}, "secret-cli-arg")

    def test_url_credential_and_env_dump(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - git clone https://user:pw@example.invalid/repo.git
        """)}, "url-credential")
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - env | sort
        """)}, "env-dump")

    def test_unused_credentials(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo ok
        """, extra="vars:\n  TOKEN: '{{.CONNECT_RPM_TOKEN | default \"\"}}'\n")}, "unused-credential")
        self.assertFlags({".buildkite/pipeline.yml": pipeline("""
            - command: task t
              plugins:
                - docker#v5.8.0:
                    image: img
                    environment:
                      - CONNECT_RPM_TOKEN
        """), "scripts/test_check_secret_hygiene.py": "# mentions CONNECT_RPM_TOKEN\n"}, "unused-credential")

    def test_plugin_hooks_are_checked(self):
        self.assertFlags({".buildkite/pipeline.yml": pipeline("""
            - command: task t
              plugins:
                - docker#v5.8.0:
                    image: img
                    pre-exit: 'echo "$GCP_CREDS" | base64 -d'
        """)}, "secret-to-stdout")

    def test_cloud_cli_debug_flags(self):
        for cmd in ("gcloud storage ls --log-http", "gcloud storage ls --verbosity=debug", "aws s3 ls --debug"):
            with self.subTest(cmd=cmd):
                self.assertFlags({"Taskfile.yml": taskfile(f"""
                    t:
                      cmds:
                        - {cmd}
                """)}, "debug-output")

    def test_pw_suffix(self):
        self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - echo {{.ADMIN_PW}}
        """)}, "templated-secret")

    def test_malformed_input_is_a_finding(self):
        rc, out = run_guard({"Taskfile.yml": "version: '3'\ntasks: [a, b]\n"}, "--static")
        self.assertEqual(rc, 1, out)
        self.assertIn("[internal]", out)


@unittest.skipUnless(HAVE_TASK, "task not on PATH")
class CanaryReporting(GuardTestCase):
    def test_canary_hits_are_masked_and_base64_values_found(self):
        out = self.assertFlags({"Taskfile.yml": taskfile("""
            t:
              cmds:
                - terraform apply -var='x={{.GCP_CREDS}}' -var='y={{.SASL_PASSWORD}}'
        """)}, "canary", "--canary")
        self.assertRegex(out, r"\[canary\] [^\n]*GCP_CREDS[^\n]*printed in clear")
        self.assertIn("<SASL_PASSWORD>", out)
        self.assertNotRegex(out, r"canary\d{3}x")

    def test_files_under_home_never_reach_the_report(self):
        with tempfile.TemporaryDirectory() as home:
            pathlib.Path(home, "secret.txt").write_text("home-value-7781\n")
            rc, out = run_guard({"Taskfile.yml": taskfile("""
                t:
                  cmds:
                    - echo {{.R}} {{.SASL_PASSWORD}}
            """, extra="vars:\n  R:\n    sh: 'cat $HOME/secret.txt 2>/dev/null || true'\n")}, "--canary", env={"HOME": home})
            self.assertNotIn("home-value-7781", out)

if __name__ == "__main__":
    unittest.main()
