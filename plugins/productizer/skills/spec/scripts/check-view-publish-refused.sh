#!/usr/bin/env bash
# check-view-publish-refused.sh [--root DIR] [--hook PATH] [--fixture DIR]
#                              [--settings PATH] [--version] [--help]
#
# Asserts the half of R31 that nothing observed: IF A PUBLISHED VIEW DECLARES A
# CAPABILITY THAT CAN PUBLISH NEW VERSIONS OF ITSELF, THEN THE LIFECYCLE SHALL
# REFUSE TO PUBLISH IT.
#
# WHY THIS EXISTS SEPARATELY FROM `view-read-only`. That check reads the
# generated page and asserts it declares no such capability - it observes the
# page NOT ASKING. R31's obligation is that the lifecycle REFUSES TO PUBLISH,
# and until `.claude/hooks/artifact-gate.sh` there was no refusal to observe,
# because an artifact is published through the Artifact tool and the existing
# publish gate is registered on Bash. Half of R31 was unimplemented rather than
# merely unverified. This check drives the real hook and watches it decline.
#
# It also reaches the surface `view-read-only` writes down that it cannot
# reach. Its limitations block says the grant is made when the page is
# published, not inside the page, so a capability granted at publish time
# leaves no trace in the file it reads. Cases marked `call` here are exactly
# that: a clean page, a forbidden capability in the publish call's
# `capabilities` argument, and a refusal.
#
# NOTHING IS EVER PUBLISHED. The hook is a filter on a tool call, so it is fed
# a payload on stdin and its decision is read off stdout. No page leaves this
# machine, and the fixture pages are not real views - they are the smallest
# thing that declares each capability.
#
# SIX ASSERTIONS, COUNTED SEPARATELY. A single `ok` flag reported above six
# lines of evidence is how a check in this repo printed `upheld: 0` while
# holding six things; each group below carries its own case count and its own
# upheld count, and a group is upheld only when every case in it is.
#
#   A1  a page ASKING for a self-publishing capability is refused
#   A2  a self-publishing capability GRANTED BY THE CALL is refused, even when
#       the page's own source is clean
#   A3  a publish this gate cannot read is refused rather than guessed at
#   A4  a publish that declares only output IS ALLOWED. A gate that blocks
#       every publish is as broken as one that blocks none, and it is switched
#       off just as fast
#   A5  the emitted document carries exactly ONE decision, and it is the gate's
#       own. Text out of the page reaches the reason string, so a page holding
#       the literal bytes of an allow decision must not be able to forge one by
#       being quoted back
#   A6  the hook this check drove is the hook the harness is CONFIGURED TO RUN.
#       A1-A5 feed it a payload directly, so all five hold just as well for a
#       correct gate that nothing ever invokes. Three parts, and each one is a
#       way the wiring has failed elsewhere: an entry exists whose matcher is
#       exactly `Artifact`; its command resolves to a file that exists and is
#       executable; and that file is BYTE-IDENTICAL to the one driven here, so
#       a registration pointing at a stale or different copy is a finding
#       rather than a pass. Compared by content, never by string equality of
#       the configured value - two spellings of the same path are the same
#       hook, and one spelling of two different files is not.
#
# A6 ASSERTS THE WIRING, NOT THE FIRING. It proves the settings file NAMES this
# hook on the Artifact matcher. It does not prove the Artifact tool actually
# calls it: that would take a real publish, and the whole point of this gate is
# that a publish under test is still a publish. The gap is narrower than it was
# and it is not closed, and R31's coverage claim says so in those words.
#
# THE PREMISE IS GUARDED, FIVE WAYS. If the fixture holds no page declaring a
# forbidden capability, no call granting one, no unreadable publish, or nothing
# that must be allowed, then the corresponding refusal was never exercised and
# this run asserts nothing about it - exit 2, unmeasured, never a pass. An
# assertion sweeping an empty set has already shipped in this repo once. The
# fifth premise is A6's: a settings file that is absent or that does not parse
# is exit 2, because a registration nobody could read has not been shown to
# exist, and "I could not find it" is not "it is not there".
#
# DECLARED LIMITATION OF A6. The matcher must be spelled exactly `Artifact`. A
# harness that also honours a regex spelling - `Artifact|Bash`, say - would be
# correctly wired and reported here as a finding. That is the false positive
# this strictness buys, it is loud rather than silent, and the finding names
# the matcher it did find so the reader is not left guessing.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every case reached the decision the fixture says it must
#   1  findings - a publish that had to be refused was not, one that had to go
#      through did not, or a decision was not the gate's own
#   2  could not run - bad usage, no work tree, no hook, no fixture, an
#      unreadable case file, or a premise that was never exercised
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# which the runner parses as coverage. Case lines, findings and counts are
# INDENTED. Nothing absolute is printed and no reason text is reproduced: this
# output is tailed into a committed result file, and both a home directory and
# a page's own bytes would be published to everyone who clones the repo.
set -euo pipefail

