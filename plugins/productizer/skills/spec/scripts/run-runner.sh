#!/usr/bin/env bash
# run-runner.sh [--root DIR] --runner FILE [--dry-run] [--input FILE]
#
# Validates a runner definition (`templates/runners/*.json`) and either prints
# the resolved plan or executes it. Until this existed the format was a format:
# `id`, `agent`, `timeout_ms`, a sandbox scope, an anchored rubric and an output
# contract, and nothing in the repository read any of it (backlog `B16`).
#
# The validator is the load-bearing half. A definition that would run something
# it must not is refused and NOT executed, and the refusal names the rule.
#
# USAGE
#
#   run-runner.sh --runner templates/runners/gate-bypass.json --dry-run
#   run-runner.sh --runner templates/runners/gate-bypass.json \
#                 --input vars.json --root /path/to/repo
#
#   --runner FILE  the definition. Required.
#   --root DIR     the repository the runner is judging, and the directory the
#                  agent is given. DEFAULT: `git rev-parse --show-toplevel` as
#                  seen from the definition's own directory - NEVER the working
#                  directory. Defaulting a root to the working directory has
#                  produced four separate silent-wrong-answer bugs in this
#                  repository; the failure is quiet every time, because a
#                  wrong-but-existing root yields a clean run over the wrong
#                  tree. If no work tree can be resolved this exits 2 and asks
#                  for `--root` rather than guessing.
#   --dry-run      validate and print the plan. Nothing is executed.
#   --input FILE   JSON object of placeholder values for the prompt template,
#                  e.g. `{"branch": "feat/x", "base_branch": "main"}`. Values
#                  are substituted into the PROMPT in a single pass and never
#                  reach a shell.
#   --version      prints the version, exit 0
#   --help         prints this header, exit 0
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  the runner ran and its verdict satisfied the output contract; or
#      `--dry-run` validated the definition
#   1  the runner RAN and reported failure - the agent exited non-zero, the
#      timeout fired, or its last line did not satisfy the declared output
#      contract. The definition was fine; the run was not.
#   2  bad usage - a missing or unknown flag, no resolvable root, an
#      unbound prompt placeholder at execution time, or a request to execute a
#      runner whose own `enabled` is false
#   3  the definition could not be READ - absent, not a regular file, or no
#      read permission. Never folded into 0: a file nobody opened is not a
#      file that passed
#   4  the definition is INVALID and was REFUSED. It was not executed
#
# 1 and 4 stay apart on purpose. 4 sends someone to the definition; 1 sends
# them to the run. Collapsing them sends everyone to the wrong place.
#
# WHAT A DEFINITION MAY NOT DO (constitution `P4` - a repository being
# examined never chooses what runs)
#
# A runner definition is A FILE IN A REPOSITORY. Someone who lands a commit
# writes it, and whoever clones the repository runs it. So it selects no
# executable, anywhere, ever:
#
#   - `runtime.agent` is a KEY INTO A FIXED TABLE in this script, never a
#     command. An unknown agent name is refused; it is not looked up on PATH.
#   - Any command-shaped value (`command`, `argv`, `exec`, `cmd`,
#     `entrypoint`), at ANY depth in the document, must be a list of non-empty
#     strings. A string is refused outright: a string is handed to a shell.
#   - EVERY ELEMENT OF THE ARGV IS VALIDATED, not just argv[0]. An
#     argv[0]-only check is a live bypass - `["python3", "lint.py"]` walks
#     straight past it, and so does `["nice", "sh", "-c", "..."]`, whose shell
#     sits at index 1.
#   - A shell or a wrapper that takes a command as an operand (`sh`, `bash`,
#     `zsh`, `env`, `xargs`, `nohup`, `timeout`, `ssh`, `sudo`, ...) is refused
#     in ANY position.
#   - `awk`, `gawk`, `nawk` and `mawk` are refused OUTRIGHT, in any position,
#     with or without a flag. awk takes its program as a POSITIONAL argument,
#     so a rule that only looks for `-c`/`-e`/`-E` misses
#     `["awk", "BEGIN{system(\"...\")}"]` entirely. That specific gap is open in
#     this repository's other validator today; it is closed here.
#   - An interpreter (`python3`, `node`, `perl`, `ruby`, ...) is refused when
#     an inline-program flag (`-c`, `-e`, `-E`) appears anywhere after it, and
#     ALSO when its first non-flag operand is a script file - `evil.py` is a
#     program the repository supplied, and naming it after an interpreter is
#     the same act as naming it directly.
#   - `allowed_tools` is held to the same rule: a `Bash(prefix)` grant whose
#     prefix begins with a shell, an interpreter or a work-tree-relative path
#     is refused, because the grant is what the sandbox will permit.
#   - A write-capable tool (`Write`, `Edit`, `NotebookEdit`) is refused. A
#     runner produces a judgment; one that can edit the tree can close the gap
#     it just found and report a clean run (`references/delegation.md`).
#
# ERRORS REPORT BY LOCATION, NEVER BY QUOTING THE FILE
#
# A definition can contain text a stranger wrote, aimed at whoever reads the
# report next. So a refusal names the file, the JSON path and the rule, and
# stops. The same rule governs the plan: values that survived an enumerated
# allowlist are printed (they are this script's own strings), and free text
# from the file - `display_name`, `label`, band descriptions, the prompt - is
# reported as a length or a count and never echoed.
#
# WHAT THIS SCRIPT DOES NOT ENFORCE, SAID OUT LOUD
#
#   - `sandbox.network: deny` and `sandbox.repo_token: read` are VALIDATED and
#     NOT ENFORCED. This script has no mechanism to deny an agent the network
#     or to scope a token. It passes `allowed_tools` through as the agent's
#     allowlist, adds an explicit deny for the write tools, and that is the
#     whole of the sandbox. Treat the two fields as a declaration this script
#     checks the shape of, not a control it applies.
#   - `timeout_ms` is enforced by a watchdog that signals the process group of
#     the agent. A process that ignores TERM is followed by KILL.
set -euo pipefail

