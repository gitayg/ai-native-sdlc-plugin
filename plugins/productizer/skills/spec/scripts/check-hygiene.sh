#!/usr/bin/env bash
# check-hygiene.sh [--version] [--help] [--patterns FILE] [--print-patterns] <file>...
#
# Refuses content that must not reach a public repo: personal filesystem
# paths, machine hostnames, private key material, and anything shaped like a
# credential.
#
# TWO PATTERN SOURCES, UNIONED.
#
#   1. The BUILT-IN generic list below. It names no person, no company and no
#      project, on purpose. This file ships to everyone who installs the
#      plugin, and a deny list that spells out the private names tells every
#      stranger who clones it exactly which names are worth looking for.
#
#   2. An optional LOCAL list, one extended regular expression per line, `#`
#      comments and blank lines ignored. Resolution order:
#
#          --patterns FILE
#          $PRODUCTIZER_HYGIENE_PATTERNS
#          .claude/productizer/hygiene-local.txt under the git work tree
#
#      This is where a maintainer keeps the names they cannot publish - an
#      <employer>, a private project - in a file that is not committed. A
#      local list that was NAMED and cannot be read is exit 2, never a quiet
#      fall back to generic-only: someone who configured a private list and
#      then saw a clean run would believe those names had been checked.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file examined, nothing found
#   1  findings, reported by location
#   2  could not run - bad usage, an unreadable file, an unreadable local list
#
# WHAT IT PRINTS.
#
#   One BARE PATH per line for every file EXAMINED. The runner parses those as
#   coverage and treats a check that exits 0 having examined less than it
#   declared as hollow, which is a failure and not a pass.
#
#   Findings are INDENTED, and name the file, the line and the CLASS of the
#   finding. THE MATCHED TEXT IS NEVER PRINTED. Printing the offending line
#   once copied a leaked path into the committed checks-result.json, so
#   finding a leak created one, and the next run found its own report.
#
#   A file that was NOT examined - missing, a directory, or binary - is named
#   on an indented line. It is visible, and it is not counted as covered.
#
# WHAT THIS FIXES IN THE 1.0 CHECK. Every one of these was found by a security
# scan of the 1.0 script; none of them may come back.
#
#   - The `PATTERNS=` BYPASS. 1.0 dropped its own definition line by piping
#     the results through `grep -v '^[0-9]*:PATTERNS='`, which exempted any
#     line beginning with that word in ANY scanned file - a real, reproduced
#     bypass. Here the exclusion is by FILE AND LINE NUMBER: exactly the one
#     line of THIS file that defines the list, located by reading this file,
#     and nothing else anywhere. No content-based exemption exists.
#   - FAILING OPEN. 1.0 wrapped grep in `|| true`, which swallowed grep's
#     exit 2. An unreadable file came out as exit 0 AND was reported as
#     covered. Here grep's status is inspected and anything other than
#     match/no-match is exit 2.
#   - `-I` HID BINARIES. A file holding one NUL byte was skipped in silence
#     while still counted as examined. Binaries are named and not counted.
#   - MISSING PATHS VANISHED. 1.0 did `[ -f "$f" ] || continue`. They are
#     named now.
#   - CASE. 1.0 matched case-sensitively against a lower-case list, so a
#     CamelCase spelling walked straight past a rule that named it, into a
#     public commit. Matching is case-insensitive.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr.
set -euo pipefail

VERSION="check-hygiene 2.0"

# ONE ALTERNATIVE PER PATTERN, AND NO `|` INSIDE AN ALTERNATIVE. The single
# line is deliberate: other tools read the list as data without executing this
# script. It is also split on `|` at run time for reporting, and
# PATTERN_CLASSES names each alternative in the same order - a length mismatch
# refuses the run rather than mislabelling a finding.
PATTERNS='/Users/[A-Za-z][A-Za-z0-9._-]*|/home/[A-Za-z][A-Za-z0-9._-]*|C:\\Users\\[A-Za-z][A-Za-z0-9._-]*|[A-Za-z0-9][A-Za-z0-9-]*\.local[^A-Za-z0-9_.-]|[A-Za-z0-9][A-Za-z0-9-]*\.local$|-----BEGIN [A-Z ]*PRIVATE KEY|gh[opsur]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|A[KS]IA[0-9A-Z]{16}|sk-ant-[A-Za-z0-9_-]{16,}|sk-proj-[A-Za-z0-9_-]{16,}|^sk-[A-Za-z0-9]{20,}|[^A-Za-z0-9]sk-[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|[sr]k_live_[A-Za-z0-9]{10,}|AIza[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}'
PATTERN_CLASSES='personal filesystem path|personal filesystem path|personal filesystem path|machine hostname|machine hostname|private key material|GitHub token|GitHub personal access token|AWS access key id|Anthropic API key|OpenAI project API key|OpenAI API key|OpenAI API key|Slack token|Stripe live key|Google API key|npm token|JSON Web Token'

