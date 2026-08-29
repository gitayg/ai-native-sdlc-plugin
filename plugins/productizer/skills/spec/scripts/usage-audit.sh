#!/usr/bin/env bash
# scripts/usage-audit.sh — how often Productizer's own scripts are run, and how
# often they fail.
#
#   usage-audit.sh [--scripts DIR] [--transcripts DIR] [--probe] [--format text|json]
#
#   --scripts DIR      the scripts to audit. Default: this script's directory
#   --transcripts DIR  Claude Code project transcripts.
#                      Default $CLAUDE_TRANSCRIPTS, else ~/.claude/projects
#   --probe            additionally EXECUTE each script twice in an empty temp
#                      directory: once with --help, once with a nonsense flag.
#                      Off by default, because executing a script to audit it is
#                      a different risk from reading it.
#   --format           text (default) or json
#
# Two halves, and they answer different questions.
#
# CENSUS reads transcripts and counts what actually happened: invocations,
# failures, an error rate WITH the sample size beside it, and whether the agent
# recovered on its next try. A rate without an n is a number people quote.
#
# CONTRACT reads each script and compares two things that are supposed to agree:
# the options the argument parser accepts, and the options the help text names.
# A script whose help text lies about its arguments produces a usage bug in
# every session that reads it, and it looks like an agent mistake every time.
#
# Every "nothing" is distinguished. No transcript root, an empty one, transcripts
# that will not parse, and transcripts that parse and contain no invocation are
# four different findings; only the last is a measured zero.
#
# Exit: 0  audited
#       2  usage
#       3  no transcript source at all — the census did not happen
#       4  transcripts present, nothing parseable
#       5  transcripts parsed, zero invocations found (a measured zero)
#
# The contract half needs no transcripts and always runs; an exit of 3, 4 or 5
# means the census had nothing to say, not that the audit found nothing.
set -euo pipefail

export TZ=UTC
export LC_ALL=C

die_usage() { printf 'usage-audit: %s\n' "$1" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE"
TRANSCRIPTS=""
PROBE=0
FORMAT=text

while [ $# -gt 0 ]; do
  case "$1" in
    --scripts)       [ $# -ge 2 ] || die_usage "--scripts needs a directory";     SCRIPTS="$2"; shift 2 ;;
    --scripts=*)     SCRIPTS="${1#--scripts=}"; shift ;;
    --transcripts)   [ $# -ge 2 ] || die_usage "--transcripts needs a directory"; TRANSCRIPTS="$2"; shift 2 ;;
    --transcripts=*) TRANSCRIPTS="${1#--transcripts=}"; shift ;;
    --format)        [ $# -ge 2 ] || die_usage "--format needs text or json";     FORMAT="$2"; shift 2 ;;
    --format=*)      FORMAT="${1#--format=}"; shift ;;
    --probe)         PROBE=1; shift ;;
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
    -*)              die_usage "unknown option: $1" ;;
    *)               die_usage "unexpected argument: $1 (there is no positional argument)" ;;
  esac
done

case "$FORMAT" in text|json) ;; *) die_usage "--format must be text or json, not '$FORMAT'" ;; esac
[ -d "$SCRIPTS" ] || die_usage "no such directory: $SCRIPTS"
SCRIPTS="$(cd "$SCRIPTS" && pwd)"
[ -n "$TRANSCRIPTS" ] || TRANSCRIPTS="${CLAUDE_TRANSCRIPTS:-$HOME/.claude/projects}"

command -v python3 >/dev/null 2>&1 ||
  die_usage "python3 is not on PATH. Refusing rather than half-parsing transcripts with awk."

