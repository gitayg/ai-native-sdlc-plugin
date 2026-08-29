#!/bin/bash
# score.sh — judgment, computed on top of signals and keyed to their hash.
#
# THE ONE RULE THIS FILE EXISTS TO ENFORCE:
#
#     A SCORE CANNOT OUTLIVE THE EVIDENCE IT WAS COMPUTED FROM.
#
# Every score carries the hash of the exact signal set it was derived from. A
# cached score whose hash no longer matches the current signals is stale and is
# refused — not adjusted, not served with a warning. And a score computed from no
# signals at all is `null`, never 0, because those two mean opposite things: 0 is
# "we looked and it is bad", null is "we did not look".
#
# That second rule is enforced by the wire format rather than by convention. The
# number never appears at the top level of the document. It only exists nested
# inside an object that also carries `signals_hash` and `signal_count`, and the
# emitter refuses to write that object when the count is zero. There is nowhere
# to put a 0 without simultaneously asserting the evidence behind it.
#
# Usage:
#   score.sh --signals PATH|-  [--cache PATH] [--serve-cached] [--out PATH|-]
#
# Exit codes follow the rest of the skill:
#   0  scored, nothing refused
#   3  refused — no signals, a stale cache, a hollow gap, or a failing signal
#   2  bad usage, or a signals document that does not match its own hash
#   1  crashed
set -euo pipefail

export TZ=UTC
export LC_ALL=C

SIGNALS=""
CACHE=""
OUT="-"
SERVE_CACHED=0

usage() {
  cat <<'USAGE'
score.sh — compute judgment from signals, keyed to the signals hash.

  --signals PATH   signals document from signals.sh ("-" for stdin). Required.
  --cache PATH     read/write a hash-keyed cached judgment
  --serve-cached   serve the cached judgment ONLY if its hash matches the signals;
                   refuse (exit 3) otherwise. Never recomputes.
  --out PATH       where to write the score document ("-" for stdout, the default)
  -h, --help       this
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --signals)      [ $# -ge 2 ] || { echo "score: --signals needs a value" >&2; exit 2; }; SIGNALS="$2"; shift 2 ;;
    --cache)        [ $# -ge 2 ] || { echo "score: --cache needs a value" >&2; exit 2; };   CACHE="$2"; shift 2 ;;
    --out)          [ $# -ge 2 ] || { echo "score: --out needs a value" >&2; exit 2; };     OUT="$2"; shift 2 ;;
    --serve-cached) SERVE_CACHED=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "score: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$SIGNALS" ] || { echo "score: --signals is required. There is no scoring without evidence." >&2; usage >&2; exit 2; }
if [ "$SERVE_CACHED" -eq 1 ] && [ -z "$CACHE" ]; then
  echo "score: --serve-cached needs --cache." >&2
  exit 2
fi

if ! command -v python3 >/dev/null; then
  echo "score: python3 is required — it is what re-derives the evidence hash." >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pz-score.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ "$SIGNALS" = "-" ]; then
  cat > "$WORK/signals.json"
  SIGNALS="$WORK/signals.json"
elif [ ! -f "$SIGNALS" ]; then
  echo "score: no signals document at $SIGNALS. Collect evidence before asking for a verdict." >&2
  exit 2
fi

export PZ_SIGNALS="$SIGNALS"
export PZ_CACHE="$CACHE"
export PZ_OUT="$OUT"
export PZ_SERVE_CACHED="$SERVE_CACHED"

set +e
python3 <<'PY'
import hashlib, json, os, sys

def die(code, msg):
    sys.stderr.write("score: %s\n" % msg)
    sys.exit(code)

try:
    with open(os.environ["PZ_SIGNALS"], "r", errors="replace") as fh:
        sig = json.load(fh)
except (ValueError, OSError) as exc:
    die(2, "the signals document would not parse: %s" % exc)

if not isinstance(sig, dict) or sig.get("schema") != "productizer.signals/1":
    die(2, "not a productizer.signals/1 document (schema=%r)." % (
        sig.get("schema") if isinstance(sig, dict) else type(sig).__name__))

signals = sig.get("signals") or []
absences = sig.get("absences") or []

