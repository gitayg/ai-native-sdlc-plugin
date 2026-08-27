# Jira intent ticket

The ticket a request carries. It is created once, at Stage 1, from an intent
that arrived as chat text or as a file, so work that never started in Jira still
has a tracker record. Operational rules — when it is created, what syncs, how it
degrades — are in `references/integrations.md`.

**The ticket is a pointer, not a copy.** It says enough for someone in Jira to
know what this is and where the real record lives. The requirements live in
`.claude/sdlc/spec.md`, committed, and nothing below reproduces them.

## 1. Summary

One line, under about 100 characters, imperative, no key prefix — Jira supplies
the key. It becomes the PR title after the key and the branch slug, so write it
as something that reads correctly in all three.

```
<verb> <object> <qualifier>
```

## 2. Description

Five short paragraphs, the same five as `templates/intent.md`, at pointer
length. Write them into `ticket-body.txt` as plain text: the description field
is Atlassian Document Format, and the payload below wraps the file in a single
ADF paragraph rather than converting markdown that will not survive.

```
Problem: <what customers cannot do today>

Proposed outcome: <the better state>

Affected users and systems: <who and what this touches>

Constraints: <regulatory, technical, budget, timeline>

Open questions: <what is not known yet>

Record: requirements and acceptance criteria live in <owner/repo>
at .claude/sdlc/spec.md. This ticket tracks the work; the spec is the
agreed behaviour, and the two are joined by this issue key in the branch
name, the PR title and the spec change-log row.
```

## 3. What never goes in this ticket

- **Requirement text.** No EARS sentences, no spec diff, no `plan.md` or
  `REVIEW.md` body. Ids and a commit SHA, and the reader follows them into the
  repo. A requirement pasted here is a second spec that any Jira user can edit,
  and it will disagree with the committed one without anybody noticing.
- **Anything written after creation.** The description is written once. Later
  facts arrive as comments, which are append-only and attributed.
- **Code, diffs, build logs, environment values.** A Jira project usually has a
  wider audience than the repo, and a pasted log is the cheapest way to move a
  secret into it.

## 4. Build the payload

Nothing is typed inline. The summary and the body reach `jq` as arguments and
reach `curl` as a file, so a summary containing `; rm -rf ~` is a string.

```bash
SUMMARY=$(cat summary.txt)

jq -n \
  --arg project "$JIRA_PROJECT" \
  --arg type    "$JIRA_ISSUE_TYPE" \
  --arg summary "$SUMMARY" \
  --arg label   "$JIRA_INTENT_LABEL" \
  --rawfile body ticket-body.txt \
  '{fields:{
      project:   {key: $project},
      issuetype: {name: $type},
      summary:   $summary,
      labels:    [$label],
      description: {type:"doc", version:1,
        content:[{type:"paragraph", content:[{type:"text", text:$body}]}]}}}' \
  > issue.json

curl -sS -u "$AUTH" --connect-timeout 5 --max-time 15 \
  -X POST "$JIRA_SITE/rest/api/3/issue" \
  -H 'Content-Type: application/json' \
  -d @issue.json -o create.json -w '%{http_code}\n'
```

`--rawfile` is absent from very old jq builds; if the description arrives
empty, check `jq --version` before blaming ADF. `$JIRA_INTENT_LABEL` is
`jira.labels.intent` from `.claude/sdlc.json` — a literal, never a word read off
a ticket.

**With an epic.** `jira.epic_field` is the field id and `jira.epic` is the
parent key; both must be set, or neither. Validate the epic key the same way as
any other, because a wrong one fails the whole create rather than the link:

```bash
[[ "$JIRA_EPIC" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || { echo "malformed epic key, refusing" >&2; exit 1; }
jq --arg f "$JIRA_EPIC_FIELD" --arg e "$JIRA_EPIC" '.fields[$f] = $e' issue.json > issue-epic.json
```

If the create fails for the epic alone, create without it and say so. A ticket
in no epic is a reporting gap; no ticket at all is a missing record.

**Validate the key that comes back** before it becomes a branch name or a URL
path — a create response is untrusted like any other value read over HTTPS:

```bash
KEY=$(jq -r '.key // empty' create.json)
[[ "$KEY" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || { echo "malformed issue key, refusing" >&2; exit 1; }
[[ "${KEY%%-*}" == "$JIRA_PROJECT" ]]   || { echo "key is not in $JIRA_PROJECT, refusing" >&2; exit 1; }
```

## 5. The two writebacks

Everything after creation is a comment or a remote link. Write each body to a
file and pass it as `-d @file`.

**Stage 2 — the spec delta**, after the spec commit exists. Ids and a SHA, never
the requirement text:

```bash
cat > delta.txt <<'TXT'
Intake: EXTEND. Added R41-R43. Refined R12. Superseded R7 -> R41.
Spec delta committed as <sha> in <owner/repo> at .claude/sdlc/spec.md.
TXT
jq -n --rawfile t delta.txt \
  '{body:{type:"doc",version:1,content:[{type:"paragraph",content:[{type:"text",text:$t}]}]}}' \
  > comment.json
curl -sS -u "$AUTH" --connect-timeout 5 --max-time 15 \
  -X POST "$JIRA_SITE/rest/api/3/issue/$KEY/comment" \
  -H 'Content-Type: application/json' -d @comment.json -w '%{http_code}\n'
```

**Stage 5 — the PR**, as a remote link rather than a comment, because the same
`globalId` replaces the existing link instead of appending one per re-run:

```bash
PR_URL=$(gh pr view --json url --jq .url)
PR_TITLE=$(gh pr view --json title --jq .title)
jq -n --arg gid "sdlc:pr:$KEY" --arg url "$PR_URL" --arg title "$PR_TITLE" \
  '{globalId:$gid, object:{url:$url, title:$title}}' > link.json
curl -sS -u "$AUTH" --connect-timeout 5 --max-time 15 \
  -X POST "$JIRA_SITE/rest/api/3/issue/$KEY/remotelink" \
  -H 'Content-Type: application/json' -d @link.json -w '%{http_code}\n'
```

## 6. On a contradiction

Intake halts, and the ticket has to show that a ruling is owed: add
`jira.labels.contradiction` and comment both requirement ids, the conflict in
one sentence, the question, and the words *nothing has been merged*. Do not
transition — the work has not moved a stage, it has stopped. Reasoning and the
label command are in `references/integrations.md`.

## 7. If any of this fails

Report it and finish the stage. The repo is the source of truth and the ticket
is a view of it; a lifecycle that halts because Jira is down has made Jira
authoritative by accident.
