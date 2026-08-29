#!/usr/bin/env bash
# drift-reverse.sh [repo-root] [--format text|json] [--include-ignored]
#                  [--limit N] [--out FILE]
#
# The reverse drift pass. Stage 5 asks whether every requirement is
# implemented; nothing asks whether every implementation has a requirement.
# This walks the CODE and reports behaviour that no current requirement asks
# for.
#
# The gap is created by the spec's own invariant. Ids are permanent and a
# superseded requirement keeps its original sentence, so when a requirement
# stops being current the code it justified does not announce itself. It keeps
# running, its tests keep passing, and nothing fails.
#
# WHAT THIS IS.
#
#   Evidence for a human or an agent to judge. It gathers signals with
#   `file:line` anchors and labels them candidates. It concludes nothing, it
#   opens nothing, it writes nothing into the spec. Everything below is a
#   question, and `references/drift.md` says who answers it.
#
# WHAT A SHELL SCRIPT CANNOT DO, AND DOES NOT PRETEND TO.
#
#   It cannot read code. It cannot tell a second parallel implementation from
#   a legitimate second caller, an abandoned validation from a defensive one,
#   or a field the spec forgot from a field the spec never wanted. Those need
#   a reader. What it can do is find the places worth reading, and refuse to
#   call the rest clean.
#
# THE SIGNALS.
#
#   A  A requirement id cited in code, comments or tests where the spec marks
#      that id superseded or withdrawn. The strongest signal here: someone
#      wrote the id down, and the agreement behind it has since been replaced.
#   B  A requirement id cited in code that the spec does not contain, and
#      that the spec's own `Next requirement id` says WAS allocated. The spec
#      never deletes, so an allocated id with no row is either a deletion that
#      should not have happened or a citation of another product's spec.
#   D  A cited id at or above the `Next requirement id` watermark — never
#      allocated here. Usually documentation examples and typos, which is why
#      it is kept apart from B rather than inflating it. In this very repo it
#      is most of the volume and none of the interest.
#   C  A test whose name is built entirely from words that appear nowhere in
#      the spec. A test names a flow; a flow with no vocabulary in the spec is
#      worth a look. This one is the noisiest and proves the least.
#
# HOW IT REFUSES TO REPORT A ZERO IT DID NOT MEASURE.
#
#   A tree that cannot be walked, and a tree with no id-reference convention
#   in it, both exit 4 and say "cannot determine". Neither is reported as
#   "0 candidates", which reads as a clean bill of health and is the exact
#   failure this repo blocks on elsewhere. A measured zero — files were read,
#   citations were found, none of them pointed at a dead requirement — exits 0
#   and says so with the counts that back it.
#
# GITIGNORE, AND THE BLIND SPOT IT CREATES.
#
#   By default the file list comes from `git ls-files`, so gitignored trees
#   are NOT scanned. That is usually right (build output, vendored deps) and
#   occasionally very wrong: a generated-then-committed-nowhere directory can
#   hold the only copy of the behaviour in question, and the search silently
#   shrinks to fit. The report always names which list it used. Pass
#   --include-ignored to walk the tree with `find` instead.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  the scan ran and the report is complete. Zero candidates here is a
#      measured zero, and the report shows the counts it was measured from
#   4  CANNOT DETERMINE — no file could be walked, or the tree carries no
#      requirement-id reference convention to read. Not a pass. Not a zero
#   2  bad usage, or no spec / no requirement ids in it — nothing to compare
#      against, so nothing was compared
#   1  crashed before reaching a report. Read as undetermined, never as clean
#
# It never suppresses stderr. An error and a genuine no-match look identical
# once hidden, and this whole file exists to keep those two apart.
set -euo pipefail
export LC_ALL=C

on_exit() {
  status=$?
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi
  case "$status" in
    0 | 2 | 4) exit "$status" ;;
    *)
      printf 'drift-reverse: exited %s before reaching a report. Undetermined, not clean.\n' "$status" >&2
      exit 1
      ;;
  esac
}
trap on_exit EXIT

die_usage() { printf 'drift-reverse: %s\n' "$1" >&2; exit 2; }