# Re-derive the hash rather than trusting the field. The whole staleness rule
# rests on this number, so a document whose declared hash does not match its own
# content is not evidence with a typo in it — it is a document that has been
# edited after the fact, and it is refused.
canonical = json.dumps({"signals": signals, "absences": absences},
                       sort_keys=True, separators=(",", ":"), ensure_ascii=True)
derived = "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
declared = sig.get("signals_hash")
if declared != derived:
    die(2, "the signals document does not hash to its own declared value.\n"
           "        declared: %s\n        derived:  %s\n"
           "        The content was changed after collection. Re-run signals.sh."
           % (declared, derived))

SIGNALS_HASH = derived

# --- serve-cached: the staleness rule, on its own ---------------------------
def read_cache():
    p = os.environ["PZ_CACHE"]
    if not p or not os.path.exists(p):
        return None, "miss"
    try:
        with open(p, "r", errors="replace") as fh:
            doc = json.load(fh)
    except (ValueError, OSError) as exc:
        return None, "unreadable: %s" % exc
    if doc.get("schema") != "productizer.score.cache/1":
        return None, "not a productizer.score.cache/1 document"
    return doc, ("hit" if doc.get("signals_hash") == SIGNALS_HASH else "stale")

cache_doc, cache_state = (None, "not_used")
if os.environ["PZ_CACHE"]:
    cache_doc, cache_state = read_cache()

def emit(doc, code):
    payload = json.dumps(doc, indent=2) + "\n"
    out = os.environ["PZ_OUT"]
    if out == "-":
        sys.stdout.write(payload)
    else:
        d = os.path.dirname(os.path.abspath(out))
        if d:
            os.makedirs(d, exist_ok=True)
        with open(out, "w") as fh:
            fh.write(payload)
    sys.exit(code)

if os.environ["PZ_SERVE_CACHED"] == "1":
    if cache_state == "hit":
        cache_doc["cache"] = {"state": "hit", "signals_hash": SIGNALS_HASH}
        sys.stderr.write("score: cache HIT — the cached judgment was computed from these exact "
                         "signals (%s).\n" % SIGNALS_HASH)
        emit(cache_doc, 0)
    cached_hash = (cache_doc or {}).get("signals_hash")
    sys.stderr.write(
        "score: REFUSED — cached judgment %s.\n"
        "        cached against: %s\n"
        "        signals now:    %s\n"
        "        A verdict computed from other evidence is not a verdict about this evidence.\n"
        % (cache_state, cached_hash or "(none)", SIGNALS_HASH))
    emit({
        "schema": "productizer.score/1",
        "signals_hash": SIGNALS_HASH,
        "score": None,
        "verdict": "refused",
        "refusal": {
            "reason": "stale_cache" if cache_state == "stale" else "cache_%s" % cache_state,
            "message": "The cached judgment was computed against %s; the signals now hash to "
                       "%s. A cached score is served only against the evidence it was computed "
                       "from." % (cached_hash or "(no cached hash)", SIGNALS_HASH),
            "cached_signals_hash": cached_hash,
            "current_signals_hash": SIGNALS_HASH,
        },
        "cache": {"state": cache_state},
    }, 3)

# --- no evidence: null, never 0 --------------------------------------------
if not signals:
    missing = sorted({a["source"] for a in absences if isinstance(a, dict) and "source" in a})
    reasons = ["%s: %s" % (a.get("source"), a.get("meaning")) for a in absences
               if isinstance(a, dict)]
    msg = ("No signals found. %s" % (
        "Link a PR and wait for CI/reviews first." if not reasons
        else "Missing preconditions: " + "; ".join(missing) + "."))
    sys.stderr.write("score: REFUSED — no signals. The score is null, not 0.\n")
    for r in reasons:
        sys.stderr.write("        precondition: %s\n" % r)
    emit({
        "schema": "productizer.score/1",
        "signals_hash": SIGNALS_HASH,
        "score": None,
        "verdict": "refused",
        "refusal": {
            "reason": "no_signals",
            "message": msg,
            "missing_preconditions": missing,
            "detail": reasons,
        },
        "cache": {"state": cache_state},
    }, 3)

