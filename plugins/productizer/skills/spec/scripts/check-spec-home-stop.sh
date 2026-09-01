#!/usr/bin/env bash
# check-spec-home-stop.sh [--version] [--help] [--root DIR] [--fixture DIR]
#                         [--tree DIR]
#
# Asserts R19: IF THE SPEC HOME IS UNREACHABLE, THEN THE LIFECYCLE SHALL STOP
# RATHER THAN CLASSIFY AGAINST A REMEMBERED COPY.
#
# WHY THIS EXISTS, MEASURED RATHER THAN ARGUED. `check-spec-home.sh` was the
# only check the acceptance table pointed at for this, and its own header says
# it asserts R1 - one living spec per product. An audit made the spec home
# unreachable in two otherwise identical trees, one where nothing had been
# classified (R19 obeyed) and one where a classification had been recorded from
# a remembered copy (R19 violated), and that check produced byte-identical
# output and the same exit code in both. Its verdict is independent of whether
# R19 was obeyed, so it is not evidence about R19.
#
# `check-classification-provenance.sh` owns the other half of the mechanism and
# cannot own this one either: its first act is to read the spec, and it exits 2
# - unmeasured - the moment the spec home is unreachable. The one situation R19
# is about is the one situation it refuses to render a verdict in.
#
# WHAT R19 IS ABOUT. An agent cannot reach the authoritative spec, so it
# classifies an intent against a copy it remembers. A classification made
# against a remembered spec can miss a contradiction the real spec would have
# caught. The obligation is to STOP, not to proceed on stale information.
#
# WHAT MAKES THE VIOLATION OBSERVABLE. `record-classification.sh` writes the
# spec commit and content hash every classification was made against. So
# "classified from a remembered copy" is a fact on disk rather than a mood:
#
#   a record in a tree whose spec home cannot be read was made against
#   something other than the live spec, because the live spec was not there
#   to be read;
#
#   a record whose `Spec commit` is absent, blank, a placeholder or not
#   commit-shaped cannot name the spec it was made against at all.
#
# WHAT IT ASSERTS, SEPARATELY, EACH NAMED IN THE OUTPUT. Every one is driven by
# a constructed case under `fixtures/spec-home-stop/`, and every case declares
# both the construction and the verdict the detector must reach.
#
#   A1  unreachable spec home + nothing classified   -> CLEAN. The lifecycle
#       stopped. This is the honest inverse; without it the check only ever
#       proves it can say no.
#   A2  unreachable spec home + a classification recorded anyway -> FINDING.
#       This is the violation and the point of the check. A1 and A2 are
#       constructed as the same tree differing in exactly one thing: whether a
#       record is present. That is the audit's two-tree experiment, committed.
#   A3  a record whose `Spec commit` is absent, blank, a placeholder or not
#       commit-shaped -> FINDING. A record that cannot say which spec it was
#       made against cannot show it was made against the live one.
#   A4  reachable spec home + a well-formed record -> CLEAN. The negative
#       control: without it, a detector that fired on the mere existence of a
#       record would pass A2 and A3 and be worthless.
#
# THE PREMISE IS GUARDED BOTH WAYS, AND A FAILED PREMISE IS NEVER A PASS.
#
#   a case declared unreachable whose spec turns out readable   exit 2
#   a case declared reachable whose spec cannot be read         exit 2
#   a case declaring records whose store holds none             exit 2, and it
#       says which assertion was therefore never exercised. This repo has
#       already shipped an assertion that swept an empty set from the day it
#       was written; the second one does not get to happen quietly.
#   an assertion no case exercises                              exit 2
#   no cases at all, or a case with no `case.txt`               exit 2
#
# `--tree DIR` runs the detector on ONE tree and reports its verdict directly -
# 0 clean, 1 findings - with no declared expectation to compare against. That
# is the mode the two-tree experiment is run in, and it is also how this check
# is pointed at a real repository.
#
# NO NETWORK, EVER. Reachability is decided from local state: the spec named by
# `spec.path` in the tree's own `.claude/productizer/config.json`, read or not
# read. A check that asked the network would render one verdict on a train and
# another in the office, and CI would hang on the difference.
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not resolve a well-formed commit
# against an object store. That is `check-classification-provenance.sh`'s job,
# it needs a repository the record's tree may not be, and duplicating it here
# would go red on every shallow clone. Unresolvable here means unresolvable as
# a commit identity: no field, no value, a placeholder, or not a sha.
#
# It observes RECORDS, not the act of classifying. Nothing in a file can
# observe an act. The writer's refusal path is the other half, and the two are
# deliberately separate: this check would still fire on a record written by
# hand, by a model, or by a future writer that forgot to refuse.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. A record names an intent a
# stranger can write, and this output is tailed into a committed results file
# and read back into a model's context. The value of a field is never echoed -
# only the field, the line and the class of problem.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# unindented, which the runner parses as coverage. Everything else is indented
# or is a multi-word line. No absolute path is ever printed: an absolute path
# in a committed result names whoever ran it.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr. Nothing
# is written into the repository under examination; the only scratch is a
# temporary directory removed on exit.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean - every assertion held, or (--tree) the tree holds no finding
#   1  findings - an assertion did not hold, or (--tree) the tree holds one
#   2  could not run - bad usage, no fixture, no python3, a case whose premise
#      did not hold, or an assertion no case exercised. Never confused with 0.
set -euo pipefail