ROOT=""
FORMAT=text
INCLUDE_IGNORED=0
LIMIT=50
OUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --format)     [ "$#" -ge 2 ] || die_usage "--format needs text or json"; FORMAT="$2"; shift 2 ;;
    --format=*)   FORMAT="${1#--format=}"; shift ;;
    --limit)      [ "$#" -ge 2 ] || die_usage "--limit needs a number"; LIMIT="$2"; shift 2 ;;
    --limit=*)    LIMIT="${1#--limit=}"; shift ;;
    --out)        [ "$#" -ge 2 ] || die_usage "--out needs a file"; OUT="$2"; shift 2 ;;
    --out=*)      OUT="${1#--out=}"; shift ;;
    --include-ignored) INCLUDE_IGNORED=1; shift ;;
    -h | --help)  sed -n '2,76p' "$0"; exit 0 ;;
    -*)           die_usage "unknown option: $1" ;;
    *)            [ -z "$ROOT" ] || die_usage "only one repo-root"; ROOT="$1"; shift ;;
  esac
done

case "$FORMAT" in text | json) ;; *) die_usage "--format must be text or json, not '$FORMAT'" ;; esac
case "$LIMIT" in '' | *[!0-9]*) die_usage "--limit must be a whole number, not '$LIMIT'" ;; esac

[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

SPEC_REL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPEC_REL"
[ -f "$SPEC" ] || die_usage "no living spec at $SPEC_REL. There is nothing to compare the code against, so nothing was compared."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/drift-reverse.XXXXXX")"
: >"$TMP/unreadable"
: >"$TMP/cand.tsv"
: >"$TMP/notes"

note() { printf '%s\n' "$1" >>"$TMP/notes"; }

# --- the baseline: which ids are current, and which have been replaced ------
# Matches the requirement pattern stage-status.sh and build-view.sh already
# count on. Three counters for one number disagree the moment one is edited,
# so the pattern is copied deliberately and noted in all three places.
awk '
  /^([-*][ \t]+)?\*\*R[0-9]+\*\*/ {
    if (match($0, /R[0-9]+/)) {
      cur = substr($0, RSTART, RLENGTH)
      st[cur] = "active"
      if (!(cur in seen)) { seen[cur] = 1; order[++n] = cur }
    }
    next
  }
  cur != "" {
    t = $0; sub(/^[ \t]+/, "", t)
    if (t ~ /^Superseded by/) { st[cur] = "superseded"; cur = ""; next }
    if (t ~ /^Withdrawn\./)   { st[cur] = "withdrawn";  cur = ""; next }
    cur = ""
  }
  END { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], st[order[i]] }
' "$SPEC" >"$TMP/ids.tsv"

TOTAL_IDS=$(( $(wc -l <"$TMP/ids.tsv") ))
if [ "$TOTAL_IDS" -eq 0 ]; then
  die_usage "$SPEC_REL holds no requirement ids matching '**R<n>**'. Nothing to compare against; this is not a clean tree."
fi
# The allocation watermark. It is what separates "this id was handed out and
# its requirement is gone" from "this is an example in a sentence about ids".
# Without it every `R58` in the documentation reads as a finding, which is how
# a report earns 71 rows and no readers.
NEXT_ID="$(awk '
  /^[Nn]ext requirement id/ { want = 1; next }
  want && /^:/ { if (match($0, /R[0-9]+/)) { print substr($0, RSTART + 1, RLENGTH - 1); exit } want = 0 }
' "$SPEC")"
case "$NEXT_ID" in
  '' | *[!0-9]*)
    NEXT_ID=0
    note "$SPEC_REL does not state a parseable 'Next requirement id', so an id absent from the spec cannot be told from an id never allocated. Every such citation is reported under B, and B is correspondingly noisier."
    ;;
esac

N_ACTIVE=$(( $(awk -F'\t' '$2=="active"' "$TMP/ids.tsv" | wc -l) ))
N_SUPER=$(( $(awk -F'\t' '$2=="superseded"' "$TMP/ids.tsv" | wc -l) ))
N_WITHDRAWN=$(( $(awk -F'\t' '$2=="withdrawn"' "$TMP/ids.tsv" | wc -l) ))