VERSION="run-runner 1.0"

usage() {
  printf 'usage: run-runner.sh [--root DIR] --runner FILE [--dry-run] [--input FILE]\n' >&2
}

print_help() {
  sed -n '2,$ { /^#/!q; s/^#$//; s/^# //; p; }' "$0"
}

RUNNER=""
ROOT=""
INPUT=""
DRY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) print_help; exit 0 ;;
    --dry-run) DRY=1; shift ;;
    --runner)
      [ "$#" -ge 2 ] || { printf 'run-runner: --runner needs a file\n' >&2; usage; exit 2; }
      RUNNER="$2"; shift 2 ;;
    --root)
      [ "$#" -ge 2 ] || { printf 'run-runner: --root needs a directory\n' >&2; usage; exit 2; }
      ROOT="$2"; shift 2 ;;
    --input)
      [ "$#" -ge 2 ] || { printf 'run-runner: --input needs a file\n' >&2; usage; exit 2; }
      INPUT="$2"; shift 2 ;;
    --) shift; break ;;
    *) printf 'run-runner: unknown option %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [ "$#" -gt 0 ]; then
  printf 'run-runner: unexpected operand. The definition is named with --runner.\n' >&2
  usage; exit 2
fi

if [ -z "$RUNNER" ]; then
  printf 'run-runner: --runner is required. Nothing validated is not a clean validation.\n' >&2
  usage; exit 2
fi

# --- reading the definition is a separate outcome from validating it --------
# 3 exists so that "nobody could open it" never arrives dressed as a pass.
if [ ! -e "$RUNNER" ]; then
  printf 'run-runner: cannot read %s: no such path. Unread, not valid.\n' "$RUNNER" >&2
  exit 3
fi
if [ ! -f "$RUNNER" ]; then
  printf 'run-runner: cannot read %s: not a regular file. Unread, not valid.\n' "$RUNNER" >&2
  exit 3
fi
if [ ! -r "$RUNNER" ]; then
  printf 'run-runner: cannot read %s: no read permission. Unread, not valid.\n' "$RUNNER" >&2
  exit 3
fi

if [ -n "$INPUT" ]; then
  if [ ! -f "$INPUT" ] || [ ! -r "$INPUT" ]; then
    printf 'run-runner: cannot read the --input file %s.\n' "$INPUT" >&2
    exit 3
  fi
fi

# --- the root ---------------------------------------------------------------
# Resolved from the DEFINITION's directory, not the working directory. A root
# that silently becomes $PWD produces a clean run over the wrong tree, which is
# the failure mode nobody notices.
if [ -z "$ROOT" ]; then
  RUNNER_DIR=$(dirname -- "$RUNNER")
  ROOT=$(git -C "$RUNNER_DIR" rev-parse --show-toplevel) || ROOT=""
  if [ -z "$ROOT" ]; then
    printf 'run-runner: no git work tree holds %s, so there is no root to default to.\n' "$RUNNER" >&2
    printf 'run-runner: pass --root DIR. This script does not fall back to the working directory: a wrong-but-existing root runs cleanly over the wrong tree.\n' >&2
    exit 2
  fi
