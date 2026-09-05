#!/usr/bin/env bash
# emit-attestation.sh [--repo DIR] [--spec PATH] [--result PATH] [--out PATH]
#                     [--version] [--help]
#
# Emits a CycloneDX Attestations document from what this repository already
# holds: requirement ids, the checks that assert them, the classification each
# intent was given, and the ruling that resolved a contradiction.
#
# WHY CYCLONEDX AND NOT SOMETHING ELSE.
#
#   Four supply-chain provenance formats were read before this was written, and
#   only one of them has a place to put "requirement R14 is asserted by this
#   check, and here is the evidence". Measured, not assumed:
#
#     in-toto attestation predicates — the vetted list is 12 bullets naming 13
#       predicate types (SPDX2 and SPDX3 share a bullet). Grepping every one of
#       their specifications for AI, machine learning, LLM, authorship,
#       co-author or assisted returns ONE line, in spdx3.md, and it is about an
#       AI model as a SUBJECT of a BOM, not as an author of work.
#       https://github.com/in-toto/attestation/tree/main/spec/predicates
#
#     SLSA — Provenance v1 describes a BUILD: buildDefinition, buildType,
#       builder.id, resolvedDependencies. The words AI and agent appear zero
#       times on its v1.1 provenance page and zero times across the v1.2 about,
#       threats, terminology, FAQ and future-directions pages.
#       https://slsa.dev/spec/v1.1/provenance
#
#     GitHub Artifact Attestations sign a SLSA Provenance predicate, so they
#       inherit exactly that vocabulary and add no authorship field.
#
#     CycloneDX Attestations — requirements with permanent `bom-ref`s, mapped
#       requirement -> claims -> evidence, with conformance and confidence
#       scores and signatures. That is the shape this repository is already in.
#       https://cyclonedx.org/use-cases/attestations/
#
# WHAT IT MAPS, AND FROM WHERE. Every field name below was read out of the
# CycloneDX 1.6 JSON schema, not remembered:
# https://raw.githubusercontent.com/CycloneDX/specification/master/schema/bom-1.6.schema.json
#
#   spec.md requirements       -> definitions.standards[].requirements[]
#                                 (bom-ref, identifier, title, text, properties)
#   the checks that assert them-> declarations.claims[] (target, predicate,
#                                 reasoning, evidence) and declarations.evidence[]
#                                 (bom-ref, propertyName, description, created)
#   the coverage verdict       -> declarations.attestations[].map[]
#                                 (requirement, claims, conformance)
#   classification records     -> declarations.evidence[]
#   the decision record        -> declarations.evidence[] with reviewer, WHEN a
#                                 human is named. When none is, the field is
#                                 left out rather than filled.
#   the product               -> declarations.targets.components[]
#
# WHAT CYCLONEDX CANNOT SAY, AND WHY THAT IS NOT PAPERED OVER.
#
#   Nearly every commit behind these requirements was written by a model. There
#   is no field anywhere in `declarations` that can record that.
#
#     - `evidence.author` and `evidence.reviewer` are both
#       `#/definitions/organizationalContact`, whose properties are exactly
#       bom-ref, name, email and phone. That is a person. Putting a model's
#       name in it makes the same false claim `Co-authored-by:` does, one layer
#       further from anyone who could catch it, so this emitter LEAVES THOSE
#       FIELDS EMPTY when a tool did the work.
#     - `assessors[]` carries `thirdParty` and an `organization`. There is no
#       assessor-is-a-tool. The assessor here is a shell script, so it is
#       emitted with `thirdParty: false` and NO organization.
#     - `claim` and `evidence` have no `properties` name-value store at all —
#       `requirement` does, and the BOM root does, and those two are the only
#       places a fact CycloneDX has no field for can legitimately go.
#     - The `cdx:ai-ml` property taxonomy exists, and it does not help: every
#       property in it describes a model as a COMPONENT — modality, parameter
#       count, tokenizer, context length. Nothing in it says a model performed
#       work.
#       https://github.com/CycloneDX/cyclonedx-property-taxonomy/blob/main/cdx/ai-ml.md
#
#   So the gap is written into the document itself, in the root `properties`
#   array, which the schema describes as being for "data not officially
#   supported in the standard". A reader who parses only the CycloneDX fields
#   gets a true document with a hole in it; a reader who reads the properties
#   is told where the hole is and how big. Bending `author` to carry a model
#   name would have hidden both.
#
#   references/attestation.md carries the proposed in-toto predicate that would
#   close it.
#
# EXIT CODES ARE THE CONTRACT. Note these are check-hygiene.sh's three, not
# req-trailer.sh's five: this emitter either produced a document or did not.
#
#   0  emitted, and every active requirement is mapped with a MEASURED
#      conformance. Backed by the printed counts.
#   1  emitted, and there are findings: a requirement nothing claims, a
#      conformance that could not be scored, a decision with no human named.
#      The document is still valid and still worth signing; the findings say
#      what it does not establish.
#   2  COULD NOT MEASURE. No spec, no checks result, no git, no python3, or a
#      result file that does not parse. Nothing is emitted, because an
#      attestation with no evidence in it is worse than no attestation.
#
# NO VALUE IS EVER RENDERED AS A ZERO IT DID NOT MEASURE. A `Partial` coverage
# verdict gets NO `conformance.score` — only a rationale saying which part is
# unasserted — because the fraction was never measured and 0.5 would be an
# invention. An absent rulings directory is reported as absent, never as zero
# rulings.
#
# Every timestamp is the HEAD commit's, pinned to UTC, so two runs over one
# commit produce the same bytes. A wall-clock timestamp would make the document
# unreproducible and would date the RUN rather than the state being attested.
#
# It never suppresses stderr, and it never prints an absolute path: this
# repository is public and a path carries a username.
set -euo pipefail
export LC_ALL=C

