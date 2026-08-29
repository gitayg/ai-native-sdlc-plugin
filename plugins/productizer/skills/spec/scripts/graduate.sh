#!/usr/bin/env bash
# scripts/graduate.sh — harvest repeated corrections, cluster them, promote them.
#
# A correction is a human telling the agent it got something wrong. Corrections
# are the cheapest signal a repo produces and the one it throws away fastest:
# they live in a transcript nobody reads again. This walks them up a ladder.
#
#   graduate.sh lexicon                  print the two lexicons and the thresholds
#   graduate.sh harvest  [opts]          scan sources, write corrections.jsonl
#   graduate.sh present  [opts]          cluster, threshold, draft ops, print cards
#   graduate.sh excerpts --id TAG        the raw messages behind one cluster
#   graduate.sh apply    --id TAG --decide accept
#   graduate.sh undo     --id TAG
#
#   --root DIR         repo the guidance is promoted into. Default "."
#   --work DIR         where harvest/draft/journal state lives.
#                      Default <root>/.claude/productizer/graduation
#   --transcripts DIR  root of Claude Code project transcripts.
#                      Default $CLAUDE_TRANSCRIPTS, else ~/.claude/projects
#   --source LIST      comma list of transcripts,pr. Default transcripts
#   --refresh-context  re-run detect-context.sh instead of using the cached probe
#
# THE HUMAN DECIDES. There is no auto-apply flag, defaulted on or otherwise.
# `present` writes nothing outside --work. `apply` refuses without an explicit
# `--decide accept` naming one cluster.
#
# Counting is by DISTINCT CONVERSATION, not by message. Ten repeats in one
# session is one lesson badly received; three across three sessions is a rule.
# The promotion threshold is 3 distinct conversations. That number is here, in
# THRESHOLD_CONVERSATIONS, and nowhere else.
#
# The ladder is prose -> skill -> hook -> ci-gate. Instructions are advisory and
# decay as the context window fills; checks are deterministic and never tire. A
# cluster climbs as high as its evidence justifies and no higher — the rung is
# recommended, printed, and never silently taken.
#
# Clustering is a lexicon, not a model. Every grouping decision is a named
# regex you can read in `graduate.sh lexicon`. A correction that matches no
# topic tag is not guessed at and not dropped: it lands in UNDECIDED and is
# escalated to the human as its own card.
#
# Apply is all-or-nothing and precondition-checked. A create must not already
# exist; an update or remove must match the target file exactly as it was when
# the suggestion was drafted. On any mismatch nothing is written at all and the
# suggestion is flagged, rather than silently clobbering your work. Undo
# restores prior contents, and only if the file still matches what was written.
#
# What this cannot do: it extends a lexicon from corrections people actually
# made. It trains nothing, and it produces precision data only — the corrections
# that WERE voiced. It has no view of the ones nobody bothered to voice, so it
# cannot close a recall gap. See references/graduation.md.
#
# Exit: 0  did the thing
#       2  usage
#       3  no source was available at all — nothing was scanned
#       4  sources were present but nothing in them would parse
#       5  sources parsed, and zero messages were corrections (a measured zero)
#       6  corrections found, none reached the conversation threshold
#       7  apply refused: a precondition failed. NOTHING was written.
#       8  undo refused: a file no longer matches what apply wrote.
set -euo pipefail

export TZ=UTC
export LC_ALL=C

THRESHOLD_CONVERSATIONS=3
RUNG_SCORE_SKILL=12
RUNG_SCORE_HOOK=36
RUNG_SCORE_GATE=72

die_usage() { printf 'graduate: %s\n' "$1" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$HERE/detect-context.sh"

[ $# -gt 0 ] || die_usage "no subcommand. One of: lexicon, harvest, present, excerpts, apply, undo."

CMD=""
case "$1" in
  lexicon|harvest|present|excerpts|apply|undo) CMD="$1"; shift ;;
  -h|--help) sed -n '2,58p' "$0"; exit 0 ;;
  -*) die_usage "unknown option before the subcommand: $1" ;;
  *)  die_usage "unknown subcommand: $1" ;;
esac

