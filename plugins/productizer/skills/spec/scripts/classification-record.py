#!/usr/bin/env python3
# classification-record.py --version | --help
#                          --today
#                          --slug INTENT
#                          --sha256 PATH
#                          --active-ids PATH
#                          --validate RECORD SPEC_CONTENT
#
# SPEC_CONTENT is the spec as it stands at the commit the record cites, already
# fetched by the caller. Pass `-` when it could not be fetched: the scope
# comparison is then reported as not made rather than made against the wrong
# file.
#
# The parser that both halves of the classification-provenance mechanism
# share. `record-classification.sh` writes a record with it;
# `check-classification-provenance.sh` validates one with it.
#
# ONE PARSER, NOT TWO. The writer computes the in-scope requirement ids and
# the check recomputes them to compare. Two implementations of "which ids are
# active" would disagree the first time the spec grew a shape neither author
# anticipated, and the disagreement would surface as a check failing on a
# correct record - which teaches people to delete the check. So the active-id
# rules exist once, here.
#
# THE ACTIVE-ID RULES ARE build-view.sh's, DELIBERATELY UNCHANGED. Its
# regexes and its three-line status lookahead are reproduced verbatim below.
# A requirement's status marker is the line under it, so the id and its status
# have to be read together; counting every `**Rn**` as active would put
# superseded and withdrawn requirements into the scope list, and the record
# would then claim the classifier saw ids that are not agreed behaviour.
#
# EXIT CODES ARE THE CONTRACT, and they are the same three the shell scripts
# use, so a caller never has to translate:
#
#   0  did what was asked. For --validate that means the record was PARSED,
#      not that it was clean - findings are printed and the caller decides.
#   1  unused here. Reserved so it keeps meaning "findings" everywhere.
#   2  could not run - bad usage, a file that could not be read.
#
# --validate PRINTS TSV, one record per line, `kind<TAB>line<TAB>detail`:
#
#   VALUE     a header field the caller needs: detail is `key=value`
#   SCOPE     one requirement id the record lists as in scope
#   FINDING   a problem, already written as the sentence to print
#
# NOTHING FROM THE RECORD'S FREE TEXT IS EVER PUT IN A FINDING. A record names
# an intent a stranger may have written, and this output reaches a committed
# results file and a model's context. Findings name a field, a line and a
# class of problem. The one value ever echoed back is a classification word,
# which is checked against a closed set of four before it is printed.

import hashlib
import os
import re
import sys

VERSION = "classification-record 1.0"

USAGE = """usage: classification-record.py --version | --help
       classification-record.py --today
       classification-record.py --slug INTENT
       classification-record.py --sha256 PATH
       classification-record.py --active-ids PATH
       classification-record.py --validate RECORD SPEC_CONTENT
"""

# The four classifications, and nothing else is one. Ordered as the skill
# orders them so any message listing them reads the same way the skill does.
CLASSIFICATIONS = ("extend", "refine", "duplicate", "contradict")

# Header fields every record carries. `Spec commit` and `Spec hash` are the
# two that may never be unset - see REFUSED_UNSET below.
REQUIRED_FIELDS = (
    "Intent",
    "Classification",
    "Recorded",
    "Spec path",
    "Spec commit",
    "Spec hash",
    "In scope count",
)

# The rest of the spec may go unmeasured and say so with an em dash. These two
# may not. An unreachable spec home yields no commit and no hash, and the
# correct behaviour there is to write no record at all - so an em dash in
# either field is a record that should not exist, and is a finding rather than
# an honest unknown. This is the one place in the lifecycle where the em dash
# is refused, and R19 is the reason.
REFUSED_UNSET = ("Spec commit", "Spec hash")

# Values that look like a measurement and are not. `--` and `-` catch the
# hand-typed em dash; the rest are what people write when they have no hash.
PLACEHOLDERS = {
    "—", "–", "--", "-", "?", "??", "n/a", "na", "none", "null",
    "nil", "unknown", "unset", "tbd", "todo", "pending", "placeholder",
    "sha256:", "0",
}