VERSION="emit-attestation 1.0"

TMP=""
cleanup() { if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi; }
trap cleanup EXIT

die_refuse() { printf 'emit-attestation: CANNOT MEASURE — %s\n' "$1" >&2; exit 2; }

usage() {
  cat <<'USAGE'
emit-attestation.sh — a CycloneDX Attestations document from the living spec.

  emit-attestation.sh [--repo DIR] [--out attestation.cdx.json]

Options:
  --repo <dir>     repository root (default: current directory)
  --spec <path>    living spec (default: <repo>/.claude/productizer/spec.md)
  --result <path>  checks result (default: <repo>/.claude/productizer/checks-result.json)
  --out <path>     write here instead of stdout
  --version        print the version
  -h, --help       this text

Exit: 0 emitted and fully measured · 1 emitted with findings
      2 could not measure — nothing emitted
USAGE
}

ROOT=""
SPEC=""
RESULT=""
OUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)     [ "$#" -ge 2 ] || die_refuse "--repo needs a directory"; ROOT="$2"; shift 2 ;;
    --repo=*)   ROOT="${1#--repo=}"; shift ;;
    --spec)     [ "$#" -ge 2 ] || die_refuse "--spec needs a path"; SPEC="$2"; shift 2 ;;
    --spec=*)   SPEC="${1#--spec=}"; shift ;;
    --result)   [ "$#" -ge 2 ] || die_refuse "--result needs a path"; RESULT="$2"; shift 2 ;;
    --result=*) RESULT="${1#--result=}"; shift ;;
    --out)      [ "$#" -ge 2 ] || die_refuse "--out needs a path"; OUT="$2"; shift 2 ;;
    --out=*)    OUT="${1#--out=}"; shift ;;
    --version)  printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         printf 'emit-attestation: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)          printf 'emit-attestation: unexpected argument %s. Paths go after --spec, --result or --out.\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || die_refuse "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
[ -n "$SPEC" ]   || SPEC="$ROOT/.claude/productizer/spec.md"
[ -n "$RESULT" ] || RESULT="$ROOT/.claude/productizer/checks-result.json"

command -v python3 >/dev/null \
  || die_refuse "python3 is not on PATH. The document is JSON and this refuses to hand-roll the escaping of requirement text that contains quotes and backticks."
command -v git >/dev/null \
  || die_refuse "git is not on PATH. The attested state is a commit, and the timestamp is that commit's."

[ -f "$SPEC" ] \
  || die_refuse "no living spec at ${SPEC#"$ROOT"/}. There are no requirements to attest, so nothing was attested."
[ -f "$RESULT" ] \
  || die_refuse "no checks result at ${RESULT#"$ROOT"/}. Run run-checks.sh first. A declarations document with claims and no evidence is an assertion wearing an attestation's clothes."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/emit-attestation.XXXXXX")"

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>"$TMP/git.err" \
  || die_refuse "$(basename "$ROOT") is not a git repository, or git failed: $(tr '\n' ' ' <"$TMP/git.err")"