fi
if [ ! -d "$ROOT" ]; then
  printf 'run-runner: --root %s is not a directory.\n' "$ROOT" >&2
  exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-runner.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

PLAN="$WORK/plan.tsv"
PROMPT="$WORK/prompt.txt"

# --- validation -------------------------------------------------------------
# Python reads the definition; the heredoc is quoted, so not one byte of shell
# expansion reaches the Python source. Every value it needs arrives on argv.
rc=0
python3 - "$RUNNER" "$INPUT" "$PLAN" "$PROMPT" "$DRY" <<'PY' || rc=$?
import json, os, re, sys

DEF_PATH, INPUT_PATH, PLAN_PATH, PROMPT_PATH, DRY = sys.argv[1:6]
DRY = DRY == "1"

# Report by LOCATION and RULE. A definition can carry text written by a
# stranger and aimed at whoever reads this report next, so nothing from the
# file is echoed - not a value, not a key's contents, not an excerpt.
def refuse(rule, where, why):
    sys.stderr.write(
        "run-runner: REFUSED %s\n"
        "  rule  %s\n"
        "  at    %s\n"
        "  why   %s\n"
        "  The definition was NOT executed. Open the file at that path to see the value.\n"
        % (DEF_PATH, rule, where, why))
    sys.exit(4)

try:
    with open(DEF_PATH, "r") as fh:
        raw = fh.read()
except OSError as exc:
    sys.stderr.write("run-runner: cannot read %s (%s). Unread, not valid.\n"
                     % (DEF_PATH, exc.__class__.__name__))
    sys.exit(3)

try:
    doc = json.loads(raw)
except ValueError:
    refuse("json-parse", DEF_PATH,
           "the file is not valid JSON. A half-read definition silently drops fields, so it is refused whole.")

if not isinstance(doc, dict):
    refuse("json-object", DEF_PATH, "the top level of a runner definition must be a JSON object")

# --- helpers ----------------------------------------------------------------

def need(obj, key, where, kind, typename):
    if key not in obj:
        refuse("required-field", "%s.%s" % (where, key),
               "required field is absent. The definition is refused whole rather than run with a default "
               "nobody chose: a default is this script deciding something the definition was supposed to.")
    v = obj[key]
    if not isinstance(v, kind) or isinstance(v, bool) is not (kind is bool):
        refuse("field-type", "%s.%s" % (where, key),
               "must be %s" % typename)
    return v

def enum(value, allowed, rule, where):
    if value not in allowed:
        refuse(rule, where,
               "not one of the values this script accepts: %s. The set is deliberately the one the shipped "
               "templates use; widening it is a change to this script that someone reviews in a diff, not a "
               "value a repository supplies." % ", ".join(sorted(allowed)))

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")

# --- P4: nothing in this file selects an executable -------------------------

# Programs that take a command as an operand. Naming one of these anywhere in
# an argv IS the shell invocation the argv-only rule exists to forbid.
SHELLS = {
    "sh", "bash", "zsh", "dash", "ksh", "mksh", "csh", "tcsh", "fish", "rc",
    "busybox", "env", "xargs", "nohup", "time", "timeout", "gtimeout",
    "stdbuf", "nice", "ionice", "setsid", "script", "ssh", "scp", "sudo",
    "doas", "su", "eval", "find", "watch", "parallel", "make", "open",
}
# awk is separate because the -c/-e/-E rule does not reach it: awk takes its
# program as a POSITIONAL argument. `["awk", "BEGIN{system(...)}"]` has no
# inline-program flag to find.
AWKS = {"awk", "gawk", "nawk", "mawk", "busybox-awk"}
INTERPRETERS = {
    "python", "python2", "python3", "perl", "ruby", "node", "deno", "bun",
    "php", "lua", "luajit", "tclsh", "expect", "Rscript", "osascript",
    "swift", "ghc", "runghc", "groovy", "jshell", "scala",
}
SCRIPT_EXT = re.compile(
    r"\.(py|sh|bash|zsh|pl|rb|js|mjs|cjs|ts|lua|php|r|scpt|tcl|exp|ps1|awk)$",
    re.IGNORECASE)