RE_INTENT = re.compile(r"^[A-Za-z0-9#][A-Za-z0-9#._/-]{0,63}$")
RE_COMMIT = re.compile(r"^[0-9a-f]{40}$")
RE_HASH = re.compile(r"^sha256:[0-9a-f]{64}$")
RE_DATE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
RE_RID = re.compile(r"^R[0-9]+$")
RE_FIELD = re.compile(r"^([A-Za-z][A-Za-z ]*):(.*)$")

# build-view.sh's three, verbatim.
RE_ACTIVE = re.compile(r"^(?:[-*]\s+)?\*\*(R[0-9]+)\*\*")
RE_SUPER = re.compile(r"^\s*Superseded by R[0-9]+")
RE_WITHDRW = re.compile(r"^\s*Withdrawn\.")

SCOPE_HEADING = "## Requirement ids in scope"


def die(message):
    sys.stderr.write("classification-record: %s\n" % message)
    raise SystemExit(2)


def read_text(path):
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        die("cannot read %s: %s. Unmeasured, not empty." % (path, exc))
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        die("%s is not valid UTF-8: %s" % (path, exc))


def active_ids(text):
    """Every requirement id the spec text records as active, in file order."""
    lines = text.split("\n")
    out = []
    for i, line in enumerate(lines):
        mm = RE_ACTIVE.match(line)
        if not mm:
            continue
        status = "active"
        for follow in lines[i + 1:i + 4]:
            if not follow.strip() or RE_ACTIVE.match(follow):
                break
            if RE_SUPER.match(follow):
                status = "superseded"
                break
            if RE_WITHDRW.match(follow):
                status = "withdrawn"
                break
        if status == "active":
            out.append(mm.group(1))
    return out


def rid_key(rid):
    return int(rid[1:])


def slug_for(intent):
    s = re.sub(r"[^A-Za-z0-9._-]+", "-", intent).strip("-.")
    return s


def today():
    stamp = os.environ.get("SOURCE_DATE_EPOCH", "").strip()
    import datetime
    if stamp:
        try:
            when = datetime.datetime.fromtimestamp(
                int(stamp), datetime.timezone.utc)
        except (ValueError, OverflowError, OSError):
            die("SOURCE_DATE_EPOCH is set but is not a usable epoch second. "
                "Refusing rather than stamping a record with a date nobody chose.")
    else:
        when = datetime.datetime.now(datetime.timezone.utc)
    return when.strftime("%Y-%m-%d")


def sha256_of(path):
    try:
        with open(path, "rb") as fh:
            return "sha256:" + hashlib.sha256(fh.read()).hexdigest()
    except OSError as exc:
        die("cannot hash %s: %s. No hash means no record - that is R19, not a "
            "reason to write a blank one." % (path, exc))


# ---------------------------------------------------------------- validate

def emit(kind, line, detail):
    sys.stdout.write("%s\t%d\t%s\n" % (kind, line, detail))


def parse_header(lines):
    """The run of `Key: value` lines around the Classification line, above the
    first `## ` heading. Scoping it this way is what makes a `Classification:`
    written inside a body paragraph not a classification - the same rule
    check-ruling-requested.sh applies to a ruling's Status."""
    limit = len(lines)
    for i, line in enumerate(lines):
        if line.startswith("## "):
            limit = i
            break
    anchor = None
    for i in range(limit):
        if lines[i].startswith("Classification:"):
            anchor = i
            break
    if anchor is None:
        for i in range(limit):
            if lines[i].startswith("Intent:"):
                anchor = i
                break
    if anchor is None:
        return {}, {}
    start = anchor
    while start > 0 and lines[start - 1].strip():
        start -= 1
    end = anchor
    while end + 1 < limit and lines[end + 1].strip():
        end += 1
    values, counts = {}, {}
    for i in range(start, end + 1):
        mm = RE_FIELD.match(lines[i])
        if not mm:
            continue
        key = mm.group(1)
        counts[key] = counts.get(key, 0) + 1
        values[key] = (i + 1, mm.group(2).strip())
    return values, counts