git -C "$ROOT" rev-parse --verify HEAD >"$TMP/head" 2>"$TMP/head.err" \
  || die_refuse "this repository has no commits yet (no HEAD). There is no state to attest."

HEAD_SHA="$(cat "$TMP/head")"
HEAD_TS="$(TZ=UTC git -C "$ROOT" log -1 --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%ad' HEAD)"

# The commit trailers. This is the half CycloneDX has no field for, so it is
# counted here and reported as a gap rather than mapped into a human field.
TZ=UTC git -C "$ROOT" log --format='%H%x01%B%x02' HEAD >"$TMP/log" 2>"$TMP/log.err" \
  || die_refuse "git log failed: $(tr '\n' ' ' <"$TMP/log.err")"

export EA_ROOT="$ROOT" EA_SPEC="$SPEC" EA_RESULT="$RESULT" \
       EA_HEAD="$HEAD_SHA" EA_TS="$HEAD_TS" EA_LOG="$TMP/log" \
       EA_OUT="${OUT:-}" EA_VERSION="$VERSION"


# The document is built by python3 EMBEDDED HERE rather than in a file beside
# this one. A second file can be installed without this one and then produces a
# document nobody validated; one file cannot be half-installed.
#
# It writes the document to stdout and its report to stderr, and its exit code
# is this script's contract, unchanged: 0 fully measured, 1 findings, 2 refused.
set +e
python3 - >"$TMP/doc.json" 2>"$TMP/report" <<'PYEOF'
import hashlib
import json
import os
import re
import sys

ROOT    = os.environ["EA_ROOT"]
SPEC    = os.environ["EA_SPEC"]
RESULT  = os.environ["EA_RESULT"]
HEAD    = os.environ["EA_HEAD"]
STAMP   = os.environ["EA_TS"]
LOGPATH = os.environ["EA_LOG"]
VERSION = os.environ["EA_VERSION"]

# CycloneDX 1.6. Pinned, not "latest": 1.6 is the version whose schema every
# field below was read out of, and a document claiming a version nobody checked
# it against is the same defect as a check claiming more than it proved.
SPEC_VERSION = "1.6"
SCHEMA_URL = ("https://raw.githubusercontent.com/CycloneDX/specification/"
              "master/schema/bom-1.6.schema.json")


def rel(path):
    """Never an absolute path, and never one that climbs out of the repository.

    This repository is public and a path carries a username. `os.path.relpath`
    alone is not enough: pointed at a file OUTSIDE the root it returns a
    `../../../..` traversal that still spells the whole absolute path out.
    Measured — `--result` under a scratch directory produced exactly that, and
    check-hygiene.sh's slug-form rule is what would have caught it downstream.
    A path that escapes the root is reduced to its basename and labelled."""
    relative = os.path.relpath(path, ROOT)
    if relative.split(os.sep)[0] == os.pardir:
        return "%s (outside the repository)" % os.path.basename(path)
    return relative


def refuse(msg):
    sys.stderr.write("emit-attestation: CANNOT MEASURE — %s\n" % msg)
    sys.exit(2)


findings = []
notes = []


def brief(text, limit=200, tail=" [...] (full text in the document)"):
    """A finding line is a pointer, not the evidence. The full text is in the
    document; a screenful of it per requirement buries the other sixteen. Cut
    on a word boundary — a string severed mid-word reads as a broken file."""
    flat = " ".join((text or "").split())
    if len(flat) <= limit:
        return flat
    cut = flat[:limit]
    space = cut.rfind(" ")
    if space > limit // 2:
        cut = cut[:space]
    return cut.rstrip(" ,;:.") + tail

# ---------------------------------------------------------------- the spec
#
# The requirement pattern is the one req-trailer.sh, stage-status.sh,
# build-view.sh and drift-reverse.sh already count on: a list item whose first
# bold run is the id, with the status marker on the line AFTER it — the line
# immediately after, not the next non-blank one. Five readers of one shape
# disagree the moment one of them is edited, so the rule is copied deliberately
# and said out loud here as it is said out loud there.
try:
    spec_bytes = open(SPEC, "rb").read()
except OSError as exc:
    refuse("cannot read %s: %s" % (rel(SPEC), exc))

SPEC_SHA = hashlib.sha256(spec_bytes).hexdigest()
spec_text = spec_bytes.decode("utf-8", "replace")

REQ_LINE = re.compile(r"^([-*][ \t]+)?\*\*(R[0-9]+)\*\*")