ROOT=""
WORK=""
TRANSCRIPTS=""
SOURCES="transcripts"
ID=""
DECIDE=""
REFRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)         [ $# -ge 2 ] || die_usage "--root needs a directory";       ROOT="$2"; shift 2 ;;
    --root=*)       ROOT="${1#--root=}"; shift ;;
    --work)         [ $# -ge 2 ] || die_usage "--work needs a directory";       WORK="$2"; shift 2 ;;
    --work=*)       WORK="${1#--work=}"; shift ;;
    --transcripts)  [ $# -ge 2 ] || die_usage "--transcripts needs a directory"; TRANSCRIPTS="$2"; shift 2 ;;
    --transcripts=*) TRANSCRIPTS="${1#--transcripts=}"; shift ;;
    --source)       [ $# -ge 2 ] || die_usage "--source needs a list";          SOURCES="$2"; shift 2 ;;
    --source=*)     SOURCES="${1#--source=}"; shift ;;
    --id)           [ $# -ge 2 ] || die_usage "--id needs a cluster id";        ID="$2"; shift 2 ;;
    --id=*)         ID="${1#--id=}"; shift ;;
    --decide)       [ $# -ge 2 ] || die_usage "--decide needs a decision";      DECIDE="$2"; shift 2 ;;
    --decide=*)     DECIDE="${1#--decide=}"; shift ;;
    --refresh-context) REFRESH=1; shift ;;
    -h|--help)      sed -n '2,58p' "$0"; exit 0 ;;
    -*)             die_usage "unknown option: $1" ;;
    *)              die_usage "unexpected argument: $1" ;;
  esac
done

command -v python3 >/dev/null 2>&1 ||
  die_usage "python3 is not on PATH. Refusing rather than half-parsing transcripts with awk."

[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

[ -n "$WORK" ] || WORK="$ROOT/.claude/productizer/graduation"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

if [ -z "$TRANSCRIPTS" ]; then
  TRANSCRIPTS="${CLAUDE_TRANSCRIPTS:-$HOME/.claude/projects}"
fi

# --- the lexicons ------------------------------------------------------------
# Both are data, printed by `graduate.sh lexicon`, and every clustering decision
# this script makes is traceable to one line of them. That is the whole point:
# an opaque similarity score would group better and be unarguable, which is the
# wrong trade for a tool whose output a human has to rule on.
#
# CUE decides whether a message is a correction at all.
# TOPIC decides which cluster it joins, and whether that cluster is the kind of
# thing a deterministic check could ever assert.
LEXICON_PY='
CUES = [
    ("negation",     r"^\s*(no|nope|not quite|wrong)\b|\b(that\x27s|thats|this is) (not|wrong)\b"),
    ("prohibition",  r"\b(don\x27t|do not|never|stop)\b"),
    ("repetition",   r"\b(again|as i said|i said|i already|i told you|like i told you)\b"),
    ("wrongness",    r"\b(wrong|incorrect|broken|you broke|that\x27s a bug)\b"),
    ("undo",         r"\b(revert|undo|roll it back|roll back|back out)\b"),
    ("redirection",  r"\b(instead|actually|rather than|should have|was supposed to)\b"),
    ("omission",     r"\b(you forgot|you missed|you didn\x27t|you did not|still missing|you skipped)\b"),
]

# checkable = a deterministic check could assert this. Only checkable clusters
# are allowed to reach the hook or ci-gate rungs; everything else caps at skill,
# because a gate that cannot be written is not a gate, it is a promise.
TOPICS = [
    ("run-tests",             r"\brun (the )?(unit |integration )?tests?\b|\btest suite\b|\bwithout running the tests\b", True,
     "asked agents to run the tests before saying a change was ready"),
    ("no-stderr-suppression", r"2>\s*/dev/null|\bsuppress(ing|ed)? stderr\b|\bswallow(ing|ed)? (the )?errors?\b", True,
     "told agents not to suppress stderr"),
    ("absolute-paths",        r"\babsolute paths?\b|\brelative path\b", True,
     "asked for absolute paths"),
    ("no-blind-staging",      r"\bgit add -A\b|\bgit add \.\b|\bstage (the )?(specific )?files by name\b", True,
     "told agents to stage files by name instead of staging everything"),
    ("version-bump",          r"\bbump (the )?version\b|\bversion (number|bump)\b|\bforgot to bump\b", True,
     "asked for the version to be bumped before the commit"),
    ("update-docs",           r"\breadme\b|\bchangelog\b|\bupdate (the )?docs?\b|\bdocumentation\b", True,
     "asked for the docs to be updated in the same change"),
    ("no-emoji",              r"\bemoji(s)?\b", True,
     "asked agents not to use emoji"),
    ("file-ownership",        r"\bdon\x27t touch\b|\boff.limits\b|\bnever (modify|edit|touch)\b|\byou own only\b", True,
     "told agents to stay inside the files they own"),
    ("verify-before-claiming", r"\bsee it fail\b|\bprove it\b|\bverbatim\b|\bdon\x27t (just )?(claim|assume)\b|\bevidence\b", False,
     "asked agents to show evidence instead of asserting a result"),
    ("scope-discipline",      r"\bout of scope\b|\bdidn\x27t ask\b|\bdid not ask\b|\bonly what (i|we) asked\b|\bstop adding\b", False,
     "asked agents not to go beyond what was asked"),
]
'

# --- shared python preamble --------------------------------------------------
COMMON_PY='
import hashlib, json, os, re, sys

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()

def load_jsonl(path):
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            out.append(json.loads(line))
    return out
'

case "$CMD" in

lexicon)
  python3 -c "$LEXICON_PY"'
