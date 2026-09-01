#!/usr/bin/env bash
# .claude/hooks/artifact-gate.sh — PreToolUse hook on the Artifact tool.
#
# R31: IF A PUBLISHED VIEW DECLARES A CAPABILITY THAT CAN PUBLISH NEW VERSIONS
# OF ITSELF, THEN THE LIFECYCLE SHALL REFUSE TO PUBLISH IT.
#
# The refusal had nowhere to live. `publish-gate.sh` is registered on the Bash
# matcher, and an artifact is not published through Bash - it is published
# through the Artifact tool, which that gate never sees. So the `view-read-only`
# check asserted the page NOT ASKING for such a capability, and nothing at all
# observed the publish step declining, because no such refusal existed. Half of
# R31 was unimplemented, not merely unverified. This is that half.
#
# Register it beside publish-gate.sh, matched to Artifact rather than Bash:
#
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Artifact",
#       "hooks": [{ "type": "command",
#                   "command": ".claude/hooks/artifact-gate.sh" }]
#     }]
#   }
#
# THE DECISION IS `deny`, AND DELIBERATELY NOT `ask`.
#
# publish-gate.sh asks a person, because whether a release post is ready is a
# judgement call and the gate cannot make it. This one is not a judgement call.
# A page that can rewrite itself becomes a second source of truth that can
# disagree with the repository, and the provenance line under every panel - the
# sentence saying every figure was read from the repository at generation time -
# stops being true the moment it can. R4 and the views reference forbid it
# outright. There is nothing for a person to weigh, so there is no approval
# path here: offering one would only invite the answer that R4 forbids.
#
# `deny` is also the decision the documentation is explicit about: "A hook that
# returns permissionDecision: \"deny\" blocks the tool even in bypassPermissions
# mode or with --dangerously-skip-permissions." That sentence names `deny`. It
# says nothing of the sort about `ask`, which is why publish-gate.sh refuses
# outright in any mode it is not sure prompts a human.
#
# BOTH SURFACES ARE REFUSED, BECAUSE THEY ARE DIFFERENT HOLES.
#
#   THE PAGE ASKS.   `claude.use("artifact")` inside the published HTML. This
#                    is the surface `view-read-only` reads, and it reads it in
#                    the generator's output rather than in the publish call.
#
#   THE CALL GRANTS.  `capabilities: {artifact: {}}` passed to the Artifact
#                    tool. `view-read-only` states in its own limitations block
#                    that it cannot see this one: the grant is made when the
#                    page is published, not inside the page, so a capability
#                    granted at publish time leaves no trace in the file. A
#                    gate on the publish call is the only place it is visible.
#
# Both are classified by the same taxonomy, and it is the taxonomy
# `check-view-readonly.sh` already uses:
#
#   an output capability          `downloads` - the page hands the viewer a
#                                 file built from its own bytes and reads
#                                 nothing back. ALLOWED. A gate that blocks
#                                 every publish is as broken as one that blocks
#                                 none, and it gets switched off just as fast.
#   a self-publishing capability  `artifact`, `self`. REFUSED.
#   anything else                 REFUSED. An unrecognised name has not been
#                                 shown to be output-only, and this gate does
#                                 not certify what it cannot read.
#
# A `use()` whose argument is not a string literal is refused for the same
# reason: a name computed at run time cannot be read out of the page, so it is
# not readable as absent either.
#
# EVERYTHING IT CANNOT READ IS REFUSED, NOT GUESSED. No payload, a payload that
# is not the shape this gate expects, an action it does not recognise, a
# missing or unreadable file, a `capabilities` value that is not an object, a
# capability name carrying characters that cannot be rendered - each of those
# is a publish this gate cannot judge, and an unjudged publish is refused. A
# page whose capabilities are UNKNOWN is never treated as a page with none.
#
# THE DECISION IS BUILT WITH `jq --arg`, NEVER BY CONCATENATION. Text out of
# the page reaches the reason string, and a page containing the literal bytes
# `"permissionDecision":"allow"` must not be able to forge a verdict by being
# quoted back. --arg makes it a JSON string value and nothing else.
#
# KNOWN LIMITATION, WRITTEN DOWN RATHER THAN HIDDEN. Omitting `capabilities` on
# a redeploy carries the artifact's STORED declaration forward, and that stored
# declaration is held by the publishing service, not in this repository. This
# gate cannot read it. What it judges is the page's own source plus whatever
# this call grants; a self-publishing capability granted by an earlier call and
# silently inherited by a later one is out of its reach. Refusing every publish
# that omits the field would close it, and would also block every ordinary
# redeploy, so it is written down instead of pretended away.
#
# THE SECOND KNOWN LIMITATION. `file_path` is read from the filesystem at the
# moment the hook runs. A file rewritten between this read and the tool's own
# read would be judged in its earlier state. Nothing in this lifecycle writes
# to a page between the two, and the window is a single tool dispatch, but it
# is a window and it is not closed here.
#
# EXIT CODES ARE THE CONTRACT.
#   0  a decision was emitted on stdout - `allow` or `deny`, both are exit 0.
#   2  this gate could not run. The tool call is blocked and stderr is the
#      reason. Every unexpected status becomes this: the EXIT trap rewrites
#      anything that is not a successfully emitted decision into 2, because a
#      gate that crashes with 1 or 127 is a gate that published.
#
# NOTHING ABSOLUTE IS EVER PRINTED. Only the file's basename appears in a
# reason, never the path it came from: this text is quoted into transcripts and
# into committed records, and an absolute path there is somebody's home
# directory published to everyone who clones the repo.
set -euo pipefail

