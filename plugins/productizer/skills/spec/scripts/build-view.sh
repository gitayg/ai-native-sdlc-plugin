#!/usr/bin/env bash
# build-view.sh [repo-root] [--out FILE]
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
# Exit: 0 on success, 2 on a bad argument or a missing template.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"
TEMPLATE="$SKILL/templates/view.html"
STAGE_STATUS="$HERE/stage-status.sh"

ROOT=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "build-view: --out needs a file" >&2; exit 2; }; shift 2 ;;
    --out=*) OUT="${1#--out=}"; shift ;;
    -h|--help) echo "usage: build-view.sh [repo-root] [--out FILE]"; exit 0 ;;
    -*) echo "build-view: unknown option: $1" >&2; exit 2 ;;
    *) [ -z "$ROOT" ] || { echo "build-view: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
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

python3 - "$ROOT" "$TMP" "$TEMPLATE" "$OUT" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Render the lifecycle dashboard. Reads only; writes one HTML file."""
import io, json, os, re, sys

ROOT, TMP, TEMPLATE, OUT = sys.argv[1:5]

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
                        'subject': f[3], 'body': f[4] if len(f) > 4 else ''})

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
        cells = [c.strip() for c in rest.split('|')]
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
            header = [c.strip().lower() for c in line.strip().strip('|').split('|')]
        mm = re.match(r'^\|\s*(B[0-9]+)\s*\|', line)
        if not mm:
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
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
                           'why': c.get('why', '')})
        check_state = 'ok'
    except ValueError:
        check_state = 'unreadable'

bad_checks = [c for c in checks if c['status'] not in ('pass', 'skipped')]

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

def cp(text, label='copy prompt'):
    return '<button class="cp" data-copy="%s">%s</button>' % (esc(text), esc(label))

# --- stat tiles -----------------------------------------------------------
# Four renderings, kept apart on purpose: a measured number, a file that was
# never written, a file that could not be read, and a question that does not
# apply to this repo. Collapsing any of the last three into a zero is how a
# dashboard starts lying, so each one has its own glyph and its own reason.
# `style` is an attribute string, not a value, and every existing caller omits
# it - a tile that passes nothing renders exactly the bytes it rendered before.
WIDE = ' style="grid-column:1/-1"'

def tile_num(label, n, detail, level='', style=''):
    """A measured value. The number is real; level is 'att', 'warn' or ''."""
    return ('<div class="stat %s"%s><span class="stat-l">%s</span>'
            '<span class="stat-n">%s</span><span class="stat-d">%s</span></div>'
            % (level, style, esc(label), esc(n), detail))

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
                          else 'none open in the concerns table', lvl))

if check_state == 'absent':
    stats.append(tile_absent('Checks, last run',
                             'no %s; nothing has been checked' % RESULT_PATH))
elif check_state == 'unreadable':
    stats.append(tile_unknown('Checks, last run',
                              '%s exists and would not parse' % RESULT_PATH))
else:
    ok = verdict == 'pass' and not bad_checks
    detail = '%d of %d not passing' % (len(bad_checks), len(checks)) if bad_checks \
        else '%d check(s), all passing' % len(checks)
    stats.append(tile_num('Checks, last run', str(verdict or 'unstated').upper(),
                          esc(detail), '' if ok else 'att'))

if spec is None:
    stats.append(tile_absent('Requirements with no test',
                             'no spec; there is no acceptance table to compare'))
else:
    lvl = 'warn' if untested else ''
    stats.append(tile_num('Requirements with no test', str(len(untested)),
                          esc('of %d active · %s' % (len(spec_ids), ', '.join(untested[:6])))
                          if untested else esc('of %d active · %d acceptance rows'
                                               % (len(spec_ids), ac_rows)), lvl))

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
                          'principles ratified' if principles else 'file exists, nothing ratified', lvl))

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
                          'warn', style=WIDE))
else:
    _rej = ('' if not inf_rejected
            else ' and %d rejected at import' % len(inf_rejected))
    stats.append(tile_num(INF_LABEL, '0',
                          esc('a measured zero — %d promotion(s)%s recorded here and no marker left '
                              'unconfirmed, so this import was worked through rather than never started'
                              % (len(inf_promoted), _rej)), '', style=WIDE))

# --- banners --------------------------------------------------------------
banners = []

def banner(level, title, body, prompt):
    return ('<div class="bn %s"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" '
            'stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>'
            '<p><b>%s</b> %s</p>%s</div>'
            % (level, '#da3633' if level == 'crit' else '#d29922',
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
                          'the conflict in one sentence, and do not pick a winner.' % SPEC_PATH))

if check_state == 'unreadable':
    banners.append(banner('warn', 'The last check result will not parse.',
                          '<span class="mono">%s</span> is present and unreadable. An unreadable result is '
                          'not a passing one, and this page will not render it as one.' % esc(RESULT_PATH),
                          'The file %s will not parse as JSON. Show me why, and re-run the checks rather '
                          'than repairing the result by hand.' % RESULT_PATH))
elif bad_checks:
    banners.append(banner('crit', '%d check%s not passing.' % (len(bad_checks), '' if len(bad_checks) == 1 else 's'),
                          'Stage 5 refused: %s.'
                          % esc(', '.join('%s (%s)' % (c['id'], c['status']) for c in bad_checks)),
                          'Show me why these checks did not pass in %s and what each one examined: %s'
                          % (PRODUCT, ', '.join(c['id'] for c in bad_checks))))

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
                          'Add acceptance criteria rows for these requirements in %s, naming the test or '
                          'command and the observable that proves each one: %s'
                          % (SPEC_PATH, ', '.join(untested[:10]))))

if constit is not None and principles == 0:
    banners.append(banner('warn', 'The constitution has no principles.',
                          '<span class="mono">%s</span> exists and nothing has been ratified in it, so '
                          'intake checks every delta against an empty gate.' % esc(CONST_PATH),
                          'Draft principles for %s in %s from how this repo already works. Number them '
                          'P1 upward and do not ratify any of them without asking me.'
                          % (PRODUCT, CONST_PATH)))

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
                          _tag_prompt))

# --- kanban ---------------------------------------------------------------
def card(cid, title, note='', level=''):
    n = '<span class="kc-n">%s</span>' % esc(note) if note else ''
    return ('<div class="kc %s"><span class="kc-id mono">%s</span>'
            '<span class="kc-t">%s</span>%s</div>' % (level, esc(cid), esc(title), n))

cols = [('Backlog', []), ('Intake · 2', []), ('Build · 3', []),
        ('Check · 5', []), ('Review · 6', []), ('Gated · 8', [])]

for it in items:
    st = it['status'].lower()
    if st in ('done',):
        continue
    if st in ('in-progress', 'in progress'):
        cols[1][1].append(card(it['id'], it['what'], it['note'] or 'at intake'))
    elif st == 'blocked':
        cols[0][1].append(card(it['id'], it['what'], it['note'] or 'blocked', 'att'))
    else:
        cols[0][1].append(card(it['id'], it['what'], it['note']))
for c in contradictions:
    if c['open']:
        cols[1][1].append(card(c['id'], c['what'] or 'contradiction', 'waiting on a ruling', 'att'))
if os.path.exists(rel('plan.md')):
    cols[2][1].append(card('plan.md', 'A build plan is committed', stage('3')['detail']))
for c in bad_checks:
    cols[3][1].append(card(c['id'], c['why'][:90] or c['id'], c['status'], 'att'))
if os.path.exists(rel('REVIEW.md')):
    cols[4][1].append(card('REVIEW.md', 'A review policy is in the tree', stage('6')['detail'],
                           'warn' if stage('6')['state'] == 'waiting' else ''))
for r in UNTAGGED[:3]:
    cols[5][1].append(card(r['ver'], r['title'], 'shipped, never tagged — you press publish', 'warn'))

kan_total = sum(len(c[1]) for c in cols)
kanban = '<div class="kanban">' + ''.join(
    '<div class="kcol"><div class="kcol-h"><span>%s</span><span class="kcol-c">%d</span></div>%s</div>'
    % (name, len(cards), ''.join(cards)) for name, cards in cols) + '</div>'

# --------------------------------------------------------------------------
# panel: dashboard
# --------------------------------------------------------------------------
attention = len(banners)
sub = ('<span class="h-sub">%d thing%s need%s you</span>'
       % (attention, '' if attention == 1 else 's', 's' if attention == 1 else '')) \
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
QH = '<div class="h" style="margin-top:26px">Inferred requirements — the promotion queue</div>'

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
START = ('Start work on backlog item %s: "%s". Open it as an intent at Stage 1, classify it against '
         'the whole living spec before anything is planned, record the issue number in its Notes and '
         'set it in-progress. If it contradicts an agreed requirement, stop and tell me - do not merge it.')

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
    for rank, it in enumerate(items):
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
            '<li class="bk" draggable="true" data-id="%s" data-rank="%d" data-st="%d">'
            '<span class="bk-grip" aria-hidden="true">⋮⋮</span>'
            '<span class="bk-id mono">%s</span><span class="bk-what">%s</span>'
            '<span class="bk-st %s" data-src="%s">%s</span><span class="bk-j">%s</span>'
            '<span class="bk-note">%s</span>%s</li>'
            % (esc(it['id']), rank, it['rank'], esc(it['id']), esc(it['what']), esc(cls),
               'jira' if it['jira'] else 'local', esc(it['status']), j, esc(it['note']),
               '<button class="bk-act" data-copy="%s">start work</button>'
               % esc(START % (it['id'], it['what']))))
    p_backlog = (
        '<div class="h">Backlog — the queue in front of the lifecycle</div>'
        '<div class="relnote"><b>Nothing here is agreed.</b> These are wants, not requirements. '
        '<b>Order is the priority</b>; there is no priority field, because two orderings disagree the '
        'moment someone edits one and not the other. Drag to rearrange.</div>'
        '<div class="bksort">Sort <button class="sb on" data-s="rank">rank</button>'
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
    for r in releases:
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
            '<div class="rel"><div class="relside"><span class="relv mono">%s</span>'
            '<span class="reldot %s"></span></div><div class="relbody"><div class="relhead">'
            '<h3>%s</h3><span class="rkind %s">%s</span>%s<span style="flex:1"></span>%s'
            '<span class="reldate mono">%s</span></div><ul class="rlist">%s</ul></div></div>'
            % (esc(r['ver']), dot, esc(r['title']), '', esc(r['kind']), tag, sha,
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
    for c in checks:
        bad = c['status'] not in ('pass', 'skipped')
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
        crows.append('<div class="chkrow r"><span class="ci">%s</span>'
                     '<span class="cs %s">%s</span><span class="cc">%s</span></div>'
                     % (esc(c['id']), 'unk' if unk else ('bad' if bad else ''), esc(c['status']), cov))
    checks_block = ('<div class="h" style="margin-top:26px">Stage 5 — the last check run, per check</div>'
                    '<div class="chk">%s</div>'
                    '<p class="provenance">Read from <span class="mono">%s</span>. Coverage is what each '
                    'check reported it examined; a check with no coverage recorded is shown as unknown, '
                    'never as nothing examined.</p>' % (''.join(crows), esc(RESULT_PATH)))
elif check_state == 'unreadable':
    checks_block = ('<div class="h" style="margin-top:26px">Stage 5</div><div class="empty">'
                    '<b>The result file would not parse.</b><p><span class="mono">%s</span> exists and is '
                    'not readable JSON. An unreadable result is not a passing one.</p></div>' % esc(RESULT_PATH))
else:
    checks_block = ('<div class="h" style="margin-top:26px">Stage 5</div><div class="empty">'
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
# assembly
# --------------------------------------------------------------------------
TABS = [('dash', 'Dashboard', ''),
        ('board', 'Board', board_count),
        ('stages', 'Stages', str(len(S))),
        ('files', 'Files', str(len(rows))),
        ('backlog', 'Backlog', str(len(items)) if backlog is not None else '—'),
        ('rel', 'Releases', str(len(releases)) if IS_GIT else '—'),
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

BODY = (
    '<div class="bar"><span class="crumb"><b>%s</b> · SDLC pipeline</span>'
    '<span style="flex:1"></span>%s%s<span class="crumb mono">read-only · %s</span></div>'
    '<div class="banners">%s%s</div>'
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
    '<section class="panel" id="p-cmds">%s</section>'
    '</div>'
    % (crumb, verchip, data_stamp, stamp, setup_bar, ''.join(banners), tabs,
       p_dash, p_board, p_stages, p_files, p_backlog, p_rel, p_cmds))

DATA = ('var PROD = %s;\nvar CUR0 = %d;\nvar S = %s;\n'
        % (json.dumps(PRODUCT), CUR0,
           json.dumps(S, indent=1, sort_keys=True, ensure_ascii=False)))

tpl = slurp(TEMPLATE)
for marker in ('@@TITLE@@', '@@BODY@@', '@@DATA@@'):
    if marker not in tpl:
        sys.stderr.write('build-view: template has no %s\n' % marker)
        sys.exit(2)
page = (tpl.replace('@@TITLE@@', esc('%s — SDLC pipeline' % PRODUCT))
           .replace('@@BODY@@', BODY)
           .replace('@@DATA@@', DATA))

outdir = os.path.dirname(os.path.abspath(OUT))
if outdir and not os.path.isdir(outdir):
    os.makedirs(outdir)
with io.open(OUT, 'w', encoding='utf-8') as fh:
    fh.write(page)
sys.stderr.write('build-view: wrote %s (%d bytes)\n' % (OUT, len(page.encode('utf-8'))))
PYEOF