def validate(record_path, spec_content_path):
    text = read_text(record_path)
    lines = text.split("\n")
    if not text.strip():
        emit("FINDING", 1, "the record is empty. An empty file records no "
                           "classification and no spec it was made against.")
        return

    values, counts = parse_header(lines)

    for key in REQUIRED_FIELDS:
        n = counts.get(key, 0)
        if n == 0:
            emit("FINDING", 1,
                 "header field '%s' is missing. A missing line and a blank "
                 "value are indistinguishable to anything counting these "
                 "records, and a counter that cannot tell them apart reports "
                 "an unrecorded classification as recorded." % key)
        elif n > 1:
            emit("FINDING", values[key][0],
                 "header field '%s' appears %d times, so which value is "
                 "authoritative is undefined. Exactly one classification means "
                 "exactly one line." % (key, n))
        elif not values[key][1]:
            emit("FINDING", values[key][0],
                 "header field '%s' is blank." % key)

    def one(key):
        if counts.get(key, 0) == 1 and values[key][1]:
            return values[key]
        return None

    # --- the two fields that carry the provenance itself --------------------
    for key, pattern, shape in (
            ("Spec commit", RE_COMMIT, "a 40-character lowercase hex commit sha"),
            ("Spec hash", RE_HASH, "sha256:<64 lowercase hex>")):
        got = one(key)
        if got is None:
            continue
        lineno, value = got
        if value.strip().lower() in PLACEHOLDERS:
            emit("FINDING", lineno,
                 "header field '%s' carries a placeholder rather than a "
                 "measurement. An unreachable spec home yields no %s, and the "
                 "answer to that is no record - not a record with the gap "
                 "written in. This is the one field in the lifecycle where an "
                 "em dash is refused." % (key, key.split()[-1]))
        elif not pattern.match(value):
            emit("FINDING", lineno,
                 "header field '%s' is not %s, so nothing can check it against "
                 "the spec it claims to have read." % (key, shape))
        else:
            emit("VALUE", lineno, "%s=%s" % (key, value))

    got = one("Classification")
    if got is not None:
        lineno, value = got
        if value in CLASSIFICATIONS:
            emit("VALUE", lineno, "Classification=%s" % value)
        else:
            emit("FINDING", lineno,
                 "the classification is not one of the four the lifecycle "
                 "allows (%s). A fifth value is a classification nothing "
                 "downstream knows how to act on."
                 % ", ".join(CLASSIFICATIONS))

    got = one("Intent")
    if got is not None:
        lineno, value = got
        if RE_INTENT.match(value):
            emit("VALUE", lineno, "Intent=%s" % value)
        else:
            emit("FINDING", lineno,
                 "the intent identifier is not id-shaped (letters, digits and "
                 "'#._/-', at most 64 characters, no spaces). An intent is "
                 "text a stranger can write, so this store holds its id and "
                 "never its words.")

    got = one("Recorded")
    if got is not None and not RE_DATE.match(got[1]):
        emit("FINDING", got[0],
             "the Recorded date is not YYYY-MM-DD, so staleness cannot be "
             "derived from it.")

    got = one("Spec path")
    if got is not None:
        emit("VALUE", got[0], "Spec path=%s" % got[1])

    # --- the in-scope list --------------------------------------------------
    heading_at = None
    for i, line in enumerate(lines):
        if line.rstrip() == SCOPE_HEADING:
            heading_at = i
            break
    listed = []
    if heading_at is None:
        emit("FINDING", 1,
             "no '%s' section. Without the list there is no evidence about "
             "what the classification was made from, which is the whole "
             "purpose of the record." % SCOPE_HEADING)
    else:
        for i in range(heading_at + 1, len(lines)):
            line = lines[i]
            if line.startswith("## "):
                break
            for token in line.split():
                if RE_RID.match(token):
                    listed.append((i + 1, token))
                else:
                    emit("FINDING", i + 1,
                         "the in-scope list holds a token that is not a "
                         "requirement id. Ids only: this list is compared "
                         "against the spec by exact match.")
        seen = {}
        for lineno, rid in listed:
            if rid in seen:
                emit("FINDING", lineno,
                     "requirement id %s is listed twice in scope, so the "
                     "count and the set disagree." % rid)
            seen[rid] = lineno
        if not listed:
            emit("FINDING", heading_at + 1,
                 "the '%s' section is empty. A record that names no ids "
                 "asserts nothing about what was read." % SCOPE_HEADING)

    listed_ids = []
    for _, rid in listed:
        if rid not in listed_ids:
            listed_ids.append(rid)
    for rid in sorted(listed_ids, key=rid_key):
        emit("SCOPE", 0, rid)

    got = one("In scope count")
    if got is not None:
        lineno, value = got
        if not value.isdigit():
            emit("FINDING", lineno,
                 "'In scope count' is not a whole number, so nothing can "
                 "compare it against the list.")
        elif int(value) != len(listed_ids):
            emit("FINDING", lineno,
                 "'In scope count' says %s but the section lists %d distinct "
                 "requirement ids. A count that disagrees with its own list is "
                 "the count people read." % (value, len(listed_ids)))

    # --- what the spec at the recorded commit actually says -----------------
    #
    # The caller passes `-` when it could not fetch that content: the recorded
    # hash did not match, or the commit is not in this clone. Comparing the
    # scope list against a spec the record does not claim to have read would
    # print a confident sentence about the wrong thing, so the comparison is
    # reported as NOT MADE. Unknown is an em dash; it is never a zero, and it
    # is never a clean pass either - the caller already holds a finding or a
    # refusal.
    if spec_content_path == "-":
        emit("VALUE", 0, "Active at commit=\u2014")
        return

    spec_text = read_text(spec_content_path)
    expected = active_ids(spec_text)
    expected_set = set(expected)
    listed_set = set(listed_ids)

    missing = sorted(expected_set - listed_set, key=rid_key)
    extra = sorted(listed_set - expected_set, key=rid_key)

    if missing:
        emit("FINDING", 1,
             "%d active requirement id(s) were NOT in the context this "
             "classification was made from: %s. A classification that saw part "
             "of the spec can be right by luck; R6 requires it to have been "
             "made against the whole of it."
             % (len(missing), " ".join(missing)))
    if extra:
        emit("FINDING", 1,
             "%d requirement id(s) claimed in scope are not active in the spec "
             "this record hashed: %s. A scope list that names ids the spec does "
             "not have is not evidence of what was read."
             % (len(extra), " ".join(extra)))

    emit("VALUE", 0, "Active at commit=%d" % len(expected))