requirements = []
by_id = {}
pending = None
for line in spec_text.split("\n"):
    match = REQ_LINE.match(line)
    if match:
        rid = match.group(2)
        body = line[match.end():].lstrip()
        body = re.sub(r"^[\u2014\u2013-]\s*", "", body).strip()
        pending = {"id": rid, "num": int(rid[1:]), "text": body,
                   "status": "active", "note": None}
        requirements.append(pending)
        by_id[rid] = pending
        continue
    if pending is not None:
        stripped = line.strip()
        if stripped.startswith("Superseded by"):
            pending["status"] = "superseded"
            pending["note"] = stripped
        elif stripped.startswith("Withdrawn."):
            pending["status"] = "withdrawn"
            pending["note"] = stripped
        pending = None

if not requirements:
    refuse("%s holds no ids matching '**R<n>**'. There is nothing to attest, "
           "and an attestation over zero requirements is not a clean one."
           % rel(SPEC))

requirements.sort(key=lambda r: r["num"])
active = [r for r in requirements if r["status"] == "active"]

# The product's own name for itself. The template ships a placeholder, and a
# document naming `<system-name>` as the target of every claim is a document
# that attests nothing, so the placeholder is refused and the repository's own
# directory name is used instead — with the substitution recorded.
product = os.path.basename(ROOT)
product_source = "the repository directory name"
sysmatch = re.search(r"^System\n:\s*`([^`]+)`", spec_text, re.M)
if sysmatch and not sysmatch.group(1).startswith("<"):
    product = sysmatch.group(1)
    product_source = "the spec's `System` field"
elif sysmatch:
    notes.append(
        "the spec's `System` field still holds the template placeholder "
        "`%s`, so the target component is named from %s instead."
        % (sysmatch.group(1), product_source))

# ------------------------------------------------------- the checks result
try:
    result = json.load(open(RESULT, encoding="utf-8"))
except (OSError, ValueError) as exc:
    refuse("cannot read %s as JSON: %s. Nothing was emitted." % (rel(RESULT), exc))

if result.get("schema") != "productizer.checks.result/1":
    refuse("%s declares schema %r, which this emitter has not been read "
           "against. Refusing rather than mapping fields by their names and "
           "hoping." % (rel(RESULT), result.get("schema")))

coverage = result.get("spec_coverage") or {}
units = coverage.get("units")
if not units:
    refuse("%s carries no `spec_coverage.units`. There is no evidence to "
           "attach to any claim, so no claim was made." % rel(RESULT))
if coverage.get("status") != "measured":
    refuse("%s reports spec coverage as %r, not `measured`. An attestation "
           "built on an unmeasured coverage run would state as evidence "
           "something nothing examined." % (rel(RESULT), coverage.get("status")))

unit_by_id = {u["id"]: u for u in units if u.get("id")}
check_by_id = {c["id"]: c for c in result.get("checks", []) if c.get("id")}

# ------------------------------------------------- classifications, rulings
CLASS_DIR = os.path.join(ROOT, ".claude", "productizer", "classifications")
RULING_DIR = os.path.join(ROOT, ".claude", "productizer", "rulings")

classifications = []
if os.path.isdir(CLASS_DIR):
    for name in sorted(os.listdir(CLASS_DIR)):
        if not name.endswith(".md"):
            continue
        body = open(os.path.join(CLASS_DIR, name), encoding="utf-8").read()

        def field(key, text=body):
            hit = re.search(r"^%s:\s*(.+)$" % re.escape(key), text, re.M)
            return hit.group(1).strip() if hit else None

        classifications.append({
            "file": os.path.join("classifications", name),
            "intent": field("Intent"),
            "classification": field("Classification"),
            "recorded": field("Recorded"),
            "spec_commit": field("Spec commit"),
            "reconstructed": "RECONSTRUCTED" in body,
        })
else:
    notes.append(
        "there is no %s directory, so how each intent was classified is "
        "UNMEASURED here. It is not zero classifications."
        % rel(CLASS_DIR))

rulings = []
if os.path.isdir(RULING_DIR):
    for name in sorted(os.listdir(RULING_DIR)):
        if name.endswith(".md"):
            rulings.append(os.path.join("rulings", name))
    if not rulings:
        notes.append("%s exists and holds no ruling file. No contradiction has "
                     "been ruled on here." % rel(RULING_DIR))