export LC_ALL=C

VERSION="check-spec-home-stop 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/spec-home-stop"
TREE=""

die_unmeasured() { printf 'check-spec-home-stop: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --tree)      [ "$#" -ge 2 ] || die_unmeasured "--tree needs a path";    TREE="$2";    shift 2 ;;
    --tree=*)    TREE="${1#--tree=}";       shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

command -v python3 >/dev/null 2>&1 ||
  die_unmeasured "python3 is not on PATH, so no tree can be read. Refusing rather than reporting an unexamined fixture as clean."

# The work tree, never the working directory. --root does not decide WHAT is
# examined - the fixture is found beside this script, so the case set is the
# same wherever this is invoked from - it decides what the printed paths are
# relative to, so nothing absolute reaches the committed result.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)"
else
  # No work tree: an installed plugin is not a repository. Paths are then
  # printed relative to the skill directory, which is still not absolute.
  ROOT="$SKILL"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-spec-home-stop.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# The detector. One tree in, TSV out. It reads and never writes.
#
#   PATH    <printable path>                     a file actually examined
#   INFO    home=reachable|unreachable  <why>    the premise, measured
#   INFO    records=<n>                          how many records the store holds
#   FINDING <class>  <path:line>  <sentence>     a violation, by location
#
# Exit 0 having reported, or 2 having refused. Never 0 on a tree it could not
# read: a store nobody could list is not a store with nothing in it.
# ---------------------------------------------------------------------------
cat > "$WORK/detect.py" <<'PY'
"""Decide, from local state only, whether one tree stopped or classified anyway."""
import json
import os
import posixpath
import re
import sys

tree, prefix = sys.argv[1], sys.argv[2]

CONFIG_REL = ".claude/productizer/config.json"
DEFAULT_SPEC = ".claude/productizer/spec.md"
STORE_REL = ".claude/productizer/classifications"

# The writer's own list, so a value it would refuse to write is a value this
# refuses to believe. A record whose provenance is a placeholder is a record
# that should not exist: an unreachable home yields no commit, and the answer
# to that is no record, not a record with the gap written into it.
PLACEHOLDERS = {
    "—", "–", "--", "-", "?", "??", "n/a", "na", "none", "null",
    "nil", "unknown", "unset", "tbd", "todo", "pending", "placeholder", "0",
}

RE_COMMIT = re.compile(r"^[0-9a-f]{40}$")

WHY_A3 = ("A record that cannot name the spec it was made against cannot show "
          "it was made against the live one.")


def die(message):
    sys.stderr.write("check-spec-home-stop: %s\n" % message)
    raise SystemExit(2)


def out(*fields):
    sys.stdout.write("\t".join(fields) + "\n")


def show(path):
    """Repo-relative, canonical, never absolute and never carrying a `..`
    segment - the runner matches these against the change set by exact text."""
    rel = posixpath.normpath(os.path.relpath(path, tree).replace(os.sep, "/"))
    if prefix:
        rel = posixpath.normpath(prefix + "/" + rel)
    if rel.startswith("..") or rel.startswith("/"):
        die("a path escaped the tree being examined. Refusing to print it: an "
            "unanchored path is one the runner cannot match and one that may "
            "name somebody's home directory.")
    return rel


