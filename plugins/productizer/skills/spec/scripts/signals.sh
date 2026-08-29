#!/bin/bash
# signals.sh — collect typed, objective records of what was OBSERVED. No judgment.
#
# The checks stage answers "did the tools pass?". This answers the prior question:
# "what evidence exists at all, and what is provably absent?". Judgment lives in
# `score.sh`, which is keyed to the hash this script emits, so a verdict can never
# outlive the evidence it was computed from.
#
# THE INVARIANT THIS FILE SERVES:
#
#     ABSENCE IS AN OBSERVATION, NOT AN EMPTY SUCCESS.
#
# No `gh`, no remote, no pull request and no CI run are four different states of
# the world. Collapsing them into "nothing to report, looks clean" is the failure
# this script refuses to make. Each one is emitted as a named absence, and every
# absence is inside the hashed content, so a score computed against a box with no
# `gh` cannot be reused on a box that has one.
#
# Usage:
#   signals.sh [--checks-result PATH] [--out PATH|-] [--no-github] [--base REF]
#
# Exit codes follow the rest of the skill:
#   0  signals collected (including "collected: nothing but absences")
#   2  bad usage, or python3 is missing
#   1  crashed
set -euo pipefail

# Determinism is the whole product here. A timestamp rendered in the operator's
# local zone would hash differently on two machines looking at identical evidence,
# which would make the staleness rule fire on nothing at all.
export TZ=UTC
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

CHECKS_RESULT=".claude/productizer/checks-result.json"
OUT="-"
USE_GITHUB=1
BASE_REF=""

usage() {
  cat <<'USAGE'
signals.sh — collect typed signal records with provenance.

  --checks-result PATH   local checks output (default .claude/productizer/checks-result.json)
  --out PATH             where to write the signals document ("-" for stdout, the default)
  --no-github            do not call gh, and say so as a declared absence
  --base REF             base ref for diff stats (default: origin/<default branch>)
  -h, --help             this
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --checks-result) [ $# -ge 2 ] || { echo "signals: --checks-result needs a value" >&2; exit 2; }; CHECKS_RESULT="$2"; shift 2 ;;
    --out)           [ $# -ge 2 ] || { echo "signals: --out needs a value" >&2; exit 2; };           OUT="$2"; shift 2 ;;
    --base)          [ $# -ge 2 ] || { echo "signals: --base needs a value" >&2; exit 2; };          BASE_REF="$2"; shift 2 ;;
    --no-github)     USE_GITHUB=0; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "signals: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null; then
  echo "signals: python3 is required — it is what canonicalises and hashes the evidence." >&2
  echo "signals: a shell-built hash over unsorted, unescaped values is not a hash of the evidence." >&2
  exit 2
fi

if [ ! -f "$SCRIPT_DIR/detect-context.sh" ]; then
  echo "signals: $SCRIPT_DIR/detect-context.sh is missing. Context detection is not duplicated here." >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pz-signals.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Subprocess stderr is captured to a file so it can be reasoned about, then always
# replayed to the operator's terminal — including when the command SUCCEEDED. A
# warning on a successful `git diff` is exactly the kind of thing that explains a
# surprising hash later, and it is lost the moment anything discards it.
surface() {
  [ -s "$1" ] || return 0
  sed "s|^|signals: $2: |" "$1" >&2
  : > "$1"
}

# ---------------------------------------------------------------------------
# 1 · context. detect-context.sh already probes gh availability, the remote and
#     the owner match, and it is hardened against hostile branch and remote
#     names. Re-detecting here would be a second, weaker implementation of the
#     same probe that drifts away from it.
# ---------------------------------------------------------------------------
bash "$SCRIPT_DIR/detect-context.sh" > "$WORK/ctx.json"

read_ctx() {
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print("" if d is None else (d if isinstance(d,str) else json.dumps(d)))' "$WORK/ctx.json" "$1"
}

GH_STATE="$(read_ctx github_cli.state)"
GH_OWNER_MATCH="$(read_ctx github_cli.owner_match)"
REPO="$(read_ctx git.repo)"
HOST="$(read_ctx git.host)"
IS_REPO="$(read_ctx git.is_repo)"
DEFAULT_BRANCH="$(read_ctx git.default_branch)"