else:
    notes.append(
        "there is no %s directory. Whether any contradiction has been ruled "
        "on is UNMEASURED — it is not zero rulings, and this document "
        "therefore attests no human ruling."
        % rel(RULING_DIR))

# The spec's own Decision record is the second place a human ruling lives.
# Template rows are skipped; a row whose `Who` column is an em dash names no
# human, and that is a finding rather than something to quietly leave blank.
decisions = []
in_table = False
for line in spec_text.split("\n"):
    if line.startswith("## Decision record"):
        in_table = True
        continue
    if in_table and line.startswith("## "):
        break
    if not in_table or not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 4 or cells[0] in ("Date", "---") or set(cells[0]) <= set("-: "):
        continue
    if cells[0].startswith("<"):
        continue
    who = cells[3]
    decisions.append({"date": cells[0], "decision": cells[1],
                      "why": cells[2], "who": who,
                      "human_named": bool(who) and who not in ("\u2014", "-", "", "n/a")})

# --------------------------------------------------- what the history says
#
# This is the half CycloneDX has no field for. It is counted here so the gap
# can be stated with a number instead of a worry.
raw = open(LOGPATH, encoding="utf-8", errors="replace").read()
commits_total = 0
commits_req = 0
commits_assisted = 0
commits_agent_coauthor = 0
AGENT_RE = re.compile(
    r"^co-authored-by:.*\b(claude|anthropic|gpt|openai|copilot|cursor|codeium"
    r"|codex|gemini|llm|bot|devin|aider|windsurf)\b", re.I | re.M)
for record in raw.split("\x02"):
    if "\x01" not in record:
        continue
    commits_total += 1
    body = record.split("\x01", 1)[1]
    flat = "\n".join(l.lstrip() for l in body.split("\n"))
    if re.search(r"^productizer-req:", flat, re.I | re.M):
        commits_req += 1
    if re.search(r"^assisted-by:", flat, re.I | re.M):
        commits_assisted += 1
    if AGENT_RE.search(flat):
        commits_agent_coauthor += 1

if commits_total == 0:
    refuse("walked no commits. There is no history to attest against.")

# ============================================================ the document
#
# Field names below are the CycloneDX 1.6 schema's own. Anything not in the
# schema goes in a `properties` array, which is the only place the schema
# sanctions for it, and it is labelled so nobody mistakes it for a standard
# field.

TARGET_REF = "target-product"
ASSESSOR_REF = "assessor-productizer-checks"
STANDARD_REF = "standard-living-spec"

std_requirements = []
for req in requirements:
    entry = {
        "bom-ref": "req-%s" % req["id"],
        "identifier": req["id"],
        # `title` and `text` are both the requirement's own sentence; the
        # title is cut at a WORD boundary, because a title severed mid-word
        # reads as a truncated file rather than as a short name.
        "title": brief(req["text"], 110, tail=" [...]"),
        "text": req["text"],
        "properties": [
            {"name": "productizer:requirement:status", "value": req["status"]},
        ],
    }
    if req["note"]:
        entry["properties"].append(
            {"name": "productizer:requirement:status-note", "value": req["note"]})
    std_requirements.append(entry)

claims = []
evidence = []
attestation_map = []