print("promotion threshold: %d distinct conversations" % '"$THRESHOLD_CONVERSATIONS"')
print("rung bands by score (signals x conversations x pain):")
print("  score <  %d          prose" % '"$RUNG_SCORE_SKILL"')
print("  score <  %d          skill" % '"$RUNG_SCORE_HOOK"')
print("  score <  %d          hook      (checkable clusters only)" % '"$RUNG_SCORE_GATE"')
print("  score >= %d          ci-gate   (checkable clusters only)" % '"$RUNG_SCORE_GATE"')
print("  a cluster that is not checkable is capped at skill, whatever its score")
print("")
print("CUE lexicon - decides whether a message is a correction")
# The lexicon is only inspectable if it prints as the pattern it is, so the
# apostrophe escape the shell needed is undone for display.
def show(rx):
    return rx.replace(chr(92) + "x27", chr(39))
for name, rx in CUES:
    print("  %-16s %s" % (name, show(rx)))
print("")
print("TOPIC lexicon - decides which cluster it joins")
for tag, rx, checkable, summary in TOPICS:
    print("  %-24s checkable=%-5s %s" % (tag, checkable, show(rx)))
    print("  %-24s summary: you %s" % ("", summary))
'
  ;;

harvest)
  # detect-context.sh already probes this repo for git, gh and config. Re-deriving
  # any of that here would be a second copy that disagrees with the first the day
  # someone edits one of them.
  CTX="$WORK/context.json"
  if [ ! -f "$CTX" ] || [ "$REFRESH" -eq 1 ]; then
    if [ -x "$DETECT" ] || [ -f "$DETECT" ]; then
      ( cd "$ROOT" && bash "$DETECT" ) > "$CTX.tmp"
      mv "$CTX.tmp" "$CTX"
    else
      printf 'graduate: detect-context.sh not found at %s\n' "$DETECT" >&2
      printf 'graduate: the harvest will not know what this repo is bound to.\n' >&2
      printf '{"detect_context":"missing"}\n' > "$CTX"
    fi
  fi

  python3 -c "$COMMON_PY$LEXICON_PY"'
transcripts_root = sys.argv[1]
sources         = [s for s in sys.argv[2].split(",") if s]
work            = sys.argv[3]
ctx_path        = sys.argv[4]

try:
    ctx = json.load(open(ctx_path))
except Exception:
    ctx = {"detect_context": "unparseable"}

cue_res   = [(n, re.compile(rx, re.I)) for n, rx in CUES]
topic_res = [(t, re.compile(rx, re.I), c, s) for t, rx, c, s in TOPICS]

# A brief is not a correction. The cap is a length, stated, not a judgement:
# a 4000-character message that happens to contain "don\x27t" is a task
# description, and letting it in poisons every cluster it touches.
MAX_CORRECTION_CHARS = 1200

report = {"sources": {}, "files_seen": 0, "files_unparseable": 0,
          "conversations_seen": 0, "messages_seen": 0, "corrections": 0}
records = []

def user_texts(obj):
    m = obj.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return [c]
    out = []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                out.append(b.get("text") or "")
    return out