# ---------------------------------------------------------------------------
# 2 · git. Evidence-derived timestamps only. There is no wall clock anywhere in
#     the hashed content, so the same tree hashes the same tomorrow.
# ---------------------------------------------------------------------------
: > "$WORK/git_head.txt"
: > "$WORK/diffstat.txt"
DIFF_SOURCE="none"

if [ "$IS_REPO" = "true" ]; then
  # %H and %cI: the commit's own identity and its own committer date, with the
  # offset it was written with. Normalisation to UTC happens in python, where a
  # real datetime parser does it, not a `date` binary whose flags differ by OS.
  HEAD_LINE=""
  HEAD_RC=0
  HEAD_LINE="$(git log -1 --format='%H%x09%cI' 2>"$WORK/git.err")" || HEAD_RC=$?
  # An unborn HEAD is normal in a fresh repo. Report the stderr rather than
  # swallowing it; a real git failure and an empty repo must not look alike.
  surface "$WORK/git.err" "git log"
  if [ "$HEAD_RC" -eq 0 ]; then
    printf '%s\n' "$HEAD_LINE" > "$WORK/git_head.txt"
  fi

  if [ -z "$BASE_REF" ] && [ -n "$DEFAULT_BRANCH" ]; then
    BASE_REF="origin/$DEFAULT_BRANCH"
  fi
  if [ -n "$BASE_REF" ]; then
    REV_RC=0
    git rev-parse --verify --quiet "$BASE_REF^{commit}" >"$WORK/rev.out" 2>"$WORK/rev.err" || REV_RC=$?
    surface "$WORK/rev.err" "git rev-parse"
    if [ "$REV_RC" -eq 0 ]; then
      DIFF_RC=0
      git diff --numstat "$BASE_REF...HEAD" > "$WORK/diffstat.txt" 2>"$WORK/diff.err" || DIFF_RC=$?
      surface "$WORK/diff.err" "git diff"
      if [ "$DIFF_RC" -eq 0 ]; then
        DIFF_SOURCE="base_to_head"
      else
        : > "$WORK/diffstat.txt"
      fi
    fi
  fi
  if [ "$DIFF_SOURCE" = "none" ] && [ "$HEAD_RC" -eq 0 ]; then
    DIFF_RC=0
    git diff --numstat HEAD > "$WORK/diffstat.txt" 2>"$WORK/diff.err" || DIFF_RC=$?
    surface "$WORK/diff.err" "git diff"
    if [ "$DIFF_RC" -eq 0 ]; then
      DIFF_SOURCE="worktree_to_head"
    else
      : > "$WORK/diffstat.txt"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3 · GitHub. Four separate preconditions, four separate absences. `gh` present
#     but signed out is not the same as `gh` absent; a repo with no remote is not
#     the same as a remote with no pull request; a pull request with no CI run is
#     not the same as CI that ran and passed.
# ---------------------------------------------------------------------------
GH_REASON=""
PR_STATE="not_attempted"
PR_REASON=""
CI_STATE="not_attempted"
CI_REASON=""
: > "$WORK/pr.json"
: > "$WORK/checks.json"

if [ "$USE_GITHUB" -eq 0 ]; then
  GH_REASON="--no-github was passed; GitHub evidence was not collected"
elif [ "$GH_STATE" = "absent" ]; then
  GH_REASON="the gh CLI is not installed, so no CI run, review or comment could be observed at all"
elif [ "$GH_STATE" = "unauthenticated" ]; then
  GH_REASON="gh is installed but not signed in; GitHub evidence is unreadable, not empty"
elif [ "$IS_REPO" != "true" ]; then
  GH_REASON="not a git repository, so there is nothing for gh to look at"
elif [ -z "$REPO" ]; then
  GH_REASON="the repository has no origin remote, so there is no upstream to carry CI, reviews or comments"
elif [ "$HOST" != "github.com" ]; then
  GH_REASON="origin is on ${HOST:-an unknown host}, not github.com; gh cannot read its checks"
