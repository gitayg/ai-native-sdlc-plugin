#!/usr/bin/env bash
# check-spec-home.sh [--version] [--config PATH] [--repo SLUG=PATH]... [--remote]
#
# Asserts R1: THE LIFECYCLE SHALL HOLD EXACTLY ONE LIVING SPEC PER PRODUCT.
#
# Until this existed, nothing did. `product.spec_home` was declared in
# config.json and never read back, so a product could grow a second
# `.claude/productizer/spec.md` in a second repo and nothing would say so -
# two allocators both handing out R42, two specs both believed, and the
# divergence discovered later by whoever trusted the wrong one.
#
# WHAT IT MEASURES. Every repo in `product.repos`, asked one question: does it
# hold the spec file named by `spec.path`? Then:
#
#   exactly one, and it is the declared home        pass
#   exactly one, but not the declared home          fail - the home is a lie
#   two or more                                     fail - R1 is broken now
#   none, and every repo was reachable              fail - no living spec
#   any repo could not be reached                   REFUSED, see below
#
# UNREACHABLE IS NOT ABSENT, AND THIS IS THE WHOLE POINT.
#
# A repo this check cannot open is not a repo with no spec in it. Counting it
# as "no spec there" is how a two-spec product reports as a one-spec product:
# the second spec is in the repo nobody could reach. So an unreachable repo is
# reported by name, with the reason it could not be reached, and the run exits
# 2 - refused, distinct from both pass and fail, and never folded into the
# "specs found" count in either direction.
#
# The one ordering rule: two specs already found is a definite answer, so it
# fails (1) even when a third repo was unreachable. Unreachability only
# refuses when it could still change the verdict.
#
# HOW A REPO IS REACHED, in order:
#
#   1. --repo SLUG=PATH, given on the command line. Explicit wins.
#   2. `github.repo` in the config matches the slug - this is the repo the
#      check is running in, so the working directory is used.
#   3. The working directory's own basename matches the slug's.
#   4. A sibling checkout: ../<basename> holding a .git or a .claude.
#   5. --remote, and `gh` on PATH: the GitHub contents API. OFF BY DEFAULT,
#      because a check that reaches the network is not deterministic and a
#      rate limit would read as an outage rather than a verdict.
#
# Nothing matched means UNREACHABLE. It never means absent.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  exactly one living spec, in the declared home
#   1  R1 is violated - too many, none, or not where the config says
#   2  COULD NOT MEASURE - a repo out of reach, or a config that cannot be
#      read or does not declare what this check needs
set -euo pipefail

VERSION="check-spec-home 1.0"
CONFIG=".claude/productizer/config.json"
REMOTE=""
MAP_SLUG=()
MAP_PATH=()

die_unmeasured() { printf 'check-spec-home: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --config) [ "$#" -ge 2 ] || die_unmeasured "--config needs a path"; CONFIG="$2"; shift 2 ;;
    --remote) REMOTE=1; shift ;;
    --repo)
      [ "$#" -ge 2 ] || die_unmeasured "--repo needs SLUG=PATH"
      case "$2" in
        *=*) MAP_SLUG+=("${2%%=*}"); MAP_PATH+=("${2#*=}") ;;
        *) die_unmeasured "--repo $2 is not SLUG=PATH" ;;
      esac
      shift 2
      ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

[ -f "$CONFIG" ] && [ -r "$CONFIG" ] ||
  die_unmeasured "cannot read $CONFIG. A config nobody could open says nothing about how many specs exist; it is not a product with zero repos."
command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the config cannot be parsed. Refusing rather than guessing what was declared."

# The config is read, never sourced. Output is one TAB-separated record per
# line so the shell below never has to parse JSON.
DECL="$(python3 - "$CONFIG" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path) as fh:
        cfg = json.load(fh)
except (OSError, ValueError) as exc:
    sys.stderr.write("check-spec-home: %s could not be parsed: %s\n" % (path, exc))
    sys.exit(2)
if not isinstance(cfg, dict):
    sys.stderr.write("check-spec-home: %s is not a JSON object\n" % path)
    sys.exit(2)

out = []
product = cfg.get("product")
if not isinstance(product, dict):
    sys.stderr.write("check-spec-home: %s declares no `product` object. Unmeasured.\n" % path)
    sys.exit(2)

repos = product.get("repos")
if not isinstance(repos, list) or not repos or not all(isinstance(r, str) and r.strip() for r in repos):
    sys.stderr.write("check-spec-home: %s declares no non-empty `product.repos` list. A product with no "
                     "repos named is a product nobody can count the specs of - unmeasured, not zero.\n" % path)
    sys.exit(2)

