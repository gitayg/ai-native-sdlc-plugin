#!/usr/bin/env bash
# build-guide.sh [--root DIR] [--spec FILE] [--guide FILE] [--check] [--version] [--help]
#
# R9 - when a release is prepared, the lifecycle shall regenerate the user
# guide from the active requirements. This is that regeneration, and it is
# deliberately narrow.
#
# WHAT IT GENERATES, AND WHAT IT REFUSES TO TOUCH.
#
# GUIDE.md is written prose, and it is good BECAUSE it is written prose. A
# guide regenerated wholesale out of EARS sentences would be accurate,
# unreadable, and therefore unread - a worse failure than a stale one, and a
# quieter one. So this writes exactly ONE section, the active requirement set,
# between two markers. Every byte outside them is left as its author left it.
#
# MARKERS ABSENT IS A REFUSAL, NOT A BEST GUESS. A generator that picks a
# plausible spot overwrites a paragraph somebody wrote, and prose does not come
# back the way a regenerated section does. It exits 2 and prints the two lines
# to paste where the section belongs.
#
# SUPERSEDED AND WITHDRAWN REQUIREMENTS ARE NOT RENDERED. This section says
# what the product does now. A replaced requirement stays in the spec forever -
# that is R3 - but nothing in the sentence itself tells a reader it stopped
# being true, so a reader who acts on one from the guide acts on behaviour that
# was withdrawn.
#
# NO CLOCK IS WRITTEN. No generation date, no "last updated". A wall clock in
# the output makes two runs against an unchanged spec differ, and --check would
# then go red every day for a reason that has nothing to do with the
# requirements. The section is a function of the spec's content and of nothing
# else, which is the whole reason its staleness is worth acting on. Anywhere a
# date is ever needed it is taken UTC.
#
# --ROOT DEFAULTS TO THE WORK TREE, NEVER THE WORKING DIRECTORY. Defaulting to
# `.` writes a GUIDE.md into whatever directory the release happened to be run
# from, and the real one stays stale while a run reports success.
#
# --CHECK REGENERATES INTO MEMORY AND WRITES NOTHING, so a release can be gated
# on the guide being current. It names the ids that drifted, because "GUIDE.md
# is stale" is not actionable and "R29 is in the spec and not in the guide" is.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  written, or already current, or --check found it current
#   1  --check only: the committed guide is out of date with the spec
#   2  cannot run - bad usage, no repository root, an unreadable guide, or a
#      guide carrying no markers to write between
#   3  COULD NOT READ THE SPEC. Never reported as "0 active requirements": a
#      spec nobody could open is not a product with nothing agreed about it.
set -euo pipefail

VERSION="build-guide 1.0"

usage() {
  printf 'usage: build-guide.sh [--root DIR] [--spec FILE] [--guide FILE] [--check] [--version] [--help]\n'
}

ROOT=""; SPEC=""; GUIDE=""; MODE="write"

need_value() {
  [ -n "${2:-}" ] || { printf 'build-guide: %s needs a value\n' "$1" >&2; usage >&2; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    need_value "$1" "${2:-}"; ROOT="$2";  shift 2 ;;
    --spec)    need_value "$1" "${2:-}"; SPEC="$2";  shift 2 ;;
    --guide)   need_value "$1" "${2:-}"; GUIDE="$2"; shift 2 ;;
    --check)   MODE="check"; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)         printf 'build-guide: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  # Not `.`. A release run from a subdirectory would otherwise regenerate a
  # guide nobody reads and leave the real one stale, reporting success both
  # times. git's own fatal goes to the terminal on purpose.
  ROOT="$(git rev-parse --show-toplevel)" || {
    printf 'build-guide: --root was not given and this is not a git work tree, so there is no repository root to default to. Pass --root DIR.\n' >&2
    exit 2
  }
fi
[ -d "$ROOT" ] || { printf 'build-guide: no such directory: %s\n' "$ROOT" >&2; exit 2; }

[ -n "$SPEC" ]  || SPEC="$ROOT/.claude/productizer/spec.md"
[ -n "$GUIDE" ] || GUIDE="$ROOT/GUIDE.md"

command -v python3 >/dev/null 2>&1 || {
  printf 'build-guide: python3 is not installed, so the spec was never parsed. Missing, not clean.\n' >&2
  exit 2
}