else
  GH_REASON=""
fi

if [ -z "$GH_REASON" ]; then
  PR_RC=0
  gh pr view --json number,state,isDraft,headRefOid,additions,deletions,changedFiles,reviews,comments,statusCheckRollup \
    > "$WORK/pr.json" 2>"$WORK/pr.err" || PR_RC=$?
  # Never suppressed: gh's own words go to stderr where an operator sees them,
  # whether it succeeded or not.
  surface "$WORK/pr.err" "gh pr view"
  if [ "$PR_RC" -ne 0 ]; then
    PR_STATE="none"
    PR_REASON="gh found no pull request for this branch (gh exit $PR_RC). Unreviewed, not approved."
    : > "$WORK/pr.json"
  else
    PR_STATE="found"
    CI_STATE="collected"
  fi
else
  PR_STATE="unavailable"
  PR_REASON="$GH_REASON"
  CI_STATE="unavailable"
  CI_REASON="$GH_REASON"
fi

if [ "$PR_STATE" = "none" ]; then
  CI_STATE="unavailable"
  CI_REASON="no pull request, so no pull-request CI, review or comment evidence exists"
fi

# ---------------------------------------------------------------------------
# 4 · assemble, canonicalise, hash. All untrusted values reach python as file
#     contents or argv, never as shell source. Nothing here is eval'd.
# ---------------------------------------------------------------------------
export PZ_WORK="$WORK"
export PZ_CHECKS_RESULT="$CHECKS_RESULT"
export PZ_OUT="$OUT"
export PZ_GH_STATE="$GH_STATE"
export PZ_GH_REASON="$GH_REASON"
export PZ_GH_OWNER_MATCH="$GH_OWNER_MATCH"
export PZ_PR_STATE="$PR_STATE"
export PZ_PR_REASON="$PR_REASON"
export PZ_CI_STATE="$CI_STATE"
export PZ_CI_REASON="$CI_REASON"
export PZ_DIFF_SOURCE="$DIFF_SOURCE"
export PZ_IS_REPO="$IS_REPO"
export PZ_REPO="$REPO"
export PZ_HOST="$HOST"
export PZ_USE_GITHUB="$USE_GITHUB"

python3 <<'PY'
import hashlib, json, os, re, sys
from datetime import datetime, timezone

W = os.environ["PZ_WORK"]

def slurp(name):
    p = os.path.join(W, name)
    if not os.path.exists(p):
        return ""
    with open(p, "r", errors="replace") as fh:
        return fh.read()

def load_json(path):
    """Returns (doc, error). A malformed evidence file is an observation about the
    evidence, not a reason to abort and not a reason to report nothing found."""
    if not path or not os.path.exists(path):
        return None, "absent"
    try:
        with open(path, "r", errors="replace") as fh:
            return json.load(fh), None
    except (ValueError, OSError) as exc:
        return None, "unreadable: %s" % exc

def utc(ts):
    """Every timestamp in the hashed content is normalised to UTC by a real parser.
    A naive timestamp carries no zone, so guessing one would invent evidence: it is
    reported as unanchored instead."""
    if not ts:
        return None, "none"
    s = ts.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    # datetime.fromisoformat is stricter about fractional seconds on older
    # interpreters than on newer ones. Two boxes disagreeing about whether a
    # timestamp parses would produce two different hashes for one piece of
    # evidence, so the fraction is normalised to six digits before parsing
    # rather than left to the interpreter's mood.
    s = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], s, count=1)
    try:
        d = datetime.fromisoformat(s)
    except ValueError:
        return None, "unparseable"
    if d.tzinfo is None:
        return None, "unanchored"
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "evidence"

# Lightsprint's two enums, adopted verbatim. A record that does not fit one of
# these is not a signal, it is prose.
CATEGORIES = {"ci", "review", "deployment", "bot_comment", "human_comment", "custom"}
STATUSES = {"success", "failure", "pending", "running", "neutral", "warning"}

signals = []
absences = []