_rc=2
trap '[ "$_rc" = 0 ] && exit 0; exit 2' EXIT

command -v jq >/dev/null 2>&1 || {
  echo "artifact-gate: jq is not installed, so this gate cannot read the publish it is meant to judge. Blocking." >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "artifact-gate: python3 is not installed, so the page's capability declarations cannot be read. A page whose capabilities are unknown is not a page with none. Blocking." >&2
  exit 2
}

payload="$(cat)" || { echo "artifact-gate: could not read the hook payload. Blocking." >&2; exit 2; }

# --- the taxonomy ----------------------------------------------------------
#
# Space-delimited so a name is matched whole: ` self ` never matches `myself`.
GATE_OUTPUT_ONLY=' downloads '
GATE_SELF_PUBLISHING=' artifact self '

# Actions of the Artifact tool that do not put a new version of a page in front
# of anyone. Reading, listing, watching, commenting and asset handling do not
# publish, so they are not R31's business and are not this gate's. An action
# NOT on this list and not `publish` is refused rather than assumed harmless:
# a new action name this gate has never heard of may well publish.
GATE_NON_PUBLISHING=' list read comments reply resolve watch unwatch status resume_replies upload_asset list_assets read_asset delete_asset '

# --- emitting the decision -------------------------------------------------

emit() {
  jq -n --arg decision "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse",
                           permissionDecision: $decision,
                           permissionDecisionReason: $reason}}'
  _rc=0
  exit 0
}