VERSION="check-view-publish-refused 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=""; HOOK=""; FIXTURE=""; SETTINGS=""

die_unmeasured() { printf 'check-view-publish-refused: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --hook)      [ "$#" -ge 2 ] || die_unmeasured "--hook needs a path";    HOOK="$2";    shift 2 ;;
    --hook=*)    HOOK="${1#--hook=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --settings)   [ "$#" -ge 2 ] || die_unmeasured "--settings needs a path"; SETTINGS="$2"; shift 2 ;;
    --settings=*) SETTINGS="${1#--settings=}"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1. The tree is named with --root." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1. The tree is named with --root."

# The work tree, never the working directory. Run from a subdirectory this must
# check the same thing it checks from the root, or the answer depends on where
# the person stood when they asked.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given. The hook to drive could not be located; unmeasured, not clean."
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$HOOK" ]    || HOOK="$ROOT/.claude/hooks/artifact-gate.sh"
[ -n "$FIXTURE" ] || FIXTURE="$HERE/../fixtures/view-publish-refused"

[ -f "$HOOK" ] && [ -r "$HOOK" ] \
  || die_unmeasured "no readable publish hook at the path given. There is nothing to drive, so whether the lifecycle refuses to publish a self-publishing view is UNMEASURED, not satisfied"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory at the path given; there are no publishes to drive"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
CASES="$FIXTURE/cases.tsv"
[ -f "$CASES" ] && [ -r "$CASES" ] || die_unmeasured "no readable cases.tsv in the fixture; nothing to drive"

command -v jq >/dev/null 2>&1 || die_unmeasured "jq is not installed; the hook's decision could not be read, which is unmeasured and not a pass"

# The case file's shape is checked BEFORE any case runs. `read` pads missing
# fields with empty strings, so a short row would otherwise arrive looking like
# a case with an empty expectation and be judged rather than refused.
#
# `|| :` is load-bearing and is not tolerance of an unknown failure: awk exits 1
# exactly when it found a bad row, which is the condition being detected, and
# under `set -e` with `pipefail` that status would kill the script here - right
# exit code, and no reason printed at all.
_badrow="$(awk -F'\t' '/^#/ || NF == 0 { next } NF != 7 { printf "%d ", NR; bad = 1 } END { exit bad ? 1 : 0 }' "$CASES" || :)"
[ -z "$_badrow" ] || die_unmeasured "cases.tsv has rows that are not seven tab-separated fields (line(s): $_badrow). A case file this check cannot read is not one it may guess at"

# Paths are printed repo-relative. An absolute path in this output is somebody's
# home directory in a committed file.
rel() { case "$1" in "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;; *) printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;; esac; }

SEEN=' '
examined() {
  local r; r="$(rel "$1")"
  case "$SEEN" in *" $r "*) return 0 ;; esac
  SEEN="$SEEN$r "
  printf '%s\n' "$r"
}

examined "$HOOK"
examined "$CASES"