if "transcripts" in sources:
    if not os.path.isdir(transcripts_root):
        report["sources"]["transcripts"] = {"state": "absent",
            "detail": "no such directory: %s" % transcripts_root}
    else:
        files = []
        for dirpath, dirnames, filenames in os.walk(transcripts_root):
            dirnames.sort()
            for fn in sorted(filenames):
                if fn.endswith(".jsonl"):
                    files.append(os.path.join(dirpath, fn))
        files.sort()
        if not files:
            report["sources"]["transcripts"] = {"state": "empty",
                "detail": "directory exists, contains no .jsonl transcripts"}
        else:
            convs = set()
            parsed_any = False
            for path in files:
                report["files_seen"] += 1
                try:
                    objs = load_jsonl(path)
                except Exception as e:
                    report["files_unparseable"] += 1
                    continue
                parsed_any = True
                seen_assistant = False
                for lineno, obj in enumerate(objs, 1):
                    if not isinstance(obj, dict):
                        continue
                    conv = obj.get("sessionId") or path
                    convs.add(conv)
                    if obj.get("type") == "assistant":
                        seen_assistant = True
                        continue
                    if obj.get("type") != "user":
                        continue
                    for text in user_texts(obj):
                        report["messages_seen"] += 1
                        # A correction is a reply to something the agent did.
                        # The first message of a session is the task.
                        if not seen_assistant:
                            continue
                        if not text or len(text) > MAX_CORRECTION_CHARS:
                            continue
                        if "<system-reminder>" in text or "<command-name>" in text:
                            continue
                        cues = sorted(n for n, rx in cue_res if rx.search(text))
                        if not cues:
                            continue
                        tags = sorted(t for t, rx, c, s in topic_res if rx.search(text))
                        report["corrections"] += 1
                        records.append({
                            "conversation": conv,
                            "source": "transcripts",
                            "ts": obj.get("timestamp") or "",
                            "cues": cues,
                            "tags": tags or ["UNDECIDED"],
                            "excerpt": " ".join(text.split())[:300],
                            "file": path,
                            "line": lineno,
                        })
            report["conversations_seen"] = len(convs)
            report["sources"]["transcripts"] = {
                "state": "read" if parsed_any else "unparseable",
                "detail": "%d file(s), %d unparseable" % (report["files_seen"], report["files_unparseable"]),
                "root": transcripts_root}

if "pr" in sources:
    # Never faked. gh state comes from detect-context.sh, not from a second probe.
    gh = (ctx.get("github_cli") or {}).get("state", "unknown")
    report["sources"]["pr"] = {"state": "unavailable",
        "detail": "detect-context.sh reports gh state=%s; PR review comments were NOT read" % gh}

records.sort(key=lambda r: (r["file"], r["line"]))
with open(os.path.join(work, "corrections.jsonl"), "w", encoding="utf-8") as fh:
    for r in records:
        fh.write(json.dumps(r, sort_keys=True) + "\n")
with open(os.path.join(work, "harvest.json"), "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2, sort_keys=True)

for name, s in sorted(report["sources"].items()):
    print("source %-12s %-12s %s" % (name, s["state"], s.get("detail", "")))

states = [s["state"] for s in report["sources"].values()]
# Four different nothings, and they lead to four different actions. Collapsing
# any of them into "0 corrections found" reads as "nothing to learn", which is a
# claim about the repo rather than a report about the scan.
if not states or all(st == "absent" for st in states):
    print("")
    print("NO SOURCE WAS AVAILABLE. Nothing was scanned, so nothing is known about")
    print("this repo\x27s corrections. Not a zero - a scan that did not happen.")
    sys.exit(3)
if all(st in ("absent", "empty") for st in states):
    print("")
    print("NO TRANSCRIPTS. The source directory exists and holds no transcript, so")
    print("there was nothing to read. Not a zero - an empty shelf.")
    sys.exit(3)
if all(st in ("absent", "empty", "unparseable") for st in states):
    print("")
    print("NOTHING PARSEABLE. %d file(s) seen, %d would not parse. No correction"
          % (report["files_seen"], report["files_unparseable"]))
    print("count is reported, because none was measured.")
    sys.exit(4)

print("")
print("scanned    %d message(s) across %d conversation(s) in %d file(s)"
      % (report["messages_seen"], report["conversations_seen"], report["files_seen"]))
print("harvested  %d correction(s)" % report["corrections"])
if report["corrections"] == 0:
    print("")
    print("A MEASURED ZERO. The sources were read and no message matched the cue")
    print("lexicon. That is a real answer about these transcripts, not a missing one.")
    sys.exit(5)
' "$TRANSCRIPTS" "$SOURCES" "$WORK" "$WORK/context.json"
  ;;

present)
  [ -f "$WORK/corrections.jsonl" ] || die_usage "no harvest in $WORK. Run: graduate.sh harvest --work $WORK"

  python3 -c "$COMMON_PY$LEXICON_PY"'
import difflib, datetime
work      = sys.argv[1]
root      = sys.argv[2]
threshold = int(sys.argv[3])
b_skill   = int(sys.argv[4])
b_hook    = int(sys.argv[5])
b_gate    = int(sys.argv[6])

recs = load_jsonl(os.path.join(work, "corrections.jsonl"))
meta = {t: (c, s) for t, rx, c, s in TOPICS}

clusters = {}
for r in recs:
    for tag in r["tags"]:
        cl = clusters.setdefault(tag, {"tag": tag, "recs": []})
        cl["recs"].append(r)

