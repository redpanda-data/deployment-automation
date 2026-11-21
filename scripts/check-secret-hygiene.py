#!/usr/bin/env python3
"""Fail when a task or a CI step can write a credential to a job log or the
terminal.

Task echoes every command after expanding {{.VAR}} templates, so a credential
must reach a command through a task env: block and be read by the program from
its environment, never templated into the command or placed on its argv.

Two checks, both offline and credential-free:

  canary  Copies the repo, turns off `silent:`, sets every credential-like
          variable to a distinct canary in a scrubbed environment and as a
          task argument, runs `task --dry --force` for every task, and fails
          if a canary is printed or a printed command turns on debug output.
  static  Reads the task files, pipeline, workflows and scripts for what a
          dry run cannot see: credentials expanded from shell variables onto
          a command line, credential-named --extra-vars and -var arguments,
          debug and trace switches, no_log turned off, credentials written to
          fixed paths or uploaded as artifacts, credentials nothing reads,
          and steps that can run when this guard fails.

usage: scripts/check-secret-hygiene.py [--canary | --static] [REPO_ROOT]
"""

import argparse
import base64
import concurrent.futures
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:
    sys.exit("check-secret-hygiene: PyYAML is required (the CI image's python3 has it)")

SECRET_ENV_NAME = re.compile(
    r"(PASSWORD|PASSWD|_PWD$|SECRET|TOKEN|CREDS|CREDENTIALS|LICENSE|API_KEY|ACCESS_KEY|SA_KEY|KEY_JSON"
    r"|PASSPHRASE|(^|_)AUTH$|(^|_)PASS$|(^|_)PW$)"
)
SECRET_PARAM_NAME = re.compile(
    r"(passw|(^|_)pass$|(^|_)pw$|pwd|secret|token|creds|credential|license|api_key|access_key|private_key"
    r"|passphrase)",
    re.I,
)
NOT_A_SECRET_SUFFIX = ("_PATH", "_FILE", "_DIR", "_SOURCE", "_NAME", "_STATUS")
LITERAL_FLAG = re.compile(r"(?i)(true|false|yes|no|on|off|\d+)")
# Read by a tool from its own environment, so nothing in the repo names them.
IMPLICIT_READER = re.compile(r"^(GOOGLE_|AWS_|ARM_|AZURE_|TF_VAR_|IBMCLOUD_|CLOUDSMITH_)")

# Always given a canary, so a rename or a new consumer is still covered when
# the task files do not mention the variable yet.
KNOWN_SECRETS = [
    "GCP_CREDS",
    "GOOGLE_CREDENTIALS",
    "GOOGLE_CREDENTIALS_BASE64",
    "REDPANDA_LICENSE",
    "SASL_PASSWORD",
    "SASL_TEST_PASSWORD",
    "SASL_SUPERUSER_PASSWORD",
    "CONNECT_RPM_TOKEN",
    "TOKEN",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "DA_AWS_ACCESS_KEY_ID",
    "DA_AWS_SECRET_ACCESS_KEY",
    "AZURE_CLIENT_SECRET",
    "ARM_CLIENT_SECRET",
    "ARM_ACCESS_KEY",
    "IBMCLOUD_API_KEY",
    "GRAFANA_ADMIN_PASS",
]

# Switches that print module arguments, task environments, request bodies or
# every expanded command, with their quiet value. Developers may set them
# locally; CI must not.
DEBUG_KNOBS = {
    "TF_LOG": "",
    "TF_LOG_CORE": "",
    "TF_LOG_PROVIDER": "",
    "ANSIBLE_DEBUG": "false",
    "ANSIBLE_VERBOSITY": "0",
    "ANSIBLE_DISPLAY_ARGS_TO_STDOUT": "false",
    "REDPANDA_BROKER_NO_LOG": "true",
    "HTTP_DEBUG": "false",
    "RPK_DEBUG": "false",
}
QUIET_VALUES = {"", "0", "false", "no", "off"}
# The only template branches a static scan may drop: they render nothing
# unless a local run sets the switch.
OPT_IN_BRANCH = re.compile(r'{{-?\s*if\s+eq\s+\.(HTTP_DEBUG|RPK_DEBUG)\s+"true"\s*-?}}.*?{{-?\s*end\s*-?}}', re.S)

TEMPLATE_ACTION = re.compile(r"{{-?(.*?)-?}}", re.S)
TEMPLATE_REF = re.compile(r"(?<![\w\"'])\.([A-Za-z_][A-Za-z0-9_]*)|\bindex\s+\.\s+\"([A-Za-z_][A-Za-z0-9_]*)\"")
SHELL_REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
RISKY_ARTIFACT = re.compile(
    r"tfstat|tfvars|creds|credential|secret|license|\.key\b|\.env\b|testkey|ansible/tls|artifacts/|\*\*|\.log\b", re.I
)
GUARD_STEP = "secret-hygiene"


def is_secret_env(name):
    if name.upper().endswith(NOT_A_SECRET_SUFFIX):
        return False
    return bool(SECRET_ENV_NAME.search(name.upper()))