# --- the registration, read before anything is driven -----------------------
#
# Read here rather than at the end so an unreadable settings file refuses the
# run before twenty publishes are judged against a gate nobody can show is
# wired in.
[ -n "$SETTINGS" ] || SETTINGS="$ROOT/.claude/settings.json"
[ -f "$SETTINGS" ] && [ -r "$SETTINGS" ] \
  || die_unmeasured "no readable settings file at the path given, so whether this hook is registered on the Artifact matcher is UNKNOWN. A registration nobody could read has not been shown to exist"
examined "$SETTINGS"

# jq names the file it was handed in its error messages, and that name would be
# an absolute path landing in a committed result file. Handed the bytes on
# STDIN it says `<stdin>` instead, which is all a reader needs.
REG_CMDS="$(jq -r '
  .hooks.PreToolUse // []
  | .[]
  | select((.matcher? // "") == "Artifact")
  | (.hooks // [])[]
  | select((.type? // "command") == "command")
  | .command // empty' < "$SETTINGS" 2>&1)" \
  || die_unmeasured "the settings file did not parse, so the registration could not be read: $REG_CMDS"

# Only for the wording of a part-1 finding: a matcher that mentions Artifact
# without being exactly it. `|| :` is load-bearing and is not tolerance of an
# unknown failure - jq exits non-zero when `test` is handed a matcher that is
# not a string, and under `set -e` with `pipefail` that would kill the script
# here with the right exit code and no reason printed at all.
REG_NEAR="$(jq -r '
  .hooks.PreToolUse // [] | .[] | (.matcher? // "")
  | select(type == "string") | select(test("Artifact")) | select(. != "Artifact")' \
  < "$SETTINGS" || :)"

FINDINGS_FILE="$(mktemp)"
# The hook writes to stderr when it blocks a call it could not read, and jq
# writes there when it is handed something it cannot parse. Neither is thrown
# away: both are captured here and reported INDENTED, because this check's own
# unindented lines are what the runner counts as coverage, and a refusal
# message loose in that stream would be read as a file path.
ERR_FILE="$(mktemp)"
trap 'rm -f "$FINDINGS_FILE" "$ERR_FILE"' EXIT

findings=0
cases_run=0

# Per-assertion tallies. Never one flag: a group is upheld only when its own
# count of upheld cases equals its own count of cases.
a1_n=0; a1_ok=0     # a page asking for a self-publishing capability is refused
a2_n=0; a2_ok=0     # a self-publishing capability granted by the CALL is refused
a3_n=0; a3_ok=0     # a publish the gate cannot read is refused, not guessed
a4_n=0; a4_ok=0     # a publish declaring only output is allowed
a5_n=0; a5_ok=0     # one decision, and it is the gate's own
a6_n=3; a6_ok=0     # the hook driven here is the hook the harness is wired to

note_finding() {
  findings=$((findings + 1))
  printf '  FINDING: %s\n' "$1" >> "$FINDINGS_FILE"
}

while IFS=$'\t' read -r id expect surface page caps action _note; do
  case "${id:-}" in ''|'#'*) continue ;; esac

  # --- build the payload the tool would have handed the hook ---------------
  if [ "${page#raw:}" != "$page" ]; then
    payload="${page#raw:}"
  else
    fp=""
    if [ "$page" != "-" ]; then
      fp="$FIXTURE/pages/$page"
      # A case naming a page that IS there is a file this check examined; one
      # naming a page that is deliberately absent is not, and printing it would
      # claim coverage of a file that does not exist.
      [ -f "$fp" ] && examined "$fp"
    fi
    [ "$caps" = "-" ] && caps=""
    [ "$action" = "-" ] && action=""
    payload="$(jq -nc --arg fp "$fp" --arg act "$action" --arg caps "$caps" '
      {tool_name: "Artifact", tool_input: (
         (if $fp   == "" then {} else {file_path: $fp} end)
       + (if $act  == "" then {} else {action: $act} end)
       + (if $caps == "" then {} else {capabilities: ($caps | fromjson)} end)
      )}')" \
      || die_unmeasured "case '$id' does not describe a payload this check can build; its caps column is not JSON. A fixture that cannot be read is not a fixture that passed"
  fi

  # --- drive the real hook -------------------------------------------------
  #
  # `|| rc=$?` is load-bearing and is not tolerance of an unknown failure: exit
  # 2 is the hook's documented way of blocking a call it could not read, and
  # under `set -e` with `pipefail` that status would kill this script here -
  # right exit code, and no case line printed at all.
  rc=0
  : > "$ERR_FILE"
  out="$(printf '%s' "$payload" | bash "$HOOK" 2>"$ERR_FILE")" || rc=$?
  cases_run=$((cases_run + 1))

  # --- read the decision ---------------------------------------------------
  #
  # A5 is evaluated here for every case that produced a document: exactly one
  # decision field, carrying the gate's own verdict. jq parses; a page that
  # spliced a second decision into the text would show up as a second path.
  got=""
  if [ "$rc" -eq 0 ]; then
    ndec=0
    ndec="$(printf '%s' "$out" | jq -r '[paths | select(.[-1] == "permissionDecision")] | length' 2>>"$ERR_FILE")" || ndec="unparseable"
    if [ "$ndec" = "unparseable" ]; then
      got="malformed"
      note_finding "$id: the hook exited 0 without emitting a decision this check could parse. A gate whose verdict cannot be read has not delivered one"
    else
      got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "absent"')"
      evname="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // "absent"')"
      # A decision is `allow` or `deny`. Anything else came out of a document
      # the gate did not fully write - which, when a gate concatenates its JSON
      # instead of building it, is the PAGE'S OWN TEXT wearing the decision
      # field. It is truncated to one short line before it is printed anywhere:
      # this output is tailed into a committed result file, and a page whose
      # bytes land there has published itself by another route.
      case "$got" in
        allow|deny) ;;
        *) got="not-a-decision[$(printf '%s' "$got" | tr -d '\n' | cut -c1-32)]" ;;
      esac
      a5_n=$((a5_n + 1))
      if [ "$ndec" = 1 ] && [ "$evname" = "PreToolUse" ] && { [ "$got" = allow ] || [ "$got" = deny ]; }; then
        a5_ok=$((a5_ok + 1))
      else
        note_finding "$id: the emitted document carries $ndec decision fields, event name '$evname', decision '$got'. Exactly one decision, named by the gate itself, is the whole point: a page whose bytes reach the reason string must not be able to write the verdict"
      fi
    fi
  elif [ "$rc" -eq 2 ]; then
    got="blocked"
  else
    got="exit$rc"
    note_finding "$id: the hook exited $rc, which is neither a decision nor a block. Claude Code runs the tool anyway on any status other than 0 or 2, so this is a gate that published"
  fi

  # `blocked` and `deny` are both refusals; they differ only in whether the gate
  # could speak. A case that must be refused is upheld by either, and never by
  # an allow.
  refused=0
  case "$got" in deny|blocked) refused=1 ;; esac

  ok=0
  case "$expect" in
    deny)    [ "$got" = deny ] && ok=1 ;;
    blocked) [ "$got" = blocked ] && ok=1 ;;
    allow)   [ "$got" = allow ] && ok=1 ;;
    *) die_unmeasured "case '$id' expects '$expect', which is not one of deny, allow, blocked. An expectation this check cannot read is not one it may skip" ;;
  esac

  case "$surface" in
    page)
      a1_n=$((a1_n + 1))
      if [ "$refused" = 1 ]; then a1_ok=$((a1_ok + 1)); else
        note_finding "$id: a page declaring a capability that can publish new versions of itself was NOT refused; the gate said '$got'. This is R31's whole obligation"
      fi ;;
    call)
      a2_n=$((a2_n + 1))
      if [ "$refused" = 1 ]; then a2_ok=$((a2_ok + 1)); else
        note_finding "$id: a self-publishing capability granted in the PUBLISH CALL was NOT refused; the gate said '$got'. Reading the page cannot catch this one - check-view-readonly.sh says so in its own limitations - so this gate is the only place it is visible"
      fi ;;
    shape|action)
      a3_n=$((a3_n + 1))
      if [ "$refused" = 1 ]; then a3_ok=$((a3_ok + 1)); else
        note_finding "$id: a publish the gate could not read was NOT refused; it said '$got'. A page whose capabilities are unknown is not a page with none"
      fi ;;
    output)
      a4_n=$((a4_n + 1))
      if [ "$got" = allow ]; then a4_ok=$((a4_ok + 1)); else
        note_finding "$id: a publish that declares only output was refused; the gate said '$got'. A gate that blocks every publish is as broken as one that blocks none, and it gets switched off just as fast"
      fi ;;
    *) die_unmeasured "case '$id' names surface '$surface', which this check cannot classify" ;;
  esac

  if [ "$ok" = 1 ]; then
    printf '  case %s: expected %s, got %s\n' "$id" "$expect" "$got"
  else
    printf '  case %s: expected %s, GOT %s\n' "$id" "$expect" "$got"
    note_finding "$id: expected $expect, got $got"
  fi
  if [ -s "$ERR_FILE" ]; then
    # Only the first line, and only its first 120 characters. The whole message
    # is the hook's own prose, and reproducing it would put a second copy of a
    # refusal inside a committed result file.
    printf '    the gate wrote to stderr: %.120s\n' "$(head -1 "$ERR_FILE")"
  fi
