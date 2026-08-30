#!/usr/bin/env bash
# build-view.sh [repo-root] [--out FILE] [--stale-after SECONDS|never]
#
# Generates the lifecycle dashboard from a repository's real files. Nothing on
# the page is stored here: every count, every state and every row is read from
# the tree at generation time, which is the only way a view can be wrong in a
# way anyone notices.
#
# Three states are kept apart everywhere, because they lead to three different
# actions and collapsing them is how a dashboard starts lying:
#
#   a measured zero   the file was read and the answer is nothing
#   not run           the file does not exist yet, and the page says why that matters
#   unknown           the file exists and could not be read, or is not derivable
#
# A value that could not be read is never drawn as a measured zero.
#
# Stage state is not re-derived here. stage-status.sh already reads every stage
# off the tree, including the "not run" / "unknown" / "n/a" distinction, and it
# is run as a subprocess and parsed. Two copies of that reasoning would disagree
# the first time one was edited.
#
# --stale-after is off by default and off is the point of the default. The page
# is a static file: served again, it re-serves the same bytes, and the numbers
# only move when this script runs again. So instead of reloading itself, the
# page can be told to notice its own age and print the command that re-measures
# it. Knowing its age means embedding a wall-clock generation time, and a
# wall-clock value makes two runs of an unchanged repo differ - which is the one
# property this script otherwise guarantees. That trade is opt-in, never taken
# for a reader who did not ask for it, and written down in references/views.md.
#
# Exit: 0 on success, 2 on a bad argument or a missing template.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"
TEMPLATE="$SKILL/templates/view.html"
STAGE_STATUS="$HERE/stage-status.sh"