for req in active:
    unit = unit_by_id.get(req["id"])
    claim_ref = "claim-%s" % req["id"]
    ev_refs = []

    if unit is None:
        findings.append(
            "%s is active in the spec and absent from %s. Nothing claims it, "
            "so this document maps it to no claim at all rather than to an "
            "empty one." % (req["id"], rel(RESULT)))
        attestation_map.append({
            "requirement": "req-%s" % req["id"],
            "claims": [],
            "conformance": {
                "rationale": "UNMEASURED. This requirement does not appear in "
                             "the coverage run, so no score is emitted. It is "
                             "not a score of zero.",
            },
        })
        continue

    for claim in unit.get("claims") or []:
        check_id = claim.get("check") or "unnamed-check"
        ev_ref = "evidence-%s-%s" % (req["id"], check_id)
        check = check_by_id.get(check_id, {})
        pieces = []
        if claim.get("evidence"):
            pieces.append(claim["evidence"])
        if claim.get("reason"):
            pieces.append("Declared limitation: %s" % claim["reason"])
        pieces.append(
            "Check `%s` claimed %s; the check itself exited %s and was "
            "recorded as %s."
            % (check_id, claim.get("claimed"), check.get("exit_code"),
               check.get("status")))
        if claim.get("voided"):
            findings.append(
                "%s: the claim by check `%s` is voided — %s"
                % (req["id"], check_id, brief(claim["voided"])))
            pieces.append("VOIDED: %s" % claim["voided"])

        entry = {
            "bom-ref": ev_ref,
            "propertyName": "productizer:check:%s" % check_id,
            "description": " ".join(pieces),
            "created": STAMP,
        }
        # `author` and `reviewer` are deliberately ABSENT. Both are
        # organizationalContact — a person — and the author of this evidence is
        # a shell script. See the gap block at the foot of the document.
        evidence.append(entry)
        ev_refs.append(ev_ref)

    verdict = unit.get("verdict")
    conformance = {}
    if verdict == "Covered":
        conformance["score"] = 1
        conformance["rationale"] = (
            "Covered: at least one check asserts the whole of this "
            "requirement and passed in the run this document was built from.")
    elif verdict == "Missing":
        conformance["score"] = 0
        conformance["rationale"] = (
            "Missing: no check claims this requirement. The zero is measured "
            "— the coverage run examined every declared check and none named "
            "it.")
        findings.append("%s: Missing — no check claims it." % req["id"])
    else:
        # Partial and n/a get NO score. A Partial's fraction was never
        # measured, and 0.5 would be an invention; an n/a requirement is out of
        # force, which is not a conformance of zero.
        reasons = [c.get("reason") for c in (unit.get("claims") or [])
                   if c.get("reason")]
        conformance["rationale"] = (
            "%s: NO SCORE IS EMITTED, because the fraction of this "
            "requirement that is asserted was never measured, and a number "
            "here would be an invention rather than a reading. What the run "
            "does say: %s"
            % (verdict, " | ".join(reasons) or unit.get("note")
               or "no reason was recorded."))
        findings.append(
            "%s: %s — conformance is unscored, not zero. %s"
            % (req["id"], verdict, brief(" | ".join(reasons))))

    claims.append({
        "bom-ref": claim_ref,
        "target": TARGET_REF,
        "predicate": req["text"],
        "reasoning": "The requirement is asserted by %d declared check(s) in "
                     "%s, run against commit %s."
                     % (len(ev_refs), rel(RESULT), HEAD[:12]),
        "evidence": ev_refs,
    })
    attestation_map.append({
        "requirement": "req-%s" % req["id"],
        "claims": [claim_ref],
        "conformance": conformance,
    })

# The spec itself is evidence: every claim above is a claim about a sentence in
# one file at one commit, and the hash is what makes that checkable.
evidence.append({
    "bom-ref": "evidence-living-spec",
    "propertyName": "productizer:spec:sha256",
    "description": "The living spec %s at commit %s, sha256 %s. %d requirement "
                   "id(s): %d active, %d superseded, %d withdrawn."
                   % (rel(SPEC), HEAD[:12], SPEC_SHA, len(requirements),
                      len(active),
                      sum(1 for r in requirements if r["status"] == "superseded"),
                      sum(1 for r in requirements if r["status"] == "withdrawn")),
    "created": STAMP,
})

for record in classifications:
    evidence.append({
        "bom-ref": "evidence-classification-%s" % (record["intent"] or "unknown"),
        "propertyName": "productizer:classification",
        "description": "Intent %s classified `%s` on %s against the spec at "
                       "commit %s (%s).%s"
                       % (record["intent"], record["classification"],
                          record["recorded"], (record["spec_commit"] or "?")[:12],
                          record["file"],
                          " RECONSTRUCTED after the fact; it does not show "
                          "which ids were in front of the classifier."
                          if record["reconstructed"] else ""),
        "created": STAMP,
    })
    if record["reconstructed"]:
        findings.append(
            "classification for intent %s is a reconstruction, not a "
            "contemporaneous record, and says so." % record["intent"])

for decision in decisions:
    entry = {
        "bom-ref": "evidence-decision-%s" % decision["date"],
        "propertyName": "productizer:decision-record",
        "description": "%s — %s Why: %s"
                       % (decision["date"], decision["decision"], decision["why"]),
        "created": STAMP,
    }
    if decision["human_named"]:
        # The ONE place a name legitimately belongs: a human reviewed and
        # decided this, and `reviewer` is exactly the field for that.
        entry["reviewer"] = {"name": decision["who"]}
    else:
        findings.append(
            "the decision record row dated %s names no human in its `Who` "
            "column, so `evidence.reviewer` is left out rather than filled. A "
            "ruling with nobody's name on it is the failure R34 exists to "
            "prevent, recorded one layer up." % decision["date"])
    evidence.append(entry)

