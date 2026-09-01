#!/usr/bin/env bash
# check-installed-copies.sh [--root DIR] [--templates DIR] [--hooks DIR]
#                           [--version] [--help]
#
# AN EXECUTABLE INSTALLED FROM A TEMPLATE MUST STILL BE THAT TEMPLATE.
#
# The publish gate exists twice: `templates/publish-gate.sh`, which every repo
# installing this plugin receives, and `.claude/hooks/publish-gate.sh`, which is
# this repo's own copy. They were byte-identical and nothing said so.
#
# Measured, not argued: editing one drifted them instantly, and the drift stayed
# invisible until a check that drives the TEMPLATE failed against a fix that had
# only landed in the hook. The dangerous direction is the other one - this repo
# hardening its own gate while every repo installing the plugin keeps the weaker
# copy, and the suite staying green because it only ever tests the template.
#
# WHAT IS COMPARED, AND WHAT IS DELIBERATELY NOT.
#
# Only executables that landed under the hooks directory. `templates/` also
# holds SEEDS - `spec.md`, `backlog.md`, `config.json`, `constitution.md`,
# `checks.yaml` - which are copied once and then edited, and which differ from
# their template the moment the repo is used. Comparing those would go red on
# five files for doing exactly what they are for. A hook is not a seed: it is
# code, and there is no per-repo edit it is meant to carry.
#
# Two assertions, separately.
#
#   1. Every template executable with a counterpart in the hooks directory is
#      byte-identical to it.
#   2. Every such counterpart is executable. A hook the shell will not run is a
#      gate that is not there, and it fails silently rather than loudly.
#
# THE PREMISE IS GUARDED. If no pair exists at all, nothing was compared and the
# run asserts nothing - exit 2, unmeasured, never a clean pass. An assertion
# sweeping an empty set is how a check in this repo passed for months without
# ever seeing the thing it looked for.
#
# CONTENT IS NEVER PRINTED, only the first differing LINE NUMBER. This output is
# tailed into a committed result file, and a diff there would put one copy of
# the gate inside the record of the other.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every installed executable matches its template and is runnable
#   1  a copy drifted, or lost its executable bit
#   2  could not run - bad usage, a missing directory, an unreadable file, or
#      no pair to compare
#
# WHAT IT PRINTS. One BARE repo-relative path per file examined, which the
# runner parses as coverage. Findings and notes are INDENTED.
set -euo pipefail

VERSION="check-installed-copies 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""; TEMPLATES=""; HOOKS=""

die_unmeasured() { printf 'check-installed-copies: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)        [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";      ROOT="$2";      shift 2 ;;
    --root=*)      ROOT="${1#--root=}";           shift ;;
    --templates)   [ "$#" -ge 2 ] || die_unmeasured "--templates needs a path"; TEMPLATES="$2"; shift 2 ;;
    --templates=*) TEMPLATES="${1#--templates=}"; shift ;;
    --hooks)       [ "$#" -ge 2 ] || die_unmeasured "--hooks needs a path";     HOOKS="$2";     shift 2 ;;
    --hooks=*)     HOOKS="${1#--hooks=}";         shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given; the pair could not be located"
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$TEMPLATES" ] || TEMPLATES="$HERE/../templates"
[ -n "$HOOKS" ]     || HOOKS="$ROOT/.claude/hooks"
[ -d "$TEMPLATES" ] || die_unmeasured "no templates directory, so there is nothing to compare against"
[ -d "$HOOKS" ]     || die_unmeasured "no hooks directory at the path given; whether an installed copy drifted is UNKNOWN, which is not the same as no drift"
TEMPLATES="$(cd "$TEMPLATES" && pwd -P)"
HOOKS="$(cd "$HOOKS" && pwd -P)"

rel() { case "$1" in "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;; *) printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;; esac; }

pairs=0
findings=0
upheld_same=0
upheld_exec=0

for tpl in "$TEMPLATES"/*.sh; do
  [ -f "$tpl" ] || continue
  base="$(basename "$tpl")"
  inst="$HOOKS/$base"
  [ -f "$inst" ] || continue
  pairs=$((pairs + 1))
  rel "$tpl"
  rel "$inst"

  [ -r "$tpl" ] && [ -r "$inst" ] \
    || die_unmeasured "$base could not be read on one side, so whether the two agree is UNKNOWN"

  # ASSERTION 1. Byte-identical. Only the first differing line number is
  # reported; printing the difference itself would put one copy of a gate
  # inside the committed record of the other.
  if cmp -s "$tpl" "$inst"; then
    upheld_same=$((upheld_same + 1))
    printf '  held: %s matches its template byte for byte\n' "$base"
  else
    findings=$((findings + 1))
    # cmp's own message is NOT parsed and NOT printed: it names both files by
    # path, and this output is tailed into a committed result. What is reported
    # is derived here instead - the first differing line if there is one, or the
    # two sizes when one file is simply a prefix of the other, which is what an
    # append looks like and what cmp reports as EOF rather than as a line.
    #
    # `|| :` on the pipeline is load-bearing and is not tolerance of an unknown
    # failure: cmp exits 1 because the files differ, which is the case we are
    # already in, and `set -o pipefail` turns that into the pipeline's status
    # for `set -e` to kill the script on. Without it this branch died having
    # printed the paths and no finding - right exit code, invisible reason.
    line="$(cmp "$tpl" "$inst" 2>/dev/null | sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -1 || :)"  # stderr-ok: cmp's stderr names both files by absolute path and this text reaches a committed file; the line number is taken from stdout and the prefix case is reported from sizes below
    _ts="$(wc -c < "$tpl" | tr -d ' ')"
    _is="$(wc -c < "$inst" | tr -d ' ')"
    if [ -n "$line" ]; then
      where="first differing line $line"
    elif [ "$_ts" != "$_is" ]; then
      where="one file is a prefix of the other; template $_ts bytes, installed $_is bytes"
    else
      where="same length, and the differing position could not be read"
    fi
    printf '  FINDING: %s has drifted from its template: %s. This repo and every repo installing the plugin are no longer running the same code, and the suite tests only one of them. Content is not printed here.\n' \
      "$base" "$where"
  fi

  # ASSERTION 2. Runnable. A hook the shell will not execute is a gate that is
  # not there, and it fails silently rather than loudly.
  if [ -x "$inst" ]; then
    upheld_exec=$((upheld_exec + 1))
  else
    findings=$((findings + 1))
    printf '  FINDING: the installed %s is not executable, so it never runs. A gate that cannot run does not refuse anything; it is absent, quietly.\n' "$base"
  fi
done

# The empty set, guarded. Nothing compared is nothing asserted.
[ "$pairs" -gt 0 ] || die_unmeasured "no template executable has a counterpart in the hooks directory, so nothing was compared. An assertion with no pair to fire on holds vacuously forever; this refuses instead"

printf '  pairs compared: %d\n' "$pairs"
printf '  assertions evaluated: %d, upheld: %d\n' "$((pairs * 2))" "$((upheld_same + upheld_exec))"

if [ "$findings" -ne 0 ]; then
  printf '  An executable installed from a template is no longer that template.\n'
  exit 1
fi
printf '  Every installed executable is its template, and every one of them runs.\n'
exit 0