# The command the staleness notice prints has to be the command that was
# actually run, argument for argument - a reader who generated to --out
# somewhere.html and is handed a default invocation regenerates the wrong file.
# So argv is captured before it is consumed, and shell-quoted as it is copied.
#
# Reproducing argv is not the same as reproducing the run, and this line got it
# wrong twice in opposite directions. Omitting the root reproduced a command
# that only worked from inside the repo, and regenerated an almost-empty page
# anywhere else. Echoing the root back verbatim then wrote an absolute path -
# somebody's home directory - into a page that gets published, which is the
# leak that shipped in v4.2.0. Both come from treating the literal invocation
# as the thing to reproduce. What has to survive is the MEANING: any path that
# is the work tree is emitted as the expression that finds the work tree, so
# the command carries no home directory and runs from any directory.
TOPLEVEL_EXPR='"$(git rev-parse --show-toplevel)"'
_quote_arg() {
  # The work tree itself, and anything under it, are emitted relative to the
  # expression that finds the work tree. Everything else - an --out under
  # /tmp, a flag, a number - is quoted literally, because rewriting a path
  # that is NOT in the repo would point the command somewhere it never ran.
  if [ -z "${GIT_TOPLEVEL:-}" ]; then printf '%q' "$1"; return; fi
  case "$1" in
    "$GIT_TOPLEVEL")   printf '%s' "$TOPLEVEL_EXPR" ;;
    "$GIT_TOPLEVEL"/*) printf '%s/%s' "$TOPLEVEL_EXPR" "${1#"$GIT_TOPLEVEL"/}" ;;
    *)                 printf '%q' "$1" ;;
  esac
}
GIT_TOPLEVEL="$(git rev-parse --show-toplevel 2>&1)" || GIT_TOPLEVEL=""
case "$GIT_TOPLEVEL" in /*) ;; *) GIT_TOPLEVEL="" ;; esac

SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
REGEN_CMD="bash $(_quote_arg "$SELF")"
for _arg in "$@"; do
  REGEN_CMD="$REGEN_CMD $(_quote_arg "$_arg")"
done

ROOT=""
OUT=""
STALE_AFTER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "build-view: --out needs a file" >&2; exit 2; }; shift 2 ;;
    --out=*) OUT="${1#--out=}"; shift ;;
    # A bare --stale-after is the common case, so it takes the default rather
    # than erroring; anything starting with - is the next option, not a value.
    --stale-after)
      case "${2:-}" in
        ''|-*) STALE_AFTER=120; shift ;;
        *)     STALE_AFTER="$2"; shift 2 ;;
      esac ;;
    # --stale-after= with nothing after it is still the flag with no value.
    --stale-after=*) STALE_AFTER="${1#--stale-after=}"
                     [ -n "$STALE_AFTER" ] || STALE_AFTER=120; shift ;;
    -h|--help) echo "usage: build-view.sh [repo-root] [--out FILE] [--stale-after SECONDS|never]"; exit 0 ;;
    -*) echo "build-view: unknown option: $1" >&2; exit 2 ;;
    *) [ -z "$ROOT" ] || { echo "build-view: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
# 0 and never are the same instruction, and both mean "do not embed a clock".
case "$STALE_AFTER" in
  ''|never|off|no) STALE_AFTER=0 ;;
  *[!0-9]*) echo "build-view: --stale-after wants whole seconds or 'never': $STALE_AFTER" >&2; exit 2 ;;
esac
[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || { echo "build-view: no such directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
[ -n "$OUT" ] || OUT="$ROOT/.claude/productizer/pipeline.html"
[ -f "$TEMPLATE" ] || { echo "build-view: missing template: $TEMPLATE" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- stage state -----------------------------------------------------------
# Not a gate, so a failure here must not fail the build; it becomes "unknown"
# on the page, which is the honest rendering of "the reporter did not answer".
if [ -x "$STAGE_STATUS" ]; then
  "$STAGE_STATUS" --by-stage "$ROOT" >"$TMP/stage-status" 2>"$TMP/stage-status.err" || :
fi

# --- git -------------------------------------------------------------------
# One walk of the history, not one call per file. Everything below is written
# to files and parsed in python so the shell does no interpretation of its own.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  : >"$TMP/is-git"
  TZ=UTC git -C "$ROOT" log --no-color --date=format-local:'%Y-%m-%d %H:%M' \
      --pretty=format:'%x01%H%x1f%h%x1f%ad%x1f%s%x1f%b%x02' >"$TMP/log" 2>/dev/null || :
  TZ=UTC git -C "$ROOT" log --no-color --date=format-local:'%Y-%m-%dT%H:%M' \
      --pretty=format:'%x01%ad' --name-only >"$TMP/log-files" 2>/dev/null || :
  git -C "$ROOT" for-each-ref --format='%(objectname) %(*objectname) %(refname:short)' \
      refs/tags >"$TMP/tags" 2>/dev/null || :
  git -C "$ROOT" ls-files -z >"$TMP/files" 2>/dev/null || :
  git -C "$ROOT" remote get-url origin >"$TMP/remote" 2>/dev/null || :
  git -C "$ROOT" rev-parse --short HEAD >"$TMP/head" 2>/dev/null || :
  TZ=UTC git -C "$ROOT" log -1 --date=format-local:'%Y-%m-%d' --pretty=format:'%ad' >"$TMP/head-date" 2>/dev/null || :
  TZ=UTC git -C "$ROOT" log -1 --date=format-local:'%Y-%m-%d' --pretty=format:'%ad' \
      -- .claude/productizer/spec.md >"$TMP/spec-date" 2>/dev/null || :
fi

python3 - "$ROOT" "$TMP" "$TEMPLATE" "$OUT" "$STALE_AFTER" "$REGEN_CMD" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Render the lifecycle dashboard. Reads only; writes one HTML file."""
import io, json, os, re, sys, time

ROOT, TMP, TEMPLATE, OUT, STALE_AFTER, REGEN_CMD = sys.argv[1:7]
STALE_AFTER = int(STALE_AFTER)

# --------------------------------------------------------------------------
# reading
# --------------------------------------------------------------------------

def slurp(path):
    try:
        with io.open(path, encoding='utf-8', errors='replace') as fh:
            return fh.read()
    except (IOError, OSError):
        return None

def rel(*parts):
    return os.path.join(ROOT, *parts)

def tmpf(name):
    return slurp(os.path.join(TMP, name))

CFG_PATH      = '.claude/productizer/config.json'
SPEC_PATH     = '.claude/productizer/spec.md'
BACKLOG_PATH  = '.claude/productizer/backlog.md'
CONST_PATH    = '.claude/productizer/constitution.md'
CHECKS_PATH   = '.claude/productizer/checks.yaml'
RESULT_PATH   = '.claude/productizer/checks-result.json'

cfg_raw   = slurp(rel(CFG_PATH))
spec      = slurp(rel(SPEC_PATH))
backlog   = slurp(rel(BACKLOG_PATH))
constit   = slurp(rel(CONST_PATH))
result_raw = slurp(rel(RESULT_PATH))

# --- .claude/productizer/config.json ----------------------------------------------------
# A config that will not parse is not an absent config, and is not a default.
cfg, cfg_state = {}, 'absent'
if cfg_raw is not None:
    try:
        cfg = json.loads(cfg_raw)
        cfg_state = 'ok'
    except ValueError:
        cfg, cfg_state = {}, 'unreadable'

def dig(obj, *keys):
    for k in keys:
        if not isinstance(obj, dict):
            return None
        obj = obj.get(k)
    return obj

PRODUCT = dig(cfg, 'product', 'name') or os.path.basename(ROOT)
SPEC_REPO = dig(cfg, 'product', 'spec_repo')
JIRA_SITE = (dig(cfg, 'jira', 'site') or '').rstrip('/')

# --- git ------------------------------------------------------------------
IS_GIT = os.path.exists(os.path.join(TMP, 'is-git'))
HEAD_SHA = (tmpf('head') or '').strip()
HEAD_DATE = (tmpf('head-date') or '').strip()
SPEC_DATE = (tmpf('spec-date') or '').strip()

remote = (tmpf('remote') or '').strip()
GH = None
m = re.match(r'^(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?$', remote)
if m:
    GH = m.group(1)

tracked = []
raw = tmpf('files')
if raw:
    tracked = [p for p in raw.split('\0') if p]

# last-change date per tracked path, from a single history walk
file_dates = {}
raw = tmpf('log-files')
if raw:
    date = None
    for line in raw.split('\n'):
        if line.startswith('\x01'):
            date = line[1:].strip()
        elif line.strip() and date and line not in file_dates:
            file_dates[line] = date

# tags -> the sha they point at (annotated tags deref through the third field)
tag_of = {}
raw = tmpf('tags')
if raw:
    for line in raw.split('\n'):
        if not line.strip():
            continue
        parts = line.split(' ', 2)
        if len(parts) < 3:
            continue
        obj, deref, name = parts
        tag_of[deref or obj] = name

# Commit subjects and bodies are the one thing on this page that is NOT read
# from a file someone can edit. They come out of git, they are permanent, and
# they are rendered verbatim as release notes - so a name that was scrubbed from
# every file still reaches a published artifact through the log. That happened:
# the files and the release notes were cleaned, the commit messages were not,
# and the page put them back.
#
# So git-derived text is redacted before it is displayed. This is a DISPLAY
# rule, not a gate: check-hygiene.sh keeps its own hardcoded list precisely
# because a gate that reads its patterns from an editable config can be
# switched off by editing the config. Under-redacting here is a leak; the gate
# is what stops the commit being made in the first place.
#
# A pattern list that cannot be read is reported ON THE PAGE, never silently
# skipped - unredacted output that looks redacted is worse than no redaction.
REDACT_PATTERNS = []
REDACT_STATE = 'none declared'


def _patterns_from(text):
    """Two shapes, because the two sources are different kinds of file.

    A shell check declares its list on one `PATTERNS='a|b|c'` line. A private
    list is one regex per line with # comments. Read as DATA either way - the
    shell one is a script, and running it is exactly what P4 forbids.
    """
    m = re.search(r"^PATTERNS='([^']*)'", text, re.M)
    if m:
        return [p for p in m.group(1).split('|') if p]
    out = []
    for ln in text.split('\n'):
        ln = ln.strip()
        if ln and not ln.startswith('#'):
            out.append(ln)
    return out


_rf = dig(cfg, 'views', 'redact_from')
if isinstance(_rf, str) and _rf:
    _rf = [_rf]
if isinstance(_rf, list) and _rf:
    # Sources are unioned, and each one's failure is named separately. A public
    # generic list plus a private local list is the shipped arrangement, and
    # the private one is gitignored - so it is ABSENT in CI and in a fresh
    # clone. Absent is reported, never treated as "nothing to redact".
    _good, _bad, _notes = [], 0, []
    for _one in _rf:
        if not isinstance(_one, str) or not _one:
            _notes.append('an unusable entry'); continue
        try:
            with io.open(os.path.join(ROOT, _one), encoding='utf-8', errors='replace') as _fh:
                _src = _fh.read()
        except (IOError, OSError):
            _notes.append('%s absent or unreadable' % _one); continue
        _n = 0
        for _p in _patterns_from(_src):
            try:
                _good.append(re.compile(_p, re.I)); _n += 1
            except re.error:
                _bad += 1
        _notes.append('%d from %s' % (_n, _one))
    REDACT_PATTERNS = _good
    REDACT_STATE = '; '.join(_notes) if _notes else 'nothing readable'
    if _bad:
        REDACT_STATE += '; %d unusable and NOT applied' % _bad
    if not _good:
        REDACT_STATE += ' - NOTHING was redacted'


def _redact(text):
    if not text or not REDACT_PATTERNS:
        return text
    for _pat in REDACT_PATTERNS:
        text = _pat.sub('[redacted]', text)
    return text


# commits
commits = []
raw = tmpf('log')
if raw:
    for entry in raw.split('\x01'):
        entry = entry.split('\x02')[0]
        if not entry.strip():
            continue
        f = entry.split('\x1f')
        if len(f) < 4:
            continue
        commits.append({'sha': f[0], 'short': f[1], 'date': f[2],
                        'subject': _redact(f[3]),
                        'body': _redact(f[4]) if len(f) > 4 else ''})

# --------------------------------------------------------------------------
# stage state, parsed out of stage-status.sh rather than re-derived
# --------------------------------------------------------------------------
STATES = ('blocked', 'waiting', 'unknown', 'not run', 'ok', 'n/a')
stage_rows, STAGE_STATUS_OK = {}, False
raw = tmpf('stage-status')
if raw is not None:
    for line in raw.split('\n'):
        if not line.startswith('  ') or len(line) < 31:
            continue
        state = line[21:30].strip()
        if state not in STATES:
            continue
        stage_rows[line[2:6].strip()] = {'name': line[7:20].strip(),
                                         'state': state,
                                         'detail': line[31:].strip()}
    STAGE_STATUS_OK = bool(stage_rows)

def stage(sid):
    """Never invents a row. A stage the reporter did not describe is unknown."""
    return stage_rows.get(sid, {
        'name': '', 'state': 'unknown',
        'detail': 'stage-status.sh did not report this stage'})

# --------------------------------------------------------------------------
# spec.md
# --------------------------------------------------------------------------
# The active-requirement pattern is stage-status.sh's, widened only by an
# optional list marker so the shipped template's own "- **R1**" rows are seen.
# Anything else would report a spec full of requirements as zero requirements,
# which is exactly the failure this file exists to prevent.
RE_ACTIVE  = re.compile(r'^(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_SUPER   = re.compile(r'^\s*Superseded by R[0-9]+')
RE_WITHDRW = re.compile(r'^\s*Withdrawn\.')

# A markdown table cell may hold a pipe by escaping it as `\|`. Splitting on a
# bare '|' tears such a row into extra cells and silently shifts every column
# after it - B6's note quotes a spec row, and this view rendered that note as a
# stray backtick for as long as the note existed. Split on unescaped pipes only,
# then put the real character back.
RE_MD_PIPE = re.compile(r'(?<!\\)\|')


def md_cells(row):
    return [c.strip().replace('\\|', '|') for c in RE_MD_PIPE.split(row)]


RE_CONTRA  = re.compile(r'^\|\s*(C[0-9]+)\s*\|(.*)$', re.M)

spec_ids, spec_super, spec_withdrawn = [], 0, 0
contradictions, contra_open = [], 0
ac_ids, ac_rows = set(), 0
if spec is not None:
    # A requirement's status marker is the line under it, so the id and its
    # status are read together. Counting every **Rn** as active would report
    # superseded and withdrawn requirements as needing a test they must not
    # have - the acceptance table is the same length as the active set by
    # design, and a count that ignores that turns a correct spec into a
    # backlog of imaginary gaps.
    lines = spec.split('\n')
    for i, line in enumerate(lines):
        mm = RE_ACTIVE.match(line)
        if not mm:
            continue
        status = 'active'
        for follow in lines[i + 1:i + 4]:
            if not follow.strip() or RE_ACTIVE.match(follow):
                break
            if RE_SUPER.match(follow):
                status = 'superseded'
                break
            if RE_WITHDRW.match(follow):
                status = 'withdrawn'
                break
        if status == 'superseded':
            spec_super += 1
        elif status == 'withdrawn':
            spec_withdrawn += 1
        else:
            spec_ids.append(mm.group(1))
    for cid, rest in RE_CONTRA.findall(spec):
        cells = md_cells(rest)
        status = cells[-2] if len(cells) >= 2 else (cells[-1] if cells else '')
        is_open = bool(re.search(r'open|unruled|waiting', status, re.I))
        contradictions.append({'id': cid, 'what': cells[0] if cells else '',
                               'status': status or 'unstated', 'open': is_open})
        if is_open:
            contra_open += 1
    # acceptance criteria: the rows of the table under that heading, not every
    # R-shaped cell in the file
    sec = re.split(r'^##\s+Acceptance criteria\s*$', spec, flags=re.M)
    if len(sec) > 1:
        body = re.split(r'^##\s', sec[1], flags=re.M)[0]
        for line in body.split('\n'):
            mm = re.match(r'^\|\s*`?(R[0-9]+)`?\s*\|', line)
            if mm:
                ac_rows += 1
                ac_ids.add(mm.group(1))
untested = [i for i in spec_ids if i not in ac_ids]

# --------------------------------------------------------------------------
# the import promotion queue, read out of spec.md
# --------------------------------------------------------------------------
# Stage 0c drafts requirements from code that already exists. Every one lands
# inferred and unconfirmed, carries the file or test it was read from, and
# cannot trigger the Stage 2 contradiction halt until a person promotes it -
# which is a commit, not a click. Left unmeasured, a spec holding thirty
# unpromoted sentences and a spec holding none render identically here, and a
# barely-started import reads as a finished one. That is the confidently-wrong
# failure this whole page exists to refuse, so it is counted.
#
# Only the literal markers templates/import.md mandates are read. Nothing is
# inferred about the inference:
#
#   Inferred from ... Unconfirmed.                  awaiting a person
#   Inferred (weak evidence) from ... Unconfirmed.  the same, cited from a doc
#   Withdrawn. Rejected at import: ...              refused, the id spent
#
# The parenthetical is matched rather than assumed away. A weak-tier requirement
# this queue did not see would be drawn as an agreed one, which is worse than
# never drafting it - it would now look measured.
#
# Promotion deletes the marker line outright, so a promoted requirement leaves
# nothing behind in its own entry. The one place the promotion procedure says
# the ratification is written is the decision record, and a row there is counted
# as a promotion only when it names an id this spec actually has, reads as a
# confirmation, and says the id came from the import. A promotion recorded some
# other way is invisible to this page, and the panel says so underneath itself
# rather than quietly counting it - an unread promotion is not a missing one.
RE_INFER   = re.compile(r'^Inferred(\s*\(([^)]*)\))?\s+from\b')
RE_REJIMP  = re.compile(r'^Withdrawn\.\s*Rejected at import\b', re.I)
RE_RID     = re.compile(r'\bR[0-9]+\b')
RE_RATIFY  = re.compile(r'confirm|promot|ratif', re.I)
RE_FROMIMP = re.compile(r'import|inferred', re.I)

# spec.md missing and spec.md unreadable are two different answers, and slurp
# returns None for both. Asking the filesystem separates them, so "there is no
# spec" is never printed over a spec that is sitting right there.
SPEC_EXISTS = os.path.exists(rel(SPEC_PATH))
inf_await, inf_rejected, inf_promoted, spec_all_ids = [], [], [], []

if spec is not None:
    slines = spec.split('\n')
    for i, line in enumerate(slines):
        mm = RE_ACTIVE.match(line)
        if not mm:
            continue
        rid = mm.group(1)
        spec_all_ids.append(rid)
        # The entry runs to the first blank line or the next requirement rather
        # than a fixed three-line window, so a marker sitting under a sentence
        # that wrapped over four lines is still found. A marker this page fails
        # to see is a requirement it reports as agreed.
        entry = []
        for follow in slines[i + 1:]:
            if not follow.strip() or RE_ACTIVE.match(follow):
                break
            entry.append(follow.strip())
        if any(RE_REJIMP.match(e) for e in entry):
            inf_rejected.append(rid)
            continue
        k, mo = None, None
        for j, e in enumerate(entry):
            mo = RE_INFER.match(e)
            if mo:
                k = j
                break
        if k is None:
            continue
        # The marker wraps too. It runs to the line carrying "Unconfirmed." when
        # it was written correctly, and to the end of the entry when it was not -
        # which is reported as an incomplete marker, never silently as a
        # promotion. The weak tier is allowed to say more after "Unconfirmed.",
        # so the word is looked for in the line rather than at the end of it.
        marker = []
        for e in entry[k:]:
            marker.append(e)
            if 'Unconfirmed.' in e:
                break
        mtext = ' '.join(marker)
        cite = mtext[mo.end():].split('Unconfirmed.')[0]
        cite = cite.strip().rstrip('.').replace('`', '').strip()
        what = ' '.join([line[mm.end():].strip()] + entry[:k]).strip()
        what = what.lstrip('\u2014-').strip()
        inf_await.append({'id': rid, 'what': what, 'cite': cite,
                          'sealed': 'Unconfirmed.' in mtext,
                          'weak': bool(mo.group(2) and 'weak' in mo.group(2).lower())})

    known = set(spec_all_ids)
    seen = set(x['id'] for x in inf_await) | set(inf_rejected)
    dsec = re.split(r'^##\s+Decision record\s*$', spec, flags=re.M)
    if len(dsec) > 1:
        dbody = re.split(r'^##\s', dsec[1], flags=re.M)[0]
        for drow in dbody.split('\n'):
            if not drow.startswith('|'):
                continue
            if not (RE_RATIFY.search(drow) and RE_FROMIMP.search(drow)):
                continue
            for rid in RE_RID.findall(drow):
                if rid in known and rid not in seen:
                    seen.add(rid)
                    inf_promoted.append(rid)

inf_promoted.sort(key=lambda r: int(r[1:]))
inf_rejected.sort(key=lambda r: int(r[1:]))

# What this file records about the import, which is a floor and not a census.
INF_RECORDED = len(inf_await) + len(inf_promoted) + len(inf_rejected)

# --------------------------------------------------------------------------
# backlog.md  - columns are read from the table's own header, not assumed
# --------------------------------------------------------------------------
ST_RANK = {'blocked': 0, 'in-progress': 1, 'in progress': 1, 'todo': 2,
           'long-term': 3, 'long term': 3, 'done': 4}
items = []
if backlog is not None:
    header, lines = None, backlog.split('\n')
    for line in lines:
        if re.match(r'^\|', line) and re.search(r'\bId\b', line) and re.search(r'Status', line):
            header = [c.lower() for c in md_cells(line.strip().strip('|'))]
        mm = re.match(r'^\|\s*(B[0-9]+)\s*\|', line)
        if not mm:
            continue
        cells = md_cells(line.strip().strip('|'))
        cols = header or ['id', 'what is wanted', 'status', 'jira', 'notes']
        row = {}
        for i, name in enumerate(cols):
            row[name] = cells[i] if i < len(cells) else ''
        def col(*names):
            for n in names:
                for k in row:
                    if n in k:
                        return row[k]
            return ''
        status = col('status').strip('`').strip()
        jira = col('jira').strip('`').strip()
        if jira in ('-', '—', '—', ''):
            jira = ''
        items.append({'id': mm.group(1), 'what': col('what', 'wanted'),
                      'status': status or 'unstated', 'jira': jira,
                      'note': col('note'),
                      'rank': ST_RANK.get(status.lower(), 5)})

# --------------------------------------------------------------------------
# constitution.md
# --------------------------------------------------------------------------
principles = len(re.findall(r'^### P[0-9]+', constit, re.M)) if constit is not None else None

# --------------------------------------------------------------------------
# checks-result.json  - the only honest source for Stage 5
# --------------------------------------------------------------------------
checks, verdict, check_state = [], None, 'absent'
if result_raw is not None:
    try:
        res = json.loads(result_raw)
        verdict = res.get('verdict')
        for c in res.get('checks', []):
            checks.append({'id': c.get('id', '?'),
                           'status': c.get('status') or 'unknown',
                           'covered': dig(c, 'coverage', 'observed', 'covered'),
                           'scope': dig(c, 'coverage', 'observed', 'files_in_scope'),
                           'from': dig(c, 'coverage', 'from'),
                           'satisfied': dig(c, 'coverage', 'satisfied'),
                           'why': c.get('why', ''),
                           # Carried through so the tile can tell an `always`
                           # check that did not run (a gap) from a scoped one
                           # that did not match (not applicable). Dropping it
                           # here made every check read as scoped.
                           'trigger_scope': c.get('trigger_scope', 'scoped')})
        check_state = 'ok'
    except ValueError:
        check_state = 'unreadable'

bad_checks = [c for c in checks if c['status'] not in ('pass', 'skipped')]

# One classification, and everything that draws a check reads it -----------
# The tile learned to tell an `always` check that did not run - a gap - from a
# path-scoped check that did not match, which is not applicable to this change.
# The banner never learned it, and went on counting every non-pass as a
# failure. So one run printed `PASS - 2 check(s), all passing - 1 not
# applicable` in the tile and `1 check not passing` in a banner directly above
# it, from the same file, and the banner's prompt sent a maintainer to
# investigate a check that had behaved exactly as configured. It cost them a
# question.
#
# Two places deriving the same fact disagree the first time one is edited, and
# this pair had already disagreed. So the three answers are derived once, here,
# and the tile, the banner, the board card and the Stage 5 row all read them:
#
#   CHK_FAILED  it ran, or it could not run, and neither is a pass
#   CHK_UNRUN   declared `always` and did not run - nothing was wrong, and
#               nothing was checked either
#   CHK_NA      scoped, and this change did not match it: never in the running
#
# CHK_ACT is the union that needs a person. A scoped miss is in none of it, so
# a run whose only non-pass is a scoped miss fires no banner at all - which is
# what the tile was already saying on its own.
CHK_UNRUN = [c for c in bad_checks
             if c['status'] in ('not_triggered', 'disabled')
             and c['trigger_scope'] == 'always']
CHK_NA = [c for c in bad_checks
          if c['status'] == 'not_triggered'
          and c['trigger_scope'] != 'always']
# Membership by identity, not by value: two checks may carry equal dicts, and
# `in` on a list of dicts compares them field by field.
_CHK_UNRUN_IDS = set(id(c) for c in CHK_UNRUN)
_CHK_NA_IDS = set(id(c) for c in CHK_NA)
CHK_FAILED = [c for c in bad_checks
              if id(c) not in _CHK_UNRUN_IDS and id(c) not in _CHK_NA_IDS]
_CHK_FAILED_IDS = set(id(c) for c in CHK_FAILED)
_CHK_ACT_IDS = _CHK_FAILED_IDS | _CHK_UNRUN_IDS
# In the order the Stage 5 table draws them, so the banner names them in the
# order the reader will meet them.
CHK_ACT = [c for c in checks if id(c) in _CHK_ACT_IDS]

# --------------------------------------------------------------------------
# releases, from the commit subjects that carry a version
# --------------------------------------------------------------------------
RE_VER = re.compile(r'^v?([0-9]+)\.([0-9]+)\.([0-9]+)\s*[:—-]\s*(.+)$')
releases = []
for c in commits:
    mm = RE_VER.match(c['subject'].strip())
    if not mm:
        continue
    bullets = []
    for line in (c['body'] or '').split('\n'):
        t = line.strip()
        if t.startswith(('- ', '* ')):
            bullets.append(t[2:].strip())
        elif t and bullets and line[:1] in ' \t':
            bullets[-1] += ' ' + t
    if not bullets:
        para = [p.strip().replace('\n', ' ') for p in (c['body'] or '').split('\n\n') if p.strip()]
        bullets = para[:4]
    releases.append({'ver': '%s.%s.%s' % mm.group(1, 2, 3),
                     'major': int(mm.group(1)), 'minor': int(mm.group(2)),
                     'patch': int(mm.group(3)), 'title': mm.group(4).strip(),
                     'sha': c['sha'], 'short': c['short'], 'date': c['date'],
                     'tag': tag_of.get(c['sha']), 'bullets': bullets})
# kind is derived from the bump against the next-older release, never guessed
for i, r in enumerate(releases):
    older = releases[i + 1] if i + 1 < len(releases) else None
    if older is None:
        r['kind'] = 'first'
    elif r['major'] != older['major']:
        r['kind'] = 'major'
    elif r['minor'] != older['minor']:
        r['kind'] = 'minor'
    else:
        r['kind'] = 'patch'
LATEST = releases[0]['ver'] if releases else None
UNTAGGED = [r for r in releases if not r['tag']]

# --------------------------------------------------------------------------
# the file tree
# --------------------------------------------------------------------------
SKIP_DIRS = {'.git', 'node_modules', '.venv', '__pycache__', 'dist', 'build'}

def walk_fs():
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for fn in sorted(filenames):
            p = os.path.relpath(os.path.join(dirpath, fn), ROOT)
            out.append(p.replace(os.sep, '/'))
    return out

paths = sorted(tracked) if tracked else walk_fs()

DESC_LIMIT = 150

def describe(path):
    """One honest line about a file, or None. Never a guess about its purpose."""
    full = rel(path)
    try:
        if os.path.getsize(full) > 512 * 1024:
            return None
    except OSError:
        return None
    txt = slurp(full)
    if txt is None:
        return None
    ext = os.path.splitext(path)[1].lower()
    if ext == '.json':
        try:
            d = json.loads(txt)
        except ValueError:
            return None
        for k in ('description', 'why', 'summary'):
            v = d.get(k) if isinstance(d, dict) else None
            if isinstance(v, str) and v.strip():
                return v.strip()[:DESC_LIMIT]
        return None
    for line in txt.split('\n')[:12]:
        s = line.strip()
        if not s or s.startswith('#!'):
            continue
        if ext == '.md':
            if s.startswith('#'):
                return s.lstrip('#').strip()[:DESC_LIMIT] or None
            return s[:DESC_LIMIT]
        if s.startswith('#'):
            body = s.lstrip('#').strip()
            if body and not body.startswith('-*- coding'):
                return body[:DESC_LIMIT]
        if s.startswith('//'):
            body = s.lstrip('/').strip()
            if body:
                return body[:DESC_LIMIT]
    return None

# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def esc(t):
    return (str(t).replace('&', '&amp;').replace('<', '&lt;')
            .replace('>', '&gt;').replace('"', '&quot;'))

def blob(path):
    if GH and path in tracked:
        return 'https://github.com/%s/blob/HEAD/%s' % (GH, path)
    return ''

EXTLINK = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" '
           'stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7"/>'
           '<path d="M9 7h8v8"/></svg>')

LIMPROMPT = (
    'In %s, the declared check `%s` records this limitation:\n\n'
    '  %s\n\n'
    'Read the check itself and tell me three things. Is that still true? Is it '
    'wider or narrower than the sentence says? And what would it take to close '
    'it?\n\n'
    'If closing it is not worth doing, say so and say why - a limitation '
    'somebody examined and decided to keep is worth more than one nobody read. '
    'Change no file until I answer.')

def cp(text, label='copy prompt'):
    return '<button class="cp" data-copy="%s">%s</button>' % (esc(text), esc(label))

# --- in-page anchors ------------------------------------------------------
# Anything drawn as needing a person is a link to the place that person acts,
# and a link to an id that does not exist is worse than no link: it looks like
# a way through and is a dead end. So every id on this page is minted here, by
# one function, and a link is only ever written from an id this run actually
# minted - which is why the targets are built before the things pointing at
# them, and why `href` is threaded through the renderers instead of being
# guessed at the call site.
#
# The slug is not the raw value. A check id, a backlog id or a version string
# is arbitrary text, and a fragment carrying a space or a quote is not the
# fragment the browser resolves - it is percent-encoded, and getElementById
# then finds nothing. Reducing to [A-Za-z0-9-] makes href and id agree by
# construction. Two different values can collapse to the same slug, so the
# counter keeps them apart; it runs in generation order, which is fixed, so
# the same repo mints the same ids every run.
_anch_used = {}

def anchor(prefix, raw):
    body = re.sub(r'[^A-Za-z0-9]+', '-', str(raw)).strip('-') or 'x'
    base = '%s-%s' % (prefix, body)
    n = _anch_used.get(base, 0)
    _anch_used[base] = n + 1
    return base if n == 0 else '%s-%d' % (base, n + 1)

# Every id anything on this page points at, minted once, here. A card and the
# row it lands on read the same entry, so they cannot disagree about what the
# id is - which is the only way "the target exists" stays true after an edit.
# Keyed by position rather than by the id text, because two checks may carry
# the same id string and the counter above has already told them apart.
CHECK_ID = dict((i, anchor('chk', c['id'])) for i, c in enumerate(checks))
BK_ID = dict((i, anchor('bk', it['id'])) for i, it in enumerate(items))
REL_ID = dict((i, anchor('rel', r['ver'])) for i, r in enumerate(releases))
# Two headings that are always rendered, so a link to either always resolves.
STAGE5_ID = 'stage5'
QUEUE_ID = 'promoqueue'

# --- banners --------------------------------------------------------------
# Every banner is a specific, named thing somebody has to act on, so every one
# gets an id: the count in the Dashboard subtitle links to the region, and a
# per-banner id costs one attribute and lets anything later point at one of
# them instead of at the pile. Numbered in call order, which is document order.
banners = []
_bn_seq = [0]
# key -> the id that banner actually got, and only for banners this run emitted.
# A tile reads its destination out of here rather than counting banners itself:
# a second copy of the emit conditions would point at bn-3 on the run where the
# config parsed and the numbering shifted.
BN = {}

def banner(level, title, body, prompt, key=None):
    _bn_seq[0] += 1
    if key:
        BN[key] = 'bn-%d' % _bn_seq[0]
    return ('<div class="bn %s" id="bn-%d"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" '
            'stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>'
            '<p><b>%s</b> %s</p>%s</div>'
            % (level, _bn_seq[0], '#da3633' if level == 'crit' else '#d29922',
               esc(title), body, cp(prompt)))

if cfg_state == 'unreadable':
    banners.append(banner('warn', 'The binding will not parse.',
                          '<span class="mono">%s</span> exists and is not valid JSON, so every name on '
                          'this page fell back to the directory name. Nothing downstream can read it either.'
                          % esc(CFG_PATH),
                          'Fix %s in %s: it is not valid JSON. Show me the parse error and the '
                          'smallest change that makes it valid.' % (CFG_PATH, PRODUCT)))
elif cfg_state == 'absent':
    banners.append(banner('warn', 'This repo is not bound.',
                          'There is no <span class="mono">%s</span>, so no stage knows what product this '
                          'is, where the spec lives, or which repos share it. Everything below is read '
                          'from the tree alone.' % esc(CFG_PATH),
                          'Bind %s for the SDLC lifecycle: write .claude/productizer/config.json naming the product, '
                          'the spec home repo and the source of truth. Check .gitignore does not block '
                          '.claude/ first.' % PRODUCT))

if contra_open:
    banners.append(banner('crit', '%d open contradiction%s.' % (contra_open, '' if contra_open == 1 else 's'),
                          'Nothing merges into the spec until a human rules: %s.'
                          % esc(', '.join(c['id'] for c in contradictions if c['open'])),
                          'Show me the open contradictions in %s: quote both requirements in full, state '
                          'the conflict in one sentence, and do not pick a winner.' % SPEC_PATH,
                          key='contra'))

if check_state == 'unreadable':
    banners.append(banner('warn', 'The last check result will not parse.',
                          '<span class="mono">%s</span> is present and unreadable. An unreadable result is '
                          'not a passing one, and this page will not render it as one.' % esc(RESULT_PATH),
                          'The file %s will not parse as JSON. Show me why, and re-run the checks rather '
                          'than repairing the result by hand.' % RESULT_PATH,
                          key='checks-unreadable'))
elif CHK_ACT:
    # Membership, level and wording all come from the one classification above,
    # so this banner and the Checks tile cannot describe the same run
    # differently. A gap and a failure are different things to do next, so the
    # title says which of the two it is rather than calling both `not passing`.
    _n = len(CHK_ACT)
    _s1 = '' if _n == 1 else 's'
    if CHK_FAILED and CHK_UNRUN:
        _lvl, _title = 'crit', '%d check%s did not pass.' % (_n, _s1)
        _lead = 'Some failed and some never ran'
        _ask = 'Show me why these checks did not pass in %s and what each one examined: %s'
    elif CHK_FAILED:
        _lvl, _title = 'crit', '%d check%s failed.' % (_n, _s1)
        _lead = 'Stage 5 refused'
        _ask = 'Show me why these checks failed in %s and what each one examined: %s'
    else:
        # Amber, because the tile is amber for exactly this run. A red banner
        # over an amber tile is the same disagreement one colour further on.
        _lvl, _title = 'warn', '%d check%s never ran.' % (_n, _s1)
        _lead = ('Declared always and not triggered, so nothing about %s was measured'
                 % ('it' if _n == 1 else 'them'))
        _ask = ('These checks in %s are declared always and did not run. Show me why each one was '
                'not triggered and what it would have examined: %s')
    _body = '%s: %s.' % (esc(_lead),
                         esc(', '.join('%s (%s)' % (c['id'], c['status']) for c in CHK_ACT)))
    if CHK_NA:
        # Named, and named as not counted. Leaving them out entirely is how a
        # reader ends up wondering whether the scoped ones were forgotten; the
        # prompt still does not mention them, because there is nothing to ask.
        _body += (' %d scoped check%s did not match the files in this change and %s not counted '
                  'above: %s.'
                  % (len(CHK_NA), '' if len(CHK_NA) == 1 else 's',
                     'is' if len(CHK_NA) == 1 else 'are',
                     esc(', '.join(c['id'] for c in CHK_NA))))
    banners.append(banner(_lvl, _title, _body,
                          _ask % (PRODUCT, ', '.join(c['id'] for c in CHK_ACT)),
                          key='checks'))

if spec is None and cfg_state == 'ok':
    banners.append(banner('warn', 'Bound, but not scaffolded.',
                          'Stage 2 has no spec to merge into, so stages 1–4 have never run — '
                          'the pipeline has a tail and no head.',
                          'Scaffold %s for the SDLC lifecycle: write an empty .claude/productizer/spec.md with the '
                          'allocator at R1, a REVIEW.md, and a CLAUDE.md if absent. Check .gitignore first '
                          'and do not overwrite anything.' % PRODUCT))

if untested:
    banners.append(banner('warn', '%d active requirement%s with no acceptance row.'
                          % (len(untested), '' if len(untested) == 1 else 's'),
                          'The acceptance table is how "do the tests assert this" is answered as a fact: %s.'
                          % esc(', '.join(untested[:10])),
                          # An agent handed "add acceptance rows" will finish the job by
                          # inventing test names, and a fabricated row turns "nobody knows"
                          # into a confident "yes" in the one table that exists to answer
                          # that question with a fact. So the prompt asks rather than writes.
                          'Interrogate me about the requirements in %s that have no acceptance row, one '
                          'at a time, starting with %s. Quote each requirement in full with its id, then '
                          'ask me what asserts it today - a test name, a command, a manual check, or '
                          'nothing. Write a row into the acceptance table only from an answer I give '
                          'you: do not infer one from the code, do not read the test suite and guess, '
                          'and do not fill a row to make the table look complete. "Nothing asserts this '
                          'yet" is a real answer and is recorded as one, not a gap to paper over. Treat '
                          'silence as silence - an id I do not answer gets no row. At the end, name the '
                          'ids I left unanswered.'
                          % (SPEC_PATH, ', '.join(untested[:10])),
                          key='untested'))

if constit is not None and principles == 0:
    banners.append(banner('warn', 'The constitution has no principles.',
                          '<span class="mono">%s</span> exists and nothing has been ratified in it, so '
                          'intake checks every delta against an empty gate.' % esc(CONST_PATH),
                          'Draft principles for %s in %s from how this repo already works. Number them '
                          'P1 upward and do not ratify any of them without asking me.'
                          % (PRODUCT, CONST_PATH),
                          key='constitution'))

# --- what a pushed tag actually starts here --------------------------------
# This banner used to tell people to push tags "so CI builds the releases".
# Nothing ever read whether this repo has any CI. A repo with no workflows
# builds nothing on a tag push, and a page that says otherwise is asserting a
# capability it never measured - the same failure as drawing an unknown as a
# zero, committed on a sentence instead of on a number. So: measure it.
#
# The file list is the evidence. If it could not be read, that is unknown, not
# "no CI", and an unknown never earns a claim - the CI clause is dropped either
# way, because the wrong thing to do with "I cannot tell" is to say something.
FILES_READ = tmpf('files') is not None
WORKFLOWS = sorted(p for p in tracked
                   if p.startswith('.github/workflows/')
                   and p.rsplit('.', 1)[-1].lower() in ('yml', 'yaml'))

# A workflow answers a tag push only if its trigger block says so. Only the
# text above `jobs:` counts: `tags:` under a step's `with:` is an argument to
# an action - docker/build-push-action takes exactly that key - and reading it
# as a trigger would put back a guess of the same kind that was here before.
TAG_WORKFLOWS = []
for _p in WORKFLOWS:
    _text = slurp(rel(_p))
    if _text is None:
        continue
    _trig = re.split(r'^jobs\s*:', _text, maxsplit=1, flags=re.M)[0]
    if re.search(r'^\s+tags\s*:', _trig, re.M):
        TAG_WORKFLOWS.append(_p)

if TAG_WORKFLOWS:
    _names = ', '.join('<span class="mono">%s</span>' % esc(os.path.basename(p)) for p in TAG_WORKFLOWS)
    _one = len(TAG_WORKFLOWS) == 1
    _tag_effect = (' Pushing the tag also starts %s, which %s a tag push in %s trigger block.'
                   % (_names, 'names' if _one else 'name', 'its' if _one else 'their'))
    _tag_prompt = ('Tag the untagged released versions in %s and push the tags so %s %s and each '
                   'version gets a release page. List what you will tag before you do it.'
                   % (PRODUCT, ', '.join(os.path.basename(p) for p in TAG_WORKFLOWS),
                      'runs' if _one else 'run'))
elif WORKFLOWS:
    _tag_effect = (' This repo has %s, and %s a tag push in its trigger block, so do not expect '
                   'the tag itself to build anything.'
                   % ('1 workflow file' if len(WORKFLOWS) == 1 else '%d workflow files' % len(WORKFLOWS),
                      'it does not name' if len(WORKFLOWS) == 1 else 'not one of them names'))
    _tag_prompt = ('Tag the untagged released versions in %s and push the tags so each version gets a '
                   'release page. Nothing here is known to build on a tag push, so do not wait on CI. '
                   'List what you will tag before you do it.' % PRODUCT)
elif FILES_READ:
    # The measured fact, and then nothing. No CI clause at all rather than a
    # softened one: the reader who was told to expect a build needs the
    # correction, and the prompt they paste needs no premise beyond the tag.
    _tag_effect = (' There is no <span class="mono">.github/workflows/</span> in this repo, so pushing '
                   'a tag starts no build here.')
    _tag_prompt = ('Tag the untagged released versions in %s and push the tags so each version gets a '
                   'release page. List what you will tag before you do it.' % PRODUCT)
else:
    # The tracked-file list could not be read, so whether anything builds is
    # unknown. The banner says the part that is true regardless and no more.
    _tag_effect = ''
    _tag_prompt = ('Tag the untagged released versions in %s and push the tags so each version gets a '
                   'release page. List what you will tag before you do it.' % PRODUCT)

if IS_GIT and UNTAGGED and releases:
    banners.append(banner('warn', '%d version%s shipped without a tag.'
                          % (len(UNTAGGED), '' if len(UNTAGGED) == 1 else 's'),
                          'The newest untagged one is <span class="mono">%s</span>. A version in the log with '
                          'no tag has no release page, which is where most people look.%s'
                          % (esc(UNTAGGED[0]['ver']), _tag_effect),
                          _tag_prompt, key='untagged'))

# --- stat tiles -----------------------------------------------------------
# Four renderings, kept apart on purpose: a measured number, a file that was
# never written, a file that could not be read, and a question that does not
# apply to this repo. Collapsing any of the last three into a zero is how a
# dashboard starts lying, so each one has its own glyph and its own reason.
# `style` is an attribute string, not a value, and every existing caller omits
# it - a tile that passes nothing renders exactly the bytes it rendered before.
WIDE = ' style="grid-column:1/-1"'

def tile_num(label, n, detail, level='', style='', href='', go=''):
    """A measured value. The number is real; level is 'att', 'warn' or ''.

    A tile at 'att' or 'warn' is drawn as something that needs a person, and a
    thing that needs a person is a link to where that person acts - the banner
    carrying its prompt, or the section listing the items behind the number. A
    tile at '' is calm and stays a div: making the quiet tiles clickable spends
    the signal the loud ones carry, which is the only thing the colour buys.
    `go` names the destination in the tile rather than leaving the reader to
    hover and guess, and every caller that passes neither renders exactly the
    bytes it rendered before."""
    if not href:
        return ('<div class="stat %s"%s><span class="stat-l">%s</span>'
                '<span class="stat-n">%s</span><span class="stat-d">%s</span></div>'
                % (level, style, esc(label), esc(n), detail))
    return ('<a class="stat lk %s"%s href="%s"><span class="stat-l">%s</span>'
            '<span class="stat-n">%s</span><span class="stat-d">%s</span>'
            '<span class="stat-go">%s</span></a>'
            % (level, style, esc('#' + href), esc(label), esc(n), detail, esc(go)))

def tile_absent(label, why, style=''):
    """Never run. An em dash, and what it costs that it was never run."""
    return ('<div class="stat"%s><span class="stat-l">%s</span>'
            '<span class="stat-n n-absent" title="%s">—</span>'
            '<span class="stat-d">not run · %s</span></div>'
            % (style, esc(label), esc(why), esc(why)))

def tile_unknown(label, why, style=''):
    """Read and not understood, or not derivable. Never a zero."""
    return ('<div class="stat unk"%s><span class="stat-l">%s</span>'
            '<span class="stat-n n-unknown" title="%s">?</span>'
            '<span class="stat-d">unknown · %s</span></div>'
            % (style, esc(label), esc(why), esc(why)))

def tile_na(label, why, style=''):
    """The fourth answer: read, and the question does not apply. Not a failure
    and not a zero - and the one a dashboard usually spends as a zero, because
    n/a and 0 look the same until someone acts on the difference."""
    return ('<div class="stat"%s><span class="stat-l">%s</span>'
            '<span class="stat-n n-absent" title="%s">n/a</span>'
            '<span class="stat-d">not applicable · %s</span></div>'
            % (style, esc(label), esc(why), esc(why)))

stats = []

if spec is None:
    stats.append(tile_absent('Contradictions waiting',
                             'no %s; nothing has been classified' % SPEC_PATH))
else:
    lvl = 'att' if contra_open else ''
    ids = ', '.join(c['id'] for c in contradictions if c['open'])
    stats.append(tile_num('Contradictions waiting', str(contra_open),
                          esc(ids + ' · nothing merges until ruled') if contra_open
                          else 'none open in the concerns table', lvl,
                          href=BN.get('contra', '') if contra_open else '',
                          go='→ the banner, and the prompt that quotes both sides'))

if check_state == 'absent':
    stats.append(tile_absent('Checks, last run',
                             'no %s; nothing has been checked' % RESULT_PATH))
elif check_state == 'unreadable':
    stats.append(tile_unknown('Checks, last run',
                              '%s exists and would not parse' % RESULT_PATH))
else:
    # A check that was never triggered and a check that failed are different
    # facts, and collapsing them printed a red tile with the word PASS on it -
    # the colour saying stop and the headline saying fine. Untriggered is amber:
    # nothing was wrong, and nothing was checked either. Only a real failure is
    # red, and only an all-clear says PASS.
    # Only an `always` check that did not run is a gap. A path- or tag-scoped
    # check that did not match is not applicable to this change, and counting
    # it turned the tile amber on every commit that touched no shell script -
    # which is how an amber signal stops meaning anything.
    #
    # These are the three lists the banner above was built from, derived once
    # beside `bad_checks`. They are read here rather than recomputed: the
    # recomputation was the bug, not the arithmetic.
    unrun, na, failed = CHK_UNRUN, CHK_NA, CHK_FAILED
    if failed:
        head, lvl = 'FAIL', 'att'
        # The denominator drops the not-applicable here too. `1 of 3 failed` of
        # a run where one of the three never applied is a fraction of a set the
        # check was never in.
        detail = '%d of %d failed' % (len(failed), len(checks) - len(na))
        if unrun:
            detail += ' \u00b7 %d never ran' % len(unrun)
        if na:
            detail += ' \u00b7 %d not applicable to this change' % len(na)
    elif unrun:
        head, lvl = 'PARTIAL', 'warn'
        # Neither the gaps nor the not-applicable ones ran, so neither counts
        # among the passing. The denominator drops the not-applicable too:
        # a check that does not apply to this change was never in the running.
        ran = len(checks) - len(unrun) - len(na)
        detail = ('%d of %d ran and passed \u00b7 %d never triggered, so %s not checked'
                  % (ran, ran + len(unrun), len(unrun),
                     'it was' if len(unrun) == 1 else 'they were'))
        if na:
            detail += ' \u00b7 %d not applicable to this change' % len(na)
    else:
        head, lvl = str(verdict or 'unstated').upper(), ''
        # Do not count the not-applicable ones among the passing ones. Saying
        # "3 all passing \u00b7 1 not applicable" of three checks is two claims
        # that cannot both be true.
        ran = len(checks) - len(na)
        detail = '%d check(s), all passing' % ran
        if na:
            detail += (' \u00b7 %d not applicable to this change'
                       % len(na))
    # Not the banner: the banner names which checks, and the question this
    # tile raises is what each one examined. That is the per-check table, and
    # it lives on another tab, so the link opens the tab as well as jumping.
    stats.append(tile_num('Checks, last run', head, esc(detail), lvl,
                          href=STAGE5_ID if lvl else '',
                          go='→ Stages · the last run, per check'))

if spec is None:
    stats.append(tile_absent('Requirements with no test',
                             'no spec; there is no acceptance table to compare'))
else:
    lvl = 'warn' if untested else ''
    stats.append(tile_num('Requirements with no test', str(len(untested)),
                          esc('of %d active · %s' % (len(spec_ids), ', '.join(untested[:6])))
                          if untested else esc('of %d active · %d acceptance rows'
                                               % (len(spec_ids), ac_rows)), lvl,
                          href=BN.get('untested', '') if untested else '',
                          go='→ the banner, and the prompt that asks you id by id'))

if spec is None:
    stats.append(tile_absent('Living spec', 'Stage 2 has nothing to merge into'))
else:
    stats.append(tile_num('Living spec', str(len(spec_ids)),
                          esc('active · %d superseded, %d withdrawn of %d in the file'
                              % (spec_super, spec_withdrawn,
                                 len(spec_ids) + spec_super + spec_withdrawn))))

if backlog is None:
    stats.append(tile_absent('Backlog', 'intents arrive without a queue'))
else:
    by = {}
    for it in items:
        by[it['status']] = by.get(it['status'], 0) + 1
    d = ' · '.join('%d %s' % (v, esc(k)) for k, v in sorted(by.items())) or 'no items in the table'
    stats.append(tile_num('Backlog', str(len(items)), d))

if constit is None:
    stats.append(tile_absent('Constitution', 'intake has no prior gate'))
else:
    lvl = 'warn' if principles == 0 else ''
    stats.append(tile_num('Constitution', str(principles),
                          'principles ratified' if principles else 'file exists, nothing ratified', lvl,
                          href=BN.get('constitution', '') if principles == 0 else '',
                          go='→ the banner, and the prompt that drafts them'))

if not IS_GIT:
    # Not "no releases". There is no record to read, which is a different answer.
    stats.append(tile_unknown('Releases', 'not a git repository; there is no history to read'))
elif not releases:
    stats.append(tile_num('Releases', '0', 'no commit subject carries a version'))
else:
    stats.append(tile_num('Releases', str(len(releases)),
                          esc('%d tagged · latest %s' % (len(releases) - len(UNTAGGED), LATEST))))

if spec is None:
    stats.append(tile_absent('Spec last changed', 'the spec has never existed'))
elif not IS_GIT:
    stats.append(tile_unknown('Spec last changed', 'not a git repository'))
elif not SPEC_DATE:
    stats.append(tile_unknown('Spec last changed', 'on disk but never committed'))
else:
    stats.append(tile_num('Spec last changed', SPEC_DATE, 'last commit touching the spec'))

# Onboarding progress, spanning the row because it is about the whole spec
# rather than one number in it. Amber, not red: an unpromoted requirement is not
# blocking anything - it cannot halt Stage 2, which is exactly why nobody
# notices it - so it belongs with "soon", beside requirements with no test.
INF_LABEL = 'Inferred, awaiting promotion'
if not SPEC_EXISTS:
    stats.append(tile_absent(INF_LABEL,
                             'no %s; an import cannot be part-way through a spec that does not exist'
                             % SPEC_PATH, style=WIDE))
elif spec is None:
    stats.append(tile_unknown(INF_LABEL,
                              '%s exists and could not be read; a queue that could not be counted is '
                              'not an empty one' % SPEC_PATH, style=WIDE))
elif INF_RECORDED == 0:
    stats.append(tile_na(INF_LABEL,
                         'no requirement in this spec was ever drafted by import, so there is no queue '
                         'to be part-way through', style=WIDE))
elif inf_await:
    _weak = len([x for x in inf_await if x['weak']])
    stats.append(tile_num(INF_LABEL, str(len(inf_await)),
                          esc('of %d requirement(s) in the spec · %d promoted, %d rejected at import '
                              'recorded so far · %s · promotion is a human commit, and until it '
                              'happens none of these can halt Stage 2'
                              % (len(spec_all_ids), len(inf_promoted), len(inf_rejected),
                                 ', '.join(x['id'] for x in inf_await[:8])
                                 + ('…' if len(inf_await) > 8 else '')
                                 + ('' if not _weak else ' · %d at weak evidence' % _weak))),
                          'warn', style=WIDE, href=QUEUE_ID,
                          go='→ the queue below, one row per sentence waiting on you'))
else:
    _rej = ('' if not inf_rejected
            else ' and %d rejected at import' % len(inf_rejected))
    stats.append(tile_num(INF_LABEL, '0',
                          esc('a measured zero — %d promotion(s)%s recorded here and no marker left '
                              'unconfirmed, so this import was worked through rather than never started'
                              % (len(inf_promoted), _rej)), '', style=WIDE))

# --- kanban ---------------------------------------------------------------
def short(text, cap=96):
    """A card is a glance. Take the first sentence, and only that.

    Truncation is marked with an ellipsis so a shortened note never reads as a
    complete one - a card that silently ends early makes a partial claim look
    whole, which is the same failure as rendering unknown as zero.
    """
    t = ' '.join((text or '').split())
    if not t:
        return ''
    m = re.match(r'^(.{20,%d}?[.!?])\s' % cap, t)
    if m:
        one = m.group(1)
        return one if len(one) <= cap else one[:cap - 1].rstrip(' ,;:-') + '\u2026'
    if len(t) <= cap:
        return t
    return t[:cap - 1].rstrip(' ,;:-') + '\u2026'


def card(cid, title, note='', level='', href='', go=''):
    """A card in a board column. A card at 'att' or 'warn' is something holding
    work, so it is a link off the board to the thing that unholds it - the
    ruling, the check that failed, the row with the action on it. A card at ''
    is just where a piece of work sits and stays a div."""
    n = '<span class="kc-n">%s</span>' % esc(short(note)) if note else ''
    if not href:
        return ('<div class="kc %s"><span class="kc-id mono">%s</span>'
                '<span class="kc-t">%s</span>%s</div>' % (level, esc(cid), esc(title), n))
    return ('<a class="kc lk %s" href="%s"><span class="kc-id mono">%s</span>'
            '<span class="kc-t">%s</span>%s<span class="kc-go">%s</span></a>'
            % (level, esc('#' + href), esc(cid), esc(title), n, esc(go)))

cols = [('Backlog', []), ('Intake · 2', []), ('Build · 3', []),
        ('Check · 5', []), ('Review · 6', []), ('Gated · 8', [])]

# A blocked card goes to its Backlog row, which is where the note explaining the
# block, the Jira key, the ordering and the start-work prompt all are. The row
# itself is not linked back here: it is already the place the work is done, and
# a link from a thing to the thing you just came from is a loop, not a route.
for i, it in enumerate(items):
    st = it['status'].lower()
    if st in ('done',):
        continue
    if st in ('in-progress', 'in progress'):
        cols[1][1].append(card(it['id'], it['what'], it['note'] or 'at intake'))
    elif st == 'blocked':
        cols[0][1].append(card(it['id'], it['what'], it['note'] or 'blocked', 'att',
                               href=BK_ID[i], go='→ Backlog · the row, and what it is waiting on'))
    else:
        cols[0][1].append(card(it['id'], it['what'], it['note']))
for c in contradictions:
    if c['open']:
        cols[1][1].append(card(c['id'], c['what'] or 'contradiction', 'waiting on a ruling', 'att',
                               href=BN.get('contra', ''), go='→ the banner · rule it'))
if os.path.exists(rel('plan.md')):
    cols[2][1].append(card('plan.md', 'A build plan is committed', stage('3')['detail']))
# The index is the check's position in `checks`, not its position in CHK_ACT -
# CHECK_ID is keyed by the row the Stage 5 table will actually draw.
#
# CHK_ACT, not bad_checks: a scoped check that did not match this change is not
# work in flight, and a red card for it put the same false claim on the board
# that the banner was putting above it.
_check_pos = dict((id(c), i) for i, c in enumerate(checks))
for c in CHK_ACT:
    cols[3][1].append(card(c['id'], c['why'][:90] or c['id'], c['status'], 'att',
                           href=CHECK_ID[_check_pos[id(c)]],
                           go='→ Stages · what this check examined'))
if os.path.exists(rel('REVIEW.md')):
    _s6 = stage('6')
    cols[4][1].append(card('REVIEW.md', 'A review policy is in the tree', _s6['detail'],
                           'warn' if _s6['state'] == 'waiting' else '',
                           href='stage-6' if _s6['state'] == 'waiting' else '',
                           go='→ Stages · stage 6, and what it is holding'))
for i, r in enumerate(releases):
    if r['tag'] or len([x for x in releases[:i] if not x['tag']]) >= 3:
        continue
    cols[5][1].append(card(r['ver'], r['title'], 'shipped, never tagged — you press publish', 'warn',
                           href=REL_ID[i], go='→ Releases · this version'))

# Which stage each board column belongs to. The Board and the ring are the same
# cards counted twice, so they are derived from one list rather than two.
COL_STAGE = ['1', '2', '3', '5', '6', '8']
STAGE_ITEMS = {}
for _ci, _cs in enumerate(COL_STAGE):
    STAGE_ITEMS[_cs] = STAGE_ITEMS.get(_cs, 0) + len(cols[_ci][1])

# What is on the PERSON. Stage 1 is theirs by the legend's own words - the
# intent enters there - and everything else here is a card that is HOLDING work
# rather than moving it: a contradiction nobody ruled, a check that did not
# pass, a version shipped and never announced. Each is a thing only a person
# can unhold.
HUMAN_ITEMS = len(cols[0][1]) + contra_open + len(CHK_ACT) + len(cols[5][1])

kan_total = sum(len(c[1]) for c in cols)
kanban = '<div class="kanban">' + ''.join(
    '<div class="kcol"><div class="kcol-h"><span>%s</span><span class="kcol-c">%d</span></div>%s</div>'
    % (name, len(cards), ''.join(cards)) for name, cards in cols) + '</div>'

# --------------------------------------------------------------------------
# panel: dashboard
# --------------------------------------------------------------------------
# The count is the only thing on this panel that names a number of jobs without
# showing them, and the jobs are already on the page - directly above the tab
# bar. So it links there. The other branch stays plain text on purpose: there is
# no banner to jump to, and a link that lands on an empty region is worse than
# no link.
attention = len(banners)
sub = ('<a class="h-sub" href="#banners" title="Jump to the %d banner(s) above the tabs">'
       '%d thing%s need%s you</a>'
       % (attention, attention, '' if attention == 1 else 's', 's' if attention == 1 else '')) \
    if attention else '<span style="text-transform:none;letter-spacing:0">nothing is waiting on you</span>'

kan_note = ('' if kan_total else
            '<div class="empty" style="margin-top:10px"><b>Nothing is in flight.</b>'
            '<p>Not a rendering failure — an empty board. There is no backlog item, no open '
            'contradiction, no failing check and no untagged version in this repo, so there is nothing '
            'holding work anywhere. Inventing motion to fill these columns would be the same lie as a '
            'scanner reporting a grade for files it never opened.</p></div>')

# --------------------------------------------------------------------------
# the promotion queue, as a list somebody can work from
# --------------------------------------------------------------------------
# Four renderings, and the difference between them is the feature. "There is no
# spec" and "every one has been promoted" are both quiet screens, and a
# dashboard that draws them the same way tells the reader an unread import is
# finished work.
QH = ('<div class="h" id="%s" style="margin-top:26px">Inferred requirements — '
      'the promotion queue</div>' % QUEUE_ID)

QPROV = (
    '<p class="provenance">Read from <span class="mono">%s</span>: a requirement is in this queue while '
    'the lines under it carry <span class="mono">Inferred from … Unconfirmed.</span>, and it leaves '
    'the queue when a person deletes that line, adds its acceptance row and records the ratification. '
    '<b>What this number does not tell you:</b> nothing here has been judged true — a citation says '
    'where a sentence was read from, not that the sentence is right, and a citation that no longer '
    'resolves still counts. Promotion deletes the marker, so the promoted figure is only what the '
    'decision record records: a row naming an id this spec has, reading as a confirmation, and saying '
    'the id came from the import. A promotion written down any other way is invisible here and is not '
    'counted — unread is not the same as missing. These ids also appear under <b>Requirements with '
    'no test</b>, because the acceptance table is for agreed requirements and an inferred one is given '
    'no row on purpose. And none of them can trigger the Stage 2 contradiction halt until somebody '
    'promotes them, so a large number here is a spec that is not yet defending anything.</p>'
    % esc(SPEC_PATH))

if not SPEC_EXISTS:
    p_queue = (QH + '<div class="empty"><b>This cannot be determined.</b>'
               '<p>There is no <span class="mono">%s</span> to read markers out of, so this page does '
               'not know whether an import ever ran, how many sentences it drafted, or how many are '
               'still waiting on a person. That is not a queue of zero. A zero is an answer somebody '
               'earned; this is the absence of one, and the two are drawn differently here on '
               'purpose.</p></div>' % esc(SPEC_PATH))
elif spec is None:
    p_queue = (QH + '<div class="empty"><b>The spec is there and could not be read.</b>'
               '<p><span class="mono">%s</span> exists and this run could not open it, so the count '
               'above is unknown rather than zero. A queue that could not be counted is not an empty '
               'queue — rendering it as one is the precise failure the inferred status exists to '
               'prevent, and it would be doing it on the tile that reports that status.</p></div>'
               % esc(SPEC_PATH))
elif INF_RECORDED == 0:
    p_queue = (QH + '<div class="empty"><b>Not applicable — nothing here was drafted by an import.</b>'
               '<p><span class="mono">%s</span> was read in full: %d requirement(s), not one of them '
               'carrying an <span class="mono">Inferred from … Unconfirmed.</span> marker, none '
               'withdrawn as <span class="mono">Rejected at import:</span>, and no decision-record row '
               'ratifying an imported id. This spec was written an intent at a time, so there is no '
               'promotion queue to be part-way through — which is a different answer from having '
               'worked one to the end, and is drawn differently for that reason.</p></div>'
               % (esc(SPEC_PATH), len(spec_all_ids)))
elif not inf_await:
    _done = '%d promotion(s) recorded (%s)' % (len(inf_promoted), ', '.join(inf_promoted) or 'none named')
    if inf_rejected:
        _done += ' and %d rejected at import (%s)' % (len(inf_rejected), ', '.join(inf_rejected))
    p_queue = (QH + ('<div class="empty"><b>Worked to the end — a measured zero.</b>'
               '<p>An import did run against this spec: %s. No <span class="mono">Unconfirmed.</span> '
               'marker is left anywhere in <span class="mono">%s</span>, so every sentence the import '
               'drafted has been read by a person and either ratified or refused. That is the finished '
               'state of this queue, and it is not the same picture as a repo that never imported '
               'anything.</p></div>' % (esc(_done), esc(SPEC_PATH))) + QPROV)
else:
    qrows = ['<div class="chkrow hd"><span>Requirement</span><span>Marker</span>'
             '<span>Drafted from</span></div>']
    for it in inf_await:
        short = it['what'] if len(it['what']) <= 120 else it['what'][:119] + '…'
        # A marker with no citation is shown as having none. The evidence rule
        # says one requirement, one citation, so a blank here is a finding.
        cite = it['cite'] or 'no citation in the marker'
        if not it['sealed']:
            chip, ccls = 'marker incomplete', 'unk'
            tip = 'the marker carries no "Unconfirmed.", so what this is waiting on is not stated'
        elif it['weak']:
            chip, ccls = 'weak evidence', 'unk'
            tip = ('cited from a doc, a CI job name or an inventory entry rather than from code or a '
                   'test - the marker says so, and dropping that is how it starts looking measured')
        else:
            chip, ccls = 'unconfirmed', ''
            tip = '"Unconfirmed." is what every later stage keys off'
        qrows.append('<div class="chkrow r"><span class="ci" title="%s">%s — %s</span>'
                     '<span class="cs %s" title="%s">%s</span>'
                     '<span class="cc" title="%s">%s</span></div>'
                     % (esc(it['what'] or 'no sentence was read for this id'), esc(it['id']),
                        esc(short or '—'), ccls, esc(tip), esc(chip),
                        esc(cite), esc(cite)))
    batch = [x['id'] for x in inf_await[:10]]
    p_queue = (QH +
               '<div class="relnote"><b>Nothing in this list is agreed.</b> Each one is a sentence '
               'drafted from code that already runs, and it stays inert — no contradiction halt, no '
               'acceptance row — until a person reads it and says so. Promotion is a commit: delete '
               'the marker line, add the acceptance row, record who ratified it and when.</div>'
               '<div class="chk">%s</div>'
               '<div class="bkfoot">%s</div>' % (''.join(qrows), cp(
                   'Walk me through the inferred requirements in %s one batch at a time, starting with '
                   '%s. Quote each sentence in full with the citation it carries, and take my answer by '
                   'id. Promote nothing I did not name, and do not treat silence as a yes.'
                   % (SPEC_PATH, ', '.join(batch)),
                   'copy prompt · confirm the first batch')) + QPROV)

p_dash = (
    '<div class="h">How it is going — %s</div>'
    '<div class="stats">%s</div>'
    '%s'
    '<p class="provenance">Every number here was read at generation time: '
    '<span class="mono">%s</span> for requirement counts, contradictions and the promotion queue '
    'above, <span class="mono">%s</span> for the backlog tile, '
    '<span class="mono">%s</span> for the last check run, and the git log for releases. '
    'The cards those same files put in flight are drawn on the <b>Board</b> tab, which is where '
    'the in-flight count beside it comes from. '
    'A tile showing <b>—</b> was never run; a tile showing <b>?</b> was read and could not be '
    'understood. Neither is a zero.</p>'
    % (sub, ''.join(stats), p_queue, SPEC_PATH, BACKLOG_PATH, RESULT_PATH))

# --------------------------------------------------------------------------
# panel: board
# --------------------------------------------------------------------------
# The count on the tab is the number of cards actually in flight - but only when
# every column could be counted. An unreadable checks-result leaves `checks`
# empty, so the Check column would draw a confident zero over a number nobody
# read. That case reports itself as unknown, on the tab and on the panel, for
# the same reason every other unknown on this page does.
BOARD_COUNTABLE = check_state != 'unreadable'
board_count = str(kan_total) if BOARD_COUNTABLE else '—'
board_note = '' if BOARD_COUNTABLE else (
    '<div class="relnote"><b>This board is short by an unknown number of cards.</b> '
    '<span class="mono">%s</span> is present and would not parse, so the checks it records could '
    'not be read and the <b>Check · 5</b> column below is drawn from nothing. The count on the '
    'tab reads <b>—</b> rather than a total this page cannot stand behind.</div>' % esc(RESULT_PATH))

p_board = (
    '<div class="h">In flight — one card per thing actually moving</div>'
    '%s%s%s'
    '<p class="provenance">Every card was read at generation time: '
    '<span class="mono">%s</span> for backlog items, <span class="mono">%s</span> for open '
    'contradictions, <span class="mono">%s</span> for checks that did not pass, '
    '<span class="mono">plan.md</span> and <span class="mono">REVIEW.md</span> asked of the '
    'filesystem, and the git log for versions shipped without a tag. A card sits in the column of '
    'the stage that is <i>holding</i> it, not the one it will reach next, and nothing here is '
    'carried over from a previous run.</p>'
    % (board_note, kanban, kan_note, BACKLOG_PATH, SPEC_PATH, RESULT_PATH))

# --------------------------------------------------------------------------
# the setup checklist  (rendered above the tabs, not as a panel)
# --------------------------------------------------------------------------
TICK = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" '
        'stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>')

SETUP = [
    ('0',  'Bind',         'Repo, source of truth and product written to <span class="mono">%s</span>. Asked once.' % CFG_PATH,
     'Show me the sdlc binding for %s and check the spec path is committable.'),
    ('0a', 'Scaffold',     'Empty living spec with the allocator at <span class="mono">R1</span>, <span class="mono">REVIEW.md</span>, <span class="mono">CLAUDE.md</span> if absent. Never overwrites.',
     'Scaffold %s for the SDLC lifecycle: an empty .claude/productizer/spec.md with the allocator at R1, a REVIEW.md, and a CLAUDE.md if absent. Check .gitignore first and do not overwrite anything.'),
    ('0b', 'Schedule',     'Band check and the nightly eval regression. Refuses to install an eval task against an empty suite.',
     'Install the sdlc-bands scheduled task for %s on an hourly cron.'),
    ('0c', 'Import',       'Only for a repo that already has history. A read-only survey drafts at most 30 requirements, every one marked <span class="mono">inferred</span> until a human confirms it.',
     'Run the import survey on %s and draft a first spec from it. Mark every requirement inferred with the file, line or test it came from, and do not let any of them trigger the contradiction halt until I confirm them.'),
    ('0d', 'Constitution', 'Principles intake checks every delta against, in <span class="mono">%s</span>.' % CONST_PATH,
     'Draft a constitution for %s from how this repo already works. Number the principles P1 upward and do not ratify any of them without asking me.'),
]

# Four states, four markers, four classes - the same vocabulary the stat tiles
# already use: a tick is measured done, `n/a` is read and does not apply here,
# `?` is read and could not be determined, `—` has not run. An inapplicable
# item and an unperformed one are different facts, and reporting one as the
# other is the exact failure the rest of this page exists to prevent.
SETUP_MARK = {'ok':      (TICK,  'done'),
              'n/a':     ('n/a', 'na'),
              'unknown': ('?',   'unk')}

setup_html = []
setup_done, setup_todo, setup_na, setup_unk = 0, 0, 0, 0
settled_na, settled_unk = [], []
for sid, name, what, prompt in SETUP:
    if sid == '0b':
        st, detail = 'unknown', 'scheduled tasks live outside the tree; this page cannot see them'
    else:
        r = stage(sid)
        st, detail = r['state'], r['detail']
    icon, cls = SETUP_MARK.get(st, ('—', 'todo'))
    if cls == 'done':
        setup_done += 1
    elif cls == 'na':
        setup_na += 1;  settled_na.append(sid)
    elif cls == 'unk':
        setup_unk += 1; settled_unk.append(sid)
    else:
        setup_todo += 1
    setup_html.append(
        '<div class="sx %s"><span class="sxi">%s</span><div><span class="sxt">%s · %s</span>'
        '<span class="sxd">%s</span><span class="sxd" style="opacity:.75">%s — %s</span></div>%s</div>'
        % (cls, icon, esc(sid), esc(name), what,
           esc(st), esc(detail), cp(prompt % PRODUCT)))

# Setup is not a tab. This page exists to show what needs a person, so the gate
# is what needs a person - not how many items carry ticks. `ok` needs nobody.
# `n/a` needs nobody by definition. `unknown` needs nobody either: 0b is always
# unknown because scheduled tasks live outside the tree, and no work the reader
# does will ever flip it from this page. Gating on setup_done == len(SETUP)
# would mean 0b and 0c could never both tick and the block could never leave -
# a checklist pinned to every page forever, which is worse than the tab it
# replaced. Only a genuine `todo` holds it open.
#
# It renders whole while it is up: the settled items stay on screen with their
# own markers, because a filtered view would leave the reader hunting for ticks
# that are never coming.
if setup_todo:
    _settled = []
    if setup_done:
        _settled.append('%d done' % setup_done)
    if setup_na:
        _settled.append('%d not applicable to this repo (%s)' % (setup_na, ', '.join(settled_na)))
    if setup_unk:
        _settled.append('%d this page cannot see (%s)' % (setup_unk, ', '.join(settled_unk)))
    _rest = (' The other %d need nobody: %s — those will never tick, and they are not waiting on you.'
             % (len(SETUP) - setup_todo, esc(', '.join(_settled)))) if _settled else ''
    setup_bar = (
        '<div class="bn warn setupbar"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" '
        'stroke="#d29922" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>'
        '<div class="setupbody">'
        '<p><b>Setup — %d of %d still %s you.</b> Once per repo, before the loop runs.%s '
        'Each state is <b>stage-status.sh</b>\'s answer for that stage, not a second reading of the '
        'tree: a tick is done, <b>n/a</b> was read and does not apply here, <b>?</b> was read and '
        'could not be determined — <span class="mono">0b</span> always is, because scheduled tasks '
        'are not files and a page cannot see your machine — and <b>—</b> has not run. Only the '
        '<b>—</b> items are waiting on you, and this block is not drawn at all once the last of '
        'them is done.</p>'
        '<div class="setup">%s</div></div></div>'
        % (setup_todo, len(SETUP), 'needs' if setup_todo == 1 else 'need', _rest,
           ''.join(setup_html)))
else:
    setup_bar = ''

# --------------------------------------------------------------------------
# panel: stages  (var S)
# --------------------------------------------------------------------------
# The two comparison panes describe the lifecycle itself. They are the same for
# every repo and are labelled as such under the ring; everything else on this
# panel is this repo's own state.
LIFECYCLE = {
 '1': ('human', 'you describe the problem', 'issue opened',
       'Requirements gathered by committee, distilled through workshops and sign-offs, written up by hand.',
       'An intent arrives as an issue, typed text or a file. It is an input, not an artifact.',
       'An intent is captured against the queue in front of the lifecycle. It is classified before anything is planned.',
       [BACKLOG_PATH, CFG_PATH]),
 '2': ('agent', 'you rule contradictions', 'delta merged',
       'A specification document written once, then left to rot beside the code it stopped describing.',
       'One living spec, always current. Every intent is classified against the whole of it before it merges.',
       'Intake classifies an intent as extend, refine, duplicate or contradict. A contradiction stops the work until a human rules.',
       [SPEC_PATH, CONST_PATH]),
 '3': ('agent', 'you approve the plan', 'plan.md committed',
       'Design decided in tickets and hallway conversations, rediscovered later from the diff.',
       'Plan mode first: files, order, risks and proof written down before a line is generated.',
       'The build is planned from the delta the spec gained, not from the intent.',
       ['plan.md', 'CLAUDE.md']),
 '4': ('agent', '', 'verification declared',
       'Tests written after the fact, to the shape of the code rather than the requirement.',
       'How the repo is verified is declared in CLAUDE.md, and the acceptance table says which requirement each test proves.',
       'Verification before done. The repo states how it is checked, in a file, not in someone\'s head.',
       ['CLAUDE.md', CHECKS_PATH]),
 '5': ('agent', '', 'checks pass or refuse',
       'A green pipeline that ran nothing, and nobody looks at what it covered.',
       'Declared checks with declared coverage. A check that examined less than it claimed fails as hollow.',
       'No model in this path. Stage 5 runs declared scripts and compares coverage against what they said they would cover.',
       [CHECKS_PATH, RESULT_PATH]),
 '6': ('agent', 'you approve the PR', 'human approval',
       'Deploy rights spread across whoever asked, with the gate living in a wiki page.',
       'The agent acts up to the production gate and never past it. Approval is a person, every time.',
       'Review policy and the production gate. An agent cannot approve its own code.',
       ['REVIEW.md', '.claude/hooks/production-gate.sh']),
 '7': ('agent', 'you edit the draft', 'notes drafted',
       'Release notes written from the changelog on the afternoon of the release.',
       'Notes drafted per release from the spec deltas the release contains.',
       'Runs per release, not per intent. The agent drafts from what actually changed.',
       [SPEC_PATH, 'README.md']),
 '8': ('agent', 'you press publish', 'publish gate',
       'Anyone with credentials can publish, and the first anyone knows is the tweet.',
       'Publishing is gated by a hook that fails closed. The agent drafts; a person publishes.',
       'The publish gate refuses the publishing commands until a person has approved the thing being published.',
       ['.claude/hooks/publish-gate.sh', CFG_PATH]),
 '9': ('agent', 'you triage', '3σ breach re-enters at Plan',
       'Dashboards nobody reads, and an incident channel as the only feedback path.',
       'Control bands on real signals. A 3σ breach opens an issue and re-enters the loop at Plan.',
       'A breach proposes; it does not act. Rolling back is a deploy, and an unattended run has nobody to authorise one.',
       ['ops/bands.yaml', '.claude/productizer/bands.yaml']),
}

def file_rows(paths_):
    """present / missing, checked now. Nothing here is remembered from a prior run."""
    rows = []
    for p in paths_:
        exists = os.path.exists(rel(p))
        rows.append([p, 'in the tree' if exists else 'not in the tree',
                     'present' if exists else 'missing', blob(p) if exists else ''])
    return rows

S = []
CUR0 = 0
for sid in ['1', '2', '3', '4', '5', '6', '7', '8', '9']:
    r = stage(sid)
    actor, gatedby, gate, trad, native, what, files = LIFECYCLE[sid]
    mnum = re.match(r'^(\d+)\b', r['detail'])
    S.append({
        'n': sid, 'actor': actor, 'gatedBy': gatedby,
        'name': r['name'] or {'1': 'Plan', '2': 'Design', '3': 'Build', '4': 'Test',
                              '5': 'Check', '6': 'Deploy', '7': 'Document',
                              '8': 'Announce', '9': 'Maintain'}[sid],
        'gate': gate, 'live': r['state'] == 'ok',
        'items': STAGE_ITEMS.get(sid, 0),
        'count': mnum.group(1) if mnum else '—',
        'unit': r['state'], 'trad': trad, 'native': native,
        'state': '%s — %s' % (r['state'], r['detail']),
        'mods': [{'id': sid, 'name': r['name'] or sid, 'what': what,
                  'files': file_rows(files),
                  'acts': [['Where this stage stands',
                            'In %s, show me what stage %s (%s) is holding right now and what would '
                            'move it. Read it from the files; do not assume.'
                            % (PRODUCT, sid, r['name'] or sid)]]}],
    })
for i, s_ in enumerate(S):
    if s_['live']:
        CUR0 = i
for i, s_ in enumerate(S):
    if s_['unit'] in ('blocked', 'waiting'):
        CUR0 = i
        break

badge_note = ('' if STAGE_STATUS_OK else
              '<div class="empty" style="margin-bottom:16px"><b>Stage state is unknown.</b>'
              '<p><span class="mono">stage-status.sh</span> produced no rows this run, so every stage '
              'below is drawn as unknown rather than as not run. The two are different answers and this '
              'page will not substitute one for the other.</p></div>')

# --------------------------------------------------------------------------
# panel: files
# --------------------------------------------------------------------------
rows = []
for p in paths:
    seg = p.split('/')
    cat = seg[0] if len(seg) > 1 else 'root'
    d = describe(p)
    desc = ('<td class="fdesc">%s</td>' % esc(d)) if d else (
        '<td class="fdesc none" title="no heading, leading comment or description field in this file">'
        '—</td>')
    dt = file_dates.get(p)
    if dt:
        date = '<td class="fdate" data-sort="%s">%s</td>' % (esc(dt), esc(dt.replace('T', ' ')))
    elif not IS_GIT:
        date = ('<td class="fdate none" data-sort="" title="not a git repository; there is no '
                'commit date to read">—</td>')
    else:
        date = ('<td class="fdate none" data-sort="" title="on disk, never committed">'
                '—</td>')
    url = blob(p)
    name = ('<a class="fname" href="%s" target="_blank" rel="noopener">%s%s</a>' % (url, esc(p), EXTLINK)) \
        if url else ('<span class="fname" style="color:var(--muted)">%s</span>' % esc(p))
    rows.append('<tr><td class="fcat">%s</td><td>%s</td>%s%s</tr>' % (esc(cat), name, desc, date))

if rows:
    src = 'git ls-files' if tracked else 'a walk of the directory (this is not a git repository)'
    p_files = (
        '<div class="h">Every file — click a header to sort</div>'
        '<div class="tw"><table class="ftbl"><thead><tr>'
        '<th class="so" data-col="0">Category<i></i></th><th class="so" data-col="1">File<i></i></th>'
        '<th class="so" data-col="2">What it is<i></i></th><th class="so" data-col="3">Last change<i></i></th>'
        '</tr></thead><tbody>%s</tbody></table></div>'
        '<p class="provenance">%d file(s), listed from <span class="mono">%s</span>. '
        '“What it is” is the file\'s own first heading, leading comment or '
        '<span class="mono">description</span> field — never a description written for it. '
        'A file that says nothing about itself shows an em dash.</p>'
        % (''.join(rows), len(rows), esc(src)))
else:
    p_files = ('<div class="empty"><b>No files.</b><p>Nothing was found under '
               '<span class="mono">%s</span> — neither tracked by git nor on disk.</p></div>'
               % esc(ROOT))

# --------------------------------------------------------------------------
# panel: backlog
# --------------------------------------------------------------------------
# Defined before the branch below: the tab count reads it whatever the backlog
# turns out to be, and an absent backlog must hide nothing rather than be
# undefined.
_done_hidden = 0
START = ('Start work on backlog item %s: "%s".\n\n'
         'Open it as an intent at Stage 1. Classify it against the whole living spec, including '
         'the constitution, before anything is planned.\n\n'
         'Then write the result into the files, in this order, and do not wait for me between '
         'steps: set its status to `in-progress`, and record the classification and what it was '
         'checked against in its Notes.\n\n'
         'Leave the Jira column as `-` unless this repo already has a tracker configured. If '
         'recording a ticket or issue number would mean creating one, do not create it - land '
         'everything else first, then ask me at the end as a separate question.\n\n'
         'The one thing that stops you: if it contradicts an agreed requirement, stop before '
         'changing any file, tell me which requirement, and merge nothing.')

if backlog is None:
    p_backlog = ('<div class="h">Backlog — the queue in front of the lifecycle</div>'
                 '<div class="empty"><b>There is no backlog.</b>'
                 '<p><span class="mono">%s</span> does not exist. That is not an empty queue — it '
                 'is no queue: intents arrive with nothing in front of them, so nothing records that '
                 'something was wanted before it was agreed, and priority lives wherever it was last '
                 'mentioned.</p>%s</div>' % (esc(BACKLOG_PATH), cp(
                     'Create %s for %s from the backlog template. Leave the Items table empty - do not '
                     'seed it with examples.' % (BACKLOG_PATH, PRODUCT), 'copy prompt')))
elif not items:
    p_backlog = ('<div class="h">Backlog — the queue in front of the lifecycle</div>'
                 '<div class="empty"><b>The backlog is empty.</b>'
                 '<p><span class="mono">%s</span> exists and its Items table has no <span class="mono">B</span> '
                 'rows. An empty backlog is a real answer and is drawn as one.</p>%s</div>'
                 % (esc(BACKLOG_PATH), cp(
                     'Add a backlog item to %s: <what is wanted, in the words of whoever wants it>. Give it '
                     'the next B id, status todo, and put it where I say in the order. Do not classify it - '
                     'that is intake\'s job.' % BACKLOG_PATH)))
else:
    lis = []
    _done_hidden = 0
    for rank, it in enumerate(items):
        if it['status'].strip().strip('`').lower() == 'done':
            _done_hidden += 1
            continue
        cls = re.sub(r'[^a-z-]', '-', it['status'].lower())
        if JIRA_SITE and it['jira']:
            j = ('<a class="bk-jira" href="%s/browse/%s" target="_blank" rel="noopener" '
                 'title="Status is read from Jira and never written back">%s</a>'
                 % (esc(JIRA_SITE), esc(it['jira']), esc(it['jira'])))
        elif it['jira']:
            j = ('<span class="bk-j mono" title="no jira.site in %s, so this key cannot be linked">%s</span>'
                 % (esc(CFG_PATH), esc(it['jira'])))
        else:
            j = '<span class="bk-nojira">—</span>'
        lis.append(
            '<li class="bk" id="%s" draggable="true" data-id="%s" data-rank="%d" data-st="%d">'
            '<span class="bk-grip" aria-hidden="true">⋮⋮</span>'
            '<span class="bk-id mono">%s</span><span class="bk-what">%s</span>'
            '<span class="bk-st %s" data-src="%s">%s</span><span class="bk-j">%s</span>'
            '<span class="bk-note">%s</span>%s</li>'
            % (BK_ID[rank], esc(it['id']), rank, it['rank'], esc(it['id']), esc(it['what']), esc(cls),
               'jira' if it['jira'] else 'local', esc(it['status']), j, esc(it['note']),
               '<button class="bk-act" data-copy="%s">start work</button>'
               % esc(START % (it['id'], it['what']))))
    p_backlog = (
        '<div class="h">Backlog — the queue in front of the lifecycle</div>'
        '<div class="relnote"><b>Nothing here is agreed.</b> These are wants, not requirements. '
        '<b>Order is the priority</b>; there is no priority field, because two orderings disagree the '
        'moment someone edits one and not the other. Drag to rearrange.</div>'
        + (('<div class="bkhidden">%d item(s) with status <span class="mono">done</span> are not '
            'shown. <b>They left the queue</b> - merged as a requirement, ruled a duplicate, or '
            'refused - and the spec records which. They are still in <span class="mono">%s</span>; '
            'this is a view of what is still in front of you, not of what was ever wanted.</div>'
            % (_done_hidden, esc(BACKLOG_PATH))) if _done_hidden else '')
        + '<div class="bksort">Sort <button class="sb on" data-s="rank">rank</button>'
        '<button class="sb" data-s="status">status</button>'
        '<span class="bksort-n" id="bksortnote">order is the priority — drag to change it</span></div>'
        '<div class="bkhead"><span class="bk-grip"></span><span class="bk-id">Id</span>'
        '<span class="bk-what">What is wanted</span><span class="bk-st">Status</span>'
        '<span class="bk-j">Jira</span><span class="bk-note">Notes</span>'
        '<span class="bk-acth">Action</span></div>'
        '<ul class="bklist" id="bklist">%s</ul>'
        '<div class="bkfoot"><button class="cp" id="bkcopy" data-copy="">copy the reordered backlog</button>%s</div>'
        '<p class="provenance">Read from <span class="mono">%s</span>, columns mapped from that table\'s '
        'own header. Dragging composes an edit; it does not make one — a published page has no '
        'filesystem, and the file stays the only edit surface.%s</p>'
        % (''.join(lis), cp(
            'Add a backlog item to %s: <what is wanted, in the words of whoever wants it>. Give it the '
            'next B id, status todo, and put it where I say in the order. Do not classify it - that is '
            'intake\'s job.' % BACKLOG_PATH, 'copy prompt · add an item'),
           esc(BACKLOG_PATH),
           '' if JIRA_SITE else ' No <span class="mono">jira.site</span> is configured, so any Jira key '
           'is shown as plain text rather than linked to a site this page had to invent.'))

# --------------------------------------------------------------------------
# panel: releases
# --------------------------------------------------------------------------
if not IS_GIT:
    p_rel = ('<div class="h">Release history</div><div class="empty"><b>There is no history.</b>'
             '<p><span class="mono">%s</span> is not a git repository, so there is no commit log to read '
             'releases from. This is not "no releases" — it is no record at all.</p></div>' % esc(ROOT))
elif not releases:
    p_rel = ('<div class="h">Release history</div><div class="empty"><b>No commit subject carries a version.</b>'
             '<p>%d commit(s) were read from the log and none of them begins with a version like '
             '<span class="mono">v1.2.3:</span>. Releases are read from the subjects, so this page has '
             'nothing to show rather than something invented.</p></div>' % len(commits))
else:
    parts = []
    for _ri, r in enumerate(releases):
        tag = ('<span class="rtag">tagged %s</span>' % esc(r['tag'])) if r['tag'] \
            else '<span class="rtag warn">no tag</span>'
        sha = ('<a class="relsha mono" href="https://github.com/%s/commit/%s" target="_blank" '
               'rel="noopener">%s</a>' % (esc(GH), esc(r['sha']), esc(r['short']))) if GH \
            else '<span class="relsha mono">%s</span>' % esc(r['short'])
        bl = ''.join('<li>%s</li>' % esc(b) for b in r['bullets'])
        if not bl:
            bl = ('<li style="opacity:.7">The commit for this version has an empty body, so there is '
                  'nothing to list.</li>')
        dot = 'muted' if r['tag'] else 'warn'
        parts.append(
            '<div class="rel" id="%s"><div class="relside"><span class="relv mono">%s</span>'
            '<span class="reldot %s"></span></div><div class="relbody"><div class="relhead">'
            '<h3>%s</h3><span class="rkind %s">%s</span>%s<span style="flex:1"></span>%s'
            '<span class="reldate mono">%s</span></div><ul class="rlist">%s</ul></div></div>'
            % (REL_ID[_ri], esc(r['ver']), dot, esc(r['title']), '', esc(r['kind']), tag, sha,
               esc(r['date']), bl))
    p_rel = ('<div class="h">Release history — newest first</div>'
             '<div class="relnote"><b>%d of these %d carry a git tag.</b> A version in the log with no tag '
             'has no release page.</div><div class="rels">%s</div>'
             '<p class="provenance">Read from <span class="mono">git log</span>: a release is a commit '
             'whose subject begins with a version. The bullets are that commit\'s own message body, not a '
             'summary written for it. The <b>major / minor / patch</b> label is the bump against the '
             'next-older version, not a judgement about the change. Dates are commit times.</p>'
             % (len(releases) - len(UNTAGGED), len(releases), ''.join(parts)))

# --------------------------------------------------------------------------
# panel: commands
# --------------------------------------------------------------------------
def cmdcard(label, text, note):
    return ('<div class="cmd"><span class="cl">%s</span><span class="cx">%s</span>'
            '<div class="cr">%s<span class="cw">%s</span></div></div>'
            % (esc(label), esc(text), cp(text, 'copy'), esc(note)))

def cgrp(title, cards):
    return '<div class="cgrp"><div class="h">%s</div><div class="cmds">%s</div></div>' % (title, ''.join(cards))

p_cmds = (
    cgrp('Run the loop', [
        cmdcard('Capture an intent',
                'Capture this as an intent for %s and classify it against the living spec before '
                'anything is planned: <what you want>.' % PRODUCT, 'stage 1'),
        cmdcard('Run intake',
                'Run intake on the newest intent for %s and write the spec delta into %s.'
                % (PRODUCT, SPEC_PATH), 'stage 2'),
        cmdcard('Plan the delta',
                'Start plan mode for the newest spec delta in %s and write plan.md naming files, order, '
                'risks and proof.' % PRODUCT, 'stage 3'),
        cmdcard('Run the checks',
                'Run Stage 5 checks for %s from %s and show me the coverage each check reported, not '
                'just the verdict.' % (PRODUCT, CHECKS_PATH), 'stage 5 · no model in this path'),
    ]) +
    cgrp('Look at it', [
        cmdcard('Where does everything stand',
                'Run stage-status.sh on %s and tell me which stage is holding work and why.' % PRODUCT,
                'reads the tree, gates nothing'),
        cmdcard('This page, refreshed',
                'Rebuild the SDLC pipeline view for %s and republish it to the same URL.' % PRODUCT,
                'regenerated from the files each time'),
        cmdcard('The spec', 'Show me the living spec for %s as a view.' % PRODUCT,
                'publishes a read-only artifact'),
    ]) +
    '<p class="provenance">These are the lifecycle\'s own commands with this repo\'s names filled in '
    '(<span class="mono">%s</span>). They are not read from the repo and are not a claim about it.</p>'
    % esc(PRODUCT))

# --------------------------------------------------------------------------
# panel: stages (assembled here, now that the ring markup is needed)
# --------------------------------------------------------------------------
ARCS = ['M 314.1 79.0 A 196 196 0 0 1 359.0 95.4', 'M 426.5 152.0 A 196 196 0 0 1 450.4 193.4',
        'M 465.7 280.3 A 196 196 0 0 1 457.4 327.3', 'M 413.3 403.7 A 196 196 0 0 1 376.7 434.4',
        'M 293.9 464.5 A 196 196 0 0 1 246.1 464.5', 'M 163.3 434.4 A 196 196 0 0 1 126.7 403.7',
        'M 82.6 327.3 A 196 196 0 0 1 74.3 280.3', 'M 89.6 193.4 A 196 196 0 0 1 113.5 152.0',
        'M 181.0 95.4 A 196 196 0 0 1 225.9 79.0']

if checks:
    crows = ['<div class="chkrow hd"><span>Check</span><span>Status</span><span>Coverage</span></div>']
    for _ci, c in enumerate(checks):
        unk = c['status'] == 'unknown'
        if c['covered'] is None:
            cov = '<span title="the result file records no coverage for this check">coverage unknown</span>'
        elif c['from'] in ('stdout_paths', 'per_file_exit') and c['scope'] is not None:
            cov = '%s of %s file(s) in scope' % (esc(c['covered']), esc(c['scope']))
        else:
            # A count of something other than files is not a fraction of the
            # file scope, and printing it as one invents a denominator.
            cov = '%s counted<span style="opacity:.6"> · %s</span>' % (
                esc(c['covered']), esc(c['from'] or 'source not stated'))
        if c['satisfied'] is False:
            cov += '<span style="color:var(--warn)"> · below what it declared</span>'
        # A row that did not pass is a row somebody has to act on, and the
        # thing that carries the action is the banner: it names every one of
        # them and hands over the prompt that asks what each examined. It is
        # emitted exactly when bad_checks is non-empty, which is exactly when
        # a row here is bad - so the link is minted from BN rather than
        # assumed, and a row is left plain if the banner was not written.
        #
        # A check that passed while covering less than it declared is drawn
        # amber in the coverage cell and is NOT linked: no banner names it,
        # and nowhere else on this page says more about it than this row
        # already does. A link that lands somewhere silent about the thing the
        # reader clicked is the dead end this whole change exists to remove,
        # so it is left off and written down instead of invented.
        #
        # Which of the three a row is comes from the one classification, so the
        # row cannot be red while the tile says the check does not apply. A
        # scoped miss is neither linked nor coloured: no banner names it, and
        # a link into a banner silent about the thing clicked is the dead end
        # this rule exists to remove.
        _href = BN.get('checks', '') if id(c) in _CHK_ACT_IDS else ''
        _cls = ('unk' if (unk or id(c) in _CHK_UNRUN_IDS)
                else ('bad' if id(c) in _CHK_FAILED_IDS else ''))
        if _href:
            crows.append('<a class="chkrow r lk" id="%s" href="%s"><span class="ci">%s</span>'
                         '<span class="cs %s">%s</span><span class="cc">%s</span></a>'
                         % (CHECK_ID[_ci], esc('#' + _href), esc(c['id']), _cls,
                            esc(c['status']), cov))
        else:
            crows.append('<div class="chkrow r" id="%s"><span class="ci">%s</span>'
                         '<span class="cs %s">%s</span><span class="cc">%s</span></div>'
                         % (CHECK_ID[_ci], esc(c['id']), _cls, esc(c['status']), cov))
    checks_block = ('<div class="h" id="' + STAGE5_ID + '" style="margin-top:26px">Stage 5 — '
                    'the last check run, per check</div>'
                    '<div class="chk">%s</div>'
                    '<p class="provenance">Read from <span class="mono">%s</span>. Coverage is what each '
                    'check reported it examined; a check with no coverage recorded is shown as unknown, '
                    'never as nothing examined.</p>' % (''.join(crows), esc(RESULT_PATH)))
elif check_state == 'unreadable':
    checks_block = ('<div class="h" id="' + STAGE5_ID + '" style="margin-top:26px">Stage 5</div>'
                    '<div class="empty">'
                    '<b>The result file would not parse.</b><p><span class="mono">%s</span> exists and is '
                    'not readable JSON. An unreadable result is not a passing one.</p></div>' % esc(RESULT_PATH))
else:
    checks_block = ('<div class="h" id="' + STAGE5_ID + '" style="margin-top:26px">Stage 5</div>'
                    '<div class="empty">'
                    '<b>Nothing has been checked.</b><p>There is no <span class="mono">%s</span>, so this '
                    'repo has no last check run — which is different from a run that found nothing.'
                    '</p></div>' % esc(RESULT_PATH))

p_stages = (
    '<div class="h">Click a stage</div>' + badge_note +
    '<div class="ringwrap"><svg class="ringsvg" viewBox="0 0 540 540" aria-hidden="true"><defs>'
    '<marker id="ah" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" '
    'orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"/></marker></defs>'
    + ''.join('<path class="arc" id="arc%d" d="%s" marker-end="url(#ah)"/>' % (i, d)
              for i, d in enumerate(ARCS)) +
    '</svg><div class="ringnodes" id="nodes"></div><div class="hub" id="hub"></div></div>'
    '<div class="legend">'
    '<span class="lg"><i class="sw human"></i>Stage 1 is yours — the intent enters here</span>'
    '<span class="lg"><i class="sw agent"></i>Stages 2–9 run as the agent</span>'
    '<span class="lg"><i class="sw gate"></i>You still rule contradictions, approve the PR, and triage</span></div>'
    '<div class="loopback"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#3fb950" '
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 2v6h6"/>'
    '<path d="M3 13a9 9 0 1 0 3-7.7L3 8"/></svg>'
    '<span>A 3σ breach in <b>Maintain</b> opens an issue and re-enters at <b>Plan</b></span></div>'
    '<div class="detail"><div class="dl"><div class="dhead"><span class="n" id="dnum"></span>'
    '<h2 id="dname"></h2><span class="badge" id="dbadge"></span>'
    '<span id="dactor" class="actorwrap"></span><span style="flex:1"></span>'
    '<select id="dmod" class="modsel" aria-label="Module"></select></div>'
    '<div class="dwhat" id="dwhat"></div><div class="cmps" id="dcmp"></div>'
    '<div class="state" id="dstate"></div>'
    '<div><div class="h" style="margin-bottom:8px">Files this stage touches</div>'
    '<div class="files" id="dfiles"></div></div></div>'
    '<div class="dr"><div class="h" style="margin:0">Do something — copy, paste to the agent</div>'
    '<div id="dacts" style="display:flex;flex-direction:column;gap:9px"></div></div></div>'
    + checks_block +
    '<p class="provenance">A stage\'s state, the sentence under it and its running/never-run badge all '
    'come from <span class="mono">stage-status.sh</span>. File chips are checked on disk at generation '
    'time. The <b>Traditional / AI-native</b> pair describes the lifecycle itself and reads the same for '
    'every repo — it is the only text on this panel that is not this repo\'s own state.</p>')

# --------------------------------------------------------------------------
# panel: limitations
# --------------------------------------------------------------------------
# R5 makes a check declare what it must have EXAMINED. This is the dual: what
# it could not SEE. Both belong beside the check, so both are read from
# checks.yaml - a limitation nobody wrote down is a limitation nobody knows
# about, which is the state this panel exists to end.
#
# Parsed by hand rather than with a YAML library ON PURPOSE. run-checks.sh
# refuses without PyYAML, correctly, because it decides what EXECUTES from that
# file. This page only displays; taking the same hard dependency would mean the
# dashboard stops rendering wherever PyYAML is missing - which is precisely
# what left this repo's CI red for its whole life. So: two keys, read
# line-wise, and anything unparseable is reported as unreadable rather than as
# nothing declared.
checks_raw = slurp(rel(CHECKS_PATH))
lim_by_check, lim_order, LIM_STATE = {}, [], 'read'
if checks_raw is None:
    LIM_STATE = 'unreadable'
else:
    cur, in_lims = None, False
    for raw in checks_raw.split('\n'):
        m = re.match(r'^  - id:\s*(\S+)\s*$', raw)
        if m:
            cur, in_lims = m.group(1), False
            if cur not in lim_by_check:
                lim_by_check[cur] = []
                lim_order.append(cur)
            continue
        if cur is None:
            continue
        if re.match(r'^    limitations:\s*$', raw):
            in_lims = True
            continue
        if in_lims:
            mm = re.match(r'^      - (.+?)\s*$', raw)
            if mm:
                lim_by_check[cur].append(mm.group(1))
                continue
            if raw.strip():
                in_lims = False

LIM_TOTAL = sum(len(v) for v in lim_by_check.values())
LIM_WITH = [c for c in lim_order if lim_by_check.get(c)]
LIM_WITHOUT = [c for c in lim_order if not lim_by_check.get(c)]

if LIM_STATE == 'unreadable':
    p_lims = ('<div class="h">Limitations \u2014 what the checks cannot see</div>'
              '<div class="empty"><b>%s could not be read.</b>'
              '<p>That is unknown, not none declared. A page reporting zero limitations '
              'because it could not open the file would be making the exact claim this '
              'panel exists to stop anyone making.</p></div>' % esc(CHECKS_PATH))
elif not lim_order:
    p_lims = ('<div class="h">Limitations \u2014 what the checks cannot see</div>'
              '<div class="empty"><b>No checks are declared.</b>'
              '<p>Nothing declares a limitation because nothing declares a check. '
              'Read from <span class="mono">%s</span>.</p></div>' % esc(CHECKS_PATH))
else:
    body = []
    for cid in LIM_WITH:
        ls = lim_by_check[cid]
        body.append(
            '<div class="limcard"><div class="limhead">'
            '<span class="mono limid">%s</span><span class="limn">%d</span></div>'
            '<ul class="limlist">%s</ul></div>'
            % (esc(cid), len(ls),
               ''.join('<li><span class="limtxt">%s</span>%s</li>'
                       % (esc(x), cp(LIMPROMPT % (PRODUCT, cid, x), 'discuss this'))
                       for x in ls)))
    und = ''
    if LIM_WITHOUT:
        und = ('<div class="limcard limund"><div class="limhead">'
               '<span class="mono limid">%d check(s) declare nothing</span></div>'
               '<ul class="limlist"><li>%s</li>'
               '<li><b>Undeclared, not none.</b> Every check on this page has something '
               'outside its reach, so an empty list is far more often nobody looking than '
               'nothing being there.</li></ul></div>'
               % (len(LIM_WITHOUT), esc(', '.join(LIM_WITHOUT))))
    p_lims = (
        '<div class="h">Limitations \u2014 what the checks cannot see</div>'
        '<p class="lede">Every check declares what it must have examined for its pass to '
        'count. These are the other half: what each one is blind to. '
        'A green run means these checks found nothing wrong \u2014 not that nothing is wrong.</p>'
        '<div class="limsum"><b>%d</b> limitation(s) across <b>%d</b> of <b>%d</b> declared checks</div>'
        '%s%s'
        '<p class="provenance">Read from <span class="mono">%s</span>, beside the check each one '
        'qualifies. A limitation is a committed claim like any other \u2014 it is reviewed in a '
        'diff and it goes stale the way a comment does. Nothing here is measured at run time.</p>'
        % (LIM_TOTAL, len(LIM_WITH), len(lim_order), ''.join(body), und, esc(CHECKS_PATH)))

# --------------------------------------------------------------------------
# assembly
# --------------------------------------------------------------------------
TABS = [('dash', 'Dashboard', ''),
        ('board', 'Board', board_count),
        ('stages', 'Stages', str(len(S))),
        ('files', 'Files', str(len(rows))),
        ('backlog', 'Backlog', str(len(items) - _done_hidden) if backlog is not None else '—'),
        ('rel', 'Releases', str(len(releases)) if IS_GIT else '—'),
        ('lims', 'Limitations', str(LIM_TOTAL) if LIM_STATE == 'read' else '\u2014'),
        ('cmds', 'Useful commands', '')]

tabs = ''.join('<button class="tab%s" data-p="%s">%s%s</button>'
               % (' on' if i == 0 else '', pid, esc(label),
                  '<span class="cnt">%s</span>' % esc(cnt) if cnt else '')
               for i, (pid, label, cnt) in enumerate(TABS))

# When the DATA last changed, which is not when the view was generated and not
# when the repo last had any commit. Taken from git rather than from the clock,
# because a wall-clock stamp would make two runs of an unchanged repo differ -
# and byte-identical output is what lets you tell a real change from a re-run.
_data_paths = [p for p in file_dates
               if p.startswith('.claude/productizer/') or p in ('REVIEW.md', 'CLAUDE.md')]
DATA_UPDATED = max((file_dates[p] for p in _data_paths), default='')

if IS_GIT and HEAD_SHA:
    stamp = 'generated from %s · %s' % (esc(HEAD_SHA), esc(HEAD_DATE or 'undated'))
else:
    stamp = 'generated from the directory · no git history'

if DATA_UPDATED:
    data_stamp = ('<span class="crumb mono" title="When the lifecycle files last changed in git. '
                  'Not when this page was generated - the page is regenerated from these files, '
                  'so a re-run with no change produces the same page.">data updated %s</span>'
                  % esc(DATA_UPDATED))
else:
    data_stamp = ('<span class="crumb mono" title="No lifecycle file has ever been committed, '
                  'so there is no date to report. This is not a stale page - it is an unstarted '
                  'one.">data updated &mdash; never committed</span>')

crumb = esc(SPEC_REPO or GH or PRODUCT)
verchip = ('<span class="verchip mono">%s <b>%s</b></span>' % (esc(PRODUCT), esc(LATEST))) if LATEST \
    else ('<span class="verchip mono">%s <b title="no commit subject carries a version">'
          '—</b></span>' % esc(PRODUCT))

# --------------------------------------------------------------------------
# the staleness notice
# --------------------------------------------------------------------------
# Off unless --stale-after asked for it, and the default of off is deliberate:
# everything below embeds a wall-clock generation time, which is the one value
# on this page that differs between two runs of an unchanged repo. Byte-stable
# output is how a reader tells a real change from a re-run, so it is only spent
# when somebody asks for the thing it buys.
#
# What the notice may claim is narrower than it looks, and the wording is the
# whole feature. The page knows exactly one thing: how long ago it was
# generated. It does not know whether anything in the repo has changed since -
# that needs a re-read, and a file served off disk cannot re-read anything. So
# it says the page is OLD. It never says the page is wrong: an hour-old page
# over an untouched repo is exactly right, and calling that stale would assert
# a comparison nobody made. The git-derived "data updated" stamp in the bar is
# left doing its own job beside this, because page age and data age are two
# different facts and neither substitutes for the other.
#
# It does not reload. A static file re-served is the same bytes, and a page
# that reloads itself teaches the reader that nothing changed when the truth is
# that nothing was re-measured. What makes this genuinely live is regeneration,
# so what the notice hands over is the command that regenerates it - the one
# that was actually run, argument for argument, not a guess at it.
STALE_CSS = ''
STALE = ''
if STALE_AFTER > 0:
    GEN_EPOCH = int(time.time())
    # position:fixed so it cannot push a line of the page down under a reader
    # mid-sentence, and no autofocus anywhere - role=status/aria-live=polite
    # announces it without taking the caret off whatever they were reading.
    # The transition is suppressed under prefers-reduced-motion here as well as
    # by the sheet-wide rule above it; two lines is cheaper than depending on
    # that rule still being there.
    STALE_CSS = (
        '\n.stalebox{position:fixed;right:16px;bottom:16px;z-index:40;'
        'max-width:min(460px,calc(100vw - 32px));background:var(--surface);'
        'border:1px solid var(--warn);border-left:3px solid var(--warn);border-radius:9px;'
        'padding:12px 14px;box-shadow:0 8px 24px #0009;display:flex;flex-direction:column;gap:9px;'
        'opacity:0;transition:opacity .18s ease}\n'
        '.stalebox.in{opacity:1}\n'
        '.stalebox[hidden]{display:none}\n'
        '.stalebox p{margin:0;font-size:12.5px;color:var(--muted)}\n'
        '.stalebox b{color:var(--text)}\n'
        '.stalebox code{font-family:var(--mono);font-size:11.5px;color:var(--text);'
        'background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:7px 9px;'
        'overflow-x:auto;white-space:pre}\n'
        '.stalebox .srow{display:flex;gap:8px;align-items:center;flex-wrap:wrap}\n'
        '.stalebox .snote{font-size:11px;color:var(--muted);opacity:.85;flex:1 1 100%}\n'
        '.stale-x{appearance:none;background:none;border:1px solid var(--line);border-radius:6px;'
        'color:var(--muted);font-size:11px;padding:5px 11px;cursor:pointer}\n'
        '.stale-x:hover{color:var(--text);border-color:var(--muted)}\n'
        '@media (prefers-reduced-motion:reduce){.stalebox{transition:none}}\n')
    STALE = (
        '<div class="stalebox" id="stalebox" role="status" aria-live="polite" hidden>'
        '<p><b>This page was generated <span id="staleage">a moment</span> ago and has not been '
        're-measured since.</b> It is a file. Nothing on it has been re-read from the repository '
        'since it was written, so what this tells you is that the page is <b>old</b> — not that '
        'it is wrong. An old page over a repo nobody touched is still exactly right, and this notice '
        'cannot tell you which of the two you are looking at, because knowing that would take the '
        're-read it cannot do. To re-measure it, run the command that made it:</p>'
        '<code>%s</code>'
        '<div class="srow">%s'
        '<button class="stale-x" id="stale-x">Dismiss</button>'
        '<span class="snote">This is the age of the page. <b>data updated</b> in the header is a '
        'different fact: when the lifecycle files last changed in git.</span></div></div>'
        '<script>(function(){'
        'var GEN=%d,THRESH=%d,box=document.getElementById("stalebox"),'
        'ageEl=document.getElementById("staleage"),dismissed=false,last="";'
        'document.getElementById("stale-x").addEventListener("click",function(){'
        'dismissed=true;box.hidden=true;box.classList.remove("in");});'
        'function human(s){var m,h,d;'
        'if(s<90)return Math.round(s)+" seconds";'
        'm=Math.round(s/60);if(m<90)return m+(m===1?" minute":" minutes");'
        'h=Math.round(s/3600);if(h<48)return h+(h===1?" hour":" hours");'
        'd=Math.round(s/86400);return d+(d===1?" day":" days");}'
        'function tick(){if(dismissed)return;'
        'var s=Date.now()/1000-GEN;'
        'if(s<THRESH){box.hidden=true;box.classList.remove("in");return;}'
        'var t=human(s);if(t!==last){ageEl.textContent=t;last=t;}'
        'if(box.hidden){box.hidden=false;box.classList.add("in");}}'
        'tick();setInterval(tick,15000);}());</script>'
        % (esc(REGEN_CMD), cp(REGEN_CMD, 'copy command'), GEN_EPOCH, STALE_AFTER))

# --------------------------------------------------------------------------
# the evidence, as a file the reader can save
# --------------------------------------------------------------------------
# A published view may be granted the `downloads` capability, which is still
# output: the page hands the viewer a file it generated, reads nothing and
# writes nothing back. What a view must never be granted is `artifact` - a page
# that publishes new versions of itself is a second source of truth that can
# disagree with the repo, and the provenance line under every panel stops being
# true the moment it can. Views are output only. This is the one affordance
# that could have blurred that, so it is written down here as well as in
# references/views.md.
#
# The file is built from the same lists the panels are drawn from, so it cannot
# report a different repo than the page it came off. It carries no clock: it is
# part of the page's own bytes, and a wall-clock stamp inside it would cost the
# byte-identical guarantee that --stale-after is opt-in precisely to protect.


def _cell(v):
    """One markdown table cell. A pipe inside a value splits the row."""
    return str(v).replace('|', '\\|').replace('\n', ' ').strip()


def _js(t):
    """A JavaScript string literal. `<` is escaped so nothing in the payload
    can close the script element early."""
    return json.dumps(t, ensure_ascii=True).replace('<', '\\u003c')


_ev = ['# %s \u2014 the evidence behind the SDLC pipeline view' % PRODUCT, '',
       'Read from the repository at generation time, from the same values the page shows. This '
       'is a copy of that reading, not a second source of truth: the files under '
       '`.claude/productizer/` stay the only place any of it is edited.', '']
_ev.append('- Source: `%s`' % (SPEC_REPO or GH or ROOT))
if IS_GIT and HEAD_SHA:
    _ev.append('- Generated from commit `%s` (%s)' % (HEAD_SHA, HEAD_DATE or 'undated'))
else:
    _ev.append('- Generated from the directory; there was no readable git history')
_ev.append('- Regenerate with: `%s`' % REGEN_CMD)
# Say what was hidden, and say when nothing was. A page that redacted nothing
# looks exactly like a page with nothing to redact, and only one of those is safe
# to publish.
_ev.append('- Commit subjects and bodies come from `git log`, which no file edit can '
           'correct, so they are redacted for display before rendering: %s. The gate that '
           'stops the commit being made keeps its own list.' % REDACT_STATE)
_ev += ['', '## Stage 5 \u2014 the last check run', '']
if check_state == 'absent':
    _ev.append('There is no `%s`. Nothing has been checked, which is not the same as a run that '
               'found nothing.' % RESULT_PATH)
elif check_state == 'unreadable':
    _ev.append('`%s` is present and would not parse. An unreadable result is not a passing one, '
               'and no row is invented for it.' % RESULT_PATH)
elif not checks:
    _ev.append('`%s` parsed and lists no checks. A measured zero, not an absent file.'
               % RESULT_PATH)
else:
    _ev.append('Verdict: `%s`' % (verdict or 'unstated'))
    _ev += ['', '| Check | Status | Counts as | Coverage |', '|---|---|---|---|']
    for c in checks:
        if id(c) in _CHK_FAILED_IDS:
            kind = 'failed'
        elif id(c) in _CHK_UNRUN_IDS:
            kind = 'never ran, and is declared always'
        elif id(c) in _CHK_NA_IDS:
            kind = 'not applicable to this change'
        else:
            kind = 'passing'
        if c['covered'] is None:
            cv = 'not recorded'
        elif c['from'] in ('stdout_paths', 'per_file_exit') and c['scope'] is not None:
            cv = '%s of %s file(s) in scope' % (c['covered'], c['scope'])
        else:
            cv = '%s counted, from %s' % (c['covered'], c['from'] or 'a source it did not state')
        if c['satisfied'] is False:
            cv += ' (below what it declared)'
        _ev.append('| %s | %s | %s | %s |'
                   % (_cell(c['id']), _cell(c['status']), kind, _cell(cv)))
_ev += ['', '## Requirements and acceptance', '']
if spec is None:
    _ev.append('There is no `%s`, so there is no acceptance table to compare anything against.'
               % SPEC_PATH)
elif not spec_ids:
    _ev.append('`%s` was read and holds no active requirement.' % SPEC_PATH)
else:
    _ev.append('%d active, %d superseded, %d withdrawn; %d acceptance row(s) in the table.'
               % (len(spec_ids), spec_super, spec_withdrawn, ac_rows))
    _ev += ['', '| Requirement | Acceptance row |', '|---|---|']
    for r in spec_ids:
        _ev.append('| %s | %s |'
                   % (_cell(r), 'yes' if r in ac_ids
                      else 'none - nothing on this page claims one exists'))
_ev += ['', '## Backlog', '']
if backlog is None:
    _ev.append('There is no `%s`. Intents arrive without a queue.' % BACKLOG_PATH)
elif not items:
    _ev.append('`%s` was read and its Items table is empty.' % BACKLOG_PATH)
else:
    _ev += ['| Id | What is wanted | Status | Jira | Notes |', '|---|---|---|---|---|']
    for it in items:
        _ev.append('| %s | %s | %s | %s | %s |'
                   % (_cell(it['id']), _cell(it['what']), _cell(it['status']),
                      _cell(it['jira']), _cell(it['note'])))
EVIDENCE = '\n'.join(_ev) + '\n'
EV_NAME = (re.sub(r'[^A-Za-z0-9._-]+', '-', PRODUCT).strip('-.') or 'pipeline') + '-evidence.md'

# Hidden in the markup, revealed only once the capability has actually
# resolved. `claude.use` answering null is by design indistinguishable from
# "not served" and from "not granted", and all three mean the same thing here:
# there is nothing to hand over, so nothing is offered. A button that says
# `saved` while saving nothing is the failure the copy buttons on this page are
# already wired to avoid, and it fails the same way - silently, and later.
dl_btn = '<button class="cp" id="dl-ev" hidden>download the evidence</button>'
DL = ('<script>(function(){'
      'var b=document.getElementById("dl-ev");'
      'if(!b||!window.claude||!window.claude.use)return;'
      'var NAME=%s,DATA=%s;'
      'window.claude.use("downloads").then(function(d){'
      'if(!d)return;'
      'b.hidden=false;'
      'b.addEventListener("click",function(){'
      'b.disabled=true;b.classList.remove("done");b.textContent="saving\\u2026";'
      'd.save({filename:NAME,data:DATA}).then(function(){'
      'b.textContent="saved";b.classList.add("done");},function(e){'
      # Declining is the viewer's answer, not an error to report as one: the
      # button goes back to offering the file rather than accusing them.
      'b.textContent=(e&&e.code==="declined")?"download the evidence":"not available here";'
      '}).then(function(){b.disabled=false;});});'
      '},function(){});}());</script>' % (_js(EV_NAME), _js(EVIDENCE)))


# The refresh button copies a prompt, not a click-to-reload. This page is a
# snapshot: reloading it re-serves the same bytes, and only build-view.sh moves
# the numbers. So the button hands over the exact command - rebuilt from the
# argv this run was actually given, so a non-default --out is preserved - plus
# the one sentence a reader needs to not misread what they get back.
REFRESH_PROMPT = (
    'Regenerate the %s dashboard from the current files and show it to me. Run:\n\n'
    '    %s\n\n'
    'The page is a snapshot, not a live view - the numbers only move when that '
    'script runs, so anything I am looking at now was true at generation time and '
    'not since. After it regenerates, tell me what changed from the previous '
    'generation and what still needs a person.'
    % (PRODUCT, REGEN_CMD))
refresh_btn = cp(REFRESH_PROMPT, 'refresh')

BODY = (
    '<div class="bar"><span class="crumb"><b>%s</b> · SDLC pipeline</span>'
    '<span style="flex:1"></span>%s%s%s<span class="crumb mono">read-only · %s</span></div>'
    '<div class="banners" id="banners" tabindex="-1">%s%s</div>'
    '<div class="dashnote"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#3fb950" '
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v4"/>'
    '<path d="m16.2 7.8 2.9-2.9"/><path d="M18 12h4"/><path d="m16.2 16.2 2.9 2.9"/><path d="M12 18v4"/>'
    '<path d="m4.9 19.1 2.9-2.9"/><path d="M2 12h4"/><path d="m4.9 4.9 2.9 2.9"/></svg>'
    '<span><b>Every figure on this page was read from this repository when it was generated.</b> '
    'Nothing is stored in the page. A value that is missing is drawn as missing and says what that '
    'costs; a value that could not be read is drawn as unknown. Neither is ever drawn as a zero.</span></div>'
    '<div class="tabs" id="tabs">%s</div>'
    '<div class="wrap">'
    '<section class="panel on" id="p-dash">%s</section>'
    '<section class="panel" id="p-board">%s</section>'
    '<section class="panel" id="p-stages">%s</section>'
    '<section class="panel" id="p-files">%s</section>'
    '<section class="panel" id="p-backlog">%s</section>'
    '<section class="panel" id="p-rel">%s</section>'
    '<section class="panel" id="p-lims">%s</section>'
    '<section class="panel" id="p-cmds">%s</section>'
    '</div>'
    % (crumb, verchip, data_stamp, refresh_btn + dl_btn, stamp, setup_bar, ''.join(banners), tabs,
       p_dash, p_board, p_stages, p_files, p_backlog, p_rel, p_lims, p_cmds))

# Appended rather than threaded through the format above: that string is
# positional, and adding a slot to it is how a panel ends up rendering another
# panel's content. STALE is '' unless --stale-after was passed, so the default
# page is the same bytes it was before this existed. DL is always emitted and
# holds no clock, so it costs the byte-identical guarantee nothing; its button
# rides along in the bar's existing slot rather than claiming a new one.
BODY = BODY + DL + STALE

DATA = ('var PROD = %s;\nvar CUR0 = %d;\nvar HUMAN = %d;\nvar S = %s;\n'
        % (json.dumps(PRODUCT), CUR0, HUMAN_ITEMS,
           json.dumps(S, indent=1, sort_keys=True, ensure_ascii=False)))

tpl = slurp(TEMPLATE)
# @@STALECSS@@ sits flush against the end of the last rule in the stylesheet,
# so replacing it with nothing leaves the sheet byte-for-byte what it was.
for marker in ('@@TITLE@@', '@@BODY@@', '@@DATA@@', '@@STALECSS@@'):
    if marker not in tpl:
        sys.stderr.write('build-view: template has no %s\n' % marker)
        sys.exit(2)
page = (tpl.replace('@@TITLE@@', esc('%s — SDLC pipeline' % PRODUCT))
           .replace('@@BODY@@', BODY)
           .replace('@@DATA@@', DATA)
           .replace('@@STALECSS@@', STALE_CSS))

outdir = os.path.dirname(os.path.abspath(OUT))
if outdir and not os.path.isdir(outdir):
    os.makedirs(outdir)
with io.open(OUT, 'w', encoding='utf-8') as fh:
    fh.write(page)
sys.stderr.write('build-view: wrote %s (%d bytes)\n' % (OUT, len(page.encode('utf-8'))))
PYEOF