rows = []
for tag, cl in clusters.items():
    per_conv = {}
    cues = set()
    for r in cl["recs"]:
        per_conv[r["conversation"]] = per_conv.get(r["conversation"], 0) + 1
        cues.update(r["cues"])
    conversations = len(per_conv)
    occurrences = len(cl["recs"])
    # Pain is how many times one person had to say it inside a single
    # conversation. Repeating yourself is the friction; it is not evidence of
    # breadth, which is what conversations counts, so the two never merge.
    pain = min(3, max(per_conv.values()))
    signals = len(cues)
    score = signals * conversations * pain
    checkable, summary = meta.get(tag, (False, None))
    if score < b_skill:      rung = "prose"
    elif score < b_hook:     rung = "skill"
    elif score < b_gate:     rung = "hook"
    else:                    rung = "ci-gate"
    if not checkable and rung in ("hook", "ci-gate"):
        rung = "skill"
        capped = True
    else:
        capped = False
    rows.append({"tag": tag, "conversations": conversations, "occurrences": occurrences,
                 "pain": pain, "signals": signals, "score": score, "rung": rung,
                 "capped": capped, "checkable": checkable, "summary": summary,
                 "cues": sorted(cues), "per_conv": per_conv})

rows.sort(key=lambda r: (-r["score"], r["tag"]))
promoted = [r for r in rows if r["conversations"] >= threshold and r["tag"] != "UNDECIDED"]
held     = [r for r in rows if r["conversations"] <  threshold and r["tag"] != "UNDECIDED"]
undecided = [r for r in rows if r["tag"] == "UNDECIDED"]

# --- draft the operations ----------------------------------------------------
def read_bytes(p):
    with open(p, "rb") as fh:
        return fh.read()

GUIDE_DIR = ".claude/productizer/graduated"

def ops_for(row):
    tag = row["tag"]
    sentence = "In %d conversation%s, you %s." % (
        row["conversations"], "" if row["conversations"] == 1 else "s", row["summary"])
    ops = []
    if row["rung"] == "prose":
        path = "CLAUDE.md"
        block = "\n## Graduated corrections\n\n- **%s** — %s (evidence: %d conversations, rung prose)\n" % (
            tag, row["summary"], row["conversations"])
        ops.append(("update-or-create", path, block, "append"))
    elif row["rung"] == "skill":
        path = "%s/%s.md" % (GUIDE_DIR, tag)
        body = ("# %s\n\n%s\n\nEvidence: %d conversations, %d occurrences, %d cue type(s), pain %d.\n"
                "Rung: skill. Promoted by scripts/graduate.sh.\n" % (
                    tag, sentence, row["conversations"], row["occurrences"], row["signals"], row["pain"]))
        ops.append(("create", path, body, "whole"))
    elif row["rung"] == "hook":
        path = ".claude/hooks/graduated-%s.sh" % tag
        body = ("#!/usr/bin/env bash\n# Graduated from %d conversations by scripts/graduate.sh.\n"
                "# %s\n#\n"
                "# THIS IS A STUB AND IT DOES NOT ASSERT ANYTHING YET. The lexicon knows the\n"
                "# cluster is the kind of thing a check could assert; it cannot write the\n"
                "# assertion. Replace the exit 0 below with the real test, or drop the rung\n"
                "# back to skill. A hook that always passes is worse than no hook.\n"
                "set -euo pipefail\nexit 0\n" % (row["conversations"], sentence))
        ops.append(("create", path, body, "whole"))
    else:
        path = ".claude/productizer/checks.yaml"
        block = ("\n  - id: graduated-%s\n    # %s\n    # STUB: no command yet. Fill `run:` or this check asserts nothing.\n"
                 "    run: \"\"\n    severity: blocking\n" % (tag, sentence))
        ops.append(("update-or-create", path, block, "append"))
    return sentence, ops

def resolve(op, path, payload, mode):
    ap = os.path.join(root, path)
    exists = os.path.exists(ap)
    if op == "update-or-create":
        op = "update" if exists else "create"
    before = read_bytes(ap) if exists else b""
    if op == "create":
        after = payload.encode("utf-8")
    elif op == "remove":
        after = b""
    else:
        after = before + payload.encode("utf-8") if mode == "append" else payload.encode("utf-8")
    return {"op": op, "path": path, "exists": exists,
            "before_sha256": sha256_bytes(before) if exists else None,
            "after_sha256": sha256_bytes(after) if op != "remove" else None,
            "after_b64": None if op == "remove" else __import__("base64").b64encode(after).decode(),
            "before_preview": before.decode("utf-8", "replace"),
            "after_preview": "" if op == "remove" else after.decode("utf-8", "replace")}