def check_program_ref(elem, rule_prefix, where, role):
    """A position that names a PROGRAM. Operands are not checked here - a path
    in an operand is data. Only positions that select what executes are."""
    if os.path.isabs(elem):
        if SCRIPT_EXT.search(elem):
            refuse(rule_prefix + "-script", where,
                   "%s names a script file. A script is a program the repository supplies; naming it "
                   "here is the repository choosing what runs." % role)
        return
    if "/" in elem or elem.startswith("."):
        refuse(rule_prefix + "-repo-local", where,
               "%s is a path relative to the work tree. A cloned repository would be choosing what "
               "executes on the machine that cloned it." % role)
    if SCRIPT_EXT.search(elem):
        refuse(rule_prefix + "-script", where,
               "%s names a script file. A script is a program the repository supplies; naming it here "
               "is the repository choosing what runs." % role)

INLINE_FLAGS = {"-c", "-e", "-E", "-Xc", "--command", "--eval", "--exec"}

def validate_argv(argv, where, rule_prefix="command"):
    """EVERY element, not just argv[0]. An argv[0]-only check is a bypass."""
    if isinstance(argv, str):
        refuse(rule_prefix + "-string", where,
               "commands are argv lists, never strings. A string is handed to a shell, and this file is "
               "committed, so a string here lets anyone who lands a commit choose what runs on the machine "
               "of whoever pulls it.")
    if not isinstance(argv, list) or not argv:
        refuse(rule_prefix + "-shape", where, "must be a non-empty list of non-empty strings")
    for i, elem in enumerate(argv):
        if not isinstance(elem, str) or not elem:
            refuse(rule_prefix + "-shape", "%s[%d]" % (where, i),
                   "every element must be a non-empty string")

    for i, elem in enumerate(argv):
        at = "%s[%d]" % (where, i)
        base = os.path.basename(elem)
        if base in AWKS:
            refuse(rule_prefix + "-awk", at,
                   "awk is refused outright, in every position. awk takes its program as a POSITIONAL "
                   "argument, so a rule that only looks for -c/-e/-E does not see it; there is no safe "
                   "shape for awk in a repository-supplied command.")
        if base in SHELLS:
            refuse(rule_prefix + "-shell", at,
                   "this program takes a command as an operand. That is the shell invocation the argv-only "
                   "rule exists to prevent, and the list form does not make it safe - it is refused in any "
                   "position, not only argv[0]. Name the tool you actually want to run.")
        if base in INTERPRETERS:
            for j in range(i + 1, len(argv)):
                if argv[j] in INLINE_FLAGS:
                    refuse(rule_prefix + "-inline-program", "%s[%d]" % (where, j),
                           "an interpreter is given an inline program. Put the program in a file the "
                           "repository can review - and then name a tool, not the interpreter.")
            for j in range(i + 1, len(argv)):
                if argv[j].startswith("-"):
                    continue
                check_program_ref(argv[j], rule_prefix, "%s[%d]" % (where, j),
                                  "the first operand of an interpreter")
                break
    check_program_ref(argv[0], rule_prefix, "%s[0]" % where, "the program")
    return list(argv)

COMMAND_KEYS = {"command", "argv", "exec", "cmd", "entrypoint"}

def scan_for_commands(node, path):
    """Command-shaped values are found at ANY depth. A rule that only inspects
    the keys it expects is a rule a new key walks around."""
    if isinstance(node, dict):
        for k, v in node.items():
            where = "%s.%s" % (path, k)
            if k in COMMAND_KEYS:
                validate_argv(v, where)
            scan_for_commands(v, where)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            scan_for_commands(v, "%s[%d]" % (path, i))

scan_for_commands(doc, "$")

# --- top level --------------------------------------------------------------

rid = need(doc, "id", "$", str, "a string")
if not ID_RE.match(rid):
    refuse("id-shape", "$.id",
           "must be lower-case and match [a-z0-9][a-z0-9._-]*. The id is printed in reports, so it is "
           "held to a shape rather than echoed as free text.")

display_name = need(doc, "display_name", "$", str, "a string")
if not display_name.strip():
    refuse("required-field", "$.display_name", "present but empty")

enabled = need(doc, "enabled", "$", bool, "true or false")
scope = need(doc, "scope", "$", str, "a string")
enum(scope, {"change"}, "scope-value", "$.scope")

runtime = need(doc, "runtime", "$", dict, "an object")
enum(need(runtime, "kind", "$.runtime", str, "a string"),
     {"prompt_runner"}, "runtime-kind", "$.runtime.kind")

agent = need(runtime, "agent", "$.runtime", str, "a string")
# The agent name is a KEY INTO A TABLE. It is never resolved on PATH, and an
# unknown name is refused rather than tried.
AGENTS = {"claude"}
enum(agent, AGENTS, "agent-unknown", "$.runtime.agent")