# Spec vocabulary for signal C. Words only, lowercased, four characters up —
# shorter tokens match everything and prove nothing.
tr 'A-Z' 'a-z' <"$SPEC" | tr -cs 'a-z' '\n' | awk 'length($0) >= 4' | sort -u >"$TMP/vocab"

# --- git, and what it can and cannot tell us --------------------------------
GIT_OK=""
if git -C "$ROOT" rev-parse --show-toplevel >"$TMP/toplevel" 2>"$TMP/git.err"; then
  GIT_OK=1
else
  note "not a git repository (or git failed): $(tr '\n' ' ' <"$TMP/git.err")"
fi

SPEC_DATE=""
if [ -n "$GIT_OK" ]; then
  TZ=UTC git -C "$ROOT" log -1 --date=format-local:'%Y-%m-%d' --pretty=format:'%ad' \
    -- "$SPEC_REL" >"$TMP/specdate" 2>"$TMP/specdate.err" || :
  SPEC_DATE="$(cat "$TMP/specdate")"
  if [ -s "$TMP/specdate.err" ]; then
    note "the spec's last-changed date could not be read: $(tr '\n' ' ' <"$TMP/specdate.err")"
  fi
  [ -n "$SPEC_DATE" ] || note "the spec's last-changed date is unknown (no commit touches $SPEC_REL)"
fi

# --- the file list ----------------------------------------------------------
if [ "$INCLUDE_IGNORED" -eq 1 ]; then
  SCAN_SOURCE="find, gitignored trees INCLUDED (--include-ignored)"
  ( cd "$ROOT" && find . -name .git -prune -o -type f -print0 ) >"$TMP/files.z"
elif [ -n "$GIT_OK" ]; then
  SCAN_SOURCE="git ls-files — gitignored and untracked files were NOT scanned"
  git -C "$ROOT" ls-files -z >"$TMP/files.z" 2>"$TMP/ls-files.err" || :
  if [ -s "$TMP/ls-files.err" ]; then
    note "git ls-files wrote to stderr, so the file list may be short: $(tr '\n' ' ' <"$TMP/ls-files.err")"
  fi
  note "gitignored trees were not walked. A sibling tool's blind spot shrinking the search is a real failure mode; re-run with --include-ignored to rule it out."
else
  SCAN_SOURCE="find, no git repository — any .gitignore was NOT honoured"
  ( cd "$ROOT" && find . -name .git -prune -o -type f -print0 ) >"$TMP/files.z"
fi

# --- the scanner ------------------------------------------------------------
cat >"$TMP/scan.awk" <<'AWK_EOF'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

function excerpt(s,   t) {
  t = trim(s); gsub(/\t/, " ", t)
  if (length(t) > 160) t = substr(t, 1, 157) "..."
  return t
}

# The first quoted run at or after startpos. Test names live in quotes far
# more often than they live in identifiers.
function grabquoted(s, startpos,   q, i, ch, out) {
  q = ""
  for (i = startpos; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch == "\"" || ch == "'") { q = ch; break }
  }
  if (q == "") return ""
  out = ""
  for (i = i + 1; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch == q) return out
    out = out ch
  }
  return out
}

# snake_case and CamelCase both become a sentence, so one vocabulary check
# covers Python, Go, Rust and Java without knowing which it is looking at.
function humanize(s,   i, ch, prev, out) {
  gsub(/[_-]/, " ", s)
  out = ""; prev = " "
  for (i = 1; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch ~ /[A-Z]/ && prev !~ /[A-Z ]/) out = out " "
    out = out ch
    prev = ch
  }
  return tolower(out)
}

BEGIN {
  FS = "\n"
  while ((getline ln < IDS) > 0) {
    split(ln, f, "\t")
    if (f[1] != "") status[f[1]] = f[2]
  }
  close(IDS)
  while ((getline ln < VOCAB) > 0) if (ln != "") vocab[ln] = 1
  close(VOCAB)
  split("that this with when then from into have will must shall should does " \
        "test tests testing case cases spec specs given each also they them " \
        "returns return value values true false null none only more than " \
        "user users file files line lines name names", sw, " ")
  for (i in sw) stop[sw[i]] = 1
}