def signal(sid, category, status, source, title, timestamp=None, url="", actor="",
           evidence=None):
    ts, ts_src = utc(timestamp)
    assert category in CATEGORIES, category
    assert status in STATUSES, status
    signals.append({
        "id": sid, "category": category, "status": status, "source": source,
        "title": title, "timestamp": ts, "timestamp_source": ts_src,
        "url": url or "", "actor": actor or "",
        "evidence": evidence if evidence is not None else {},
    })

def absent(source, state, meaning):
    absences.append({"source": source, "state": state, "meaning": meaning})

# --- local checks ---------------------------------------------------------
cr_path = os.environ["PZ_CHECKS_RESULT"]
cr, cr_err = load_json(cr_path)

# run-checks statuses, mapped onto the signal enum. The distinction that matters:
# a finding (failure) is a fact about the code; a hollow, timed-out or
# missing-tool check (warning) is a fact about the evidence. Flattening the second
# into the first sends someone to fix code that was never examined.
STATUS_MAP = {
    "pass": "success",
    "fail": "failure",
    "refused": "failure",
    "hollow": "warning",
    "missing_tool": "warning",
    "timeout": "warning",
    "unmapped_exit": "warning",
    "no_version": "warning",
    "not_triggered": "neutral",
    "disabled": "neutral",
}

if cr is None:
    absent("local_checks", "absent" if cr_err == "absent" else "unreadable",
           "no local checks result at %s (%s). Nothing locally verified — which is not the "
           "same as locally clean." % (cr_path, cr_err))
else:
    rows = cr.get("checks") or []
    if not rows:
        absent("local_checks", "empty",
               "%s parsed but declares no checks. A result file with no checks in it is a "
               "configuration problem, not a clean run." % cr_path)
    for row in rows:
        if not isinstance(row, dict):
            continue
        rid = str(row.get("id", "unknown"))
        st = STATUS_MAP.get(str(row.get("status", "")), "warning")
        cov = row.get("coverage") or {}
        obs = cov.get("observed") or {}
        covered = obs.get("covered_items") or []
        missed = obs.get("not_examined") or []
        covered = sorted({str(x) for x in covered if isinstance(x, (str, int))})
        missed = sorted({str(x) for x in missed if isinstance(x, (str, int))})
        # DECLARED is reconstructed as the union, not copied from the runner's own
        # difference. score.sh then recomputes the difference and cross-checks it
        # against the runner's count — two independent derivations of the same set.
        declared = sorted(set(covered) | set(missed))
        signal(
            "check:%s" % rid, "ci", st, "local_checks",
            "%s — %s" % (rid, row.get("status", "unknown")),
            evidence={
                "runner_status": str(row.get("status", "")),
                "exit_code": row.get("exit_code"),
                "severity": str(row.get("severity", "")),
                "tool_version": (row.get("tool") or {}).get("version"),
                "declared_items": declared,
                "observed_items": covered,
                "runner_files_in_scope": obs.get("files_in_scope"),
                "coverage_satisfied": cov.get("satisfied"),
            })

# --- git ------------------------------------------------------------------
if os.environ["PZ_IS_REPO"] != "true":
    absent("git", "not_a_repo",
           "not a git repository. There is no commit, no branch and no remote to anchor "
           "any of this to.")
else:
    head = slurp("git_head.txt").strip()
    if not head:
        absent("git", "unborn_head",
               "the repository has no commits yet, so there is no committed state to observe.")
    else:
        parts = head.split("\t")
        sha = parts[0]
        when = parts[1] if len(parts) > 1 else ""
        ins = dels = 0
        files = []
        for line in slurp("diffstat.txt").splitlines():
            cols = line.split("\t")
            if len(cols) < 3:
                continue
            # "-" is git's marker for a binary file: not zero lines, unknown lines.
            ins += int(cols[0]) if cols[0].isdigit() else 0
            dels += int(cols[1]) if cols[1].isdigit() else 0
            files.append(cols[2])
        signal("git:head", "custom", "neutral", "git",
               "HEAD %s" % sha[:12], timestamp=when,
               evidence={
                   "sha": sha,
                   "diff_stat": {
                       "source": os.environ["PZ_DIFF_SOURCE"],
                       "files_changed": len(files),
                       "insertions": ins,
                       "deletions": dels,
                       "files": sorted(set(files)),
                   },
               })
    if not os.environ["PZ_REPO"]:
        absent("remote", "none",
               "no origin remote. Nothing has been pushed anywhere, so no upstream CI, "
               "review or deployment could have run.")
    elif os.environ["PZ_HOST"] != "github.com":
        absent("remote", "not_github",
               "origin is on %s, not github.com. The PR and CI anchors are unavailable "
               "here; that is unmeasured, not clean." % (os.environ["PZ_HOST"] or "an unknown host"))