spec = cfg.get("spec") if isinstance(cfg.get("spec"), dict) else {}
spec_path = spec.get("path")
if not isinstance(spec_path, str) or not spec_path.strip():
    spec_path = ".claude/productizer/spec.md"
    out.append(("note", "`spec.path` is not declared; falling back to .claude/productizer/spec.md"))

# `spec.home` is a dotted pointer at the key that names the home repo. Follow
# it when it resolves; say so out loud when it dangles, because a pointer at a
# key that does not exist is exactly how `spec_home` came to be declared and
# never read.
home = None
home_source = None
pointer = spec.get("home")
if isinstance(pointer, str) and pointer.strip():
    node = cfg
    for part in pointer.split("."):
        node = node.get(part) if isinstance(node, dict) else None
    if isinstance(node, str) and node.strip():
        home, home_source = node.strip(), "spec.home -> %s" % pointer
    else:
        out.append(("note", "`spec.home` points at `%s`, which the config does not define. "
                            "Falling back to product.spec_home / product.spec_repo." % pointer))
if home is None:
    for key in ("spec_home", "spec_repo"):
        value = product.get(key)
        if isinstance(value, str) and value.strip():
            home, home_source = value.strip(), "product.%s" % key
            break
if home is None:
    sys.stderr.write("check-spec-home: %s names no home repo (`spec.home`, `product.spec_home` or "
                     "`product.spec_repo`). Unmeasured.\n" % path)
    sys.exit(2)

gh = cfg.get("github") if isinstance(cfg.get("github"), dict) else {}
here = gh.get("repo") if isinstance(gh.get("repo"), str) else ""

out.append(("specpath", spec_path.strip()))
out.append(("home", home))
out.append(("homesource", home_source))
out.append(("here", here.strip()))
for r in repos:
    out.append(("repo", r.strip()))
sys.stdout.write("".join("%s\t%s\n" % kv for kv in out))
PY
)" || exit 2

SPECPATH=""; HOME_SLUG=""; HOME_SRC=""; HERE_SLUG=""
REPOS=()
NOTES=()
while IFS=$'\t' read -r key value; do
  case "$key" in
    specpath)   SPECPATH="$value" ;;
    home)       HOME_SLUG="$value" ;;
    homesource) HOME_SRC="$value" ;;
    here)       HERE_SLUG="$value" ;;
    repo)       REPOS+=("$value") ;;
    note)       NOTES+=("$value") ;;
  esac
done <<< "$DECL"

CWD="$(pwd)"
PARENT="$(dirname "$CWD")"

# Paths printed here reach run-checks' `output_tail`, which is committed inside
# checks-result.json. An absolute path therefore writes whoever ran the check
# into a public file - the same leak that shipped in v4.2.0 and was removed in
# v4.3.0. Report relative to the work tree when the target is inside it. A path
# outside the tree stays absolute: shortening it would misname where the file is,
# and a wrong path is worse than a long one.
REL_ROOT="$(git rev-parse --show-toplevel 2>&1)" || REL_ROOT="$CWD"
case "$REL_ROOT" in /*) ;; *) REL_ROOT="$CWD" ;; esac

rel_to_root() {
  case "$1" in
    "$REL_ROOT"/*) printf '%s' "${1#"$REL_ROOT"/}" ;;
    "$REL_ROOT")   printf '.' ;;
    *)              printf '%s' "$1" ;;
  esac
}

# Echoes "<state>\t<where>". States: present, absent, unreachable.
locate() {
  slug="$1"
  base="${slug##*/}"
  dir=""
  how=""

  i=0
  while [ "$i" -lt "${#MAP_SLUG[@]}" ]; do
    if [ "${MAP_SLUG[$i]}" = "$slug" ]; then
      dir="${MAP_PATH[$i]}"
      how="--repo mapping"
      if [ ! -d "$dir" ]; then
        printf 'unreachable\t--repo %s=%s is not a directory\n' "$slug" "$dir"
        return 0
      fi
      break
    fi
    i=$((i + 1))
  done

  if [ -z "$dir" ] && [ -n "$HERE_SLUG" ] && [ "$HERE_SLUG" = "$slug" ]; then
    dir="$CWD"; how="github.repo names it, so it is the repo this check runs in"
  fi
  if [ -z "$dir" ] && [ "${CWD##*/}" = "$base" ]; then
    dir="$CWD"; how="the working directory basename matches"
  fi
  if [ -z "$dir" ] && { [ -d "$PARENT/$base/.git" ] || [ -d "$PARENT/$base/.claude" ]; }; then
    dir="$PARENT/$base"; how="sibling checkout"
  fi

  if [ -z "$dir" ]; then
    if [ -n "$REMOTE" ] && command -v gh >/dev/null; then
      err="$(mktemp "${TMPDIR:-/tmp}/check-spec-home.XXXXXX")"
      if gh api "repos/$slug/contents/$SPECPATH" --jq '.name' > /dev/null 2> "$err"; then
        rm -f "$err"
        printf 'present\tGitHub contents API\n'
        return 0
      fi
      # A 404 is an ANSWER - the file is not there. Anything else is the API
      # declining to answer, which is not the same sentence.
      if grep -q '404' "$err"; then
        rm -f "$err"
        printf 'absent\tGitHub contents API\n'
        return 0
      fi
      why="$(tr '\n' ' ' < "$err")"
      rm -f "$err"
      printf 'unreachable\tgh api failed: %s\n' "${why:-no message on stderr}"
      return 0
    fi
    if [ -n "$REMOTE" ]; then
      printf 'unreachable\tno local checkout found and gh is not on PATH\n'
    else
      printf 'unreachable\tno local checkout found; pass --repo %s=PATH, or --remote to ask GitHub\n' "$slug"
    fi
    return 0
  fi

  target="$dir/$SPECPATH"
  if [ -e "$target" ] && [ ! -r "$target" ]; then
    printf 'unreachable\t%s exists but cannot be read (%s)\n' "$(rel_to_root "$target")" "$how"
    return 0
  fi
  if [ -f "$target" ]; then
    printf 'present\t%s (%s)\n' "$(rel_to_root "$target")" "$how"
  else
    printf 'absent\t%s (%s)\n' "$(rel_to_root "$dir")" "$how"
  fi
}