# --probe executes the audited scripts. That is a real difference in kind from
# reading them, so the results are gathered here, out in the open, and handed to
# the analysis as data rather than the analysis shelling out on its own.
PROBE_TSV=""
if [ "$PROBE" -eq 1 ]; then
  PROBE_TSV="$(mktemp "${TMPDIR:-/tmp}/usage-audit-probe.XXXXXX")"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/usage-audit-sandbox.XXXXXX")"
  trap 'rm -f "$PROBE_TSV"; rm -rf "$SANDBOX"' EXIT
  for f in "$SCRIPTS"/*.sh "$SCRIPTS"/*.py; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    # Exit status is the datum, so `|| true` keeps set -e from ending the audit
    # on the very failure it is trying to measure.
    case "$b" in *.py) run=python3 ;; *) run=bash ;; esac
    ( cd "$SANDBOX" && "$run" "$f" --help >/dev/null 2>&1 ) && h=0 || h=$?
    ( cd "$SANDBOX" && "$run" "$f" --zzz-not-a-real-flag >/dev/null 2>&1 ) && n=0 || n=$?
    printf '%s\t%s\t%s\n' "$b" "$h" "$n" >> "$PROBE_TSV"
  done
fi

python3 - "$SCRIPTS" "$TRANSCRIPTS" "$FORMAT" "$PROBE_TSV" <<'PY'
import json, os, re, sys

scripts_dir, transcripts_root, out_format, probe_tsv = sys.argv[1:5]

SCRIPT_FILES = sorted(
    f for f in os.listdir(scripts_dir)
    if (f.endswith(".sh") or f.endswith(".py")) and os.path.isfile(os.path.join(scripts_dir, f)))

# ---------------------------------------------------------------- CONTRACT ---
# The parser is the truth. The help text is a claim about the parser. Reading
# both out of the same file and comparing them is the whole trick.

# `\)\s` missed `--repo)` with its body on the next line, and then reported
# --repo as an option init.sh documents but does not accept. It accepts it.
OPT_CASE = re.compile(r"^\s*(-[^)]*?)\)(\s|$)")
STAR_CASE = re.compile(r"^\s*\*\)\s*(.*)$")
SED_HELP = re.compile(r"sed\s+-n\s+'(\d+),(\d+)p'")
ECHO_HELP = re.compile(r'echo\s+"(usage:[^"]*)"')
OPT_TOKEN = re.compile(r"--?[A-Za-z][A-Za-z0-9-]*")
POSITIONAL = re.compile(r"[\[<](repo-root|repo-path|repo|template|destination|repo root)[\]>]")

def argparse_facts(text):
    """A python script with argparse documents itself: --help is generated."""
    accepted = {m.group(1) for m in
                re.finditer(r'add_argument\(\s*"(--?[A-Za-z0-9][A-Za-z0-9-]*)"', text)}
    positional = bool(re.search(r'add_argument\(\s*"[A-Za-z]', text))
    return accepted, positional

def parser_facts(path, text):
    lines = text.splitlines()
    accepted, help_line, star_action, has_help = set(), None, None, False
    rejects_unknown_options = False
    in_case = False
    for i, line in enumerate(lines):
        # `case $1 in` and `case "$1" in` are the same construct. Requiring the
        # quotes made init.sh look like it had no argument parser at all, and
        # invented two phantom options for it.
        if re.search(r"case\s+\"?\$\{?1\}?\"?\s+in", line):
            in_case = True
        if not in_case:
            continue
        if re.match(r"^\s*esac\b", line):
            in_case = False
            continue
        m = OPT_CASE.match(line)
        if m:
            for pat in m.group(1).split("|"):
                pat = pat.strip()
                if not pat.startswith("-"):
                    continue
                # `-*)` is the reject-unknown-options branch, not an option. Counting
                # it as one made every script in the repo report an undocumented
                # option it does not have - a false finding in 11 of 19 scripts.
                if "*" in pat or "?" in pat:
                    rejects_unknown_options = True
                    continue
                accepted.add(pat.split("=")[0])
                if pat in ("-h", "--help"):
                    has_help = True
                    # The body may start on the next line. init.sh writes
                    # `-h|--help)` then the sed on the line below, and reading
                    # only the branch line reported its help as unrecognised and
                    # both its options as undocumented. They are documented.
                    body = [line[line.index(")") + 1:]]
                    j = i + 1
                    while j < len(lines) and ";;" not in body[-1] and len(body) < 6:
                        body.append(lines[j])
                        j += 1
                    help_line = " ".join(body)
            continue
        m = STAR_CASE.match(line)
        if m and star_action is None:
            star_action = m.group(1).strip()
    # Not every script uses a case loop. scaffold.sh takes `--dry-run` with an
    # `if`, then reads $1 and $2 directly; reading only case branches reported it
    # as having no options and no positional, both wrong.
    for m in re.finditer(r'\$\{?1[:\-}]*\}?"?\s*=\s*"(--[A-Za-z0-9-]+)"', text):
        accepted.add(m.group(1))
    for m in re.finditer(r'"(--[A-Za-z0-9-]+)"\s*\)?\s*=\s*"?\$\{?1', text):
        accepted.add(m.group(1))
    return accepted, has_help, help_line, star_action, rejects_unknown_options

def leading_comment(lines):
    out = []
    for line in lines[1:]:
        if line.startswith("#"):
            out.append(line)
        elif out:
            break
    return "\n".join(out)

def usage_function(text):
    m = re.search(r"(?ms)^usage\(\)\s*\{(.*?)^\}", text)
    return m.group(1) if m else None

def documented(path, text, help_line):
    """The tokens a reader is told about, and where they were told."""
    lines = text.splitlines()
    if help_line:
        m = SED_HELP.search(help_line)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            body = "\n".join(lines[a - 1:b])
            return body, "--help prints lines %d-%d of the file" % (a, b)
        if re.search(r"\bawk\b.*\^#", help_line):
            return leading_comment(lines), "--help prints the leading comment block"
        if re.search(r"(^|[;\s])usage\b", help_line):
            body = usage_function(text)
            if body is not None:
                return body, "--help calls usage()"
        m = ECHO_HELP.search(help_line)
        if m:
            return m.group(1), "--help prints one usage line"
        return help_line, "--help handler, shape not recognised"
    # No -h handler. The usage may still be written in the header comment, which
    # is worse than absent: a reader who runs --help does not get it.
    # Comment lines only. Reading the code as documentation made scaffold.sh
    # report `--is-inside-work-tree` as a phantom option: that string is a git
    # flag inside the script body, not a claim to a reader.
    head = leading_comment(lines)
    if head.strip():
        return head, "header comment only - `--help` does NOT print it"
    return "", "nothing documents the arguments"

contract = []
for fn in SCRIPT_FILES:
    path = os.path.join(scripts_dir, fn)
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    argparse_documented = False
    if fn.endswith(".py"):
        accepted, py_positional = argparse_facts(text)
        if accepted or py_positional:
            has_help, help_line, rejects_unknown = True, None, True
            # argparse prints every positional in the help it generates, so a
            # positional here is documented by construction. Reporting it as
            # undocumented was this auditor asserting a gap it had not measured.
            doc, doc_where = text[:4000], "argparse generates --help from the parser itself"
            argparse_documented = True
            star_action = "accepted-by-argparse" if py_positional else None
        else:
            accepted, has_help, help_line, star_action, rejects_unknown = parser_facts(path, text)
            doc, doc_where = documented(path, text, help_line)
    else:
        accepted, has_help, help_line, star_action, rejects_unknown = parser_facts(path, text)
        doc, doc_where = documented(path, text, help_line)
    doc_tokens = {t.split("=")[0] for t in OPT_TOKEN.findall(doc)}
    # Tokens that are the script's own name fragment or a shell flag in an
    # example line are noise; only compare against what the parser could accept.
    undocumented = sorted(t for t in accepted if t not in doc_tokens and t not in ("-h", "--help"))
    phantom = sorted(t for t in doc_tokens
                     if t not in accepted and t not in ("-h", "--help", "-n", "-c", "-r", "-e", "-p", "-u", "-o", "-x")
                     and t.startswith("--"))
    # Order matters and it caught a bug here: several scripts guard the branch
    # ("only one repo-root" ... exit 2) and THEN assign. Testing for the exit
    # first classified those as rejecting a positional they in fact accept.
    if star_action == "accepted-by-argparse":
        positional = "accepted"
    elif star_action is None and not fn.endswith(".py") and re.search(
            r'(?m)^[A-Za-z_][A-Za-z0-9_]*=\$\{?1\b', text):
        positional = "accepted"
    elif star_action is None:
        positional = "none (no catch-all branch)"
    elif re.search(r'=\s*"?\$1', star_action):
        positional = "accepted"
    elif "die_usage" in star_action or "unknown" in star_action or "exit 2" in star_action:
        positional = "rejected"
    else:
        positional = "unclear: %s" % star_action[:50]
    # A bracketed word anywhere in the help text is not a claim to a positional.
    # req-trailer.sh writes "default: <repo>/.claude/..." inside an option
    # description; counting that reported a positional it never claimed.
    synopsis = [ln for ln in doc.splitlines() if fn in ln]
    doc_positional = argparse_documented or any(POSITIONAL.search(ln) for ln in synopsis)
    findings = []
    if not has_help:
        findings.append(("no-help", "high" if doc else "high",
                         "no -h/--help handler; %s" % doc_where))
    if undocumented:
        findings.append(("undocumented-options", "medium",
                         "parser accepts %s; the help text names none of them"
                         % ", ".join(undocumented)))
    if phantom:
        findings.append(("phantom-options", "high",
                         "help text names %s; the parser accepts none of them"
                         % ", ".join(phantom)))
    if positional == "accepted" and not doc_positional:
        findings.append(("undocumented-positional", "medium",
                         "the catch-all branch consumes a positional the help text does not name"))
    if positional in ("rejected", "none (no catch-all branch)") and doc_positional:
        findings.append(("phantom-positional", "high",
                         "the help text names a positional the parser will not accept"))
    if positional == "accepted" and not rejects_unknown and not argparse_documented:
        # `*) ROOT="$1"` with no `-*)` branch above it accepts --anything as the
        # positional. A mistyped option is then silently treated as a path.
        findings.append(("silent-option-swallow", "medium",
                         "there is no -*) branch, so an unrecognised --option falls into the "
                         "positional branch and is accepted as a value instead of rejected"))
    if not accepted and positional != "accepted" and not re.search(r'\$#', text):
        findings.append(("ignores-all-arguments", "medium",
                         "no argument parsing and no argument-count guard: every argument, "
                         "including a mistyped one, is silently ignored"))
    contract.append({"script": fn, "accepted": sorted(accepted),
                     "rejects_unknown_options": rejects_unknown, "has_help": has_help,
                     "doc_where": doc_where, "undocumented": undocumented,
                     "phantom": phantom, "positional": positional,
                     "doc_positional": doc_positional, "findings": findings})

probes = {}
if probe_tsv and os.path.exists(probe_tsv):
    for line in open(probe_tsv):
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 3:
            probes[parts[0]] = {"help_exit": int(parts[1]), "bogus_flag_exit": int(parts[2])}

# ------------------------------------------------------------------ CENSUS ---
NAMES = {fn for fn in SCRIPT_FILES}
NAME_RE = re.compile("|".join(re.escape(n) for n in sorted(NAMES))) if NAMES else None

CLASSES = [
    ("usage",         "low",    r"unknown (option|argument)|usage:|needs a |unexpected argument"),
    ("missing-input", "low",    r"no such (file or )?directory|no config at|no living spec|"
                               r"not a git repositor|No such file or directory|nothing to compare"),
    ("not-found",     "medium", r"command not found|: not found"),
    ("permission",    "medium", r"[Pp]ermission denied"),
    ("interpreter",   "high",   r"Traceback \(most recent|SyntaxError|unbound variable|"
                               r"bad substitution|syntax error near"),
]
CLASS_RE = [(n, s, re.compile(rx)) for n, s, rx in CLASSES]

census = {"state": None, "detail": "", "files_seen": 0, "files_unparseable": 0,
          "invocations": 0, "failures": 0, "attributed": 0, "self_named": 0,
          "conversations": 0,
          "per_script": {}, "by_class": {}, "recovery": {"recovered": 0, "not-recovered": 0}}

def walk(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.endswith(".jsonl"):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)

census_exit = 0
if NAME_RE is None:
    census["state"] = "absent"
    census["detail"] = "no scripts to look for in %s" % scripts_dir
    census_exit = 3
elif not os.path.isdir(transcripts_root):
    census["state"] = "absent"
    census["detail"] = "no such directory: %s" % transcripts_root
    census_exit = 3
else:
    files = walk(transcripts_root)
    if not files:
        census["state"] = "empty"
        census["detail"] = "directory exists, contains no .jsonl transcripts"
        census_exit = 3
    else:
        events = []          # (conversation, order, script, ok, category, severity)
        parsed_any = False
        for path in files:
            census["files_seen"] += 1
            try:
                objs = []
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        line = line.strip()
                        if line:
                            objs.append(json.loads(line))
            except Exception:
                census["files_unparseable"] += 1
                continue
            parsed_any = True
            calls, results = {}, {}
            conv = path
            order = 0
            for obj in objs:
                if not isinstance(obj, dict):
                    continue
                # A subagent runs in its own context and gets corrected on its own,
                # so it is its own conversation even though it carries the parent
                # session id. Keying on sessionId alone reported eleven parallel
                # agents as one conversation.
                conv = "%s/%s" % (obj.get("sessionId") or conv, obj.get("agentId") or "-")
                m = obj.get("message") or {}
                c = m.get("content")
                if not isinstance(c, list):
                    continue
                for b in c:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use" and b.get("name") == "Bash":
                        cmd = (b.get("input") or {}).get("command") or ""
                        hits = sorted(set(NAME_RE.findall(cmd)))
                        if hits:
                            order += 1
                            calls[b.get("id")] = (conv, order, hits, cmd)
                    elif b.get("type") == "tool_result":
                        results[b.get("tool_use_id")] = b
        # A tool_use and its tool_result can sit in different files of the same
        # session, so match within the file and report the unmatched ones rather
        # than scoring them as successes.
            for tid, (conv, order, hits, cmd) in calls.items():
                res = results.get(tid)
                for name in hits:
                    census["invocations"] += 1
                    ps = census["per_script"].setdefault(
                        name, {"invocations": 0, "failures": 0, "attributed": 0,
                               "self_named": 0, "unmatched": 0, "classes": {}})
                    ps["invocations"] += 1
                    if res is None:
                        ps["unmatched"] += 1
                        events.append((conv, order, name, None, "unmatched", "unknown"))
                        continue
                    body = res.get("content")
                    if isinstance(body, list):
                        body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
                    body = body or ""
                    # `is_error` is the only ground truth here, and two weaker
                    # heuristics were tried and thrown away before settling on it:
                    #   - "any error-shaped string in the output" attributed a
                    #     compound line's unrelated `cat` failure to the script.
                    #   - "a line starting `<script>: `" looks like an error prefix
                    #     and is not: this repo prints `build-view: wrote ...`,
                    #     `signals: 3 observed`, `score: SCORED` in the same shape.
                    # Both inflated the rate, by 3 and 6 points respectively. The
                    # cost of is_error alone is stated in the report rather than
                    # papered over: a compound shell line ending in a successful
                    # command hides a failure in its middle, so this is a floor.
                    stem = name.rsplit(".", 1)[0]
                    own = re.compile(r"(?m)^(%s|%s): (?!wrote |green |recorded |SCORED |REFUSED )"
                                     % (re.escape(stem), re.escape(name)))
                    failed = bool(res.get("is_error"))
                    # The upper bound to sit beside the floor. Neither number is
                    # the truth on its own and neither is presented as if it were.
                    if own.search(body):
                        census["self_named"] += 1
                        ps["self_named"] += 1
                    cat, sev = None, None
                    if failed:
                        for n, sv, rx in CLASS_RE:
                            if rx.search(body):
                                cat, sev = n, sv
                                break
                    if failed:
                        cat = cat or "other"
                        sev = sev or "medium"
                        census["failures"] += 1
                        ps["failures"] += 1
                        # Whether the script said so itself, or the shell line merely
                        # exited non-zero somewhere. A compound command hides which,
                        # so the two are counted apart rather than merged into one
                        # number that would overstate what these scripts did.
                        if own.search(body):
                            census["attributed"] += 1
                            ps["attributed"] += 1
                        ps["classes"][cat] = ps["classes"].get(cat, 0) + 1
                        census["by_class"][cat] = census["by_class"].get(cat, 0) + 1
                    events.append((conv, order, name, not failed, cat, sev))
        convs = {e[0] for e in events}
        census["conversations"] = len(convs)
        # Self-recovery: after a failure, did the same script succeed later in
        # the same conversation?
        for conv, order, name, ok, cat, sev in events:
            if ok is not False:
                continue
            later = [e for e in events if e[0] == conv and e[2] == name and e[1] > order and e[3] is True]
            census["recovery"]["recovered" if later else "not-recovered"] += 1
        if not parsed_any:
            census["state"] = "unparseable"
            census["detail"] = "%d file(s), all unparseable" % census["files_seen"]
            census_exit = 4
        elif census["invocations"] == 0:
            census["state"] = "zero"
            census["detail"] = ("%d transcript file(s) read and not one invoked any of these "
                                "scripts" % census["files_seen"])
            census_exit = 5
        else:
            census["state"] = "read"
            census["detail"] = "%d file(s), %d unparseable" % (
                census["files_seen"], census["files_unparseable"])

if out_format == "json":
    print(json.dumps({"census": census, "contract": contract, "probes": probes},
                     indent=2, sort_keys=True))
    sys.exit(census_exit)

# ------------------------------------------------------------------- REPORT --
print("Productizer usage audit")
print("=" * 74)
print("")
print("CENSUS — what actually ran")
print("-" * 74)
if census["state"] == "absent":
    print("  NO TRANSCRIPT SOURCE. %s" % census["detail"])
    print("  The census did not happen. This is not an error rate of 0%.")
elif census["state"] == "empty":
    print("  NO TRANSCRIPTS. %s" % census["detail"])
    print("  Nothing was read, so no rate is reported.")
elif census["state"] == "unparseable":
    print("  NOTHING PARSEABLE. %s" % census["detail"])
    print("  No rate is reported, because none was measured.")
elif census["state"] == "zero":
    print("  A MEASURED ZERO. %s" % census["detail"])
    print("  The transcripts were read. These scripts were never invoked in them.")
else:
    n = census["invocations"]
    f = census["failures"]
    rate = (100.0 * f / n) if n else 0.0
    print("  %d invocation(s) across %d conversation(s) in %d transcript file(s)"
          % (n, census["conversations"], census["files_seen"]))
    print("  %d failure(s)" % f)
    print("  Overall error rate: %.1f%%  (n=%d)" % (rate, n))
    print("  Counted from the harness's is_error flag alone. %d of the %d also carried"
          % (census["attributed"], f))
    print("  a self-named error line; for the rest the shell line failed without the")
    print("  script naming itself, so blame is not established here. A compound line")
    print("  whose LAST command succeeds hides a failure in its middle, so this rate")
    print("  is a floor, not a ceiling.")
    ub = (100.0 * census["self_named"] / n) if n else 0.0
    print("")
    print("  Upper bound: %d invocation(s) (%.1f%%) printed a message naming the script"
          % (census["self_named"], ub))
    print("  that is not one of its known success shapes. Some are refusals the shell")
    print("  line swallowed; some are status output. The true rate is between %.1f%% and"
          % rate)
    print("  %.1f%%, and this tool cannot narrow it further without separated streams." % ub)
    if census["files_unparseable"]:
        print("  %d transcript file(s) would not parse and are excluded from n."
              % census["files_unparseable"])
    print("")
    print("  %-26s %6s %6s %7s %7s  %s"
          % ("script", "runs", "fail", "rate", "selfnmd", "classes"))
    for name in sorted(census["per_script"], key=lambda k: (-census["per_script"][k]["invocations"], k)):
        ps = census["per_script"][name]
        r = (100.0 * ps["failures"] / ps["invocations"]) if ps["invocations"] else 0.0
        cls = ", ".join("%s x%d" % (k, v) for k, v in sorted(ps["classes"].items())) or "-"
        extra = "  (%d result unmatched)" % ps["unmatched"] if ps["unmatched"] else ""
        print("  %-26s %6d %6d %6.1f%% %7d  %s%s"
              % (name, ps["invocations"], ps["failures"], r, ps["self_named"], cls, extra))
    print("")
    print("  failure classes: %s" % (", ".join("%s x%d" % (k, v)
          for k, v in sorted(census["by_class"].items())) or "none"))
    print("  self-recovery:   %d recovered on a later try in the same conversation, "
          "%d did not" % (census["recovery"]["recovered"], census["recovery"]["not-recovered"]))

print("")
print("CONTRACT — what the help text claims, against what the parser accepts")
print("-" * 74)
total_findings = 0
for c in contract:
    total_findings += len(c["findings"])
for c in contract:
    if not c["findings"]:
        continue
    print("")
    print("  %s" % c["script"])
    print("    documented via: %s" % c["doc_where"])
    print("    parser accepts: %s" % (", ".join(c["accepted"]) or "no options at all"))
    print("    positional:     %s%s" % (c["positional"],
          "   (help text names one)" if c["doc_positional"] else "   (help text names none)"))
    for kind, sev, detail in c["findings"]:
        print("    [%-6s] %-24s %s" % (sev, kind, detail))
    if c["script"] in probes:
        p = probes[c["script"]]
        print("    probe:          `--help` exited %d, `--zzz-not-a-real-flag` exited %d"
              % (p["help_exit"], p["bogus_flag_exit"]))
clean = [c["script"] for c in contract if not c["findings"]]
print("")
print("  %d script(s) audited, %d finding(s)." % (len(contract), total_findings))
print("  clean: %s" % (", ".join(clean) or "none"))
if probes and not any(c["findings"] for c in contract):
    for name in sorted(probes):
        p = probes[name]
        print("  probe %-26s --help exit %d, bogus flag exit %d"
              % (name, p["help_exit"], p["bogus_flag_exit"]))
sys.exit(census_exit)
PY