# --- github ---------------------------------------------------------------
gh_state = os.environ["PZ_GH_STATE"]
gh_reason = os.environ["PZ_GH_REASON"]
pr_state = os.environ["PZ_PR_STATE"]
ci_state = os.environ["PZ_CI_STATE"]

if os.environ["PZ_USE_GITHUB"] == "0":
    absent("github_cli", "not_attempted", gh_reason)
elif gh_state != "ready":
    absent("github_cli", gh_state, gh_reason)

pr, pr_err = (None, None)
if pr_state == "found":
    pr, pr_err = load_json(os.path.join(W, "pr.json"))
    if pr is None:
        absent("pull_request", "unreadable",
               "gh returned a pull request payload that would not parse (%s)." % pr_err)
        pr_state = "unreadable"
elif pr_state == "none":
    absent("pull_request", "none", os.environ["PZ_PR_REASON"])
elif pr_state == "unavailable":
    absent("pull_request", "unavailable", os.environ["PZ_PR_REASON"])

if isinstance(pr, dict):
    num = pr.get("number")
    signal("pr:%s" % num, "review", "neutral", "github_pr",
           "pull request #%s (%s%s)" % (num, pr.get("state", "?"),
                                        ", draft" if pr.get("isDraft") else ""),
           url=str(pr.get("url") or ""),
           evidence={"number": num, "state": str(pr.get("state") or ""),
                     "draft": bool(pr.get("isDraft")),
                     "head_sha": str(pr.get("headRefOid") or ""),
                     "diff_stat": {"source": "github_pr",
                                   "files_changed": pr.get("changedFiles"),
                                   "insertions": pr.get("additions"),
                                   "deletions": pr.get("deletions")}})

    REVIEW_STATUS = {"APPROVED": "success", "CHANGES_REQUESTED": "failure",
                     "COMMENTED": "neutral", "DISMISSED": "neutral", "PENDING": "pending"}
    reviews = pr.get("reviews") or []
    if not reviews:
        absent("reviews", "none",
               "the pull request exists and carries no review. Unreviewed is not approved.")
    for i, rv in enumerate(reviews):
        if not isinstance(rv, dict):
            continue
        author = ((rv.get("author") or {}).get("login")) or ""
        signal("review:%s" % (rv.get("id") or i), "review",
               REVIEW_STATUS.get(str(rv.get("state") or ""), "neutral"), "github_pr",
               "review %s by %s" % (rv.get("state"), author or "unknown"),
               timestamp=rv.get("submittedAt"), url=str(rv.get("url") or ""), actor=author,
               evidence={"state": str(rv.get("state") or "")})

    comments = pr.get("comments") or []
    if not comments:
        absent("comments", "none", "the pull request carries no comment of any kind.")
    for i, cm in enumerate(comments):
        if not isinstance(cm, dict):
            continue
        author = ((cm.get("author") or {}).get("login")) or ""
        typ = str((cm.get("author") or {}).get("__typename") or "")
        is_bot = typ == "Bot" or author.endswith("[bot]")
        signal("comment:%s" % (cm.get("id") or i),
               "bot_comment" if is_bot else "human_comment", "neutral", "github_pr",
               "comment by %s" % (author or "unknown"),
               timestamp=cm.get("createdAt"), url=str(cm.get("url") or ""), actor=author,
               evidence={"is_bot": is_bot, "body_bytes": len(str(cm.get("body") or ""))})

    ROLLUP = {"SUCCESS": "success", "FAILURE": "failure", "ERROR": "failure",
              "CANCELLED": "failure", "TIMED_OUT": "failure", "ACTION_REQUIRED": "warning",
              "NEUTRAL": "neutral", "SKIPPED": "neutral", "STALE": "warning",
              "PENDING": "pending", "QUEUED": "pending", "IN_PROGRESS": "running",
              "EXPECTED": "pending", "REQUESTED": "pending", "WAITING": "pending"}
    rollup = pr.get("statusCheckRollup") or []
    if not rollup:
        absent("ci", "none",
               "the pull request has no status check attached. No CI ran; that is not a "
               "green CI.")
    for i, ck in enumerate(rollup):
        if not isinstance(ck, dict):
            continue
        raw = str(ck.get("conclusion") or ck.get("state") or ck.get("status") or "").upper()
        name = str(ck.get("name") or ck.get("context") or "check-%d" % i)
        # A deployment context is a different kind of evidence from a test run and
        # is categorised as such, because a score that treats "deployed" as "tested"
        # is exactly the conflation this split exists to prevent.
        cat = "deployment" if "deploy" in name.lower() else "ci"
        signal("ci:%s" % name, cat, ROLLUP.get(raw, "neutral"), "github_checks",
               "%s — %s" % (name, raw or "unknown"),
               timestamp=ck.get("startedAt") or ck.get("completedAt"),
               url=str(ck.get("detailsUrl") or ck.get("targetUrl") or ""),
               evidence={"raw_conclusion": raw,
                         "workflow": str(ck.get("workflowName") or "")})
