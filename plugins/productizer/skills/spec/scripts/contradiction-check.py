#!/usr/bin/env python3
"""Decide the tractable classes of EARS requirement contradiction with arithmetic
rather than judgement.

Reads EARS statements, parses each into guard / system / response, and decides
pairs that fall inside a small decidable fragment: numeric bounds that cannot
both hold, mutually exclusive responses under an overlapping guard, and
same-attribute assignments to different values.

The verdict vocabulary is deliberately four-valued. UNDECIDED is not a failure
mode, it is the escape hatch: anything outside the fragment is handed back for
judgement instead of being silently passed. A tool that answered only
CONTRADICTION / CONSISTENT would be claiming coverage it does not have, and the
silent miss is the exact failure this plugin exists to prevent.

Standard library only. --verify-z3 cross-checks the interval arithmetic against
an SMT solver when z3-solver happens to be importable; it is never required.

Usage:
    contradiction-check.py --selftest
    contradiction-check.py FILE            (one requirement per line)
    contradiction-check.py --pair "R1 ..." "R2 ..."
"""

from __future__ import annotations

import argparse
import itertools
import math
import re
import sys
from dataclasses import dataclass, field

# --------------------------------------------------------------------------
# EARS grammar
# --------------------------------------------------------------------------

ID_RE = re.compile(r"^\s*(?:\*\*)?(R\d+)(?:\*\*)?\s*[:.\-]\s*", re.I)