if not os.path.isdir(tree):
    die("the tree to examine is not a directory. Unmeasured, not clean.")

# --- what the tree declares about its own spec home ------------------------
spec_rel = DEFAULT_SPEC
home = "(not declared)"
config_path = os.path.join(tree, CONFIG_REL)
if os.path.exists(config_path):
    try:
        with open(config_path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        die("%s could not be read as JSON (%s). A config nobody can parse does "
            "not say where the spec home is - unmeasured, not reachable."
            % (show(config_path), exc.__class__.__name__))
    if not isinstance(cfg, dict):
        die("%s is not a JSON object, so it declares no spec home. Unmeasured."
            % show(config_path))
    out("PATH", show(config_path))
    spec = cfg.get("spec") if isinstance(cfg.get("spec"), dict) else {}
    declared = spec.get("path")
    if isinstance(declared, str) and declared.strip():
        spec_rel = declared.strip()
    product = cfg.get("product") if isinstance(cfg.get("product"), dict) else {}
    for key in ("spec_home", "spec_repo"):
        value = product.get(key)
        if isinstance(value, str) and value.strip():
            home = value.strip()
            break

if spec_rel.startswith("/") or ".." in spec_rel.split("/"):
    die("the declared `spec.path` leaves the tree. Refusing rather than "
        "reading a file the declaration does not actually name.")

out("INFO", "declared home=%s" % home, spec_rel)

# --- reachable, or not, decided locally ------------------------------------
spec_path = os.path.join(tree, spec_rel)
reachable = False
why = ""
if os.path.islink(spec_path) and not os.path.exists(spec_path):
    why = "a link at %s whose target is not there" % show(spec_path)
elif not os.path.exists(spec_path):
    why = "no file at %s" % show(spec_path)
elif not os.path.isfile(spec_path):
    why = "%s is not a regular file" % show(spec_path)
else:
    try:
        with open(spec_path, "rb") as fh:
            fh.read(1)
        reachable = True
    except OSError as exc:
        why = ("%s exists but cannot be read (%s)"
               % (show(spec_path), exc.strerror or exc.__class__.__name__))

if reachable:
    out("PATH", show(spec_path))
    out("INFO", "home=reachable", show(spec_path))
else:
    out("INFO", "home=unreachable", why)

# --- the store. Absent, unlistable and empty are three different answers ----
store = os.path.join(tree, STORE_REL)
records = []
if os.path.exists(store):
    if not os.path.isdir(store):
        die("%s exists and is not a directory, so how many classifications "
            "were recorded is UNKNOWN, not zero." % show(store))
    try:
        names = sorted(os.listdir(store))
    except OSError as exc:
        die("%s cannot be listed (%s). How many classifications were recorded "
            "is UNKNOWN, not zero - a directory nobody can open is exactly "
            "where the one made from a remembered copy hides."
            % (show(store), exc.strerror or exc.__class__.__name__))
    records = [n for n in names if n.endswith(".md")]

out("INFO", "records=%d" % len(records))

for name in records:
    path = os.path.join(store, name)
    out("PATH", show(path))
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        die("cannot read %s (%s). A record nobody could open is not a record "
            "that is fine." % (show(path), exc.__class__.__name__))

    # A2: the tree could not reach its own spec, and a classification exists.
    if not reachable:
        out("FINDING", "A2", "%s:1" % show(path),
            "a classification was recorded while the spec home was unreachable "
            "(%s). R19 says stop. A record made with no live spec to read was "
            "made against a remembered copy, and a classification made from a "
            "remembered copy can miss a contradiction the real spec would have "
            "caught." % why)

    # A3: the record cannot name the spec it was made against.
    hits = []
    for i, line in enumerate(text.split("\n")):
        if line.startswith("Spec commit:"):
            hits.append((i + 1, line.split(":", 1)[1].strip()))

    if not hits:
        out("FINDING", "A3", "%s:1" % show(path),
            "the record carries no `Spec commit` line at all, so it names no "
            "spec. " + WHY_A3)
        continue
    if len(hits) > 1:
        out("FINDING", "A3", "%s:%d" % (show(path), hits[1][0]),
            "the record carries %d `Spec commit` lines, so which spec it names "
            "is undefined. %s" % (len(hits), WHY_A3))
        continue

    lineno, value = hits[0]
    if not value:
        out("FINDING", "A3", "%s:%d" % (show(path), lineno),
            "the record's `Spec commit` is blank. " + WHY_A3)
    elif value.lower() in PLACEHOLDERS:
        out("FINDING", "A3", "%s:%d" % (show(path), lineno),
            "the record's `Spec commit` carries a placeholder rather than a "
            "measurement. An unreachable spec home yields no commit, and the "
            "answer to that is no record - not a record with the gap written "
            "in. " + WHY_A3)
    elif not RE_COMMIT.match(value):
        out("FINDING", "A3", "%s:%d" % (show(path), lineno),
            "the record's `Spec commit` is not a 40-character lowercase hex "
            "commit sha, so it resolves to no commit. " + WHY_A3)
PY

# ---------------------------------------------------------------------------
# Running the detector once, and reading back what it said.
# ---------------------------------------------------------------------------
D_HOME=""; D_WHY=""; D_RECORDS=""; D_TOTAL=0; D_A2=0; D_A3=0

run_detector() { # <tree> <printable prefix>
  local rc=0
  python3 "$WORK/detect.py" "$1" "$2" > "$WORK/detect.tsv" || rc=$?
  [ "$rc" -eq 0 ] ||
    die_unmeasured "the tree could not be examined (see the reason above). Unmeasured, and never a pass."

  D_HOME=""; D_WHY=""; D_RECORDS=""; D_TOTAL=0; D_A2=0; D_A3=0
  : > "$WORK/findings.txt"
  local kind a b c
  while IFS="$(printf '\t')" read -r kind a b c; do
    case "$kind" in
      PATH) printf '%s\n' "$a" ;;
      INFO)
        case "$a" in
          home=*)    D_HOME="${a#home=}"; D_WHY="$b" ;;
          records=*) D_RECORDS="${a#records=}" ;;
          "declared home="*) printf '  declared home: %s, spec path %s\n' "${a#declared home=}" "$b" ;;
        esac
        ;;
      FINDING)
        D_TOTAL=$((D_TOTAL + 1))
        case "$a" in
          A2) D_A2=$((D_A2 + 1)) ;;
          A3) D_A3=$((D_A3 + 1)) ;;
        esac
        printf '%s\t%s\t%s\n' "$a" "$b" "$c" >> "$WORK/findings.txt"
        ;;
    esac
  done < "$WORK/detect.tsv"

  [ -n "$D_HOME" ] && [ -n "$D_RECORDS" ] ||
    die_unmeasured "the detector reported no home state or no record count for this tree. Unmeasured."
}