done < "$CASES"

# --- the premises, guarded ---------------------------------------------------
#
# Each of these is a refusal that was never exercised. A group with no case in
# it holds vacuously forever, which is the shape of a check that passes for
# months without once seeing the thing it looks for.
[ "$cases_run" -gt 0 ] || die_unmeasured "the case file drove no publish at all. Nothing was refused and nothing was allowed; a run that exercised nothing is not a clean run"
[ "$a1_n" -gt 0 ] || die_unmeasured "no fixture page declares a capability that can publish new versions of itself, so the refusal this check exists for was never exercised. Unmeasured, not a pass"
[ "$a2_n" -gt 0 ] || die_unmeasured "no case grants a self-publishing capability in the publish call, so the surface that reading the page cannot reach was never exercised. Unmeasured, not a pass"
[ "$a3_n" -gt 0 ] || die_unmeasured "no case feeds the gate a publish it cannot read, so whether it refuses rather than guesses was never exercised. Unmeasured, not a pass"
[ "$a4_n" -gt 0 ] || die_unmeasured "no case must be ALLOWED, so this run cannot tell a gate that judges from a gate that refuses everything. Unmeasured, not a pass"
[ "$a5_n" -gt 0 ] || die_unmeasured "no case produced a decision document, so whether the verdict is the gate's own was never read. Unmeasured, not a pass"