# --- hollow: declared minus observed, as arithmetic -------------------------
#
# The heuristic this replaces was "the check said it would cover N files and its
# exit code was 0, so trust it". Here the two sets are carried on the signal
# itself and the difference is computed. Nothing is inferred from an exit code.
hollow_rows = []
checks_declared, checks_observed = set(), set()
for s in signals:
    ev = s.get("evidence") or {}
    if s.get("source") != "local_checks":
        continue
    cid = s["id"].split(":", 1)[-1]
    checks_declared.add(cid)
    # `not_triggered` counts as OBSERVED: the declaration was evaluated against the
    # change and correctly scoped out, which is a fact, not a hole. `disabled` and
    # `missing_tool` are holes — a check the config declares and that never ran.
    if str(ev.get("runner_status") or "") not in ("disabled", "missing_tool"):
        checks_observed.add(cid)
    dec = set(ev.get("declared_items") or [])
    obs = set(ev.get("observed_items") or [])
    if not dec:
        continue
    missing = sorted(dec - obs)
    extra = sorted(obs - dec)
    row = {
        "check": cid,
        "declared_count": len(dec),
        "observed_count": len(obs),
        "missing_count": len(missing),
        "missing": missing[:200],
        "observed_not_declared": extra[:200],
    }
    # Two independent derivations of the same number: this set difference, and the
    # runner's own scope count. When they disagree the evidence is inconsistent and
    # that is said out loud rather than picked between.
    runner_scope = ev.get("runner_files_in_scope")
    row["runner_files_in_scope"] = runner_scope
    row["reconstruction_agrees"] = (runner_scope is None or runner_scope == len(dec))
    if missing or not row["reconstruction_agrees"]:
        hollow_rows.append(row)

checks_missing = sorted(checks_declared - checks_observed)
hollow_gap = bool(hollow_rows) or bool(checks_missing)

# --- the score --------------------------------------------------------------
WEIGHTS = {"failure": 25, "warning": 10, "pending": 5, "running": 5,
           "success": 0, "neutral": 0}
BANDS = [
    (0, 15, "not_credible", "Not credible — the evidence does not support shipping anything."),
    (16, 30, "poor", "Poor — failing or unexamined in ways that must be fixed, not argued."),
    (31, 50, "weak", "Weak — evidence exists but too much of it is absent or unsettled."),
    (51, 70, "contested", "Contested — real findings or real gaps; a human has to look."),
    (71, 85, "nearly_ready", "Nearly ready — minor gaps, nothing blocking on the evidence."),
    (86, 100, "ready", "Ready — every declared check ran, covered what it declared, and found nothing."),
]

deductions = []
raw = 100
for s in signals:
    w = WEIGHTS.get(s["status"], 10)
    if w:
        raw -= w
        deductions.append({"signal": s["id"], "status": s["status"], "points": w,
                           "why": s["title"]})
for row in hollow_rows:
    raw -= 20
    deductions.append({"signal": "hollow:%s" % row["check"], "status": "hollow", "points": 20,
                       "why": "declared %d items, examined %d, %d never looked at"
                              % (row["declared_count"], row["observed_count"],
                                 row["missing_count"])})
for cid in checks_missing:
    raw -= 20
    deductions.append({"signal": "hollow:%s" % cid, "status": "hollow", "points": 20,
                       "why": "declared by the config and never run"})
# An absence is not a finding, and deducting points for it was the wrong shape: a
# repo with no remote and no CI would shave a few points off 100 and still land in
# a reassuring band. Absence CAPS the verdict instead. Each missing anchor sets a
# ceiling the evidence cannot see past, and the score is the lower of what the
# signals earned and what the available evidence can support. That is the whole
# reason to have a PR/CI anchor: without one, a high number is not available at
# all, however clean the local run looked.
ANCHORS = [
    ("local_checks", 50, "no local checks result: nothing on this machine verified anything",
     lambda: any(x["source"] == "local_checks" for x in signals)),
    ("pull_request", 60, "no pull request: the change has not been proposed anywhere",
     lambda: any(x["id"].startswith("pr:") for x in signals)),
    ("ci", 60, "no upstream CI status: nothing built or tested this change off this machine",
     lambda: any(x["source"] == "github_checks" for x in signals)),
    ("review", 70, "no review of any kind: unreviewed is not approved",
     lambda: any(x["category"] == "review" and not x["id"].startswith("pr:") for x in signals)),
]
ceiling = 100
ceiling_reasons = []
for name, cap, why, present in ANCHORS:
    if not present():
        ceiling = min(ceiling, cap)
        ceiling_reasons.append({"anchor": name, "ceiling": cap, "why": why})