print_findings() { # <label>
  local cls loc text
  while IFS="$(printf '\t')" read -r cls loc text; do
    [ -n "$cls" ] || continue
    printf '  %s %s: %s: %s\n' "$1" "$cls" "$loc" "$text"
  done < "$WORK/findings.txt"
}

# ---------------------------------------------------------------------------
# --tree: one tree, its own verdict, nothing declared to compare against.
# ---------------------------------------------------------------------------
if [ -n "$TREE" ]; then
  # The basename only: this message can reach a committed result file, and a
  # path typed on the command line is somebody's home directory more often
  # than not.
  [ -d "$TREE" ] || die_unmeasured "--tree names something that is not a directory: ${TREE##*/}"
  run_detector "$TREE" ""
  printf '  spec home: %s%s\n' "$D_HOME" "$([ -n "$D_WHY" ] && printf ' — %s' "$D_WHY")"
  printf '  classification records: %s\n' "$D_RECORDS"
  print_findings "detected"
  printf '  findings: %d (A2 %d, A3 %d)\n' "$D_TOTAL" "$D_A2" "$D_A3"
  if [ "$D_TOTAL" -gt 0 ]; then
    printf 'FAIL: R19 is violated in this tree - a classification exists that cannot be shown to have been made against the live spec.\n' >&2
    exit 1
  fi
  if [ "$D_HOME" = "unreachable" ]; then
    printf '  R19 obeyed: the spec home is unreachable and nothing was classified. The lifecycle stopped.\n'
  else
    printf '  the spec home is reachable, so R19 was not in force here; every record present names a spec it could have been made against.\n'
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# The declared cases.
# ---------------------------------------------------------------------------
[ -d "$FIXTURE" ] ||
  die_unmeasured "no fixture directory at ${FIXTURE##*/}; the constructed cases are missing, which is unmeasured and not a pass"