suggestions = {}
for row in promoted:
    sentence, raw = ops_for(row)
    resolved = []
    bad = None
    for op, path, payload, mode in raw:
        r = resolve(op, path, payload, mode)
        if r["op"] == "create" and r["exists"]:
            bad = "create target already exists: %s" % path
        resolved.append(r)
    suggestions[row["tag"]] = {"tag": row["tag"], "rung": row["rung"], "sentence": sentence,
                               "evidence": {k: row[k] for k in
                                            ("conversations", "occurrences", "pain", "signals", "score",
                                             "checkable", "capped", "cues")},
                               "ops": resolved, "blocked": bad}

# --- prune -------------------------------------------------------------------
# A guidance file whose cluster no longer appears in the window is a candidate
# for removal. It is a candidate and nothing more: absence in this window is not
# proof the lesson stopped mattering, so it is presented, never auto-removed.
prune_ops = []
gd = os.path.join(root, GUIDE_DIR)
live = {r["tag"] for r in rows}
if os.path.isdir(gd):
    for fn in sorted(os.listdir(gd)):
        if not fn.endswith(".md"):
            continue
        tag = fn[:-3]
        if tag not in live:
            prune_ops.append(resolve("remove", "%s/%s" % (GUIDE_DIR, fn), "", "whole"))
if prune_ops:
    suggestions["prune"] = {"tag": "prune", "rung": "n/a",
        "sentence": "%d graduated guidance file(s) had no correction in this window." % len(prune_ops),
        "evidence": {"conversations": 0, "occurrences": 0, "pain": 0, "signals": 0,
                     "score": 0, "checkable": False, "capped": False, "cues": []},
        "ops": prune_ops, "blocked": None}

with open(os.path.join(work, "suggestions.json"), "w", encoding="utf-8") as fh:
    json.dump({"drafted_utc": datetime.datetime.now(datetime.timezone.utc)
                                 .strftime("%Y-%m-%dT%H:%M:%SZ"),
               "root": root, "threshold_conversations": threshold,
               "suggestions": suggestions}, fh, indent=2, sort_keys=True)

# --- present -----------------------------------------------------------------
MARK = {"create": "+", "update": "~", "remove": "−"}

def card(row, sug):
    print("")
    print("=" * 74)
    print("  %s   [%d conversations]" % (row["tag"], row["conversations"]))
    print("=" * 74)
    print("  %s" % sug["sentence"])
    print("")
    print("  evidence  %d conversations / %d occurrences / %d cue type(s) / pain %d"
          % (row["conversations"], row["occurrences"], row["signals"], row["pain"]))
    print("            score = signals x conversations x pain = %d x %d x %d = %d"
          % (row["signals"], row["conversations"], row["pain"], row["score"]))
    print("            cues: %s" % ", ".join(row["cues"]))
    print("  rung      %s%s" % (row["rung"],
          "   (capped at skill: this cluster is not mechanically checkable)" if row["capped"] else ""))
    print("  ladder    prose -> skill -> hook -> ci-gate   (recommended, not taken)")
    print("")
    for r in sug["ops"]:
        print("  %s %s" % (MARK[r["op"]], r["path"]))
    for r in sug["ops"]:
        print("")
        d = list(difflib.unified_diff(
            r["before_preview"].splitlines(True), r["after_preview"].splitlines(True),
            fromfile="a/" + r["path"], tofile="b/" + r["path"], n=2))
        for line in d[:60]:
            print("    " + line.rstrip("\n"))
        if len(d) > 60:
            print("    ... %d more diff line(s)" % (len(d) - 60))
    if sug["blocked"]:
        print("")
        print("  BLOCKED: %s" % sug["blocked"])
    print("")
    print("  excerpts  scripts/graduate.sh excerpts --id %s" % row["tag"])
    print("  accept    scripts/graduate.sh apply --id %s --decide accept" % row["tag"])

print("Corrections harvested: %d. Threshold: %d distinct conversations."
      % (len(recs), threshold))
print("")
print("  %-24s %5s %5s %5s %5s  %s" % ("cluster", "conv", "occ", "pain", "score", "rung"))
for r in rows:
    state = "" if r["conversations"] >= threshold else "  (below threshold)"
    print("  %-24s %5d %5d %5d %5d  %s%s"
          % (r["tag"], r["conversations"], r["occurrences"], r["pain"], r["score"],
             r["rung"] if r["conversations"] >= threshold else "-", state))

