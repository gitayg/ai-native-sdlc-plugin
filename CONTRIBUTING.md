# Contributing

Suggestions are welcome, and they go through the same lifecycle this plugin
describes. That is deliberate: the repo is its own worked example.

## Suggest something

Open an issue with the **Intent** template. It asks for a problem, a proposed
outcome, who it affects, the constraints and the open questions — the shape the
skill uses at Stage 1, not a feature request form.

Describe the problem rather than the implementation. An intent that names a
solution has already made the design decision, and the interesting part of the
decision is usually the part that was skipped.

If it is not yet shaped like a problem, use [Discussions](../../discussions)
instead. Half-formed is fine there.

## What happens to it

Every intent is classified against the living spec:

| | |
|---|---|
| **Extend** | not covered yet — new requirements |
| **Refine** | covered, but imprecise — tightened in place |
| **Duplicate** | already specified — you get the requirement id |
| **Contradict** | conflicts with something agreed — labelled `sdlc:contradiction`, and nothing merges until it is ruled on |

A duplicate is not a rejection. It means the behaviour is specified, so if it is
not working, that is a bug and a more useful thing to know.

A contradiction is not a rejection either. It means two reasonable people want
opposite things, and the ruling gets recorded with its reasoning rather than
settled by whoever asked last.

## Changing the skill

Pull requests are welcome. Two things to know:

- **The skill is prose that an agent follows**, so wording is behaviour. A
  sentence that reads as a suggestion will be treated as one.
- **Requirement ids are permanent.** Never renumber, never reuse. A reused id
  silently redirects every test, plan and PR that cites it.

Match the existing voice: terse, declarative, and honest about what a thing
costs. Every rule in these files earns its place by naming the failure it
prevents — if you cannot name one, the rule probably is not needed.

## Reporting something broken

Use the other issue template. Include the prompt, the repo state, and what the
skill did instead of what you expected.