rel_to_root() {
  case "$1" in
    "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;;
    *)         printf '%s' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

field() { # <key> <file>
  awk -v k="$1" 'index($0, k ": ") == 1 { sub(/^[^:]*:[ \t]*/, ""); print; exit }' "$2"
}

A1_EX=0; A1_UP=0
A2_EX=0; A2_UP=0
A3_EX=0; A3_UP=0
A4_EX=0; A4_UP=0

bump() { # <class> <ex|up>
  case "$1:$2" in
    A1:ex) A1_EX=$((A1_EX + 1)) ;; A1:up) A1_UP=$((A1_UP + 1)) ;;
    A2:ex) A2_EX=$((A2_EX + 1)) ;; A2:up) A2_UP=$((A2_UP + 1)) ;;
    A3:ex) A3_EX=$((A3_EX + 1)) ;; A3:up) A3_UP=$((A3_UP + 1)) ;;
    A4:ex) A4_EX=$((A4_EX + 1)) ;; A4:up) A4_UP=$((A4_UP + 1)) ;;
    *) die_unmeasured "a case declares assertion '$1', which this check does not implement. Unmeasured." ;;
  esac
}

cases=0
failed=0

for CASE_DIR in "$FIXTURE"/*/; do
  # An unmatched glob arrives as its own literal text, so test the path.
  [ -d "$CASE_DIR" ] || continue
  CASE_DIR="${CASE_DIR%/}"
  DECL="$CASE_DIR/case.txt"
  [ -f "$DECL" ] && [ -r "$DECL" ] ||
    die_unmeasured "$(rel_to_root "$CASE_DIR") has no readable case.txt. A case that does not declare what it constructs cannot have its premise checked, and an unchecked premise is how a case comes to test nothing."

  cases=$((cases + 1))
  CASE_REL="$(rel_to_root "$CASE_DIR")"
  printf '%s\n' "$(rel_to_root "$DECL")"

  NAME="$(field Case "$DECL")"
  ASSERTS="$(field Asserts "$DECL")"
  WANT_HOME="$(field Home "$DECL")"
  WANT_RECORDS="$(field Records "$DECL")"
  EXPECT="$(field Expect "$DECL")"
  WANT_FINDINGS="$(field Findings "$DECL")"

  printf '  case %s: %s\n' "${CASE_DIR##*/}" "$NAME"

  case "$WANT_HOME" in unreachable|reachable) ;; *) die_unmeasured "$CASE_REL/case.txt declares Home: '$WANT_HOME', which is neither reachable nor unreachable." ;; esac
  case "$EXPECT" in clean|finding) ;; *) die_unmeasured "$CASE_REL/case.txt declares Expect: '$EXPECT', which is neither clean nor finding." ;; esac
  case "$WANT_RECORDS" in ''|*[!0-9]*) die_unmeasured "$CASE_REL/case.txt declares Records: '$WANT_RECORDS', which is not a whole number." ;; esac
  case "$WANT_FINDINGS" in ''|*[!0-9]*) die_unmeasured "$CASE_REL/case.txt declares Findings: '$WANT_FINDINGS', which is not a whole number." ;; esac
  case "$ASSERTS" in A1|A2|A3|A4) ;; *) die_unmeasured "$CASE_REL/case.txt declares Asserts: '$ASSERTS', which is not one of A1 A2 A3 A4." ;; esac

  run_detector "$CASE_DIR" "$CASE_REL"

  # --- the premise, measured against what the case says it constructed -----
  if [ "$D_HOME" != "$WANT_HOME" ]; then
    die_unmeasured "$CASE_REL declares its spec home $WANT_HOME and it measures as $D_HOME (${D_WHY:-no reason given}). The case was never tested, so assertion $ASSERTS was never exercised. Unmeasured, not a pass."
  fi
  if [ "$D_RECORDS" != "$WANT_RECORDS" ]; then
    if [ "$WANT_RECORDS" != "0" ] && [ "$D_RECORDS" = "0" ]; then
      die_unmeasured "$CASE_REL declares $WANT_RECORDS classification record(s) and its store holds none, so assertion $ASSERTS swept an empty set. An assertion with no positive case to fire on holds vacuously forever. Unmeasured, not a pass."
    fi
    die_unmeasured "$CASE_REL declares $WANT_RECORDS classification record(s) and its store holds $D_RECORDS. The case is not the case it says it is; what was exercised is unknown."
  fi

  bump "$ASSERTS" ex

  printf '  spec home: %s%s\n' "$D_HOME" "$([ -n "$D_WHY" ] && printf ' — %s' "$D_WHY")"
  printf '  classification records: %s\n' "$D_RECORDS"
  print_findings "detected"

  # --- the verdict the detector actually reached ---------------------------
  observed_class=0
  case "$ASSERTS" in
    A2) observed_class="$D_A2" ;;
    A3) observed_class="$D_A3" ;;
    *)  observed_class="$D_TOTAL" ;;
  esac

  held=1
  if [ "$D_TOTAL" -ne "$WANT_FINDINGS" ]; then held=0; fi
  if [ "$EXPECT" = "finding" ] && [ "$D_TOTAL" -eq 0 ]; then held=0; fi
  if [ "$EXPECT" = "clean" ] && [ "$D_TOTAL" -ne 0 ]; then held=0; fi
  if [ "$EXPECT" = "finding" ] && [ "$observed_class" -ne "$WANT_FINDINGS" ]; then held=0; fi

  if [ "$EXPECT" = "finding" ]; then
    WANTED="$WANT_FINDINGS finding(s), all of class $ASSERTS"
  else
    WANTED="clean - no finding of any class"
  fi

  if [ "$held" -eq 1 ]; then
    bump "$ASSERTS" up
    printf '  held: %s — expected %s; observed %d finding(s) (A2 %d, A3 %d)\n' \
      "$ASSERTS" "$WANTED" "$D_TOTAL" "$D_A2" "$D_A3"
  else
    failed=$((failed + 1))
    printf '  FINDING: did not hold - %s expected %s; observed %d finding(s) (A2 %d, A3 %d)\n' \
      "$ASSERTS" "$WANTED" "$D_TOTAL" "$D_A2" "$D_A3"
  fi