# --- A6: the hook driven above is the hook the harness will actually run -----
#
# Three parts, evaluated and counted separately. A part with nothing to fire on
# is a FINDING, never a silent hold: if no entry is registered, parts two and
# three have no file to examine, and reporting them as upheld would be this
# check certifying what it never read.
reg_count=0
reg_exec=0
reg_same=0
while IFS= read -r regcmd; do
  [ -n "$regcmd" ] || continue
  reg_count=$((reg_count + 1))
  # The shipped hooks-settings.json spells the root as ${CLAUDE_PROJECT_DIR},
  # so that is expanded BEFORE the path is judged absolute or relative -
  # getting the order wrong turns an absolute path into $ROOT/${...}/... and
  # reports a correctly wired hook as missing.
  regpath="${regcmd//\$\{CLAUDE_PROJECT_DIR\}/$ROOT}"
  regpath="${regpath//\$CLAUDE_PROJECT_DIR/$ROOT}"
  case "$regpath" in /*) ;; *) regpath="$ROOT/$regpath" ;; esac

  if [ -f "$regpath" ] && [ -x "$regpath" ]; then
    reg_exec=$((reg_exec + 1))
    # Compared by CONTENT, not by string equality of the configured value: two
    # spellings of one path are the same hook, and one spelling of two files is
    # not. `cmp -s` exits 1 when they differ, which is a case being detected
    # rather than an error, so it is asked inside an `if` and never left to
    # `set -e` to act on.
    if cmp -s "$regpath" "$HOOK"; then
      reg_same=$((reg_same + 1))
    fi
  fi
done <<EOF
$REG_CMDS
EOF

if [ "$reg_count" -gt 0 ]; then
  a6_ok=$((a6_ok + 1))
else
  if [ -n "$REG_NEAR" ]; then
    note_finding "no PreToolUse entry has matcher exactly 'Artifact'. One mentions it: '$(printf '%s' "$REG_NEAR" | tr '\n' ' ')'. This check reads the exact spelling only, and says so in its limitations - but an unregistered gate and a gate registered under a spelling nobody verified are both gates nothing has been shown to run"
  else
    note_finding "no PreToolUse entry is registered on the Artifact matcher, so nothing invokes this hook. A gate that is present, correct and unregistered is absent - quietly, and with every one of this check's other assertions still green"
  fi
fi
if [ "$reg_exec" -gt 0 ]; then
  a6_ok=$((a6_ok + 1))
else
  note_finding "no command registered on the Artifact matcher resolves to a file that exists and is executable. A hook the shell will not run is a gate that is not there, and it fails silently rather than loudly"
fi
if [ "$reg_same" -gt 0 ]; then
  a6_ok=$((a6_ok + 1))
else
  note_finding "the hook registered on the Artifact matcher is not byte-identical to the one this check drove, so A1-A5 measured a file the harness will not run. Content is not printed here. This is the stale-copy case: the gate gets hardened, the registration keeps pointing at the old file, and every assertion above stays green"
fi
printf '  registrations on the Artifact matcher: %d, resolving to an executable file: %d, identical to the hook driven here: %d\n' \
  "$reg_count" "$reg_exec" "$reg_same"

groups_ok=0
report() {
  printf '  %s: cases %d, upheld %d\n' "$2" "$1" "$3"
}
for g in \
  "$a1_n|A1 a page declaring a self-publishing capability is refused|$a1_ok" \
  "$a2_n|A2 a self-publishing capability granted in the publish call is refused|$a2_ok" \
  "$a3_n|A3 a publish the gate cannot read is refused, not guessed at|$a3_ok" \
  "$a4_n|A4 a publish declaring only output is allowed|$a4_ok" \
  "$a5_n|A5 one decision field, carrying the gate's own verdict|$a5_ok" \
  "$a6_n|A6 the hook driven here is the one settings.json wires to the Artifact tool|$a6_ok"
do
  n="${g%%|*}"; restg="${g#*|}"; label="${restg%%|*}"; okn="${restg##*|}"
  report "$n" "$label" "$okn"
  # An `if`, not `[ ... ] && ...`: an AND-list whose test fails is the last
  # command of this loop body, and that is the `set -e` shape that has killed
  # scripts in this repo mid-branch - right exit code, no reason printed.
  if [ "$n" = "$okn" ]; then groups_ok=$((groups_ok + 1)); fi
done

printf '  cases run: %d\n' "$cases_run"
printf '  assertion groups: 6, upheld: %d\n' "$groups_ok"
cat "$FINDINGS_FILE"

if [ "$findings" -ne 0 ] || [ "$groups_ok" -ne 6 ]; then
  printf '  R31 not satisfied: the lifecycle did not refuse a publish it must refuse, or refused one it must not.\n'
  exit 1
fi
printf '  R31 satisfied: every publish declaring a capability that can publish new versions of the page was refused - asked for in the page and granted in the call alike - every output-only publish went through, and the hook that did the refusing is the one the harness is wired to run.\n'
exit 0