timeout_ms = runtime.get("timeout_ms")
if timeout_ms is None:
    refuse("required-field", "$.runtime.timeout_ms",
           "required field is absent. A runner with no timeout is a runner nobody can stop.")
if isinstance(timeout_ms, bool) or not isinstance(timeout_ms, int):
    refuse("timeout-type", "$.runtime.timeout_ms",
           "must be an integer number of milliseconds. A float, a string or a boolean is refused rather "
           "than coerced: a coerced timeout is one nobody chose.")
if timeout_ms <= 0:
    refuse("timeout-positive", "$.runtime.timeout_ms",
           "must be greater than zero. A non-positive timeout either fires immediately or never.")
TIMEOUT_CAP_MS = 3600000
if timeout_ms > TIMEOUT_CAP_MS:
    refuse("timeout-cap", "$.runtime.timeout_ms",
           "exceeds the ceiling of %d ms (1 hour). A timeout raised past the point where anyone waits is "
           "a gate switched off slowly - the shipped runners' own rubrics score exactly this."
           % TIMEOUT_CAP_MS)

# --- sandbox ----------------------------------------------------------------

sandbox = need(runtime, "sandbox", "$.runtime", dict, "an object")
enum(need(sandbox, "base_template", "$.runtime.sandbox", str, "a string"),
     {"claude"}, "sandbox-base-template", "$.runtime.sandbox.base_template")
repo_token = need(sandbox, "repo_token", "$.runtime.sandbox", str, "a string")
enum(repo_token, {"read"}, "sandbox-repo-token", "$.runtime.sandbox.repo_token")
network = need(sandbox, "network", "$.runtime.sandbox", str, "a string")
enum(network, {"deny"}, "sandbox-network", "$.runtime.sandbox.network")

allowed_tools = need(sandbox, "allowed_tools", "$.runtime.sandbox", list, "a list")
if not allowed_tools:
    refuse("tools-empty", "$.runtime.sandbox.allowed_tools",
           "empty. A runner with no tools reads nothing and judges nothing, so an empty list is a runner "
           "that will report on a tree it never opened.")

KNOWN_TOOLS = {"Read", "Grep", "Glob", "Bash", "WebFetch", "WebSearch",
               "TodoWrite", "Task", "Write", "Edit", "NotebookEdit"}
WRITE_TOOLS = {"Write", "Edit", "NotebookEdit"}
TOOL_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_]*)(?:\((.*)\))?$", re.DOTALL)

tool_names = []
for i, t in enumerate(allowed_tools):
    at = "$.runtime.sandbox.allowed_tools[%d]" % i
    if not isinstance(t, str) or not t:
        refuse("tools-shape", at, "every entry must be a non-empty string")
    m = TOOL_RE.match(t)
    if not m:
        refuse("tools-shape", at, "must be `Tool` or `Tool(scope)`")
    name, arg = m.group(1), m.group(2)
    if name not in KNOWN_TOOLS:
        refuse("tools-unknown", at,
               "names a tool this script does not recognise. An unrecognised name is a typo that silently "
               "deletes a capability, and it reads to a maintainer as a capability that was granted.")
    if name in WRITE_TOOLS:
        refuse("tools-write", at,
               "grants a write-capable tool. A runner produces a judgment; one that can edit the tree can "
               "close the gap it just found and report a clean run, and the finding never reaches a human.")
    if name == "Bash" and arg:
        # The grant is what the sandbox will permit, so it is held to the same
        # rule as an argv. The prefix is split on whitespace only - it is a
        # permission pattern, not a command to run.
        head = arg.split(":", 1)[0].strip()
        toks = [tok for tok in head.split() if tok]
        if toks:
            validate_argv(toks, at, rule_prefix="tool-grant")
    tool_names.append(name if not arg else name + "(...)")

# --- automation and selection ----------------------------------------------

automation = need(doc, "automation", "$", dict, "an object")
enum(need(automation, "kind", "$.automation", str, "a string"),
     {"change_prompt"}, "automation-kind", "$.automation.kind")

select = need(doc, "select", "$", dict, "an object")
triggers = need(select, "trigger_types", "$.select", list, "a list")
if not triggers:
    refuse("select-empty", "$.select.trigger_types",
           "empty. A runner nothing triggers is a runner that was deleted, slowly.")
TRIGGERS = {"api", "push", "stage:check"}
for i, t in enumerate(triggers):
    at = "$.select.trigger_types[%d]" % i
    if not isinstance(t, str) or not t:
        refuse("select-shape", at, "every trigger must be a non-empty string")
    enum(t, TRIGGERS, "select-trigger-unknown", at)