def is_secret_param(name):
    if name.upper().endswith(NOT_A_SECRET_SUFFIX):
        return False
    return bool(SECRET_PARAM_NAME.search(name))


class Report:
    def __init__(self, root):
        self.root = root
        self.violations = []

    def add(self, path, line, rule, message):
        rel = os.path.relpath(path, self.root) if path else "-"
        entry = f"{rel}:{line}: [{rule}] {message}"
        if entry not in self.violations:
            self.violations.append(entry)


def line_of(text, needle, start=0, hint=None):
    """1-based line of needle in text at or after start, else of hint, else of start."""
    for candidate in (needle.strip(), (needle.strip().splitlines() or [""])[0].strip(), hint):
        if candidate:
            idx = text.find(candidate, start)
            if idx >= 0:
                return text.count("\n", 0, idx) + 1
    return text.count("\n", 0, start) + 1 if start else 0


def task_offset(raw, tname):
    m = re.search(r"^[ \t]+['\"]?" + re.escape(tname) + r"['\"]?:[ \t]*(#.*)?$", raw, re.M)
    return m.start() if m else 0


class TolerantLoader(yaml.SafeLoader):
    """SafeLoader that reads unknown tags such as !vault as plain values."""


def _any_tag(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_mapping(node)


TolerantLoader.add_multi_constructor("", _any_tag)


def load_yaml(path, report=None):
    try:
        with open(path) as f:
            return yaml.load(f, Loader=TolerantLoader)
    except (yaml.YAMLError, OSError) as e:
        if report is not None:
            report.add(path, getattr(getattr(e, "problem_mark", None), "line", -1) + 1, "yaml",
                       f"cannot be parsed, so it went unchecked: {str(e).splitlines()[0]}")
        return None


# ---------------------------------------------------------------------------
# Task files


def taskfiles(root):
    seen, queue = [], [root / "Taskfile.yml"]
    queue += sorted((root / ".tasks").glob("*.yml")) + sorted((root / ".tasks").glob("*.yaml"))
    while queue:
        path = queue.pop(0)
        if not path.exists() or path in seen:
            continue
        seen.append(path)
        doc = load_yaml(path)
        for inc in ((doc or {}).get("includes") or {}).values() if isinstance(doc, dict) else []:
            target = inc.get("taskfile") if isinstance(inc, dict) else inc
            if isinstance(target, str) and "{{" not in target:
                target = (root / target).resolve()
                queue.append(target / "Taskfile.yml" if target.is_dir() else target)
    return seen


def var_definitions(block):
    """Yield (name, text, is_sh) for a vars: or env: mapping."""
    if not isinstance(block, dict):
        return
    for name, value in block.items():
        if isinstance(value, dict):
            if "sh" in value:
                yield name, str(value["sh"]), True
            elif "ref" in value:
                yield name, "{{" + str(value["ref"]) + "}}", False
        elif value is not None:
            yield name, str(value), False


def call_vars(item):
    """vars: passed to another task by a cmds, deps or defer entry."""
    if not isinstance(item, dict):
        return []
    blocks = [item.get("vars")]
    if isinstance(item.get("defer"), dict):
        blocks.append(item["defer"].get("vars"))
    return [d for b in blocks for d in var_definitions(b)]


def command_strings(task):
    """Yield (kind, text) for every string Task runs or prints for a task."""
    if isinstance(task, str):
        yield "cmd", task
        return
    if isinstance(task, list):
        for item in task:
            if isinstance(item, str):
                yield "cmd", item
        return
    if not isinstance(task, dict):
        return
    if isinstance(task.get("cmd"), str):
        yield "cmd", task["cmd"]
    for item in task.get("cmds") or []:
        if isinstance(item, str):
            yield "cmd", item
        elif isinstance(item, dict):
            if isinstance(item.get("cmd"), str):
                yield "cmd", item["cmd"]
            deferred = item.get("defer")
            if isinstance(deferred, str):
                yield "defer", deferred
            elif isinstance(deferred, dict) and isinstance(deferred.get("cmd"), str):
                yield "defer", deferred["cmd"]
    for item in task.get("status") or []:
        if isinstance(item, str):
            yield "status", item
    for item in task.get("preconditions") or []:
        if isinstance(item, str):
            yield "precondition", item
        elif isinstance(item, dict) and isinstance(item.get("sh"), str):
            yield "precondition", item["sh"]
    for block in ("vars", "env"):
        for name, text, is_sh in var_definitions(task.get(block)):
            if is_sh:
                yield f"{block}.{name} (sh)", text


class TaskModel:
    def __init__(self, root, report):
        self.defs = []  # (name, text, scope) where scope is "var" or "env"
        self.commands = []  # (path, raw, task, kind, text)
        self.env_entries = []  # (path, raw, task, name, text)
        self.shell_options = []  # (path, raw, task, options)
        self.files = taskfiles(root)
        for path in self.files:
            raw = path.read_text()
            doc = load_yaml(path, report)
            if not isinstance(doc, dict):
                continue
            self.shell_options.append((path, raw, "<global>", doc.get("set")))
            for block, scope in (("vars", "var"), ("env", "env")):
                for name, text, is_sh in var_definitions(doc.get(block)):
                    self.defs.append((name, text, scope))
                    if scope == "env":
                        self.env_entries.append((path, raw, "<global>", name, text))
                    if is_sh:
                        self.commands.append((path, raw, "<global>", f"{block}.{name} (sh)", text))
            for inc in (doc.get("includes") or {}).values():
                if isinstance(inc, dict):
                    for name, text, _ in var_definitions(inc.get("vars")):
                        self.defs.append((name, text, "var"))
            for tname, task in (doc.get("tasks") or {}).items():
                if isinstance(task, dict):
                    self.shell_options.append((path, raw, tname, task.get("set")))
                    for block, scope in (("vars", "var"), ("env", "env")):
                        for name, text, _ in var_definitions(task.get(block)):
                            self.defs.append((name, text, scope))
                            if scope == "env":
                                self.env_entries.append((path, raw, tname, name, text))
                    for item in (task.get("cmds") or []) + (task.get("deps") or []):
                        for name, text, _ in call_vars(item):
                            self.defs.append((name, text, "var"))
                for kind, text in command_strings(task):
                    self.commands.append((path, raw, tname, kind, text))


def template_refs(text, include_conditions):
    refs = set()
    for action in TEMPLATE_ACTION.findall(text):
        body = action.strip()
        if not include_conditions and re.match(r"(else\s+)?if\b", body):
            continue
        for a, b in TEMPLATE_REF.findall(body):
            refs.add(a or b)
    return refs


def secret_names(model, extra=()):
    """Credential-named variables, plus every variable derived from one."""
    names = set(KNOWN_SECRETS) | set(extra)
    for name, _, _ in model.defs:
        if is_secret_env(name):
            names.add(name)
    for *_, text in model.commands:
        names |= {n for n in template_refs(text, True) | set(SHELL_REF.findall(text)) if is_secret_env(n)}
    template_secrets = set(names)
    shell_secrets = set(names)
    changed = True
    while changed:
        changed = False
        for name, text, scope in model.defs:
            if template_refs(text, include_conditions=False) & template_secrets:
                target = template_secrets if scope == "var" else shell_secrets
                if name not in target:
                    target.add(name)
                    changed = True
    shell_secrets |= template_secrets
    return template_secrets, shell_secrets


# ---------------------------------------------------------------------------
# Rules over shell text


SAFE_SHELL_FORMS = [
    # printf and echo are shell builtins: piped or redirected, the value goes
    # to the pipe or file, not to a process argv or the log.
    r"printf\s+['\"]?%s(\\n)?['\"]?\s+\"?\$\{?NAME\}?\"?\s*[|>]",
    r"\becho\s+\"?\$\{?NAME\}?\"?\s*\|",
    r"\[\s+-[nz]\s+\"?\$\{?NAME(:?[-+?=][^}]*)?\}?\"?\s+\]",
    r"\btest\s+-[nz]\s+\"?\$\{?NAME(:?[-+?=][^}]*)?\}?\"?",
    r"\[\s+\"\$\{?NAME\}?\"\s*!?=\s*\"\"\s+\]",
    r"(^|[;&|]\s*):\s+\"?\$\{NAME:?\?[^}]*\}\"?",
    r"^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*=\"?\$\{?NAME\}?\"?\s*$",
    # NAME=value cmd hands the value to cmd's environment.
    r"(^|[;&|]\s*)([A-Za-z_][A-Za-z0-9_]*=\"?\$\{?NAME\}?\"?\s+)+(?=[A-Za-z./$\"])",
]
FIXED_FILE_REDIRECT = re.compile(r"(?:(?<![0-9&>])>{1,2}|\btee\s+(?:-a\s+)?)\s*['\"]?(?!/dev/(null|std))(?!&)[^\s'\"$&|]")
ENV_PREFIX = r"(^|[;&|]\s*)([A-Za-z_][A-Za-z0-9_]*=\"?\$\{?NAME\}?\"?\s+)+(?=[A-Za-z./$\"])"
# Commands that pass what they read straight to their output.
PRINTERS = re.compile(r"^\s*(base64|cat|tr|sed|awk|jq|xxd|od|head|tail|rev|cut|fold|gunzip|zcat|openssl|tee\s+/dev/std)")


def shell_lines(text):
    text = re.sub(r"\\\n\s*", " ", text)
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            yield line


def risky_artifact(path):
    return bool(RISKY_ARTIFACT.search(path))


def check_shell(report, path, raw, where, text, template_secrets, shell_secrets, start=0):
    for action in TEMPLATE_ACTION.findall(text):
        body = action.strip()
        if re.match(r"(else\s+)?if\b", body):
            continue
        leaked = sorted({a or b for a, b in TEMPLATE_REF.findall(body)} & template_secrets)
        if leaked:
            token = "{{" + action + "}}"
            cmd_line = next((ln for ln in text.splitlines() if token in ln), token)
            report.add(
                path,
                line_of(raw, cmd_line, start, hint=token),
                "templated-secret",
                f"{where}: {{{{{body}}}}} expands {', '.join(leaked)} into a command Task echoes; "
                "pass it through the task's env: block and let the program read it from the environment",
            )

    secrets = set(shell_secrets)
    for line in shell_lines(text):
        lineno = line_of(raw, line, start)
        assign = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if assign and (set(SHELL_REF.findall(assign.group(2))) & secrets
                       or template_refs(assign.group(2), False) & template_secrets):
            secrets.add(assign.group(1))
        for name in sorted(n for n in secrets if re.search(r"\$\{?" + re.escape(n) + r"\b", line)):
            residue = line
            for form in SAFE_SHELL_FORMS:
                residue = re.sub(form.replace("NAME", re.escape(name)), " ", residue)
            if re.search(r"\$\{?" + re.escape(name) + r"\b", residue):
                report.add(
                    path,
                    lineno,
                    "shell-secret-argv",
                    f"{where}: ${name} is expanded into a command line; pass it to the "
                    "program through its environment (or printf it into a pipe or a mktemp file)",
                )

        for m in re.finditer(r"(?:^|\s)-var[= ]\s*['\"]?([A-Za-z0-9_]+)=([^\s'\"]*)", line):
            if is_secret_param(m.group(1)) and not LITERAL_FLAG.fullmatch(m.group(2)):
                report.add(
                    path,
                    line_of(raw, m.group(0), start),
                    "secret-cli-arg",
                    f"{where}: -var {m.group(1)}=... puts a credential on terraform's command line; "
                    f"export TF_VAR_{m.group(1)} from the task's env: block instead",
                )
        if re.search(r"(^|[\s;&|(/])ansible(-playbook)?\s", line):
            for m in re.finditer(r"(?:^|\s)(?:--extra-vars|-e)[= ]\s*['\"]?([^@\s'\"{][^=\s'\"]*)=([^\s'\"]*)", line):
                if is_secret_param(m.group(1)) and not LITERAL_FLAG.fullmatch(m.group(2)):
                    report.add(
                        path,
                        line_of(raw, m.group(0), start),
                        "secret-cli-arg",
                        f"{where}: --extra-vars {m.group(1)}=... puts a credential on ansible's command "
                        "line; read it in the playbook with lookup('env', ...) instead",
                    )
            for m in re.finditer(r"(?:^|\s)(?:--extra-vars|-e)[= ]\s*(['\"])(\{.*?)\1", line):
                for key in re.findall(r"[\"'](\w+)[\"']\s*:", m.group(2)):
                    if is_secret_param(key):
                        report.add(path, lineno, "secret-cli-arg",
                                   f"{where}: --extra-vars JSON key {key} puts a credential on ansible's command line")
        if re.search(r"(?:^|\s)--(password|token|client-secret|api-key)(?:[= ]|$)", line):
            report.add(path, lineno, "secret-cli-arg", f"{where}: credential passed as a command-line option")
        if re.search(r"-X\s*['\"]?(pass(word)?|sasl\.password)=", line):
            report.add(path, lineno, "secret-cli-arg",
                       f"{where}: rpk -X pass=... puts the password on the command line; set RPK_PASS in the environment")
        for m in re.finditer(r"\bbuildkite-agent\s+artifact\s+upload\s+['\"]?([^\s'\"]+)", line):
            if risky_artifact(m.group(1)):
                report.add(path, lineno, "artifact", f"{where}: uploads {m.group(1)}, which can hold credentials")

        check_masking_line(report, path, lineno, where, line)

        for name in sorted(n for n in secrets if re.search(r"\$\{?" + re.escape(n) + r"\b", line)):
            piped = re.search(r"\b(echo|printf)\b[^|]*\$\{?" + re.escape(name) + r"\b[^|]*\|", line)
            last = line.split("|")[-1]
            if piped and ">" not in last and PRINTERS.match(last):
                report.add(path, lineno, "secret-to-stdout",
                           f"{where}: ${name} is piped through {last.split()[0]} to the job log; "
                           "redirect the output to a mktemp file or into the program that needs it")
        to_file = line
        for name in secrets:
            to_file = re.sub(ENV_PREFIX.replace("NAME", re.escape(name)), " ", to_file)
        mentions_secret = any(re.search(r"\$\{?" + re.escape(n) + r"\b", to_file) for n in secrets) or bool(
            template_refs(to_file, include_conditions=False) & template_secrets
        )
        if mentions_secret and FIXED_FILE_REDIRECT.search(to_file):
            report.add(path, lineno, "secret-fixed-file",
                       f"{where}: writes a credential to a fixed path; write it to a mktemp file "
                       "(mode 600) and remove it on exit")


def check_masking_line(report, path, lineno, where, line):
    line = OPT_IN_BRANCH.sub("", line)
    end = r"(?=$|[\s'\"{])"
    if re.search(r"no_log\s*[=:]\s*['\"]?(false|no|0)\b", line, re.I) or re.search(
        r"no_log\s*=\s*{{(?!\s*\.REDPANDA_BROKER_NO_LOG\s*}})", line
    ):
        report.add(path, lineno, "masking-off", f"{where}: turns off Ansible's no_log masking")
    if re.search(r"(^|[\s;&|(])ansible(-playbook)?(?=\s)[^|;&]*?(\s|}})(-v+|--verbose)" + end, line):
        report.add(path, lineno, "debug-output",
                   f"{where}: ansible -v prints task results, -vvv module arguments and environments")
    for m in re.finditer(r"\b(" + "|".join(DEBUG_KNOBS) + r")\s*[=:]\s*['\"]?([^\s'\"{;&|]*)", line):
        if m.group(2).lower() not in QUIET_VALUES | {DEBUG_KNOBS[m.group(1)]}:
            report.add(path, lineno, "debug-output", f"{where}: sets {m.group(1)}={m.group(2)}; debug switches are for local runs only")
    if re.search(r"(^|[;&|(]\s*|\s)set\s+(-[a-zA-Z]*x|-o\s+xtrace)\b|\b(ba)?sh\s+-[a-zA-Z]*x\b", line):
        report.add(path, lineno, "shell-trace", f"{where}: shell tracing prints every expanded command")
    if re.search(r"(^|[;&|(]\s*)(env|set|export\s+-p|declare\s+-[px])\s*($|[;&|>)])", line) or re.search(
        r"(^|[;&|(]\s*)printenv\b", line
    ):
        report.add(path, lineno, "env-dump", f"{where}: dumps the environment, which holds the credentials")
    if re.search(r"\bcurl\b", line) and re.search(r"(\s|}})(-(?!-)[a-zA-Z]*v[a-zA-Z]*|--verbose)" + end, line) and re.search(
        r"\s(-u|--user|--oauth2-bearer|--cert|-E|--key)\b|Authorization|Bearer", line
    ):
        report.add(path, lineno, "debug-output", f"{where}: verbose curl on an authenticated call; gate it behind HTTP_DEBUG")
    if re.search(r"(\brpk\b|RPK_PATH\s*}}|\$\{?RPK\w*\}?)(?=[\s\"'])[^|;&]*?(\s|}})(-v+|--verbose)" + end, line):
        report.add(path, lineno, "debug-output", f"{where}: rpk -v logs requests and config; gate it behind RPK_DEBUG")
    if re.search(r"://[^/\s:@'\"]+:[^/\s@'\"]+@", line):
        report.add(path, lineno, "url-credential", f"{where}: credential embedded in a URL")
    if re.search(r"\bgcloud\b.*(--log-http|--verbosity[= ]debug)" + end, line) or re.search(r"\baws\b.*\s--debug" + end, line):
        report.add(path, lineno, "debug-output", f"{where}: cloud CLI debug output prints request headers and tokens")


def check_taskfiles(report, root, model, extra_secrets=()):
    template_secrets, shell_secrets = secret_names(model, extra_secrets)
    for path in model.files:
        raw = path.read_text()
        knob_re = r"(?:^\s*|[{,]\s*)(" + "|".join(DEBUG_KNOBS) + r"):\s*('[^']*'|\"[^\"]*\"|[^,}\s#]*)"
        for m in re.finditer(knob_re, raw, re.M):
            knob, value = m.group(1), m.group(2).strip().strip("'\"")
            quiet = DEBUG_KNOBS[knob]
            forward = r"{{\s*\." + knob + r"\s*(\|\s*default\s+\"" + re.escape(quiet) + r"\"\s*)?}}"
            if value.lower() not in QUIET_VALUES | {quiet} and not re.fullmatch(forward, value):
                report.add(path, raw.count("\n", 0, m.start()) + 1, "debug-output",
                           f"{knob} is set to {value!r}; it must stay {quiet or 'unset'} unless a local run sets it")
    for path, raw, tname, options in model.shell_options:
        if any(str(o) in ("x", "xtrace") for o in (options if isinstance(options, list) else [options] if options else [])):
            report.add(path, line_of(raw, "set:", task_offset(raw, tname) if tname != "<global>" else 0), "shell-trace",
                       f"task {tname}: set: xtrace prints every expanded command")
    for path, raw, tname, name, text in model.env_entries:
        if tname != "<global>" and name in template_refs(text, include_conditions=True):
            report.add(path, line_of(raw, f"{name}:", task_offset(raw, tname) if tname != "<global>" else 0),
                       "env-shadowed",
                       f"task {tname}: env {name} is read from {{{{.{name}}}}}, but a {name} already in the process "
                       "environment wins over a task's env:, so a task argument or .env value is ignored; "
                       "use a different name for the env entry")
    for path, raw, tname, kind, text in model.commands:
        start = task_offset(raw, tname) if tname != "<global>" else 0
        check_shell(report, path, raw, f"task {tname} {kind}", text, template_secrets, shell_secrets, start=start)
    return template_secrets | shell_secrets


# ---------------------------------------------------------------------------
# Buildkite pipeline, GitHub workflows and scripts


def pipeline_steps(steps):
    for step in steps or []:
        if isinstance(step, dict):
            yield step
            if isinstance(step.get("steps"), list):
                yield from pipeline_steps(step["steps"])


def step_plugins(step):
    plugins = step.get("plugins") or []
    if isinstance(plugins, dict):
        plugins = [{k: v} for k, v in plugins.items()]
    for plugin in plugins:
        if isinstance(plugin, dict):
            for cfg in plugin.values():
                if isinstance(cfg, dict):
                    yield cfg


def step_environment(step):
    """(name, value or None) for every variable a step sets or forwards."""
    out = [(k, None if v is None else str(v)) for k, v in (step.get("env") or {}).items()] if isinstance(step.get("env"), dict) else []
    for cfg in step_plugins(step):
        env = cfg.get("environment") or []
        if isinstance(env, dict):
            env = [f"{k}={v}" for k, v in env.items()]
        for entry in env:
            name, _, value = str(entry).partition("=")
            out.append((name, value if "=" in str(entry) else None))
    return out


def pipeline_docs(root, report=None):
    for path in sorted((root / ".buildkite").glob("*.y*ml")):
        doc = load_yaml(path, report)
        steps = doc.get("steps", []) if isinstance(doc, dict) else doc
        yield path, path.read_text(), doc, list(pipeline_steps(steps if isinstance(steps, list) else []))


def forwarded_secrets(root):
    names = set()
    for _, _, _, steps in pipeline_docs(root):
        for step in steps:
            names |= {n for n, _ in step_environment(step) if is_secret_env(n)}
    return names


def dependencies(step):
    deps = step.get("depends_on")
    deps = [deps] if isinstance(deps, (str, dict)) else deps or []
    out = []
    for d in deps:
        if isinstance(d, str):
            out.append((d, False))
        elif isinstance(d, dict):
            out.append((str(d.get("step")), bool(d.get("allow_failure"))))
    return out


def check_pipelines(report, root, secrets):
    for path, raw, doc, steps in pipeline_docs(root, report):
        names = set(secrets) | {n for s in steps for n, _ in step_environment(s) if is_secret_env(n)}
        has_guard = any(s.get("key") == GUARD_STEP for s in steps)
        for step in steps:
            label = step.get("label") or step.get("key") or step.get("group") or "step"
            anchor = next((str(step[k]) for k in ("key", "label", "group", "command") if isinstance(step.get(k), str)), "")
            start = max(raw.find(anchor), 0) if anchor else 0
            cmds = step.get("command") or step.get("commands") or []
            cmds = [cmds] if isinstance(cmds, str) else list(cmds)
            for cfg in step_plugins(step):
                for hook in ("command", "entrypoint", "pre-exit", "pre-command", "post-command"):
                    value = cfg.get(hook)
                    cmds += [value] if isinstance(value, str) else [str(v) for v in value] if isinstance(value, list) else []
            for cmd in cmds:
                check_shell(report, path, raw, f"step '{label}'", str(cmd), names, names, start=start)
            for art in ([step["artifact_paths"]] if isinstance(step.get("artifact_paths"), str) else step.get("artifact_paths") or []):
                for one in str(art).split(";"):
                    if risky_artifact(one):
                        report.add(path, line_of(raw, one, start), "artifact",
                                   f"step '{label}' uploads {one}, which can hold credentials")
            for name, value in step_environment(step):
                if name in DEBUG_KNOBS and (value is None or value.lower() not in QUIET_VALUES | {DEBUG_KNOBS[name]}):
                    report.add(path, line_of(raw, name, start), "debug-output",
                               f"step '{label}' sets or forwards {name}; debug switches are for local runs only")
            if has_guard and step.get("key") != GUARD_STEP and "depends_on" in step:
                deps = dict(dependencies(step))
                if deps.get(GUARD_STEP, True) or step.get("allow_dependency_failure"):
                    report.add(path, line_of(raw, "depends_on", start), "guard-bypass",
                               f"step '{label}' has depends_on, so it does not wait for the wait step; list "
                               f"'{GUARD_STEP}' in its depends_on without allow_failure (and give other "
                               "dependencies their own allow_failure) so it cannot run when the guard fails")
        top = doc.get("steps", []) if isinstance(doc, dict) else doc
        top = top if isinstance(top, list) else []
        guard_at = next((i for i, s in enumerate(top) if isinstance(s, dict) and s.get("key") == GUARD_STEP), None)
        if guard_at is not None:
            guard = top[guard_at]
            after = top[guard_at + 1] if guard_at + 1 < len(top) else None
            is_wait = after == "wait" or (isinstance(after, dict) and "wait" in after)
            problems = []
            if guard.get("soft_fail"):
                problems.append("the guard step has soft_fail")
            if str(guard.get("command", "")).strip() != "task tools:lint:secrets":
                problems.append("the guard step's command is not exactly `task tools:lint:secrets`")
            if any(k in guard for k in ("if", "branches", "skip")):
                problems.append("the guard step does not run on every build")
            if not is_wait:
                problems.append("no wait step follows the guard")
            elif isinstance(after, dict) and after.get("continue_on_failure"):
                problems.append("the wait after the guard has continue_on_failure")
            if any(i != guard_at for i, s in enumerate(top[: guard_at + 1]) if s != "wait"):
                problems.append("steps run before or beside the guard")
            for problem in problems:
                report.add(path, line_of(raw, GUARD_STEP), "guard-bypass",
                           f"{problem}, so steps holding credentials can run when the guard fails; "
                           f"put '{GUARD_STEP}' first, then a plain wait")
        if isinstance(doc, dict):
            for name, value in (doc.get("env") or {}).items():
                if name in DEBUG_KNOBS and str(value).lower() not in QUIET_VALUES | {DEBUG_KNOBS[name]}:
                    report.add(path, line_of(raw, name), "debug-output", f"pipeline env sets {name}")
    for path in sorted((root / ".github" / "workflows").glob("*.y*ml")):
        raw = path.read_text()
        doc = load_yaml(path, report) or {}
        for jname, job in (doc.get("jobs") or {}).items() if isinstance(doc, dict) else []:
            for step in (job or {}).get("steps") or []:
                if isinstance(step, dict) and isinstance(step.get("run"), str):
                    check_shell(report, path, raw, f"workflow job {jname}", step["run"], secrets, secrets)


def check_scripts(report, root, secrets):
    for path in sorted((root / "scripts").rglob("*.sh")):
        raw = path.read_text()
        check_shell(report, path, raw, "script", raw, secrets, secrets)


def consumer_texts(root):
    paths = taskfiles(root)
    for sub in ("ansible", "scripts", "aws", "gcp", "azure", "ibm"):
        if (root / sub).is_dir():
            paths += [f for f in (root / sub).rglob("*") if f.is_file()
                      and f.suffix in (".yml", ".yaml", ".sh", ".go", ".py", ".j2", ".tf")]
    own = {pathlib.Path(__file__).name, "test_check_secret_hygiene.py"}
    return {f: f.read_text(errors="replace") for f in paths if f.name not in own}


def check_unused_credentials(report, root, model):
    """A credential nothing reads is exposure with no purpose."""
    texts = consumer_texts(root)
    used = set()
    for *_, text in model.commands:
        used |= template_refs(text, include_conditions=True) | set(SHELL_REF.findall(text))
    for _, text, _ in model.defs:
        used |= template_refs(text, include_conditions=True)
    for path in model.files:
        raw = path.read_text()
        doc = load_yaml(path) or {}
        if not isinstance(doc, dict):
            continue
        blocks = [doc.get("vars")] + [t.get("vars") for t in (doc.get("tasks") or {}).values() if isinstance(t, dict)]
        for block in blocks:
            for name, _, _ in var_definitions(block):
                if is_secret_env(name) and name not in used:
                    report.add(path, line_of(raw, f"{name}:"), "unused-credential",
                               f"{name} holds a credential and no command, env block or variable reads it")
    for path, raw, _, steps in pipeline_docs(root):
        for step in steps:
            for name, _ in step_environment(step):
                if not is_secret_env(name) or IMPLICIT_READER.match(name):
                    continue
                if not any(re.search(r"\b" + re.escape(name) + r"\b", t) for t in texts.values()):
                    report.add(path, line_of(raw, f"- {name}"), "unused-credential",
                               f"forwards {name} into a step, but nothing in the repo reads it")


# ---------------------------------------------------------------------------
# Canary dry run


def canaries(names):
    out = {}
    for i, name in enumerate(sorted(names)):
        marker = f"canary{i:03d}x{name.lower()}x"
        value = marker
        needles = [marker]
        if re.search(r"CREDS|CREDENTIALS|BASE64|KEY_JSON|SA_KEY", name):
            value = base64.b64encode(marker.encode()).decode()
            needles.append(value)
        out[name] = (value, needles)
    return out


def dry_run_copy(root, files):
    """A copy of the repo whose task files never set silent: true."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="secret-hygiene-"))
    shutil.copytree(root, tmp / "repo", symlinks=True,
                    ignore=shutil.ignore_patterns(".git", ".terraform", "artifacts", "*.tfstate*", ".env", ".env.*"))
    for f in files:
        copy = tmp / "repo" / f.relative_to(root)
        if copy.exists():
            copy.write_text(re.sub(r"^(\s*)silent:\s*true\b", r"\1silent: false", copy.read_text(), flags=re.M))
    return tmp


def check_canary(report, root, names, files):
    task_bin = os.environ.get("TASK_BIN", "task")
    table = canaries(names)
    # Only these reach a dry run, so `sh:` vars and the report below can
    # never see a real credential from the caller's environment.
    env = {k: os.environ[k] for k in ("PATH", "TMPDIR", "LANG", "LC_ALL", "USER") if k in os.environ}
    env.update({name: value for name, (value, _) in table.items()})
    cli_vars = [f"{name}={value}" for name, (value, _) in table.items()]

    def mask(text):
        for var, (_, needles) in table.items():
            for n in needles:
                text = text.replace(n, f"<{var}>")
        return text

    tmp = dry_run_copy(root, files)
    work = tmp / "repo"
    # An empty HOME, so no config or credential file of the caller's is read.
    (tmp / "home").mkdir()
    env["HOME"] = str(tmp / "home")
    try:
        try:
            # --silent lists task names; --json lists labels in place of
            # names on older Task, but gives locations on newer ones.
            listing = subprocess.run([task_bin, "--list-all", "--silent"], cwd=work, env=env,
                                     capture_output=True, text=True, timeout=120)
            located = subprocess.run([task_bin, "--list-all", "--json"], cwd=work, env=env,
                                     capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.TimeoutExpired) as e:
            report.add(None, 0, "canary", f"cannot run {task_bin}: {e}")
            return 0
        if listing.returncode != 0:
            report.add(None, 0, "canary", f"task --list-all failed: {mask(listing.stderr.strip())}")
            return 0
        where_of = {}
        try:
            for t in json.loads(located.stdout)["tasks"]:
                loc = t.get("location") or {}
                if t.get("task") and loc.get("taskfile"):
                    where_of[t["task"]] = f"{os.path.relpath(loc['taskfile'], work)}:{loc.get('line', 0)}"
        except (ValueError, KeyError):
            pass
        tasks = [(n.strip(), where_of.get(n.strip(), "-")) for n in listing.stdout.splitlines() if n.strip()]

        def dry(item):
            name, where = item
            try:
                proc = subprocess.run([task_bin, "--dry", "--force", name, *cli_vars], cwd=work, env=env,
                                      capture_output=True, text=True, timeout=120)
                return name, where, proc.returncode, proc.stdout + proc.stderr
            except subprocess.TimeoutExpired:
                return name, where, "timeout", ""

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = sorted(pool.map(dry, tasks))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    seen = {}
    for name, where, rc, output in results:
        if rc != 0:
            report.violations.append(
                f"{where}: [canary] task --dry {name} failed (rc={rc}), so its commands went unchecked: "
                + " | ".join(mask(output).strip().splitlines()[-3:])
            )
            continue
        debug = Report(root)
        for line in output.splitlines():
            check_masking_line(debug, None, 0, f"task {name} at default settings", mask(line))
        for v in debug.violations:
            seen.setdefault(v, []).append(name)
        for line in output.splitlines():
            hits = [var for var, (_, needles) in table.items() if any(n in line for n in needles)]
            if hits:
                shown = mask(line)
                at = shown.find("<" + hits[0] + ">")
                excerpt = shown[max(0, at - 90):at + 60].strip()
                seen.setdefault(f"{where}: [canary] {', '.join(hits)} printed in clear: ...{excerpt}...", []).append(name)
    for finding, by in seen.items():
        more = f" (and {len(by) - 1} more tasks)" if len(by) > 1 else ""
        report.violations.append(f"{finding} [via task {by[0]}{more}]")
    return len(results)


def run_check(report, label, check, *args, default=None):
    """Run one check; unexpected input is reported, never a traceback."""
    try:
        return check(*args)
    except Exception as e:  # the guard fails closed on anything it cannot read
        report.add(None, 0, "internal", f"{label} stopped on input it cannot read, so it went unchecked: "
                   f"{type(e).__name__}: {e}")
        return default


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--canary", action="store_true", help="run only the canary dry run")
    mode.add_argument("--static", action="store_true", help="run only the static checks")
    parser.add_argument("root", nargs="?", default=pathlib.Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()

    report = Report(root)
    model = run_check(report, "task files", TaskModel, root, report)
    if model is None:
        model = TaskModel.__new__(TaskModel)
        model.defs, model.commands, model.env_entries, model.shell_options, model.files = [], [], [], [], []
    forwarded = run_check(report, "pipeline", forwarded_secrets, root, default=set())
    secrets = run_check(report, "task files", check_taskfiles, report if not args.canary else Report(root),
                        root, model, forwarded, default=set(KNOWN_SECRETS))
    summary = []
    if not args.canary:
        run_check(report, "pipeline", check_pipelines, report, root, secrets)
        run_check(report, "unused credentials", check_unused_credentials, report, root, model)
        run_check(report, "scripts", check_scripts, report, root, secrets)
        summary.append("static")
    if not args.static:
        n = run_check(report, "canary", check_canary, report, root, secrets, model.files, default=0)
        summary.append(f"canary over {n} tasks")
        print("credential variables given canaries: " + " ".join(sorted(secrets)))

    for v in report.violations:
        print(v)
    if report.violations:
        print(f"secret hygiene: {len(report.violations)} violation(s) ({'; '.join(summary)})")
        return 1
    print(f"secret hygiene: clean ({'; '.join(summary)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