done

[ "$cases" -gt 0 ] ||
  die_unmeasured "the fixture holds no case directory, so nothing about R19 was exercised. An empty case set is unmeasured, not clean."

printf 'cases examined: %d\n' "$cases"
printf 'assertion A1 (unreachable home, nothing classified -> clean): exercised %d, upheld %d\n' "$A1_EX" "$A1_UP"
printf 'assertion A2 (unreachable home, a classification recorded anyway -> finding): exercised %d, upheld %d\n' "$A2_EX" "$A2_UP"
printf 'assertion A3 (a record that cannot name its spec commit -> finding): exercised %d, upheld %d\n' "$A3_EX" "$A3_UP"
printf 'assertion A4 (reachable home, a well-formed record -> clean): exercised %d, upheld %d\n' "$A4_EX" "$A4_UP"

if [ "$failed" -gt 0 ]; then
  printf 'FAIL: %d case(s) did not reach the verdict R19 requires. An unreachable spec home no longer stops a classification, or the detector fires where it must not.\n' "$failed" >&2
  exit 1
fi

# An assertion nothing exercised held vacuously, and a vacuous hold reported as
# a pass is the failure this file was written to avoid repeating.
unexercised=""
[ "$A1_EX" -gt 0 ] || unexercised="$unexercised A1"
[ "$A2_EX" -gt 0 ] || unexercised="$unexercised A2"
[ "$A3_EX" -gt 0 ] || unexercised="$unexercised A3"
[ "$A4_EX" -gt 0 ] || unexercised="$unexercised A4"
if [ -n "$unexercised" ]; then
  printf 'REFUSED: no case exercised%s. An assertion with nothing to fire on holds vacuously, and this run asserts nothing about it - unmeasured, not clean.\n' "$unexercised" >&2
  exit 2
fi

printf 'PASS: %d constructed cases. An unreachable spec home with nothing classified is clean (A1); the same tree with one classification recorded is a finding (A2); a record that cannot name its spec commit is a finding (A3); and a reachable home with a well-formed record stays clean (A4).\n' "$cases"