for row in promoted:
    card(row, suggestions[row["tag"]])

if "prune" in suggestions:
    s = suggestions["prune"]
    print("")
    print("=" * 74)
    print("  prune   [no evidence in this window]")
    print("=" * 74)
    print("  %s" % s["sentence"])
    print("  Absence in one window is not proof the lesson stopped mattering.")
    for r in s["ops"]:
        print("  %s %s" % (MARK[r["op"]], r["path"]))
    print("  accept    scripts/graduate.sh apply --id prune --decide accept")

if undecided:
    u = undecided[0]
    print("")
    print("=" * 74)
    print("  UNDECIDED   [%d conversations, %d message(s)]" % (u["conversations"], u["occurrences"]))
    print("=" * 74)
    print("  These read as corrections and matched no topic in the lexicon. They are")
    print("  not guessed at and not dropped. Either they belong to a cluster the")
    print("  lexicon does not have yet, or they are not corrections and the cue")
    print("  lexicon is too wide. Only you can say which.")
    print("  excerpts  scripts/graduate.sh excerpts --id UNDECIDED")

print("")
if not promoted:
    print("NOTHING REACHED THE THRESHOLD. %d cluster(s) exist; none appeared in %d or"
          % (len(held), threshold))
    print("more distinct conversations. Repeats inside one conversation do not count.")
    sys.exit(6)
print("%d cluster(s) reached the threshold. Nothing has been written outside %s."
      % (len(promoted), work))
print("Apply requires you to name one and decide: --id TAG --decide accept")
' "$WORK" "$ROOT" "$THRESHOLD_CONVERSATIONS" "$RUNG_SCORE_SKILL" "$RUNG_SCORE_HOOK" "$RUNG_SCORE_GATE"
  ;;

excerpts)
  [ -n "$ID" ] || die_usage "excerpts needs --id TAG"
  [ -f "$WORK/corrections.jsonl" ] || die_usage "no harvest in $WORK"
  python3 -c "$COMMON_PY"'
work = sys.argv[1]; tag = sys.argv[2]
recs = [r for r in load_jsonl(os.path.join(work, "corrections.jsonl")) if tag in r["tags"]]
if not recs:
    print("No harvested correction carries the tag %s." % tag)
    print("That is a measured absence in this harvest, not a claim the tag is wrong.")
    sys.exit(0)
by_conv = {}
for r in recs:
    by_conv.setdefault(r["conversation"], []).append(r)
print("%s - %d message(s) across %d conversation(s)" % (tag, len(recs), len(by_conv)))
for conv in sorted(by_conv):
    print("")
    print("  conversation %s   (%d message(s))" % (conv, len(by_conv[conv])))
    for r in sorted(by_conv[conv], key=lambda x: (x["file"], x["line"])):
        print("    %s:%d  [%s]" % (r["file"], r["line"], ",".join(r["cues"])))
        print("      %s" % r["excerpt"])
' "$WORK" "$ID"
  ;;

apply)
  [ -n "$ID" ] || die_usage "apply needs --id TAG naming one cluster"
  [ "$DECIDE" = "accept" ] || die_usage \
    "apply needs --decide accept. This script never applies a change on its own; there is no auto-apply flag."
  [ -f "$WORK/suggestions.json" ] || die_usage "no draft in $WORK. Run: graduate.sh present --work $WORK"
  mkdir -p "$WORK/undo"

  python3 -c "$COMMON_PY"'
import base64, datetime, shutil
work = sys.argv[1]; root = sys.argv[2]; tag = sys.argv[3]

draft = json.load(open(os.path.join(work, "suggestions.json")))
sug = draft["suggestions"].get(tag)
if sug is None:
    print("graduate: no drafted suggestion with id %s. Known: %s"
          % (tag, ", ".join(sorted(draft["suggestions"]))), file=sys.stderr)
    sys.exit(2)

# --- preconditions, ALL of them, before ANY write ----------------------------
# The suggestion was drafted against a snapshot of these files. If any of them
# moved since, the diff a human approved is not the diff that would land. So the
# whole suggestion is refused and flagged rather than silently clobbering work.
failures = []
for r in sug["ops"]:
    ap = os.path.join(root, r["path"])
    exists = os.path.exists(ap)
    if r["op"] == "create":
        if exists:
            failures.append("%s: create target already exists" % r["path"])
    else:
        if not exists:
            failures.append("%s: target is gone since the suggestion was drafted" % r["path"])
            continue
        now = sha256_of(ap)
        if now != r["before_sha256"]:
            failures.append("%s: modified since the suggestion was drafted "
                            "(drafted %s..., now %s...)" % (r["path"], r["before_sha256"][:12], now[:12]))