def main(argv):
    if not argv:
        sys.stderr.write(USAGE)
        return 2
    mode = argv[0]
    rest = argv[1:]

    if mode == "--version":
        sys.stdout.write("%s\n" % VERSION)
        return 0
    if mode in ("-h", "--help"):
        sys.stdout.write(USAGE)
        return 0

    if mode == "--today":
        if rest:
            die("--today takes no arguments")
        sys.stdout.write("%s\n" % today())
        return 0

    if mode == "--slug":
        if len(rest) != 1:
            die("--slug needs exactly one intent identifier")
        s = slug_for(rest[0])
        if not s:
            die("the intent identifier reduces to an empty filename slug")
        sys.stdout.write("%s\n" % s)
        return 0

    if mode == "--sha256":
        if len(rest) != 1:
            die("--sha256 needs exactly one path")
        sys.stdout.write("%s\n" % sha256_of(rest[0]))
        return 0

    if mode == "--active-ids":
        if len(rest) != 1:
            die("--active-ids needs exactly one path")
        for rid in active_ids(read_text(rest[0])):
            sys.stdout.write("%s\n" % rid)
        return 0

    if mode == "--validate":
        if len(rest) != 2:
            die("--validate needs RECORD and SPEC_CONTENT")
        validate(rest[0], rest[1])
        return 0

    sys.stderr.write("classification-record: unknown option %s\n" % mode)
    sys.stderr.write(USAGE)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