for path in rulings:
    evidence.append({
        "bom-ref": "evidence-ruling-%s" % os.path.basename(path).split("-")[0],
        "propertyName": "productizer:ruling",
        "description": "Contradiction ruling recorded at %s." % path,
        "created": STAMP,
    })

# ------------------------------------------------------------- the gap block
#
# Root `properties` is what the schema offers for "data not officially
# supported in the standard without having to use additional namespaces or
# create extensions". It is the correct home for this and it is NOT a
# CycloneDX field for AI authorship — there is no such field, which is the
# point being recorded.
gap = [
    {"name": "productizer:attestation:ai-authorship:status",
     "value": "NOT REPRESENTABLE IN CYCLONEDX 1.6"},
    {"name": "productizer:attestation:ai-authorship:why",
     "value": "declarations.evidence.author and .reviewer are both "
              "#/definitions/organizationalContact, whose only properties are "
              "bom-ref, name, email and phone: a person. declarations.assessors "
              "carries thirdParty and an organization, with no "
              "assessor-is-a-tool. Neither claim nor evidence has a properties "
              "name-value store. metadata.tools names the tool that GENERATED "
              "this document, never the agent that did the work it describes. "
              "So no field here can record that a model wrote the change a "
              "claim is about, and none has been bent to pretend otherwise."},
    {"name": "productizer:attestation:ai-authorship:evidence-author-left-empty",
     "value": str(sum(1 for e in evidence if "author" not in e))},
    {"name": "productizer:attestation:ai-authorship:commits-walked",
     "value": str(commits_total)},
    {"name": "productizer:attestation:ai-authorship:commits-with-assisted-by",
     "value": str(commits_assisted)},
    {"name": "productizer:attestation:ai-authorship:commits-with-agent-co-authored-by",
     "value": str(commits_agent_coauthor)},
    {"name": "productizer:attestation:ai-authorship:kernel-rule",
     "value": "AI agents MUST NOT add Signed-off-by tags. Only humans can "
              "legally certify the Developer Certificate of Origin (DCO). "
              "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
              "/tree/Documentation/process/coding-assistants.rst"},
    {"name": "productizer:attestation:ai-authorship:proposal",
     "value": "references/attestation.md proposes an in-toto predicate that "
              "would carry this, and states which of the 13 vetted predicates "
              "were checked and why none covers it."},
    {"name": "productizer:attestation:requirement-trailer:commits-with-productizer-req",
     "value": str(commits_req)},
    {"name": "productizer:attestation:built-from-commit", "value": HEAD},
    {"name": "productizer:attestation:spec-sha256", "value": SPEC_SHA},
    {"name": "productizer:attestation:schema-verified-against", "value": SCHEMA_URL},
]
for note in notes:
    gap.append({"name": "productizer:attestation:unmeasured", "value": note})

document = {
    "bomFormat": "CycloneDX",
    "specVersion": SPEC_VERSION,
    "version": 1,
    "metadata": {
        # The HEAD commit's time, not the wall clock: this document describes a
        # commit, and two runs over one commit must produce the same bytes.
        "timestamp": STAMP,
        "tools": {"components": [{
            "type": "application",
            "name": "emit-attestation.sh",
            "version": VERSION.split()[-1],
            "description": "Generated this document. It did not perform the "
                           "work the document attests to, and CycloneDX has no "
                           "field that could say who did.",
        }]},
    },
    "definitions": {"standards": [{
        "bom-ref": STANDARD_REF,
        "name": "%s living spec" % product,
        "version": HEAD[:12],
        "description": "The one living spec for this product, at %s. Every "
                       "requirement id is permanent: never reused, never "
                       "renumbered, and a superseded requirement keeps its "
                       "original sentence." % rel(SPEC),
        "requirements": std_requirements,
    }]},
    "declarations": {
        "assessors": [{
            "bom-ref": ASSESSOR_REF,
            "thirdParty": False,
            # No `organization`. The assessor is run-checks.sh, and CycloneDX
            # has no way to say that. See the gap block.
        }],
        "attestations": [{
            "summary": "Conformance of %s to its own living spec, assessed by "
                       "the declared checks at commit %s. %d active "
                       "requirement(s) mapped."
                       % (product, HEAD[:12], len(active)),
            "assessor": ASSESSOR_REF,
            "map": attestation_map,
        }],
        "claims": claims,
        "evidence": evidence,
        "targets": {"components": [{
            "bom-ref": TARGET_REF,
            "type": "application",
            "name": product,
            "version": HEAD[:12],
        }]},
        # No `affirmation`. Affirmation is a signed certification by named
        # signatories, and nobody has signed this. An empty affirmation would
        # be the document's own version of the Signed-off-by a model must not
        # write.
    },
    "properties": gap,
}