value = max(0, min(100, raw, ceiling))
band, band_label = "not_credible", BANDS[0][2]
for lo, hi, name, label in BANDS:
    if lo <= value <= hi:
        band, band_label = name, label
        break

failures = [s["id"] for s in signals if s["status"] == "failure"]

# The structural guarantee, asserted rather than assumed. If this ever fails the
# process dies instead of emitting a number with nothing behind it.
if not signals:
    die(1, "unreachable: a score object was about to be built from zero signals.")

score_obj = {
    "value": value,
    "scale": {"min": 0, "max": 100, "polarity": "higher_is_better"},
    "band": band,
    "band_label": band_label,
    "signals_hash": SIGNALS_HASH,
    "signal_count": len(signals),
    "raw": max(0, min(100, raw)),
    "ceiling": ceiling,
    "ceiling_reasons": ceiling_reasons,
    "capped_by_absence": value < max(0, min(100, raw)),
    "deductions": deductions,
}
assert score_obj["signal_count"] >= 1 and score_obj["signals_hash"], score_obj

refusal = None
code = 0
if hollow_gap:
    refusal = {
        "reason": "hollow_gap",
        "message": "A check declared more than it examined. The gap is a set difference, "
                   "not an opinion: %s." % "; ".join(
            "%s declared %d, examined %d, never looked at %d (%s%s)"
            % (r["check"], r["declared_count"], r["observed_count"], r["missing_count"],
               ", ".join(r["missing"][:5]), ", ..." if r["missing_count"] > 5 else "")
            for r in hollow_rows) if hollow_rows else
                   "checks declared by the config that produced no observation: %s."
                   % ", ".join(checks_missing),
    }
    code = 3
elif failures:
    refusal = {"reason": "signal_failure",
               "message": "failing signals: %s" % ", ".join(failures)}
    code = 3

doc = {
    "schema": "productizer.score/1",
    "signals_hash": SIGNALS_HASH,
    "score": score_obj,
    "verdict": "refused" if refusal else "scored",
    "refusal": refusal,
    "hollow": {
        "gap": hollow_gap,
        "checks_declared": sorted(checks_declared),
        "checks_observed": sorted(checks_observed),
        "checks_missing": checks_missing,
        "coverage": hollow_rows,
    },
    "counts": sig.get("counts"),
    "cache": {"state": cache_state},
}

if os.environ["PZ_CACHE"]:
    cache_path = os.environ["PZ_CACHE"]
    d = os.path.dirname(os.path.abspath(cache_path))
    if d:
        os.makedirs(d, exist_ok=True)
    with open(cache_path, "w") as fh:
        fh.write(json.dumps({
            "schema": "productizer.score.cache/1",
            "signals_hash": SIGNALS_HASH,
            "score": score_obj,
            "verdict": doc["verdict"],
            "refusal": refusal,
            "hollow": doc["hollow"],
        }, indent=2) + "\n")

e = sys.stderr
e.write("score: %s  value=%d  band=%s  (earned %d, ceiling %d)  signals=%d  hash=%s  cache=%s\n"
        % (doc["verdict"].upper(), value, band, max(0, min(100, raw)), ceiling,
           len(signals), SIGNALS_HASH, cache_state))
for cr in ceiling_reasons:
    e.write("  CEILING %-14s <= %-3d %s\n" % (cr["anchor"], cr["ceiling"], cr["why"]))
for cid in checks_missing:
    e.write("  HOLLOW  %-20s declared by the config, never observed\n" % cid)
for r in hollow_rows:
    e.write("  HOLLOW  %-20s declared %d, examined %d, %d never looked at: %s%s\n"
            % (r["check"], r["declared_count"], r["observed_count"], r["missing_count"],
               ", ".join(r["missing"][:5]), ", ..." if r["missing_count"] > 5 else ""))
    if not r["reconstruction_agrees"]:
        e.write("          the runner reported %s files in scope; the declared set holds %d. "
                "Inconsistent evidence.\n" % (r["runner_files_in_scope"], r["declared_count"]))
emit(doc, code)
PY
RC=$?
set -e
exit "$RC"