refuse() {
  emit deny "REFUSED by artifact-gate: this publish is blocked, and it is not a decision anyone is being asked to make.

$1

A published view is output. A page that can save new versions of itself is a
second source of truth that can disagree with the repository it was generated
from, and the provenance line under every panel - the sentence saying every
figure was read from the repository at generation time - stops being true the
moment it can. R4 and R31 forbid it, and references/views.md says the same in
its own words: never grant \`artifact\`, and never grant \`self\`.

What to do instead: publish the page with no capability at all, or with
\`capabilities: {downloads: true}\`, which is still output - the page hands the
viewer a file built from its own bytes and reads nothing back. If the page
genuinely needs to record something, that is a change to where this lifecycle
keeps its state, which is a spec delta and not a publish flag."
}

allow() { emit allow "$1"; }

# --- reading the payload ---------------------------------------------------
#
# Every branch here is a shape this gate does not understand, and it refuses
# rather than guesses. The .tool_name check matters for the same reason it does
# in publish-gate.sh: registered on the wrong matcher this hook would be
# reading someone else's payload shape and approving publishes by accident.
action="$(printf '%s' "$payload" | jq -er '
  if type != "object" then
    error("payload is not a JSON object")
  elif ((.tool_name // "Artifact") != "Artifact") then
    error("fired on tool \(.tool_name) — register this hook on the Artifact matcher only")
  elif ((.tool_input | type) != "object") then
    error("payload has no .tool_input object")
  elif (((.tool_input.action // "publish") | type) != "string") then
    error(".tool_input.action is not a string")
  else (.tool_input.action // "publish") end' 2>&1)" || {
  echo "artifact-gate: the hook payload was not the shape this gate expects (${action:-jq failed and said nothing}). Blocking, because a gate that cannot see what it is judging has not judged it." >&2
  exit 2; }

case "$GATE_NON_PUBLISHING" in
  *" $action "*)
    allow "artifact-gate: \`$action\` does not publish a new version of a page, so R31 does not reach it. Nothing was judged about any page's capabilities here."
    ;;
esac

if [ "$action" != publish ]; then
  refuse "The Artifact tool was called with action \`$action\`, which this gate does not
recognise. It is not \`publish\`, and it is not on the list of actions known not
to publish. Whether it puts a new version of a page in front of anyone is
therefore UNKNOWN, and unknown is refused rather than assumed harmless. If this
action is safe, add it to GATE_NON_PUBLISHING in this hook, in a commit that
says why."
fi

# --- the file being published ----------------------------------------------

file="$(printf '%s' "$payload" | jq -er '
  if ((.tool_input.file_path | type) != "string") then
    error("file_path is absent or is not a string")
  elif (.tool_input.file_path | test("^[[:space:]]*$")) then
    error("file_path is empty")
  else .tool_input.file_path end' 2>&1)" || {
  refuse "The page being published could not be identified: ${file:-jq failed and said nothing}.

A publish whose file cannot be named cannot have its capabilities read, and a
page whose capabilities are unknown is not a page with none."
}

base="${file##*/}"

[ -f "$file" ] && [ -r "$file" ] || {
  refuse "The page named for publication (\`$base\`) is not a readable file at the path
given in the call.

This gate reads the page's own source to see which capabilities it asks for. It
could not read it, so what this page declares is UNKNOWN. Unknown is not zero."
}

# --- capabilities granted by the CALL --------------------------------------
#
# This is the surface `check-view-readonly.sh` states in its own limitations
# block that it cannot see: the grant is made when the page is published, not
# inside the page, so it leaves no trace in the file that check reads.

captype="$(printf '%s' "$payload" | jq -r '.tool_input.capabilities | type' 2>&1)" || {
  refuse "The \`capabilities\` argument of this publish could not be read: $captype"
}
case "$captype" in
  null|object) ;;
  *) refuse "The \`capabilities\` argument of this publish is of type $captype, not an object. The
contract is {name: config}, so a value of another type is a call this gate
cannot classify, and it is refused rather than read past." ;;
esac

# A capability name carrying a control character or a byte outside printable
# ASCII cannot be rendered into a reason, and a name that cannot be rendered
# cannot be reported to whoever has to act on the refusal. It is also how a
# newline would be smuggled into the line-oriented read below. Refused, not
# sanitised: a sanitised name is a different name, and approving one while
# reporting the other is worse than refusing both.
badcap=''
badcap="$(printf '%s' "$payload" | jq -r '
  (.tool_input.capabilities // {}) | keys_unsorted[] | select(test("[^ -~]")) | @json' 2>&1)" || {
  refuse "The capability names in this publish call could not be read: $badcap"
}
if [ -n "$badcap" ]; then
  refuse "This publish grants a capability whose name carries characters outside printable
ASCII, so it cannot be reported back accurately. A gate that cannot name what it
is judging has not judged it."
fi

granted=''
granted="$(printf '%s' "$payload" | jq -r '(.tool_input.capabilities // {}) | keys_unsorted[]' 2>&1)" || {
  refuse "The capability names in this publish call could not be read: $granted"
}

notes=''
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case "$GATE_SELF_PUBLISHING" in
    *" $name "*)
      refuse "This publish GRANTS the capability \`$name\` to \`$base\` in the publish call
itself, and \`$name\` publishes new versions of the page.

Note where this was found. The page's own source did not have to ask for it:
the grant is made by the call, so it leaves no trace in the file, and the
\`view-read-only\` check says so in its own limitations block. Reading the page
alone would have missed this entirely."
      ;;
  esac
  case "$GATE_OUTPUT_ONLY" in
    *" $name "*)
      notes="$notes
  the call grants \`$name\` - output: the page hands the viewer a file and reads nothing back"
      continue ;;
  esac
  refuse "This publish grants the capability \`$name\` to \`$base\`, and this gate cannot
classify it.

An unrecognised capability has not been shown to be output-only; a name nobody
has classified is a name nobody has shown to be safe. Classify it in this hook
and in check-view-readonly.sh - both, or the two disagree about what a view may
declare - or stop granting it."
done <<EOF
$granted
EOF

# --- capabilities the PAGE asks for ----------------------------------------
#
# A published page reaches a capability through `claude.use("<name>")`, so that
# is what is read, with the same pattern check-view-readonly.sh reads. Names
# are rendered to printable ASCII and truncated before they leave python, so a
# name cannot smuggle a newline into the line-oriented read below - a rendered
# name that no longer matches a known one falls through to the refusal, which
# is the safe direction.
page_rc=0
page_out="$(python3 - "$file" <<'PY'
import re
import sys

try:
    with open(sys.argv[1], errors="replace") as fh:
        src = fh.read()
except OSError as exc:
    sys.stdout.write("UNREADABLE %s\n" % (exc.strerror or "no reason given"))
    sys.exit(3)

if not src.strip():
    sys.stdout.write("EMPTY\n")
    sys.exit(3)


def render(s):
    s = "".join(c if 32 <= ord(c) < 127 else "?" for c in s)
    return s[:80] + "..." if len(s) > 80 else s


calls = re.findall(r"claude\s*\.\s*use\s*\(([^)]*)\)", src)
out = sys.stdout
out.write("CALLS %d\n" % len(calls))
for raw in calls:
    arg = raw.strip()
    m = re.match(r"""^(['"])(.*)\1$""", arg, re.S)
    if m:
        out.write("NAME %s\n" % render(m.group(2)))
    else:
        out.write("NONLITERAL %s\n" % render(arg))
PY
)" || page_rc=$?
# `|| page_rc=$?` is load-bearing and is not tolerance of an unknown failure:
# exit 3 is this reader's own way of saying the page could not be read, and
# under `set -e` with `pipefail` that status would kill the script here - right
# exit code, and no reason printed at all.

if [ "$page_rc" -eq 3 ]; then
  refuse "The page \`$base\` could not be read as text, so the capabilities it declares are
UNKNOWN. Unknown is not zero: a gate that treats an unreadable page as a page
declaring nothing approves exactly the page it cannot see."
fi
if [ "$page_rc" -ne 0 ]; then
  echo "artifact-gate: reading the page's capability declarations exited $page_rc. Blocking, because what the page declares is unknown." >&2
  exit 2
fi

calls=0
while IFS= read -r line; do
  case "$line" in
    "CALLS "*) calls="${line#CALLS }" ;;
    "NONLITERAL "*)
      refuse "The page \`$base\` reaches a capability by a name that is not a string literal:

  claude.use(${line#NONLITERAL })

The name is computed when the page runs, so it cannot be read out of the file -
which means it cannot be read as absent either. A declaration this gate cannot
resolve is refused, not assumed harmless."
      ;;
    "NAME "*)
      name="${line#NAME }"
      case "$GATE_SELF_PUBLISHING" in
        *" $name "*)
          refuse "The page \`$base\` declares \`$name\`, which publishes new versions of the page
itself. It asks for this in its own source, through claude.use(\"$name\")."
          ;;
      esac
      case "$GATE_OUTPUT_ONLY" in
        *" $name "*)
          notes="$notes
  the page declares \`$name\` - output: it hands the viewer a file and reads nothing back"
          continue ;;
      esac
      refuse "The page \`$base\` declares \`$name\`, which this gate cannot classify.

An unrecognised capability has not been shown to be output-only. Classify it in
this hook and in check-view-readonly.sh - both, or the two disagree about what a
view may declare - or stop declaring it."
      ;;
  esac
done <<EOF
$page_out
EOF

allow "artifact-gate: \`$base\` declares nothing that can publish a new version of itself, and
this call grants nothing that can either. Capability declarations read in the
page: $calls.$notes"