# --- the prompt and its anchored rubric -------------------------------------

prompt = need(doc, "prompt", "$", dict, "an object")
template = need(prompt, "template", "$.prompt", str, "a string")
if not template.strip():
    refuse("prompt-empty", "$.prompt.template", "present but empty")

placeholders = sorted(set(re.findall(r"\{\{([^{}]*)\}\}", template)))
PLACEHOLDER_RE = re.compile(r"^[a-z][a-z0-9_]*$")
for p in placeholders:
    if not PLACEHOLDER_RE.match(p):
        refuse("prompt-placeholder-shape", "$.prompt.template",
               "a placeholder name does not match [a-z][a-z0-9_]*. A placeholder is a variable name, and "
               "an arbitrary one is a way to smuggle text past this check.")

# An anchored rubric: every band carries a DESCRIPTION, not just a number. An
# unanchored 0-100 scale is one model's mood and is not comparable between two
# runs - which makes the recorded value a number nobody measured.
BAND_RE = re.compile(r"^[-*]\s*(\d{1,3})\s*[-–—]\s*(\d{1,3})\s*:\s*(.+?)\s*$", re.MULTILINE)
bands = BAND_RE.findall(template)
if len(bands) < 3:
    refuse("rubric-absent", "$.prompt.template",
           "fewer than three scoring bands of the form `- LOW-HIGH: description` were found. Without "
           "anchored bands the score is an open scale, and an open scale is not comparable between runs.")

parsed = []
for lo, hi, desc in bands:
    lo, hi = int(lo), int(hi)
    words = re.sub(r"[^A-Za-z]+", " ", desc).split()
    if len(words) < 3 or len(desc) < 15:
        # Report the RANGE, which this script parsed, never the description,
        # which the file wrote.
        refuse("rubric-unanchored", "$.prompt.template band %d-%d" % (lo, hi),
               "this band has no description - a number with no anchor. Every level must say what earns "
               "it, or two runs are scoring different things with the same scale.")
    if lo > hi:
        refuse("rubric-band-order", "$.prompt.template band %d-%d" % (lo, hi),
               "the band's low bound is above its high bound")
    parsed.append((lo, hi))

parsed.sort()
if parsed[0][0] != 0:
    refuse("rubric-coverage", "$.prompt.template",
           "the bands do not start at 0, so part of the scale has no anchor")
if parsed[-1][1] != 100:
    refuse("rubric-coverage", "$.prompt.template",
           "the bands do not reach 100, so part of the scale has no anchor")
for i in range(1, len(parsed)):
    prev_hi = parsed[i - 1][1]
    lo = parsed[i][0]
    if lo != prev_hi + 1:
        refuse("rubric-coverage", "$.prompt.template band %d-%d" % parsed[i],
               "the bands are not contiguous with the previous band, which ends at %d. A gap is a score "
               "with no anchor; an overlap is two anchors for one score." % prev_hi)

# --- the output contract ----------------------------------------------------

output = need(doc, "output", "$", dict, "an object")
adapter = need(output, "adapter", "$.output", str, "a string")
enum(adapter, {"last_json_line"}, "output-adapter", "$.output.adapter")
result_type = need(output, "result_type", "$.output", str, "a string")
enum(result_type, {"trail_monitor"}, "output-result-type", "$.output.result_type")

tm = need(output, "trail_monitor", "$.output", dict, "an object")
tm_key = need(tm, "key", "$.output.trail_monitor", str, "a string")
if not re.match(r"^[a-z0-9][a-z0-9_]*$", tm_key):
    refuse("output-key-shape", "$.output.trail_monitor.key",
           "must be lower-case and match [a-z0-9][a-z0-9_]*")
tm_label = need(tm, "label", "$.output.trail_monitor", str, "a string")
if not tm_label.strip():
    refuse("required-field", "$.output.trail_monitor.label", "present but empty")
value_type = need(tm, "value_type", "$.output.trail_monitor", str, "a string")
enum(value_type, {"percent"}, "output-value-type", "$.output.trail_monitor.value_type")
polarity = need(tm, "polarity", "$.output.trail_monitor", str, "a string")
enum(polarity, {"lower_is_better", "higher_is_better"},
     "output-polarity", "$.output.trail_monitor.polarity")