python3 - "$SPEC" "$GUIDE" "$MODE" "$ROOT" <<'PY'
import os
import re
import sys
import tempfile
import textwrap

BEGIN = "<!-- productizer:requirements:begin -->"
END = "<!-- productizer:requirements:end -->"

SPEC_PATH, GUIDE_PATH, MODE, ROOT = sys.argv[1:5]


# Paths are printed RELATIVE to the work tree. An absolute one carries
# somebody's home directory, and this output is captured verbatim into
# checks-result.json, which is committed. That exact leak shipped once from
# build-view.sh; it does not get to ship twice.
def disp(path):
    try:
        rel = os.path.relpath(os.path.abspath(path), os.path.abspath(ROOT))
    except ValueError:
        return path
    return path if rel.startswith("..") else rel


# GUIDE.md is wrapped prose and the generated section has to be wrapped prose
# too, or the diff of a one-word spec edit is a whole rewritten paragraph and
# the section announces itself as machine output on sight. 78 columns, the
# width the rest of the file already uses. Hyphens and long tokens are never
# broken - `read-only` split across two lines is not the same word.
WIDTH = 78


def para(text):
    return textwrap.fill(text, width=WIDTH, break_on_hyphens=False,
                         break_long_words=False)


def bullet(text):
    return textwrap.fill(text, width=WIDTH, initial_indent="- ",
                         subsequent_indent="  ", break_on_hyphens=False,
                         break_long_words=False)


def die(code, msg):
    sys.stderr.write("build-guide: " + msg + "\n")
    raise SystemExit(code)


ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety"]


def words(n):
    if n < 20:
        return ONES[n]
    if n < 100:
        t, r = divmod(n, 10)
        return TENS[t] + ("-" + ONES[r] if r else "")
    return str(n)


def Words(n):
    w = words(n)
    return w[0].upper() + w[1:]


# The prose around each group is written here rather than in the spec, because
# the spec states obligations and a guide has to read like something a person
# wrote. Fixed text, so the output stays a pure function of the spec.
FRAMING = {
    "ubiquitous": ("Always, with no trigger.",
                   "One requirement holds whatever else is happening:",
                   "{N} requirements hold whatever else is happening:"),
    "event": ("When something arrives.",
              "One thing happens on a discrete trigger:",
              "{N} things happen on a discrete trigger:"),
    "state": ("For as long as a state lasts.",
              "One requirement is true for the duration of a state, not at a moment inside it:",
              "{N} requirements are true for the duration of a state, not at a moment inside it:"),
    "unwanted": ("When something goes wrong.",
                 "One defence, written as `If \u2026 then` because a designed path and a defended one are not the same thing:",
                 "{N} defences, written as `If \u2026 then` because a designed path and a defended one are not the same thing:"),
    "optional": ("Only where the feature is present.",
                 "One requirement applies only to a build that includes the feature:",
                 "{N} requirements apply only to a build that includes the feature:"),
    "complex": ("While a state lasts, and then a trigger fires.",
                "One requirement stacks a state and a trigger, in that order:",
                "{N} requirements stack a state and a trigger, in that order:"),
    "other": ("The rest of the agreed set.",
              "One requirement sits under a heading this generator does not recognise, and is listed unchanged:",
              "{N} requirements sit under a heading this generator does not recognise, and are listed unchanged:"),
}
ORDER = ["ubiquitous", "event", "state", "unwanted", "optional", "complex", "other"]


def group_of(heading):
    h = heading.lower()
    if "ubiquit" in h:
        return "ubiquitous"
    if "complex" in h:
        return "complex"
    if "unwanted" in h:
        return "unwanted"
    if "event" in h:
        return "event"
    if "state" in h:
        return "state"
    if "optional" in h:
        return "optional"
    return "other"


def escape_pipes(s):
    # Tables downstream are split on unescaped pipes. Nothing here emits a
    # table today, but a requirement that ever contains one must not be able
    # to become a column boundary somewhere else.
    return re.sub(r"(?<!\\)\|", r"\\|", s)


# --- read the spec -----------------------------------------------------------
try:
    with open(SPEC_PATH, encoding="utf-8") as fh:
        spec = fh.read()
except OSError as exc:
    die(3, "cannot read the spec at %s (%s). Unmeasured, not empty - a guide "
           "generated from a spec nobody could open would describe a product "
           "nobody agreed to." % (disp(SPEC_PATH), exc.strerror))