if failures:
    draft["suggestions"][tag]["flagged"] = {
        "at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "reasons": failures}
    with open(os.path.join(work, "suggestions.json"), "w", encoding="utf-8") as fh:
        json.dump(draft, fh, indent=2, sort_keys=True)
    print("PRECONDITION FAILED - NOTHING WAS WRITTEN.", file=sys.stderr)
    for f in failures:
        print("  %s" % f, file=sys.stderr)
    print("", file=sys.stderr)
    print("The suggestion is flagged in %s. Re-run `present` to redraft it against"
          % os.path.join(work, "suggestions.json"), file=sys.stderr)
    print("the files as they are now, then review the new diff.", file=sys.stderr)
    sys.exit(7)

# --- write -------------------------------------------------------------------
undo_dir = os.path.join(work, "undo", tag)
if os.path.isdir(undo_dir):
    shutil.rmtree(undo_dir)
os.makedirs(undo_dir)

journal = {"tag": tag, "root": root,
           "at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "ops": []}
for i, r in enumerate(sug["ops"]):
    ap = os.path.join(root, r["path"])
    if os.path.exists(ap):
        shutil.copyfile(ap, os.path.join(undo_dir, "%d.bak" % i))
        prior = "file"
    else:
        prior = "absent"
    if r["op"] == "remove":
        os.remove(ap)
        after_sha = None
    else:
        data = base64.b64decode(r["after_b64"])
        os.makedirs(os.path.dirname(ap) or ".", exist_ok=True)
        tmp = ap + ".graduate.tmp"
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, ap)
        after_sha = sha256_bytes(data)
    journal["ops"].append({"i": i, "op": r["op"], "path": r["path"],
                           "prior": prior, "after_sha256": after_sha})
    print("%s %s" % ({"create": "+", "update": "~", "remove": "-"}[r["op"]], r["path"]))

with open(os.path.join(work, "journal-%s.json" % tag), "w", encoding="utf-8") as fh:
    json.dump(journal, fh, indent=2, sort_keys=True)
print("")
print("applied %d operation(s). Undo: scripts/graduate.sh undo --id %s" % (len(sug["ops"]), tag))
' "$WORK" "$ROOT" "$ID"
  ;;

undo)
  [ -n "$ID" ] || die_usage "undo needs --id TAG"
  [ -f "$WORK/journal-$ID.json" ] || die_usage "nothing applied for $ID from $WORK"

  python3 -c "$COMMON_PY"'
import shutil
work = sys.argv[1]; root = sys.argv[2]; tag = sys.argv[3]
journal = json.load(open(os.path.join(work, "journal-%s.json" % tag)))
undo_dir = os.path.join(work, "undo", tag)

# Undo restores what apply wrote over. If the file no longer matches what apply
# wrote, someone edited it afterwards, and restoring would destroy that edit -
# which is the same clobber the apply preconditions exist to prevent.
failures = []
for o in journal["ops"]:
    ap = os.path.join(root, o["path"])
    if o["op"] == "remove":
        if os.path.exists(ap):
            failures.append("%s: reappeared since it was removed" % o["path"])
        continue
    if not os.path.exists(ap):
        failures.append("%s: gone since it was written" % o["path"])
        continue
    now = sha256_of(ap)
    if now != o["after_sha256"]:
        failures.append("%s: changed since it was written (wrote %s..., now %s...)"
                        % (o["path"], o["after_sha256"][:12], now[:12]))

if failures:
    print("UNDO REFUSED - NOTHING WAS RESTORED.", file=sys.stderr)
    for f in failures:
        print("  %s" % f, file=sys.stderr)
    print("", file=sys.stderr)
    print("Undo only reverses its own write. A file edited after apply holds work this",
          file=sys.stderr)
    print("journal knows nothing about, and restoring the backup would destroy it.",
          file=sys.stderr)
    sys.exit(8)

for o in journal["ops"]:
    ap = os.path.join(root, o["path"])
    bak = os.path.join(undo_dir, "%d.bak" % o["i"])
    if o["prior"] == "file":
        shutil.copyfile(bak, ap)
        print("restored %s" % o["path"])
    else:
        if os.path.exists(ap):
            os.remove(ap)
        print("removed  %s  (it did not exist before apply)" % o["path"])
os.remove(os.path.join(work, "journal-%s.json" % tag))
print("")
print("undone %d operation(s)." % len(journal["ops"]))
' "$WORK" "$ROOT" "$ID"
  ;;
esac