# The contract has to name a shape the CALLER can check, or the adapter is a
# promise with nothing behind it. For last_json_line + percent the shape is
# fixed, and the prompt has to actually ask for it - a contract the prompt
# never states is a contract the model was never told about.
OUTPUT_SHAPE = '{"value": <number 0-100>, "rationale": <string>}'
for field in ('"value"', '"rationale"'):
    if field not in template:
        refuse("output-contract-unstated", "$.prompt.template",
               "the declared adapter `last_json_line` parses a JSON object with `value` and `rationale`, "
               "and the prompt never asks for %s. A contract the prompt does not state is a contract only "
               "the parser knows about, and the parse fails at run time instead of here." % field)

# --- placeholder binding ----------------------------------------------------

bindings = {}
if INPUT_PATH:
    try:
        with open(INPUT_PATH, "r") as fh:
            given = json.load(fh)
    except OSError as exc:
        sys.stderr.write("run-runner: cannot read the --input file %s (%s).\n"
                         % (INPUT_PATH, exc.__class__.__name__))
        sys.exit(3)
    except ValueError:
        sys.stderr.write("run-runner: the --input file %s is not valid JSON.\n" % INPUT_PATH)
        sys.exit(2)
    if not isinstance(given, dict):
        sys.stderr.write("run-runner: the --input file %s must hold a JSON object of "
                         "placeholder values.\n" % INPUT_PATH)
        sys.exit(2)
    for k, v in given.items():
        if not isinstance(v, str):
            sys.stderr.write("run-runner: --input value for %r is not a string. Placeholder values are "
                             "text substituted into the prompt.\n" % k)
            sys.exit(2)
        bindings[k] = v

unbound = [p for p in placeholders if p not in bindings]

if not DRY and unbound:
    sys.stderr.write("run-runner: cannot execute: %d prompt placeholder(s) have no value. Supply them with "
                     "--input. Names: %s\n" % (len(unbound), ", ".join(unbound)))
    sys.exit(2)

if not DRY and not enabled:
    sys.stderr.write("run-runner: %s declares `enabled: false`. Refusing to execute it. A disabled runner "
                     "is not a quiet pass - switch it on in the definition, or do not ask for it.\n" % rid)
    sys.exit(2)

# Single pass, so a value that itself contains `{{...}}` is not re-expanded.
rendered = re.sub(r"\{\{([a-z][a-z0-9_]*)\}\}",
                  lambda m: bindings.get(m.group(1), m.group(0)), template)
with open(PROMPT_PATH, "w") as fh:
    fh.write(rendered)

# --- the plan ---------------------------------------------------------------
# Only values that survived an enumerated allowlist are printed: those are this
# script's own strings. Free text from the file is reported as a length.
rows = [
    ("definition", DEF_PATH),
    ("id", rid),
    ("display_name", "<%d chars, not echoed>" % len(display_name)),
    ("enabled", "true" if enabled else "false"),
    ("scope", scope),
    ("runtime_kind", runtime["kind"]),
    ("agent", agent),
    ("timeout_ms", str(timeout_ms)),
    ("sandbox", "base_template=%s repo_token=%s network=%s (validated, NOT enforced by this script)"
                % (sandbox["base_template"], repo_token, network)),
    ("allowed_tools", ", ".join(tool_names)),
    ("denied_tools", "Write, Edit, NotebookEdit (added by this script, not by the definition)"),
    ("triggers", ", ".join(sorted(set(triggers)))),
    ("rubric", "%d anchored bands, contiguous 0-100, every band described" % len(parsed)),
    ("output_adapter", adapter),
    ("output_result", "%s key=%s value_type=%s polarity=%s" % (result_type, tm_key, value_type, polarity)),
    ("output_shape", OUTPUT_SHAPE),
    ("prompt", "%d chars, %d placeholder(s)" % (len(rendered), len(placeholders))),
    ("placeholders_bound", ", ".join(p for p in placeholders if p in bindings) or "(none)"),
    ("placeholders_unbound", ", ".join(unbound) or "(none)"),
]
with open(PLAN_PATH, "w") as fh:
    for k, v in rows:
        fh.write("%s\t%s\n" % (k, v))

# Machine-readable fields the shell needs, kept out of the printed plan.
with open(PLAN_PATH + ".env", "w") as fh:
    fh.write("%s\n%s\n%s\n%s\n" % (rid, agent, timeout_ms, tm_key))
PY

if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi

print_plan() {
  printf 'run-runner: plan\n'
  while IFS=$'\t' read -r k v; do
    printf '  %-21s %s\n' "$k" "$v"
  done < "$PLAN"
  printf '  %-21s %s\n' "root" "$ROOT"
}

if [ "$DRY" -eq 1 ]; then
  print_plan
  printf '  %-21s %s\n' "DRY RUN" "validated only; nothing was executed"
  exit 0
fi