elif ci_state != "collected":
    absent("ci", ci_state or "unavailable",
           os.environ["PZ_CI_REASON"] or "CI evidence was not collected.")

# --- canonicalise and hash -------------------------------------------------
signals.sort(key=lambda s: (s["category"], s["source"], s["id"]))
absences.sort(key=lambda a: (a["source"], a["state"]))

# The hashed content is exactly the evidence and its declared absences. The
# collection time, the tool versions and the summary counts sit outside it, so
# running this twice one minute apart over an unchanged tree produces the same
# hash. Anything inside this object that moved on its own would make the
# staleness rule fire constantly and therefore mean nothing.
hashed = {"signals": signals, "absences": absences}
canonical = json.dumps(hashed, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
digest = "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()

by_cat, by_status = {}, {}
for s in signals:
    by_cat[s["category"]] = by_cat.get(s["category"], 0) + 1
    by_status[s["status"]] = by_status.get(s["status"], 0) + 1

doc = {
    "schema": "productizer.signals/1",
    "signals_hash": digest,
    "canonical_bytes": len(canonical),
    "sources": {
        "local_checks": {"path": cr_path, "state": "absent" if cr is None else "read"},
        "git": {"state": "repo" if os.environ["PZ_IS_REPO"] == "true" else "not_a_repo",
                "repo": os.environ["PZ_REPO"], "host": os.environ["PZ_HOST"],
                "diff_stat_source": os.environ["PZ_DIFF_SOURCE"]},
        "github_cli": {"state": gh_state, "owner_match": os.environ["PZ_GH_OWNER_MATCH"],
                       "reason": gh_reason},
        "pull_request": {"state": pr_state, "reason": os.environ["PZ_PR_REASON"]},
        "ci": {"state": ci_state, "reason": os.environ["PZ_CI_REASON"]},
    },
    "counts": {"signals": len(signals), "absences": len(absences),
               "by_category": dict(sorted(by_cat.items())),
               "by_status": dict(sorted(by_status.items()))},
    "signals": signals,
    "absences": absences,
}

payload = json.dumps(doc, indent=2, sort_keys=False) + "\n"
out = os.environ["PZ_OUT"]
if out == "-":
    sys.stdout.write(payload)
else:
    d = os.path.dirname(os.path.abspath(out))
    if d:
        os.makedirs(d, exist_ok=True)
    with open(out, "w") as fh:
        fh.write(payload)

e = sys.stderr
e.write("signals: %d observed, %d absences, hash %s\n" % (len(signals), len(absences), digest))
for a in absences:
    e.write("  ABSENT  %-14s %-16s %s\n" % (a["source"], a["state"], a["meaning"]))
PY