printf 'config: %s\n' "$CONFIG"
printf 'spec path: %s\n' "$SPECPATH"
printf 'declared home: %s (from %s)\n' "$HOME_SLUG" "$HOME_SRC"
if [ "${#NOTES[@]}" -gt 0 ]; then
  for n in "${NOTES[@]}"; do
    printf 'note: %s\n' "$n"
  done
fi

present=0; absent=0; unreachable=0
HOLDERS=()
for slug in "${REPOS[@]}"; do
  IFS=$'\t' read -r state where <<< "$(locate "$slug")"
  printf '  %-40s %-12s %s\n' "$slug" "$state" "$where"
  case "$state" in
    present)     present=$((present + 1)); HOLDERS+=("$slug") ;;
    absent)      absent=$((absent + 1)) ;;
    unreachable) unreachable=$((unreachable + 1)) ;;
  esac
done

printf 'repos declared: %d\n' "${#REPOS[@]}"
printf 'repos reachable: %d\n' "$((present + absent))"
printf 'repos unreachable: %d\n' "$unreachable"
printf 'specs found: %d\n' "$present"

home_listed=0
for slug in "${REPOS[@]}"; do
  [ "$slug" = "$HOME_SLUG" ] && home_listed=1
done

if [ "$present" -ge 2 ]; then
  printf 'FAIL: R1 broken - %d repos hold a living spec (%s). One product, one spec: pick the home and supersede the other.\n' \
    "$present" "$(IFS=', '; printf '%s' "${HOLDERS[*]}")" >&2
  exit 1
fi

if [ "$unreachable" -gt 0 ]; then
  printf 'REFUSED: %d of %d repos could not be reached, so the number of living specs is UNKNOWN - not zero, and not one. A repo nobody could open is where a second spec hides.\n' \
    "$unreachable" "${#REPOS[@]}" >&2
  exit 2
fi

if [ "$present" -eq 0 ]; then
  printf 'FAIL: no repo in this product holds %s. Every repo was reached and none has one, so this is a measured zero, not an unmeasured one.\n' \
    "$SPECPATH" >&2
  exit 1
fi

if [ "$home_listed" -eq 0 ]; then
  printf 'FAIL: the declared home %s is not one of the repos in product.repos. A home outside the product is a home nothing checks.\n' \
    "$HOME_SLUG" >&2
  exit 1
fi

if [ "${HOLDERS[0]}" != "$HOME_SLUG" ]; then
  printf 'FAIL: the one living spec is in %s, but the config declares the home as %s. The declaration and the filesystem disagree, and downstream tooling believes the declaration.\n' \
    "${HOLDERS[0]}" "$HOME_SLUG" >&2
  exit 1
fi

printf 'PASS: exactly one living spec, in the declared home %s.\n' "$HOME_SLUG"