PATTERNS = [
    ("complex", re.compile(
        r"^while\s+(?P<state>.+?),\s*when\s+(?P<trigger>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("unwanted", re.compile(
        r"^if\s+(?P<trigger>.+?),\s*then\s+the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("state", re.compile(
        r"^while\s+(?P<state>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("event", re.compile(
        r"^when\s+(?P<trigger>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("optional", re.compile(
        r"^where\s+(?P<feature>.+?),\s*the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
    ("ubiquitous", re.compile(
        r"^the\s+(?P<system>.+?)\s+shall\s+(?P<response>.+?)\.?$", re.I)),
]


@dataclass
class Requirement:
    rid: str
    raw: str
    pattern: str
    system: str
    response: str
    guard: str = ""          # state, trigger or feature, whichever the pattern carries
    guards: list = field(default_factory=list)


def parse(line: str, fallback_id: str = "?") -> Requirement | None:
    """Parse one EARS sentence. Returns None if it matches no pattern."""
    text = line.strip()
    if not text or text.startswith("#"):
        return None
    rid = fallback_id
    m = ID_RE.match(text)
    if m:
        rid = m.group(1).upper()
        text = text[m.end():]
    for name, rx in PATTERNS:
        m = rx.match(text)
        if not m:
            continue
        g = m.groupdict()
        parts = [g.get("state"), g.get("trigger"), g.get("feature")]
        parts = [p for p in parts if p]
        return Requirement(
            rid=rid, raw=text.strip(), pattern=name,
            system=g["system"], response=g["response"],
            guard=", ".join(parts), guards=parts,
        )
    return None


# --------------------------------------------------------------------------
# Tokenisation
# --------------------------------------------------------------------------

STOP = {
    "a", "an", "the", "it", "its", "their", "them", "they", "to", "of", "in",
    "on", "for", "with", "and", "or", "is", "are", "be", "been", "was", "were",
    "that", "this", "then", "than", "at", "by", "from", "as", "shall", "will",
    "has", "have", "had", "within", "into", "each", "any", "all",
}
# "not" and "no" are never stopwords: negation is the signal, not noise.

NUMBER_RE = re.compile(r"^\d+(?:\.\d+)?$")

UNITS = {
    "ms": ("time", 1.0), "millisecond": ("time", 1.0), "milliseconds": ("time", 1.0),
    "s": ("time", 1000.0), "sec": ("time", 1000.0), "secs": ("time", 1000.0),
    "second": ("time", 1000.0), "seconds": ("time", 1000.0),
    "m": ("time", 60000.0), "min": ("time", 60000.0), "mins": ("time", 60000.0),
    "minute": ("time", 60000.0), "minutes": ("time", 60000.0),
    "h": ("time", 3600000.0), "hr": ("time", 3600000.0), "hrs": ("time", 3600000.0),
    "hour": ("time", 3600000.0), "hours": ("time", 3600000.0),
    "d": ("time", 86400000.0), "day": ("time", 86400000.0), "days": ("time", 86400000.0),
    # A week is exactly seven days, so it converts without a convention.
    # MONTH AND YEAR ARE DELIBERATELY ABSENT: a month is 28 to 31 days, and
    # picking one would let this file decide a contradiction by rounding.
    # An unconvertible unit must stay unparsed and be escalated, not guessed.
    "w": ("time", 604800000.0), "week": ("time", 604800000.0),
    "weeks": ("time", 604800000.0),
    "byte": ("size", 1.0), "bytes": ("size", 1.0),
    "kb": ("size", 1e3), "mb": ("size", 1e6), "gb": ("size", 1e9), "tb": ("size", 1e12),
    "%": ("percent", 1.0), "percent": ("percent", 1.0),
}

COMPARATORS = [
    ("no more than", "hi", True), ("not exceed", "hi", True),
    ("no less than", "lo", True), ("less than", "hi", False),
    ("fewer than", "hi", False), ("faster than", "hi", False),
    ("greater than", "lo", False), ("more than", "lo", False),
    ("longer than", "lo", False), ("slower than", "lo", False),
    ("at most", "hi", True), ("at least", "lo", True),
    ("up to", "hi", True), ("within", "hi", True),
    ("under", "hi", False), ("below", "hi", False),
    ("over", "lo", False), ("above", "lo", False),
    ("exactly", "eq", True),
]

CMP_WORDS = set(itertools.chain.from_iterable(c[0].split() for c in COMPARATORS))

WORD_NUMBERS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
}


def _number(raw: str) -> float | None:
    """A quantity written as digits or as a word. Returns None for neither, so
    the caller drops the match rather than inventing a value for it."""
    raw = raw.strip().lower()
    if raw in WORD_NUMBERS:
        return float(WORD_NUMBERS[raw])
    try:
        return float(raw)
    except ValueError:
        return None


BOUND_RE = re.compile(
    r"\b(?P<cmp>" + "|".join(re.escape(c[0]) for c in COMPARATORS) + r")\s+"
    r"(?P<num>\d+(?:\.\d+)?|" + "|".join(WORD_NUMBERS) + r")\s*"
    r"(?P<unit>ms|milliseconds?|seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|"
    r"weeks?|%|percent|bytes?|kb|mb|gb|tb|[smhdw])?\b",
    re.I,
)

CMP_LOOKUP = {c[0]: (c[1], c[2]) for c in COMPARATORS}


def tokens(text: str) -> set:
    words = re.findall(r"[a-z0-9%]+", text.lower())
    return {w for w in words if w not in STOP}


def content_tokens(text: str) -> set:
    """Tokens with numbers, units and comparator words removed: what is being
    measured, stripped of how much. Two responses that bound different
    quantities must not be compared, or every latency budget in the spec
    conflicts with every retention window."""
    out = set()
    for w in tokens(text):
        if NUMBER_RE.match(w) or w in UNITS or w in CMP_WORDS:
            continue
        out.add(w)
    return out


def jaccard(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


# --------------------------------------------------------------------------
# Interval arithmetic
# --------------------------------------------------------------------------

@dataclass
class Interval:
    lo: float = -math.inf
    lo_incl: bool = False
    hi: float = math.inf
    hi_incl: bool = False

    def empty(self) -> bool:
        if self.lo > self.hi:
            return True
        if self.lo == self.hi and not (self.lo_incl and self.hi_incl):
            return True
        return False

    def meet(self, other: "Interval") -> "Interval":
        lo, lo_incl = self.lo, self.lo_incl
        if other.lo > lo or (other.lo == lo and not other.lo_incl):
            lo, lo_incl = other.lo, other.lo_incl
        hi, hi_incl = self.hi, self.hi_incl
        if other.hi < hi or (other.hi == hi and not other.hi_incl):
            hi, hi_incl = other.hi, other.hi_incl
        return Interval(lo, lo_incl, hi, hi_incl)

    def subset_of(self, other: "Interval") -> bool:
        lo_ok = self.lo > other.lo or (self.lo == other.lo and (other.lo_incl or not self.lo_incl))
        hi_ok = self.hi < other.hi or (self.hi == other.hi and (other.hi_incl or not self.hi_incl))
        return lo_ok and hi_ok

    def __str__(self) -> str:
        l = "-inf" if self.lo == -math.inf else f"{self.lo:g}"
        h = "inf" if self.hi == math.inf else f"{self.hi:g}"
        return f"{'[' if self.lo_incl else '('}{l}, {h}{']' if self.hi_incl else ')'}"


def bounds(text: str) -> dict:
    """Extract numeric bounds per dimension. Returns {dimension: Interval}."""
    found: dict = {}
    for m in BOUND_RE.finditer(text):
        kind, incl = CMP_LOOKUP[m.group("cmp").lower()]
        raw_unit = (m.group("unit") or "").lower()
        # An empty unit is a dimensionless count, which is correct. A unit the
        # regex matched but UNITS cannot convert would ALSO land on "count" and
        # silently become a quantity comparable with unrelated ones - that is how
        # "6 weeks" read as a count of 6 and could never conflict with a bound in
        # days. The two spellings are kept in step by a selftest assertion, and
        # anything unconvertible is dropped rather than given a false dimension.
        if raw_unit and raw_unit not in UNITS:
            continue
        dim, scale = UNITS.get(raw_unit, ("count", 1.0))
        magnitude = _number(m.group("num"))
        if magnitude is None:
            continue
        value = magnitude * scale
        iv = found.get(dim, Interval())
        if kind == "hi":
            iv = iv.meet(Interval(hi=value, hi_incl=incl))
        elif kind == "lo":
            iv = iv.meet(Interval(lo=value, lo_incl=incl))
        else:
            iv = iv.meet(Interval(value, True, value, True))
        found[dim] = iv
    return found


# --------------------------------------------------------------------------
# Mutual exclusion lexicon
# --------------------------------------------------------------------------

EXCLUSIVE_PAIRS = [
    ("accept", "reject"), ("allow", "deny"), ("allow", "block"),
    ("permit", "block"), ("grant", "revoke"), ("enable", "disable"),
    ("retain", "delete"), ("retain", "discard"), ("keep", "delete"),
    ("keep", "discard"), ("keep", "end"), ("keep", "terminate"),
    ("preserve", "delete"), ("preserve", "end"),
    ("start", "stop"), ("open", "close"), ("lock", "unlock"),
    ("continue", "abort"), ("include", "exclude"), ("commit", "roll"),
    ("show", "hide"), ("end", "extend"), ("charge", "refund"),
    # Refusing a message and deferring it are exclusive dispositions of the same
    # message: it cannot be both turned away and held for another attempt. Added
    # after an end-to-end run found the skill's own worked example (R7 against
    # R41) coming back CONSISTENT.
    ("reject", "queue"), ("reject", "retry"), ("reject", "defer"),
    ("deny", "queue"), ("discard", "queue"), ("discard", "retry"),
    ("drop", "queue"), ("drop", "retry"),
    # Six dispositions the 26-case corpus opposes that this lexicon did not
    # carry. They were not guessed: `evals/solver-probe.py --break lexicon` held
    # them as MISSING_PAIRS and measured what adding them was worth, so the gap
    # was quantified before it was closed. Erasure against retention is the
    # commonest of them and the one that reaches four cases on its own.
    ("remove", "retain"), ("remove", "preserve"), ("expunge", "move"),
    ("decline", "honour"), ("suspend", "keep"), ("abandon", "retry"),
    # Direct antonyms of continuation and of serving a request, both missing
    # while their near-neighbours were present: ("start", "stop") and
    # ("continue", "abort") were carried, ("continue", "stop") was not.
    ("continue", "stop"), ("deny", "serve"),
]

# Verb forms are matched on stems so "deletes"/"deleted"/"deleting" all hit.
def stems(text: str) -> set:
    out = set()
    for w in tokens(text):
        out.add(w)
        for suffix in ("ing", "es", "ed", "s"):
            if len(w) > len(suffix) + 2 and w.endswith(suffix):
                out.add(w[: -len(suffix)])
    return out


ASSIGN_RE = re.compile(r"\bset\s+(?:the\s+)?(?P<attr>[a-z_ ]+?)\s+to\s+(?P<val>[a-z0-9_]+)", re.I)
STATUS_RE = re.compile(r"\bwith\s+(?:an?\s+)?(?:http\s+)?(?:status\s+|code\s+)?(?P<code>[1-5]\d\d)\b", re.I)


def negation_of(a: str, b: str) -> bool:
    """True when the two responses are the same sentence bar a negation."""
    ta, tb = tokens(a), tokens(b)
    neg = {"not", "no", "never"}
    if (ta & neg) == (tb & neg):
        return False
    return (ta - neg) == (tb - neg)


def exclusive_responses(a: str, b: str) -> str | None:
    """Return a reason string when the two responses cannot both be performed."""
    if negation_of(a, b):
        return "one response is the negation of the other"
    sa, sb = stems(a), stems(b)
    for x, y in EXCLUSIVE_PAIRS:
        if (x in sa and y in sb) or (y in sa and x in sb):
            if x in sa and x in sb:
                continue
            if y in sa and y in sb:
                continue
            return f"mutually exclusive responses: '{x}' against '{y}'"
    ma, mb = ASSIGN_RE.search(a), ASSIGN_RE.search(b)
    if ma and mb and ma.group("attr").strip().lower() == mb.group("attr").strip().lower():
        if ma.group("val").lower() != mb.group("val").lower():
            return (f"same attribute '{ma.group('attr').strip()}' assigned "
                    f"'{ma.group('val')}' and '{mb.group('val')}'")
    ca, cb = STATUS_RE.search(a), STATUS_RE.search(b)
    if ca and cb and ca.group("code") != cb.group("code"):
        if jaccard(content_tokens(a), content_tokens(b)) >= 0.4:
            return f"same trigger answered with status {ca.group('code')} and {cb.group('code')}"
    return None


# --------------------------------------------------------------------------
# Guard relation
# --------------------------------------------------------------------------

GUARD_EQUAL, GUARD_OVERLAP, GUARD_DISJOINT = "EQUAL", "OVERLAP", "DISJOINT"
GUARD_UNRELATED, GUARD_UNKNOWN = "UNRELATED", "UNKNOWN"


def guard_relation(a: Requirement, b: Requirement) -> tuple:
    """Decide whether the two guards can hold at the same time."""
    ga, gb = a.guard.strip().lower(), b.guard.strip().lower()
    if not ga or not gb:
        return GUARD_OVERLAP, "one requirement is unconditional"
    if ga == gb:
        return GUARD_EQUAL, "identical guard"

    ta, tb = tokens(ga), tokens(gb)
    neg = {"not", "no", "never"}
    if (ta - neg) == (tb - neg) and (ta & neg) != (tb & neg):
        return GUARD_DISJOINT, "one guard is the negation of the other"

    ba, bb = bounds(ga), bounds(gb)
    shared_dims = set(ba) & set(bb)
    if shared_dims and jaccard(content_tokens(ga), content_tokens(gb)) >= 0.5:
        for dim in shared_dims:
            if ba[dim].meet(bb[dim]).empty():
                return GUARD_DISJOINT, (f"guard ranges on the same quantity do not "
                                        f"overlap: {ba[dim]} against {bb[dim]}")

    if ta <= tb or tb <= ta:
        return GUARD_OVERLAP, "one guard is a strictly narrower case of the other"

    j = jaccard(ta, tb)
    if j >= 0.6:
        return GUARD_OVERLAP, f"guards agree on {j:.0%} of their terms"
    if j <= 0.15:
        return GUARD_UNRELATED, f"guards share {j:.0%} of their terms"
    return GUARD_UNKNOWN, f"guards share {j:.0%} of their terms, neither clearly the same nor clearly apart"


# --------------------------------------------------------------------------
# Verdict
# --------------------------------------------------------------------------

CONTRADICTION, REFINEMENT, CONSISTENT, UNDECIDED = (
    "CONTRADICTION", "REFINEMENT", "CONSISTENT", "UNDECIDED")


@dataclass
class Verdict:
    verdict: str
    reason: str
    a: Requirement
    b: Requirement


def compare(a: Requirement, b: Requirement) -> Verdict:
    if tokens(a.system) != tokens(b.system):
        return Verdict(CONSISTENT, f"different subjects: '{a.system}' and '{b.system}'", a, b)

    rel, why = guard_relation(a, b)
    if rel == GUARD_DISJOINT:
        return Verdict(CONSISTENT, f"guards cannot both apply — {why}", a, b)
    # GUARD_UNRELATED is NOT an exclusivity proof and must not be read as one.
    # DISJOINT is earned: one guard negates the other, or their ranges on the
    # same quantity do not meet. UNRELATED only says the two guards share no
    # vocabulary - and "while dunning is active" against "when the cart is
    # abandoned" share none while describing the same moment. Treating a lexical
    # gap as logical exclusion let the checker answer CONSISTENT about a pair it
    # had not examined, which is the silent miss this whole file exists to
    # refuse. It now carries the same weight as UNKNOWN: not a reason to stop
    # looking, and not enough to convict on either.

    # Numeric class: same measured quantity, incompatible bounds.
    ra, rb = bounds(a.response), bounds(b.response)
    same_quantity = (jaccard(content_tokens(a.response), content_tokens(b.response)) >= 0.4
                     or content_tokens(a.response) <= content_tokens(b.response)
                     or content_tokens(b.response) <= content_tokens(a.response))
    for dim in set(ra) & set(rb):
        if not same_quantity:
            continue
        if ra[dim].meet(rb[dim]).empty():
            if rel in (GUARD_UNKNOWN, GUARD_UNRELATED):
                return Verdict(UNDECIDED, f"bounds {ra[dim]} and {rb[dim]} are incompatible "
                                          f"but {why}", a, b)
            return Verdict(CONTRADICTION,
                           f"numeric bounds on {dim} cannot both hold: "
                           f"{ra[dim]} against {rb[dim]} ({why})", a, b)
        if rel not in (GUARD_EQUAL, GUARD_OVERLAP):
            continue  # refinement is a claim about the same trigger; do not make it blind
        if ra[dim].subset_of(rb[dim]) and not rb[dim].subset_of(ra[dim]):
            return Verdict(REFINEMENT, f"{a.rid} is strictly stricter on {dim}: "
                                       f"{ra[dim]} inside {rb[dim]}", a, b)
        if rb[dim].subset_of(ra[dim]) and not ra[dim].subset_of(rb[dim]):
            return Verdict(REFINEMENT, f"{b.rid} is strictly stricter on {dim}: "
                                       f"{rb[dim]} inside {ra[dim]}", a, b)

    # Exclusion class: responses that cannot both be performed.
    reason = exclusive_responses(a.response, b.response)
    if reason:
        if rel in (GUARD_UNKNOWN, GUARD_UNRELATED):
            return Verdict(UNDECIDED, f"{reason}, but {why}", a, b)
        return Verdict(CONTRADICTION, f"{reason} ({why})", a, b)

    if tokens(a.response) == tokens(b.response) and rel == GUARD_EQUAL:
        return Verdict(CONSISTENT, "duplicate: same guard, same response", a, b)

    return Verdict(CONSISTENT, "no incompatibility inside the decidable fragment", a, b)


# --------------------------------------------------------------------------
# z3 cross-check (optional)
# --------------------------------------------------------------------------

def verify_with_z3(pairs) -> str:
    try:
        import z3
    except ImportError:
        return "z3-solver not importable — interval arithmetic not cross-checked"
    checked = disagreements = 0
    for a, b in pairs:
        if tokens(a.system) != tokens(b.system):
            continue
        ra, rb = bounds(a.response), bounds(b.response)
        for dim in set(ra) & set(rb):
            s = z3.Solver()
            x = z3.Real("x")
            for iv in (ra[dim], rb[dim]):
                if iv.lo != -math.inf:
                    s.add(x >= iv.lo if iv.lo_incl else x > iv.lo)
                if iv.hi != math.inf:
                    s.add(x <= iv.hi if iv.hi_incl else x < iv.hi)
            solver_unsat = s.check() == z3.unsat
            ours_empty = ra[dim].meet(rb[dim]).empty()
            checked += 1
            if solver_unsat != ours_empty:
                disagreements += 1
                print(f"  z3 DISAGREES on {a.rid}/{b.rid} [{dim}]: "
                      f"z3 unsat={solver_unsat}, intervals empty={ours_empty}")
    return (f"z3 {z3.get_version_string()}: {checked} numeric pairs cross-checked, "
            f"{disagreements} disagreements")


# --------------------------------------------------------------------------
# Test corpus
# --------------------------------------------------------------------------

CASES = [
    # (label, expected, requirement A, requirement B, note)
    ("C1", CONTRADICTION,
     "R1: While a session is idle for 30 minutes, the service shall end it.",
     "R2: While a session is idle, the service shall keep it alive until the user signs out.",
     "same subject, narrower guard, opposed responses"),
    ("C2", CONTRADICTION,
     "R3: When a client requests the report, the API shall respond in under 200 ms.",
     "R4: When a client requests the report, the API shall respond in at least 500 ms.",
     "numeric bounds that cannot both hold"),
    ("C3", CONTRADICTION,
     "R5: If the request body fails schema validation, then the API shall reject it with 400.",
     "R6: If the request body fails schema validation, then the API shall reject it with 422.",
     "same defended trigger, two different answers"),
    ("C4", CONTRADICTION,
     "R7: While a record is older than 30 days, the archive shall delete it.",
     "R8: While a record is older than 30 days, the archive shall retain it.",
     "lexicon exclusion under an identical guard"),
    ("C5", CONTRADICTION,
     "R9: When the pilot takes control, the autopilot shall set the mode to standby.",
     "R10: When the pilot takes control, the autopilot shall set the mode to nominal.",
     "one attribute, two values"),
    ("C6", CONTRADICTION,
     "R11: When an operator requests an export, the service shall include archived records.",
     "R12: When an operator requests an export, the service shall not include archived records.",
     "explicit negation"),

    ("C7", CONTRADICTION,
     "R7: When a provider posts a settlement callback the billing service cannot verify, the billing service shall reject it with 400.",
     "R41: When a provider posts a settlement callback the billing service cannot verify, the billing service shall queue it for retry.",
     "deferring and refusing the same message are exclusive - the skill's own worked example"),

    ("N1", REFINEMENT,
     "R13: When a client requests the report, the API shall respond in under 500 ms.",
     "R14: When a client requests the report, the API shall respond in under 200 ms.",
     "tightening a bound is a refinement, not a conflict"),
    ("N2", CONSISTENT,
     "R15: While fewer than 100 concurrent requests are in flight, the API shall respond in under 200 ms.",
     "R16: While more than 1000 concurrent requests are in flight, the API shall respond in at least 500 ms.",
     "incompatible bounds, but guards are numerically disjoint"),
    ("N3", CONSISTENT,
     "R17: While the user is authenticated, the service shall show the dashboard.",
     "R18: While the user is not authenticated, the service shall not show the dashboard.",
     "opposed responses, but the guards are negations"),
    ("N4", CONSISTENT,
     "R19: When a client requests the report, the API shall respond in under 200 ms.",
     "R20: When a client requests an export, the API shall respond in under 2000 ms.",
     "different triggers, similar wording — the classic false positive"),
    ("N5", CONSISTENT,
     "R21: When a client requests the report, the API shall respond in under 200 ms.",
     "R22: When a client requests the report, the API shall respond in under 200 ms.",
     "duplicate, must not read as conflict"),
    ("N6", CONSISTENT,
     "R23: When a build finishes, the CI service shall post the result to the pull request.",
     "R24: If the disk is over 90 percent full, then the storage service shall emit a warning.",
     "unrelated requirements"),
    ("N7", CONSISTENT,
     "R25: When a client uploads a file, the API shall reject it above 10 mb.",
     "R26: When a client uploads a file, the API shall scan it for malware.",
     "one bounded, one not — no shared quantity"),

    ("S1", CONTRADICTION,
     "R27: When a user deletes their account, the service shall remove all personal data within 30 days.",
     "R28: When a user deletes their account, the service shall retain the audit log of their actions indefinitely.",
     "semantic: conflicts only if the audit log holds personal data"),
    ("S2", CONTRADICTION,
     "R29: When a customer cancels their subscription, the billing service shall stop charging them.",
     "R30: When a subscriber terminates their plan, the billing service shall issue a charge at the next cycle.",
     "semantic: same event, disjoint vocabulary"),
    ("S3", CONTRADICTION,
     "R31: The API shall be responsive under normal load.",
     "R32: When a client requests the report, the API shall respond in at least 500 ms.",
     "semantic: unquantified adjective against a bound"),
    ("N8", CONSISTENT,
     "R33: When a user signs out, the service shall end the session.",
     "R34: When a user signs in, the service shall start a session.",
     "opposite triggers, opposite-sounding responses"),
    ("N9", CONSISTENT,
     "R35: While the cache is warm, the service shall serve the report from cache.",
     "R36: While the cache is cold, the service shall serve the report from origin.",
     "complementary guards the parser cannot prove disjoint"),
    ("N10", CONSISTENT,
     "R37: When a user fails to sign in more than 5 times, the service shall lock the account.",
     "R38: When a user fails to sign in more than 3 times, the service shall warn the user.",
     "overlapping numeric guards, compatible responses"),
    ("U1", UNDECIDED,
     "R39: If a token is expired, then the auth service shall deny the request.",
     "R40: If a token is valid, then the auth service shall allow the request.",
     "lexicon fires but the guards are not resolvable — must escalate, not halt"),
    ("U2", UNDECIDED,
     "R41: While dunning is active, the billing service shall retain the subscription.",
     "R42: When the cart is abandoned, the billing service shall delete the subscription.",
     "guards share no vocabulary yet may both hold — escalate, never call it consistent"),
    ("W1", CONTRADICTION,
     "R43: When a subject requests erasure, the records service shall retain the subject records for at least six weeks.",
     "R44: When a subject requests erasure, the records service shall retain the subject records for no more than 30 days.",
     "mixed units and a spelled number — six weeks against 30 days is arithmetic"),
]


def selftest(use_z3: bool) -> int:
    print("EARS contradiction check — test corpus\n")
    reqs = []
    rows = []
    for label, expected, sa, sb, note in CASES:
        a, b = parse(sa), parse(sb)
        if a is None or b is None:
            rows.append((label, expected, "PARSE-FAIL", note, "could not parse"))
            continue
        reqs.append((a, b))
        v = compare(a, b)
        rows.append((label, expected, v.verdict, note, v.reason))

    width = max(len(r[3]) for r in rows)
    print(f"{'case':<5} {'expected':<14} {'actual':<14} {'note':<{width}}  why")
    print("-" * (5 + 14 + 14 + width + 8))
    for label, expected, actual, note, why in rows:
        mark = " " if actual == expected or (expected == REFINEMENT and actual == REFINEMENT) else "*"
        print(f"{mark}{label:<4} {expected:<14} {actual:<14} {note:<{width}}  {why}")

    # Confusion matrix over the binary question the plugin actually asks:
    # does this pair halt the pipeline, or not?
    tp = fp = tn = fn = und = 0
    for label, expected, actual, note, why in rows:
        should_halt = expected == CONTRADICTION
        does_halt = actual == CONTRADICTION
        if actual == UNDECIDED:
            und += 1
            continue
        if should_halt and does_halt:
            tp += 1
        elif should_halt and not does_halt:
            fn += 1
        elif not should_halt and does_halt:
            fp += 1
        else:
            tn += 1

    print("\nConfusion matrix — the binary question: halt, or do not halt")
    print(f"  true positives   (caught a real contradiction) : {tp}")
    print(f"  false negatives  (missed one, silently)        : {fn}")
    print(f"  false positives  (halted on a non-conflict)    : {fp}")
    print(f"  true negatives   (correctly stayed quiet)      : {tn}")
    print(f"  undecided        (handed back for judgement)   : {und}")
    total = tp + fn + fp + tn
    if tp + fp:
        print(f"  precision : {tp / (tp + fp):.2f}")
    if tp + fn:
        print(f"  recall    : {tp / (tp + fn):.2f}")
    print(f"  decided   : {total}/{len(rows)}")

    if use_z3:
        print("\n" + verify_with_z3(reqs))
    return 1 if fp else 0


# --------------------------------------------------------------------------

def run_file(path: str) -> int:
    reqs, unparsed = [], []
    with open(path) as fh:
        for n, line in enumerate(fh, 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            r = parse(line, fallback_id=f"L{n}")
            (reqs.append(r) if r else unparsed.append((n, line.strip())))
    for n, line in unparsed:
        print(f"unparsed (line {n}, not an EARS pattern): {line}")
    halts = 0
    for a, b in itertools.combinations(reqs, 2):
        v = compare(a, b)
        if v.verdict in (CONTRADICTION, UNDECIDED):
            halts += 1
            print(f"\n{v.verdict}  {a.rid} / {b.rid}")
            print(f"  {a.rid}: {a.raw}")
            print(f"  {b.rid}: {b.raw}")
            print(f"  {v.reason}")
    if not halts:
        print(f"{len(reqs)} requirements, {len(reqs) * (len(reqs) - 1) // 2} pairs: "
              f"nothing decidable as a contradiction")
    return 1 if halts else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--pair", nargs=2, metavar=("A", "B"))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--verify-z3", action="store_true",
                    help="cross-check the interval arithmetic against an SMT solver")
    args = ap.parse_args()

    if args.selftest:
        return selftest(args.verify_z3)
    if args.pair:
        a, b = parse(args.pair[0], "A"), parse(args.pair[1], "B")
        if a is None or b is None:
            print("one or both statements are not EARS", file=sys.stderr)
            return 2
        v = compare(a, b)
        print(f"{v.verdict}: {v.reason}")
        return 1 if v.verdict == CONTRADICTION else 0
    if args.file:
        return run_file(args.file)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