usage() {
  printf 'usage: check-hygiene.sh [--version] [--help] [--patterns FILE] [--print-patterns] <file>...\n'
}

# ---------------------------------------------------------------- arguments

PATTERNS_FILE=""
PATTERNS_SOURCE=""
PRINT_ONLY=""
FILES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --print-patterns) PRINT_ONLY=1; shift ;;
    --patterns)
      if [ "$#" -lt 2 ]; then
        printf 'check-hygiene: --patterns needs a FILE\n' >&2
        exit 2
      fi
      PATTERNS_FILE="$2"; PATTERNS_SOURCE="--patterns"; shift 2 ;;
    --patterns=*)
      PATTERNS_FILE="${1#--patterns=}"; PATTERNS_SOURCE="--patterns"; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*)
      printf 'check-hygiene: unknown option %s\n' "$1" >&2
      usage >&2
      exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

# ------------------------------------------------------- the built-in list

BUILTIN=()
CLASSES=()
IFS='|' read -r -a BUILTIN <<< "$PATTERNS"
IFS='|' read -r -a CLASSES <<< "$PATTERN_CLASSES"
if [ "${#BUILTIN[@]}" -ne "${#CLASSES[@]}" ]; then
  printf 'check-hygiene: %d built-in patterns but %d class labels. A finding would be mislabelled, so the run is refused.\n' \
    "${#BUILTIN[@]}" "${#CLASSES[@]}" >&2
  exit 2
fi

# --------------------------------------------------------- the local list

# The work tree is found by walking up for a `.git`, rather than by asking
# git, so that running outside a repository is silent instead of writing a
# fatal line to stderr. Nothing here may suppress stderr to tidy that up.
find_work_tree() {
  local d
  d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -e "$d/.git" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname -- "$d")"
  done
  if [ -e "/.git" ]; then
    printf '/\n'
  fi
  return 0
}

if [ -z "$PATTERNS_FILE" ] && [ -n "${PRODUCTIZER_HYGIENE_PATTERNS:-}" ]; then
  PATTERNS_FILE="$PRODUCTIZER_HYGIENE_PATTERNS"
  PATTERNS_SOURCE="\$PRODUCTIZER_HYGIENE_PATTERNS"
fi

if [ -z "$PATTERNS_FILE" ]; then
  WORK_TREE="$(find_work_tree)"
  if [ -n "$WORK_TREE" ] && [ -e "$WORK_TREE/.claude/productizer/hygiene-local.txt" ]; then
    PATTERNS_FILE="$WORK_TREE/.claude/productizer/hygiene-local.txt"
    PATTERNS_SOURCE="the default local list"
  fi
fi

LOCAL_PATTERNS=()
if [ -n "$PATTERNS_FILE" ]; then
  if [ ! -f "$PATTERNS_FILE" ] || [ ! -r "$PATTERNS_FILE" ]; then
    printf 'check-hygiene: cannot read the local pattern list %s (named by %s). A configured list that was not read is unmeasured, not clean - refusing rather than checking the generic patterns alone.\n' \
      "$PATTERNS_FILE" "$PATTERNS_SOURCE" >&2
    exit 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    leading="${line%%[![:space:]]*}"
    trimmed="${line#"$leading"}"
    case "$trimmed" in
      ''|'#'*) continue ;;
    esac
    LOCAL_PATTERNS+=("$trimmed")
  done < "$PATTERNS_FILE"
fi

if [ -n "$PRINT_ONLY" ]; then
  for p in "${BUILTIN[@]}"; do printf '%s\n' "$p"; done
  if [ "${#LOCAL_PATTERNS[@]}" -gt 0 ]; then
    for p in "${LOCAL_PATTERNS[@]}"; do printf '%s\n' "$p"; done
  fi
  exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'check-hygiene: no files given. Nothing scanned is not a clean scan.\n' >&2
  usage >&2
  exit 2