{
  line = $0

  # --- signals A and B: requirement ids cited in the tree -------------------
  s = line
  while (match(s, /R[0-9]+/)) {
    st = RSTART; len = RLENGTH
    before = (st == 1) ? "" : substr(s, st - 1, 1)
    after  = substr(s, st + len, 1)
    if (before !~ /[A-Za-z0-9_]/ && after !~ /[A-Za-z0-9_]/) {
      id = substr(s, st, len)
      if (!(id in status)) {
        num = substr(id, 2) + 0
        if (NEXTID > 0 && num >= NEXTID) {
          printf "D\t%s\t%d\treferences-never-allocated-id\t%s\t%s\n", REL, FNR, id, excerpt(line)
          printf "count\tunallocated\n" >> COUNTS
        } else {
          printf "B\t%s\t%d\treferences-allocated-id-absent-from-spec\t%s\t%s\n", REL, FNR, id, excerpt(line)
          printf "count\tunknown\n" >> COUNTS
        }
      } else if (status[id] == "active") {
        printf "count\tlive\n" >> COUNTS
      } else {
        printf "A\t%s\t%d\treferences-%s-requirement\t%s\t%s\n", REL, FNR, status[id], id, excerpt(line)
        printf "count\tdead\n" >> COUNTS
      }
    }
    s = substr(s, st + len)
  }

  # --- signal C: a test named in vocabulary the spec does not use -----------
  name = ""
  if (match(line, /(^|[^A-Za-z0-9_])(it|test|describe|context)[ \t]*\(/)) {
    name = grabquoted(line, RSTART)
  # The paren-less RSpec form is anchored to the start of the line. Unanchored
  # it matched prose - `do not caption it "screenshot"` in a markdown template
  # became a candidate on the real repo. A declaration sits at the start of a
  # line; a sentence does not.
  } else if (match(line, /^[ \t]*(it|describe|context)[ \t]+["']/)) {
    name = grabquoted(line, RSTART)
  } else if (match(line, /@DisplayName[ \t]*\(/) || match(line, /@test[ \t]*["']/)) {
    name = grabquoted(line, RSTART)
  } else if (match(line, /(^|[^A-Za-z0-9_])def[ \t]+test[A-Za-z0-9_]*/)) {
    name = humanize(substr(line, RSTART, RLENGTH))
  } else if (match(line, /(^|[^A-Za-z0-9_])func[ \t]+Test[A-Za-z0-9_]*/)) {
    name = humanize(substr(line, RSTART, RLENGTH))
  } else if (match(line, /(^|[^A-Za-z0-9_])fn[ \t]+[A-Za-z0-9_]*test[A-Za-z0-9_]*/)) {
    name = humanize(substr(line, RSTART, RLENGTH))
  }

  if (name != "") {
    flat = tolower(name)
    gsub(/[^a-z]/, " ", flat)
    nw = split(flat, w, " ")
    considered = 0; hit = 0
    for (i = 1; i <= nw; i++) {
      if (length(w[i]) < 4) continue
      if (w[i] in stop) continue
      if (w[i] == "func" || w[i] == "describe" || w[i] == "context") continue
      considered++
      if (w[i] in vocab) hit++
    }
    if (considered > 0 && hit == 0) {
      printf "C\t%s\t%d\ttest-name-outside-spec-vocabulary\t%s\t%s\n", REL, FNR, trim(name), excerpt(line)
    }
  }
}
AWK_EOF

FILES_SCANNED=0
FILES_SKIPPED=0
: >"$TMP/counts"

while IFS= read -r -d '' rel; do
  rel="${rel#./}"
  case "$rel" in
    .claude/productizer/*) continue ;;   # the baseline, not behaviour
    .git/*) continue ;;
  esac
  abs="$ROOT/$rel"
  [ -f "$abs" ] || continue

  # -I makes a binary file a no-match rather than a garbled one. Status 1 is
  # "binary or empty"; anything above 1 is a file we could not read, and that
  # is recorded rather than counted as scanned.
  gst=0
  grep -Iq . -- "$abs" || gst=$?
  case "$gst" in
    0) ;;
    1) FILES_SKIPPED=$((FILES_SKIPPED + 1)); continue ;;
    *) printf '%s\n' "$rel" >>"$TMP/unreadable"; continue ;;
  esac

  ast=0
  awk -v REL="$rel" -v IDS="$TMP/ids.tsv" -v VOCAB="$TMP/vocab" \
      -v COUNTS="$TMP/counts" -v NEXTID="$NEXT_ID" -f "$TMP/scan.awk" -- "$abs" >>"$TMP/cand.tsv" || ast=$?
  if [ "$ast" -ne 0 ]; then
    printf '%s\n' "$rel" >>"$TMP/unreadable"
    continue
  fi
  FILES_SCANNED=$((FILES_SCANNED + 1))
done <"$TMP/files.z"

N_UNREADABLE=$(( $(wc -l <"$TMP/unreadable") ))
REF_LIVE=$(( $(awk -F'\t' '$2=="live"' "$TMP/counts" | wc -l) ))
REF_DEAD=$(( $(awk -F'\t' '$2=="dead"' "$TMP/counts" | wc -l) ))
REF_UNKNOWN=$(( $(awk -F'\t' '$2=="unknown"' "$TMP/counts" | wc -l) ))
REF_UNALLOC=$(( $(awk -F'\t' '$2=="unallocated"' "$TMP/counts" | wc -l) ))
REF_TOTAL=$((REF_LIVE + REF_DEAD + REF_UNKNOWN + REF_UNALLOC))

sort -t$'\t' -k2,2 -k3,3n -k1,1 "$TMP/cand.tsv" >"$TMP/sorted.tsv"
for sig in A B D C; do
  awk -F'\t' -v s="$sig" '$1==s' "$TMP/sorted.tsv" >"$TMP/sig.$sig"
done
N_A=$(( $(wc -l <"$TMP/sig.A") ))
N_B=$(( $(wc -l <"$TMP/sig.B") ))
N_C=$(( $(wc -l <"$TMP/sig.C") ))
N_D=$(( $(wc -l <"$TMP/sig.D") ))

# --- status: the one decision this script is entitled to make ---------------
# It decides only whether it could look, never what it saw.
STATUS=""
CONVENTION="confirmed"
if [ "$FILES_SCANNED" -eq 0 ]; then
  STATUS="cannot-determine"
  note "no file in this tree could be read, so nothing was searched. This is not zero candidates."
elif [ "$REF_TOTAL" -eq 0 ]; then
  STATUS="cannot-determine"
  CONVENTION="absent"
  note "no requirement-id reference of any kind was found in $FILES_SCANNED scanned file(s), so this tree has no convention tying code to requirements. Signals A and B cannot be evaluated at all — that is an undetermined result, not a clean one. Before believing it, confirm the search reached the files: grep for a string you know is in them."
elif [ "$REF_LIVE" -eq 0 ]; then
  CONVENTION="unconfirmed"
  note "ids matching R<n> were found, but none of them names a currently active requirement. The convention is unconfirmed, so the signal-B rows below may be arithmetic, array indices or part numbers rather than citations."
fi
if [ -z "$STATUS" ]; then
  if [ $((N_A + N_B + N_C + N_D)) -gt 0 ]; then STATUS="candidates"; else STATUS="no-candidates"; fi
fi
[ "$N_UNREADABLE" -eq 0 ] || note "$N_UNREADABLE file(s) could not be read and were not searched; they are listed above and may hold anything."

# --- rendering --------------------------------------------------------------
json_escape() {
  local s=$1 out='' c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      '"') out+='\"' ;;
      '\') out+='\\' ;;
      $'\n') out+='\n' ;;
      $'\t') out+='\t' ;;
      *)
        case $c in [[:cntrl:]]) printf -v c '\\u%04x' "'$c" ;; esac
        out+=$c
        ;;
    esac
  done
  printf '%s' "$out"
}

render_text() {
  local bold="" dim="" red="" amber="" green="" reset=""
  if [ -t 1 ] && [ -z "$OUT" ]; then
    bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'
    amber=$'\033[33m'; green=$'\033[32m'; reset=$'\033[0m'
  fi
  local rule="-------------------------------------------------------------------"

  printf '%sReverse drift — code with no requirement behind it%s  %s\n' "$bold" "$reset" "$ROOT"
  printf '%s%s%s\n' "$dim" "$rule" "$reset"
  printf '  Baseline    %s%s\n' "$SPEC_REL" \
    "$([ -n "$SPEC_DATE" ] && printf ' (last changed %s UTC)' "$SPEC_DATE" || :)"
  printf '              %s active, %s superseded, %s withdrawn requirement id(s)\n' \
    "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf '  Scanned     %s file(s) via %s\n' "$FILES_SCANNED" "$SCAN_SOURCE"
  printf '              %s binary or empty file(s) skipped; %s unreadable\n' "$FILES_SKIPPED" "$N_UNREADABLE"
  if [ "$N_UNREADABLE" -gt 0 ]; then
    while IFS= read -r u; do printf '                - %s\n' "$u"; done <"$TMP/unreadable"
  fi
  printf '  Convention  %s id reference(s): %s live, %s superseded/withdrawn, %s allocated but\n' \
    "$REF_TOTAL" "$REF_LIVE" "$REF_DEAD" "$REF_UNKNOWN"
  printf '              missing, %s never allocated (next id: %s) [%s]\n' \
    "$REF_UNALLOC" "$([ "$NEXT_ID" -gt 0 ] && printf 'R%s' "$NEXT_ID" || printf 'unreadable')" "$CONVENTION"
  printf '%s%s%s\n\n' "$dim" "$rule" "$reset"

  if [ "$STATUS" = "cannot-determine" ]; then
    printf '  %sCANNOT DETERMINE%s — this run did not measure zero candidates. It failed\n' "$red" "$reset"
    printf '  to reach a position from which zero would mean anything. See the notes.\n\n'
  fi

  local sig title n file
  for sig in A B D C; do
    case "$sig" in
      A) title="A. Code citing a superseded or withdrawn requirement"; n=$N_A ;;
      B) title="B. Code citing an allocated id the spec no longer holds"; n=$N_B ;;
      D) title="D. Code citing an id never allocated here (examples, typos)"; n=$N_D ;;
      C) title="C. Test names built from vocabulary the spec never uses"; n=$N_C ;;
    esac
    file="$TMP/sig.$sig"
    if [ "$n" -gt 0 ]; then
      printf '  %s%s%s  %s%s candidate(s)%s\n' "$bold" "$title" "$reset" "$amber" "$n" "$reset"
    else
      printf '  %s%s  %s%s\n' "$dim" "$title" "$([ "$STATUS" = "cannot-determine" ] && printf 'not evaluated' || printf 'none found')" "$reset"
    fi
    local shown=0
    while IFS=$'\t' read -r _s f l _k tok ex; do
      [ -n "$f" ] || continue
      shown=$((shown + 1))
      if [ "$shown" -gt "$LIMIT" ]; then break; fi
      printf '      %s:%s  %s\n' "$f" "$l" "$tok"
      printf '        %s%s%s\n' "$dim" "$ex" "$reset"
    done <"$file"
    if [ "$n" -gt "$LIMIT" ]; then
      printf '      %s... and %s more, not shown (--limit %s)%s\n' "$dim" "$((n - LIMIT))" "$LIMIT" "$reset"
    fi
    printf '\n'
  done

  printf '  %sWhat was NOT determined%s\n' "$bold" "$reset"
  if [ -s "$TMP/notes" ]; then
    while IFS= read -r nline; do printf '      - %s\n' "$nline"; done <"$TMP/notes"
  else
    printf '      - nothing beyond the standing limits below.\n'
  fi
  printf '\n'

  printf '  %sWhat these signals do not prove%s\n' "$bold" "$reset"
  cat <<'CAVEAT'
      - Every row is a CANDIDATE, never a finding. A citation of a superseded
        requirement can be a correct historical note in a changelog; a test
        outside the spec's vocabulary can be an infrastructure test.
      - Signal D is mostly noise by construction: prose that explains the id
        convention cites ids that were never allocated, and this pass cannot
        tell that sentence from a citation. Read B first; read D only when B
        and A are empty and you still suspect something.
      - Signal C is the weakest. It matches vocabulary, not meaning. A test
        that says "welcome postcard" for a flow the spec calls "greeting mail"
        is flagged; one that reuses the spec's nouns for behaviour the spec
        dropped is not.
      - Nothing here reads code. Behaviour that cites no id and is named in
        the spec's own words is invisible to this pass: an unspecified field,
        a validation nobody asked for, a second parallel implementation of
        something already specified, a flag whose off-branch is dead. Those
        need a reader, and Stage 5's forward pass will not find them either.
      - Deleted requirements would be invisible too, which is one more reason
        the spec never deletes.
CAVEAT
  printf '\n'
  printf '  %sJudged by a person or an agent, per references/drift.md. Nothing here\n' "$dim"
  printf '  changes the spec, and no row is an agreement.%s\n' "$reset"
  printf '  %sstatus: %s%s%s\n' "$dim" "$([ "$STATUS" = "no-candidates" ] && printf '%s' "$green" || :)" "$STATUS" "$reset"
}

render_json() {
  local first sig f l k tok ex u nline
  printf '{\n'
  printf '  "tool": "drift-reverse",\n'
  printf '  "status": "%s",\n' "$STATUS"
  printf '  "root": "%s",\n' "$(json_escape "$ROOT")"
  printf '  "spec": {"path": "%s", "last_changed_utc": %s, "active": %s, "superseded": %s, "withdrawn": %s},\n' \
    "$(json_escape "$SPEC_REL")" \
    "$([ -n "$SPEC_DATE" ] && printf '"%s"' "$SPEC_DATE" || printf 'null')" \
    "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf '  "scan": {"source": "%s", "include_ignored": %s, "files_scanned": %s, "files_skipped_binary_or_empty": %s, "files_unreadable": [' \
    "$(json_escape "$SCAN_SOURCE")" \
    "$([ "$INCLUDE_IGNORED" -eq 1 ] && printf 'true' || printf 'false')" \
    "$FILES_SCANNED" "$FILES_SKIPPED"
  first=1
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    printf '"%s"' "$(json_escape "$u")"
  done <"$TMP/unreadable"
  printf ']},\n'
  printf '  "convention": {"state": "%s", "next_requirement_id": %s, "id_references": %s, "live": %s, "superseded_or_withdrawn": %s, "allocated_but_absent": %s, "never_allocated": %s},\n' \
    "$CONVENTION" "$([ "$NEXT_ID" -gt 0 ] && printf '"R%s"' "$NEXT_ID" || printf 'null')" \
    "$REF_TOTAL" "$REF_LIVE" "$REF_DEAD" "$REF_UNKNOWN" "$REF_UNALLOC"
  printf '  "counts": {"A": %s, "B": %s, "C": %s, "D": %s},\n' "$N_A" "$N_B" "$N_C" "$N_D"
  printf '  "limit": %s,\n' "$LIMIT"
  printf '  "candidates": [\n'
  first=1
  for sig in A B D C; do
    local shown=0
    while IFS=$'\t' read -r _s f l k tok ex; do
      [ -n "$f" ] || continue
      shown=$((shown + 1))
      [ "$shown" -le "$LIMIT" ] || break
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      printf '    {"signal": "%s", "kind": "%s", "file": "%s", "line": %s, "token": "%s", "excerpt": "%s", "verdict": "candidate-requires-judgment"}' \
        "$sig" "$(json_escape "$k")" "$(json_escape "$f")" "$l" \
        "$(json_escape "$tok")" "$(json_escape "$ex")"
    done <"$TMP/sig.$sig"
  done
  [ "$first" -eq 1 ] || printf '\n'
  printf '  ],\n'
  printf '  "not_determined": ['
  first=1
  while IFS= read -r nline; do
    [ -n "$nline" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    printf '"%s"' "$(json_escape "$nline")"
  done <"$TMP/notes"
  printf ']\n'
  printf '}\n'
}

if [ -n "$OUT" ]; then
  if [ "$FORMAT" = json ]; then render_json >"$OUT"; else render_text >"$OUT"; fi
  printf 'drift-reverse: wrote %s (status: %s)\n' "$OUT" "$STATUS"
else
  if [ "$FORMAT" = json ]; then render_json; else render_text; fi
fi

[ "$STATUS" != "cannot-determine" ] || exit 4
exit 0