lines = spec.split("\n")
start = None
for i, ln in enumerate(lines):
    if re.match(r"^##[ \t]+Requirements[ \t]*$", ln):
        start = i + 1
        break
if start is None:
    die(3, "the spec at %s has no `## Requirements` section, so no requirement "
           "was read. That is unmeasured, not a spec with none." % disp(SPEC_PATH))

stop = len(lines)
for j in range(start, len(lines)):
    if re.match(r"^##[^#]", lines[j]):
        stop = j
        break

BULLET = re.compile(r"^-[ \t]+\*\*(R\d+)\*\*[ \t]*[—–-][ \t]*(.*)$")
SUPERSEDED = re.compile(r"^Superseded by R\d+\.")
WITHDRAWN = re.compile(r"^Withdrawn\.")

reqs = []          # (id, group, text, status)
group = "other"
k = start
while k < stop:
    ln = lines[k]
    if ln.startswith("###"):
        group = group_of(ln.lstrip("#").strip())
        k += 1
        continue
    m = BULLET.match(ln)
    if not m:
        k += 1
        continue
    rid, text = m.group(1), m.group(2).strip()
    status = "active"
    k += 1
    while k < stop:
        nxt = lines[k]
        if not nxt.strip() or BULLET.match(nxt) or nxt.startswith("#"):
            break
        if not (nxt.startswith(" ") or nxt.startswith("\t")):
            break
        cont = nxt.strip()
        if SUPERSEDED.match(cont):
            status = "superseded"
        elif WITHDRAWN.match(cont):
            status = "withdrawn"
        else:
            text = (text + " " + cont).strip()
        k += 1
    reqs.append((rid, group, text, status))

if not reqs:
    die(3, "the spec at %s holds no requirements. Unmeasured, not zero - a "
           "requirements section with nothing in it is a spec that could not "
           "be read, not a product with nothing agreed about it." % disp(SPEC_PATH))

active = [r for r in reqs if r[3] == "active"]
n_active = len(active)
n_sup = sum(1 for r in reqs if r[3] == "superseded")
n_wd = sum(1 for r in reqs if r[3] == "withdrawn")

# --- render ------------------------------------------------------------------
out = [BEGIN,
       "<!-- Generated from `.claude/productizer/spec.md` by",
       "     plugins/productizer/skills/spec/scripts/build-guide.sh. Everything between",
       "     these two markers is rewritten on every release - edit the spec, not this. -->",
       ""]

out.append(para("**%s requirement%s %s active**, and they are the whole of "
                "what has been agreed."
                % (Words(n_active), "" if n_active == 1 else "s",
                   "is" if n_active == 1 else "are")))
out.append("")

if n_sup or n_wd:
    if n_sup and n_wd:
        tail = ("%s more %s superseded and %s withdrawn"
                % (Words(n_sup), "is" if n_sup == 1 else "are", words(n_wd)))
    elif n_sup:
        tail = ("%s more %s superseded and none withdrawn"
                % (Words(n_sup), "is" if n_sup == 1 else "are"))
    else:
        tail = ("None %s superseded and %s withdrawn"
                % ("is", words(n_wd)))
    out.append(para("%s, and neither kind is listed here. The spec keeps both "
                    "forever with their text intact, so a citation written two "
                    "years ago still leads somewhere \u2014 but a guide is read "
                    "by someone deciding what to do next, and a superseded "
                    "sentence gives them no sign it stopped being true." % tail))
    out.append("")

if n_active == 0:
    out.append(para("Nothing is active. Every requirement the spec has ever "
                    "held has since been superseded or withdrawn, so there is "
                    "nothing here to describe."))
    out.append("")
else:
    for g in ORDER:
        members = [r for r in active if r[1] == g]
        bold, sing, plur = FRAMING[g]
        if not members:
            if g == "unwanted":
                out.append(para("**%s** Nothing. A spec with no `If` "
                                "requirements has not considered failure, and "
                                "the tests will inherit that gap." % bold))
                out.append("")
            continue
        n = len(members)
        sentence = sing if n == 1 else plur.replace("{N}", Words(n))
        out.append(para("**%s** %s" % (bold, sentence)))
        out.append("")
        for rid, _g, text, _s in members:
            out.append(bullet("**%s** \u2014 %s" % (rid, escape_pipes(text))))
        out.append("")