fi

# ------------------------------------------------------------- the scan

GREP_ARGS=(-e "$PATTERNS")
if [ "${#LOCAL_PATTERNS[@]}" -gt 0 ]; then
  for p in "${LOCAL_PATTERNS[@]}"; do GREP_ARGS+=(-e "$p"); done
fi

# The ONE self-exemption, and it is a coordinate, not a rule about content:
# the single line of THIS file that defines the pattern list. Everything else
# in this file is scanned like anything else - run it on itself, that is the
# positive control.
SELF="${BASH_SOURCE[0]}"
SELF_DEF_LINE="$(awk '/^PATTERNS=/{print NR; exit}' "$SELF")"
SELF_ID=""
if [ -r "$SELF" ]; then
  SELF_ID="$(ls -diL -- "$SELF" | awk '{print $1}')"
fi

# A file is binary if it holds a NUL byte anywhere. Deciding this here, rather
# than letting `grep -I` decide it silently, is what makes a skipped binary
# something the reader sees.
is_binary() {
  local total kept
  total="$(wc -c < "$1")"
  kept="$(LC_ALL=C tr -d '\000' < "$1" | wc -c)"
  [ "$total" -ne "$kept" ]
}

# Name the CLASS by re-testing the line against each pattern with the same
# engine that matched it. The line is held in a variable and never printed.
classify() {
  local content="$1" out="" lab i n
  n="${#BUILTIN[@]}"
  for ((i = 0; i < n; i++)); do
    if LC_ALL=C grep -Eqi -e "${BUILTIN[$i]}" <<< "$content"; then
      lab="${CLASSES[$i]}"
      case ", $out, " in
        *", $lab, "*) ;;
        *) out="${out:+$out, }$lab" ;;
      esac
    fi
  done
  n="${#LOCAL_PATTERNS[@]}"
  for ((i = 0; i < n; i++)); do
    if LC_ALL=C grep -Eqi -e "${LOCAL_PATTERNS[$i]}" <<< "$content"; then
      lab="local list entry $((i + 1))"
      case ", $out, " in
        *", $lab, "*) ;;
        *) out="${out:+$out, }$lab" ;;
      esac
    fi
  done
  if [ -z "$out" ]; then
    out="forbidden pattern"
  fi
  printf '%s\n' "$out"
}

found=0
for f in "${FILES[@]}"; do
  if [ ! -e "$f" ]; then
    printf '    %s: does not exist (deleted in this change?) - NOT examined\n' "$f"
    continue
  fi
  if [ -d "$f" ]; then
    printf '    %s: is a directory - NOT examined\n' "$f"
    continue
  fi
  if [ ! -r "$f" ]; then
    printf 'check-hygiene: cannot read %s. Unmeasured, not clean - a file nobody could open is not a clean file.\n' "$f" >&2
    exit 2
  fi
  if is_binary "$f"; then
    printf '    %s: binary (holds a NUL byte) - NOT examined, and NOT counted as clean\n' "$f"
    continue
  fi

  printf '%s\n' "$f"          # coverage: one bare path per file examined

  skip_line=""
  if [ -n "$SELF_ID" ] && [ -n "$SELF_DEF_LINE" ]; then
    if [ "$(ls -diL -- "$f" | awk '{print $1}')" = "$SELF_ID" ]; then
      skip_line="$SELF_DEF_LINE"
    fi
  fi

  set +e
  hits="$(LC_ALL=C grep -Eni "${GREP_ARGS[@]}" -- "$f")"
  grc=$?
  set -e
  case "$grc" in
    0) ;;
    1) hits="" ;;
    *)
      printf 'check-hygiene: grep exited %s on %s. Unmeasured, not clean.\n' "$grc" "$f" >&2
      exit 2 ;;
  esac

  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      ln="${hit%%:*}"
      content="${hit#*:}"
      if [ "$ln" = "$skip_line" ]; then
        continue
      fi
      printf '    %s:%s: %s - open the file at that line; the match is deliberately not printed\n' \
        "$f" "$ln" "$(classify "$content")"
      found=1
    done <<< "$hits"
  fi
done

exit "$found"