# --- execution --------------------------------------------------------------
RID=$(sed -n '1p' "$PLAN.env")
AGENT=$(sed -n '2p' "$PLAN.env")
TIMEOUT_MS=$(sed -n '3p' "$PLAN.env")

# The agent name is a KEY, resolved here, in this file, against a table this
# script owns. The definition never names a program.
case "$AGENT" in
  claude) AGENT_PROG="claude" ;;
  *)
    printf 'run-runner: no execution mapping for agent %s.\n' "$AGENT" >&2
    exit 4 ;;
esac

if ! command -v "$AGENT_PROG" > /dev/null; then
  printf 'run-runner: the agent program for %s is not installed. Not run, and not a pass.\n' "$AGENT" >&2
  exit 1
fi

# allowed_tools straight from the definition, plus an explicit deny for the
# write tools. The validator has already refused any grant that could select a
# program, so these strings are safe to pass as separate argv elements.
TOOLS_FILE="$WORK/tools.txt"
python3 - "$RUNNER" "$TOOLS_FILE" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as fh:
    for t in doc["runtime"]["sandbox"]["allowed_tools"]:
        fh.write(t + "\n")
PY

# `--allowedTools` is variadic, so the grants go LAST, one argv element each.
# They are never joined into a string: a joined list is a string a shell splits.
CMD=("$AGENT_PROG" -p --output-format text --permission-mode dontAsk --add-dir "$ROOT")
CMD+=(--disallowedTools Write Edit NotebookEdit)
CMD+=(--allowedTools)
while IFS= read -r tool; do
  [ -n "$tool" ] || continue
  CMD+=("$tool")
done < "$TOOLS_FILE"

OUT="$WORK/out.txt"
TIMEOUT_S=$(( (TIMEOUT_MS + 999) / 1000 ))

printf 'run-runner: executing %s (agent=%s, timeout=%ss, root=%s)\n' "$RID" "$AGENT" "$TIMEOUT_S" "$ROOT" >&2

# A portable watchdog. macOS ships no `timeout`, and a runner with a declared
# timeout that nothing enforces is a declaration, not a limit.
( cd "$ROOT" && "${CMD[@]}" < "$PROMPT" > "$OUT" ) &
AGENT_PID=$!

(
  waited=0
  while [ "$waited" -lt "$TIMEOUT_S" ]; do
    sleep 1
    waited=$((waited + 1))
    if ! ps -p "$AGENT_PID" > /dev/null; then exit 0; fi
  done
  kill -TERM "$AGENT_PID" || true
  sleep 2
  kill -KILL "$AGENT_PID" || true
) &
WATCHDOG_PID=$!

agent_rc=0
wait "$AGENT_PID" || agent_rc=$?
kill -TERM "$WATCHDOG_PID" || true

if [ "$agent_rc" -ne 0 ]; then
  printf 'run-runner: %s: the agent exited %d. The runner ran and did not produce a verdict.\n' "$RID" "$agent_rc" >&2
  exit 1
fi

# `last_json_line`: the verdict is the final non-empty line and nothing else is
# parsed, so surrounding prose cannot change the number.
rc=0
python3 - "$OUT" "$RID" "$PLAN.env" <<'PY' || rc=$?
import json, sys
out_path, rid, env_path = sys.argv[1:4]
key = open(env_path).read().splitlines()[3]
lines = [ln for ln in open(out_path).read().splitlines() if ln.strip()]
if not lines:
    sys.stderr.write("run-runner: %s: the agent produced no output. Ran, no verdict.\n" % rid)
    sys.exit(1)
try:
    verdict = json.loads(lines[-1])
except ValueError:
    sys.stderr.write("run-runner: %s: the last output line is not JSON, so the declared "
                     "`last_json_line` contract is not satisfied. The line is not echoed here: it is "
                     "model output shaped by repository text.\n" % rid)
    sys.exit(1)
if not isinstance(verdict, dict) or "value" not in verdict or "rationale" not in verdict:
    sys.stderr.write("run-runner: %s: the verdict object does not carry both `value` and `rationale`.\n" % rid)
    sys.exit(1)
v = verdict["value"]
if isinstance(v, bool) or not isinstance(v, (int, float)) or not (0 <= v <= 100):
    sys.stderr.write("run-runner: %s: `value` is not a number in 0-100, so it is outside the declared "
                     "percent contract.\n" % rid)
    sys.exit(1)
json.dump({"key": key, "value": v, "rationale": verdict["rationale"]}, sys.stdout)
sys.stdout.write("\n")
PY
exit "$rc"