out.append(para("Every id above is permanent. A plan, a test or a PR title "
                "naming `%s` will still mean this sentence in two years, which "
                "is why ids are never reused and never renumbered. The whole "
                "spec \u2014 the superseded text included, with the acceptance "
                "criteria and the change log \u2014 is at "
                "`.claude/productizer/spec.md`."
                % (active[0][0] if active else "R1")))
out.append(END)

block = "\n".join(out)

# --- splice it in ------------------------------------------------------------
try:
    with open(GUIDE_PATH, encoding="utf-8") as fh:
        guide = fh.read()
except OSError as exc:
    die(2, "cannot read the guide at %s (%s)." % (disp(GUIDE_PATH), exc.strerror))

n_begin, n_end = guide.count(BEGIN), guide.count(END)
if n_begin != 1 or n_end != 1:
    if n_begin == 0 and n_end == 0:
        why = "it carries no generated-requirements markers"
    else:
        why = ("it carries %d begin marker(s) and %d end marker(s), and exactly "
               "one of each is needed to know what to replace" % (n_begin, n_end))
    die(2, "refusing to touch %s: %s. Guessing where the section belongs would "
           "overwrite prose somebody wrote, and prose does not come back the way "
           "a regenerated section does.\n"
           "  Put these two lines in %s where the requirements should appear, "
           "then run again:\n"
           "    %s\n"
           "    %s" % (disp(GUIDE_PATH), why, os.path.basename(GUIDE_PATH), BEGIN, END))

b = guide.index(BEGIN)
e = guide.index(END)
if e < b:
    die(2, "refusing to touch %s: the end marker comes before the begin marker, "
           "so there is no section between them to replace." % disp(GUIDE_PATH))

old_block = guide[b:e + len(END)]
new_guide = guide[:b] + block + guide[e + len(END):]

print(disp(SPEC_PATH))
print(disp(GUIDE_PATH))
print("2 file(s) read, %d active requirement(s) rendered" % n_active)

if new_guide == guide:
    if MODE == "check":
        print("%s is up to date with the spec." % disp(GUIDE_PATH))
    else:
        print("%s is already up to date; nothing written." % disp(GUIDE_PATH))
    raise SystemExit(0)

# Bullets are wrapped, so the rows are unwrapped again before they are
# compared. Comparing wrapped lines would call a requirement "changed" because
# a word moved across a line break.
ROW_HEAD = re.compile(r"^- \*\*(R\d+)\*\* \u2014 (.*)$")


def rows(text):
    found = {}
    rid = None
    for ln in text.split("\n"):
        m = ROW_HEAD.match(ln)
        if m:
            rid = m.group(1)
            found[rid] = m.group(2).strip()
        elif rid and ln.startswith("  ") and ln.strip():
            found[rid] = (found[rid] + " " + ln.strip()).strip()
        else:
            rid = None
    return found


was = rows(old_block)
now = rows(block)
added = [i for i in now if i not in was]
gone = [i for i in was if i not in now]
changed = [i for i in now if i in was and was[i] != now[i]]


def by_id(ids):
    return sorted(ids, key=lambda s: int(s[1:]))


if MODE == "check":
    print("    %s is OUT OF DATE with %s." % (disp(GUIDE_PATH), disp(SPEC_PATH)))
    for i in by_id(added):
        print("    added in the spec, absent from the guide:   %s — %s" % (i, now[i]))
    for i in by_id(gone):
        print("    in the guide, no longer active in the spec: %s" % i)
    for i in by_id(changed):
        print("    wording differs:                            %s" % i)
    if not (added or gone or changed):
        print("    the requirement ids match; the framing or the counts around "
              "them differ.")
    print("    Regenerate with: build-guide.sh --root <repo>")
    raise SystemExit(1)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(GUIDE_PATH)),
                           prefix=".build-guide.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new_guide)
    os.replace(tmp, GUIDE_PATH)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise

print("    wrote the requirements section of %s" % disp(GUIDE_PATH))
for i in by_id(added):
    print("    added:   %s — %s" % (i, now[i]))
for i in by_id(gone):
    print("    removed: %s" % i)
for i in by_id(changed):
    print("    changed: %s" % i)
raise SystemExit(0)
PY