sys.stdout.write(json.dumps(document, indent=2, ensure_ascii=False) + "\n")

# ------------------------------------------------------------- the report
out = sys.stderr
out.write("CycloneDX %s Attestations for %s (%s)\n"
          % (SPEC_VERSION, product, product_source))
out.write("Built from commit %s, %s UTC. Spec %s, sha256 %s.\n"
          % (HEAD[:12], STAMP, rel(SPEC), SPEC_SHA[:16]))
out.write("Requirements: %d total — %d active, %d superseded, %d withdrawn.\n"
          % (len(requirements), len(active),
             sum(1 for r in requirements if r["status"] == "superseded"),
             sum(1 for r in requirements if r["status"] == "withdrawn")))
out.write("Mapped: %d requirement(s) -> %d claim(s) -> %d piece(s) of "
          "evidence, from %d check row(s) in %s.\n"
          % (len(attestation_map), len(claims), len(evidence),
             len(check_by_id), rel(RESULT)))
scored = sum(1 for m in attestation_map if "score" in m["conformance"])
out.write("Conformance: %d of %d mapped requirement(s) carry a score; %d carry "
          "a rationale and NO score, because the value was never measured and "
          "would have had to be invented.\n"
          % (scored, len(attestation_map), len(attestation_map) - scored))
out.write("Classifications: %d record(s). Rulings: %s.\n"
          % (len(classifications),
             "%d file(s)" % len(rulings) if os.path.isdir(RULING_DIR)
             else "UNMEASURED, no rulings directory"))
out.write("\nWHAT CYCLONEDX COULD NOT BE MADE TO SAY, and was not bent into "
          "saying:\n")
out.write("  Walked %d commit(s): %d carry a Productizer-Req trailer, %d carry "
          "an Assisted-by trailer, %d carry a Co-authored-by naming an agent.\n"
          % (commits_total, commits_req, commits_assisted, commits_agent_coauthor))
out.write("  Not one of those facts has a field in `declarations`. "
          "evidence.author and evidence.reviewer are organizationalContact — a "
          "person — so %d piece(s) of evidence were emitted with NO author "
          "rather than with a model's name in a human's field. The gap is "
          "written into the document's root `properties` array, which is the "
          "only place the schema sanctions for it.\n"
          % sum(1 for e in evidence if "author" not in e))

if notes:
    out.write("\nUNMEASURED — reported as unknown, never as zero:\n")
    for note in notes:
        out.write("  %s\n" % note)

if findings:
    out.write("\nFINDINGS (%d) — the document is valid and these say what it "
              "does not establish:\n" % len(findings))
    for item in findings:
        out.write("  %s\n" % item)
    sys.exit(1)

out.write("\nEvery active requirement is mapped to a claim with a measured "
          "conformance. Measured from the counts above.\n")
sys.exit(0)
PYEOF
PYRC=$?
set -e

if [ "$PYRC" != 0 ] && [ "$PYRC" != 1 ]; then
  cat "$TMP/report" >&2
  [ "$PYRC" = 2 ] && exit 2
  printf 'emit-attestation: the builder exited %s before finishing. Undetermined, and nothing was emitted.\n' "$PYRC" >&2
  exit 2
fi

# THE DOCUMENT IS RE-READ FROM DISK BEFORE IT IS HANDED OVER. Serialising JSON
# and then trusting it parses is not a check; opening the bytes that were
# actually written is.
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/doc.json" 2>"$TMP/parse.err" || {
  cat "$TMP/report" >&2
  printf 'emit-attestation: the document written did not parse as JSON: %s. It was NOT emitted.\n' \
    "$(tr '\n' ' ' <"$TMP/parse.err")" >&2
  exit 2
}

if [ -n "$OUT" ]; then
  cat "$TMP/doc.json" >"$OUT"
  printf 'emit-attestation: wrote %s\n' "$OUT" >&2
else
  cat "$TMP/doc.json"
fi
cat "$TMP/report" >&2
exit "$PYRC"
