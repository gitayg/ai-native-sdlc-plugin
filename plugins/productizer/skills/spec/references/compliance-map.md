# Compliance map — which artifact evidences which control

A risk function asks a question this lifecycle can answer without being rebuilt
for it: *what would you show an assessor*. The answer is that the artifacts are
already there. The spec, the classification records, the rulings, the declared
checks and their result file, the waivers, the learnings and the gate decisions
are produced as a by-product of doing the work, they are committed, and they
are the same files the pipeline itself reads.

This document states, control by control, which of those artifacts evidences
which obligation — and, at greater length, which obligations they do not touch.

## What this document is not

**It is not a certification, and it is not a claim of compliance.** Certification
is an auditor's word. Nothing here has been assessed by anybody, and a map is
not an assessment. The verb used throughout is *evidences* — an artifact
evidences a control obligation when it is the kind of record the obligation
asks for. Whether that record is sufficient, current, complete and true for a
given organisation is exactly the judgement an assessor is paid to make.

**It is not a control set.** Productizer does not ship an EU AI Act module or a
NIST profile. It ships a lifecycle. The mapping is a description of what that
lifecycle already produces, written down so nobody has to guess.

**It does not write your spec.** Every artifact below is empty until someone
states an intent and it is classified. The map says where the evidence lands,
not what it says.

## Coverage labels

Every row carries exactly one.

| Label | Means |
|---|---|
| **DOCUMENTED** | The obligation is quoted from the framework text, and a named artifact records what it asks for |
| **PARTIAL** | An artifact covers part of the obligation. The row names which part, and which part is left |
| **NOT COVERED** | Productizer produces nothing for this. The row says so and stops |
| **UNVERIFIED** | The framework text has not been read. Only ISO/IEC 42001 rows carry this — see that section |

There is no fifth label meaning *probably fine*. A control nobody has an
artifact for is `NOT COVERED`, which is the same discipline the checks stage
applies to itself: a check that examined nothing is a failure, not a pass.

## How the framework text was obtained

Each quotation below was extracted from the primary document and grepped out of
it. None came from a summary, a consultancy write-up, or a model's recollection.
The one framework that could not be read this way is ISO/IEC 42001, and it is
labelled accordingly throughout.

| Framework | Document | Retrieved from | Method |
|---|---|---|---|
| NIST AI RMF 1.0 | NIST AI 100-1 | `https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf` | `pdftotext -layout`, Tables 1–4 |
| NIST SSDF | SP 800-218 v1.1 | `https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-218.pdf` | `pdftotext -layout`, Table 1, task column sliced by character offset |
| NIST GenAI Profile | SP 800-218A | `https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-218A.pdf` | `pdftotext -layout`, Scope |
| EU AI Act | Regulation (EU) 2024/1689 | `https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=OJ:L_202401689` | HTML tag-stripped, enacting articles and Annexes III and IV |
| EU AI Act, as amended | Regulation (EU) 2026/1744 | `https://eur-lex.europa.eu/eli/reg/2026/1744/oj/eng` | as recorded in this repository's research notes; Article 113 replacement and recital 40 |
| SOC 2 | AICPA TSP section 100, 2017 Trust Services Criteria (with Revised Points of Focus — 2022) | a third-party CDN copy of the AICPA PDF, `92317096_trust_services_criteria_red-lined_version.pdf` | `pdftotext -layout`; see the caveat in that section |
| ISO/IEC 42001:2023 | — | **not read** | paywalled; see that section |

## The artifacts

Everything mapped below is one of these. Each was verified to exist in this
plugin before it was cited.

| Artifact | Where | What it records |
|---|---|---|
| Living spec | `.claude/productizer/spec.md` | EARS requirements, one obligation per permanent id; superseded text kept verbatim; scope, design notes, areas of concern, change log, decision record |
| Constitution | `.claude/productizer/constitution.md` | `P`-numbered principles that bind requirements that do not exist yet; each carries a `Checked by` line |
| Classification records | `.claude/productizer/classifications/` | one per intent: extend, refine, duplicate or contradict, with the spec commit, the spec hash and the requirement ids that were in scope |
| Rulings | `.claude/productizer/rulings/D<n>-<slug>.md` | the human decision that ends a contradiction, written before the question is asked |
| Declared checks | `.claude/productizer/checks.yaml` | which checks exist, what triggers each, whether it blocks, and what it must have covered |
| Check result | `.claude/productizer/checks-result.json` | per check: the exact argv, the tool's version string, the exit code, what triggered it, what it covered and what it did not |
| Waivers | `.claude/productizer/waivers/W<n>-<check-id>.md` | a named authority accepting one measured failure until a stated date. The check stays `fail` |
| Learnings | `.claude/productizer/learnings/L<n>-<slug>.md` | what was noticed and is nobody's obligation, kept below the spec rather than inside it |
| Acceptance criteria | the table in `spec.md` | requirement → the check that asserts it, and what that check was falsified against |
| Gates | `templates/publish-gate.sh`, `templates/production-gate.sh`, `templates/artifact-gate.sh` | `PreToolUse` hooks: a person decides before anything reaches an audience or production |
| Requirement trailers | `scripts/req-trailer.sh` | `Productizer-Req: R14,R22` on the commit — which agreement a commit served |

---

## NIST AI RMF 1.0

Categories and subcategories are quoted from Tables 1–4 of NIST AI 100-1.

**Read the object of each obligation before reading the row.** The AI RMF governs
the risk of *an AI system*. Productizer governs *the process by which software is
built*, and the agent in that process happens to be an AI system. Those are two
different objects, and most of this framework is about the first one. That is
why the `NOT COVERED` rows outnumber the rest here and are the more important
half of the section.

| Subcategory | Obligation (verbatim) | Artifact | Coverage | Note |
|---|---|---|---|---|
| MAP 1.6 | "System requirements (e.g., "the system shall respect the privacy of its users") are elicited from and understood by relevant AI actors. Design decisions take socio-technical implications into account to address AI risks." | living spec; classification records | **PARTIAL** | The first sentence is the living spec, in the same `shall` grammar the subcategory illustrates, with an EARS linter enforcing the form and a classification record naming which ids were in scope when the intent was judged. The second sentence has no artifact here: nothing in the lifecycle reasons about socio-technical implications |
| GOVERN 1.2 | "The characteristics of trustworthy AI are integrated into organizational policies, processes, procedures, and practices." | constitution | **PARTIAL** | The constitution is a policy tier above requirements, checked at intake before classification, and an intent that crosses a principle is refused rather than merged with a note. What it does **not** do is supply the characteristics: Productizer ships no principles and refuses to seed invented ones, so an unratified constitution binds nothing |
| GOVERN 1.4 | "The risk management process and its outcomes are established through transparent policies, procedures, and other controls based on organizational risk priorities." | `checks.yaml`; waivers | **PARTIAL** | Transparent and reviewable is the covered part: which checks run, which block, and who accepted a failure are all in committed files that change by pull request. The result file is not among them &mdash; it is generated and untracked. "Based on organizational risk priorities" is the team's to set and nothing here derives it |
| GOVERN 2.1 | "Roles and responsibilities and lines of communication related to mapping, measuring, and managing AI risks are documented and are clear to individuals and teams throughout the organization." | `checks.yaml` owner; waiver `Authority`; ruling decider | **PARTIAL** | Three named accountabilities exist and are enforced by shape: the checks stage has one named owner who is not in the change's critical path, a waiver without an authority is `malformed` and softens nothing, and a requirement's author may not amend the constitution to unblock their own change. None of this documents anybody's *AI-risk* role |
| MEASURE 1.1 | "Approaches and metrics for measurement of AI risks enumerated during the MAP function are selected for implementation starting with the most significant AI risks. The risks or trustworthiness characteristics that will not – or cannot – be measured are properly documented." | `references/measurement.md`; `checks-result.json` | **PARTIAL** | The second sentence is the one this lifecycle answers directly and at length: a value that could not be measured is never rendered as zero, each instrument prints a distinct word for why, and `measurement.md` carries a *What remains unmeasured* section naming the plugin's own central unmeasured claim. The first sentence presupposes AI risks enumerated in MAP; Productizer enumerates none |
| MEASURE 2.13 | "Effectiveness of the employed TEVV metrics and processes in the MEASURE function are evaluated and documented." | the hollow rule in `run-checks.sh`; the acceptance criteria table | **PARTIAL** | The mechanism matches and the object does not. A check that exits zero having examined less than it declared is reported hollow and treated as a failure, and every acceptance row records what the check was falsified against — that is an evaluation of whether the verification verified anything. It is not an evaluation of an AI system's TEVV metrics, which is what the subcategory means |
| MANAGE 1.1 | "A determination is made as to whether the AI system achieves its intended purposes and stated objectives and whether its development or deployment should proceed." | — | **NOT COVERED** | The deploy gate does stop a deployment until a person approves, which is adjacent and is not this. The gate asks whether *this change* may proceed. It does not determine whether an AI system achieves its purposes, and reading it as if it did would be the more expensive of the two mistakes |
| MAP 5.1 | "Likelihood and magnitude of each identified impact (both potentially beneficial and harmful) based on expected use, past uses of AI systems in similar contexts, public incident reports, feedback from those external to the team that developed or deployed the AI system, or other data are identified and documented." | — | **NOT COVERED** | No impact assessment of any kind |
| MEASURE 2.10 | "Privacy risk of the AI system – as identified in the MAP function – is examined and documented." | — | **NOT COVERED** | |
| MEASURE 2.11 | "Fairness and bias – as identified in the MAP function – are evaluated and results are documented." | — | **NOT COVERED** | No bias testing. Nothing here is a substitute for one |
| MANAGE 4.1 | "Post-deployment AI system monitoring plans are implemented, including mechanisms for capturing and evaluating input from users and other relevant AI actors, appeal and override, decommissioning, incident response, recovery, and change management." | — | **NOT COVERED** | The lifecycle stops at the deploy gate. Change management alone is partially covered under SOC 2 CC8.1 below; the rest of this subcategory is absent |
| MANAGE 4.3 | "Incidents and errors are communicated to relevant AI actors, including affected communities. Processes for tracking, responding to, and recovering from incidents and errors are followed and documented." | — | **NOT COVERED** | |

---

## NIST SSDF — SP 800-218 version 1.1

This is the closest fit of the four frameworks, because it is the only one whose
object is the same as Productizer's: the process by which software is produced.

Tasks are quoted from Table 1 of SP 800-218.

| Task | Obligation (verbatim) | Artifact | Coverage | Note |
|---|---|---|---|---|
| PO.1.2 | "Identify and document all security requirements for organization-developed software to meet, and maintain the requirements over time." | living spec | **PARTIAL** | The spec is where they live and the id discipline is what maintains them: ids are never reused or renumbered, a replaced requirement keeps its original sentence marked superseded, and the file is always current rather than per-change. "All" is the load-bearing word and nothing here establishes that the set is complete |
| PO.3.3 | "Configure tools to generate artifacts of their support of secure software development practices as defined by the organization." | `checks-result.json`; `req-trailer.sh` | **DOCUMENTED** | The result file is that artifact and is generated by the runner rather than written by anyone: exact argv, tool version string, exit code, trigger, coverage. The commit trailer is the second artifact — which requirement a commit served, queryable with `git log --grep` on a machine that has never heard of this tooling |
| PO.4.1 | "Define criteria for software security checks and track throughout the SDLC." | `checks.yaml` | **DOCUMENTED** | The whole declaration is one committed file: which checks exist, what triggers each, whether it blocks, what it must have covered, and which requirement ids it claims. Changing it is a pull request. A config where every check is disabled is a load error rather than a clean pass |
| PO.4.2 | "Implement processes, mechanisms, etc. to gather and safeguard the necessary information in support of the criteria." | `checks-result.json`; `scripts/merge-checks-result.sh` | **PARTIAL** | Gathering is covered: the runner writes the file on every run without anyone's help. Safeguarding is the weaker half and this row says so rather than claiming it. The result file is deliberately **not committed** — a generated measurement conflicts on every merge, and every ordinary conflict resolution writes a number nobody took — so the tree retains no history of past runs, and retention is whatever the CI artifact store gives you. The merge driver that would re-measure rather than pick a side is shipped but **inert** until two `git config` lines are run |
| PW.1.2 | "Track and maintain the software's security requirements, risks, and design decisions." | living spec — *Design*, *Areas of concern*, *Decision record*; rulings | **PARTIAL** | Requirements and design decisions are covered fully, and a decision that ended a contradiction gets its own committed `D`-numbered file so the argument survives the session it was had in. Risks are covered only as far as an *Areas of concern* row goes; there is no risk register and no severity scale |
| PW.2.1 | "Have 1) a qualified person (or people) who are not involved with the design and/or 2) automated processes instantiated in the toolchain review the software design to confirm and enforce that it meets all of the security requirements and satisfactorily addresses the identified risk information." | acceptance criteria table; `acceptance-rows` check | **PARTIAL** | The second limb is instantiated: every active requirement must have a row naming the check that asserts it, and a requirement with no row fails the run. The declared limitation is the honest half — the check asserts a row *exists*, never that the row is *true* |
| PW.7.1 | "Determine whether code review (a person looks directly at the code to find issues) and/or code analysis (tools are used to find issues in code, either in a fully automated way or in conjunction with a person) should be used, as defined by the organization." | `checks.yaml`; `templates/REVIEW.md` | **DOCUMENTED** | This determination is the checks stage's entire premise: it is configured, not baked in, and per-item scoping decides which checks a given change triggers |
| PW.7.2 | "Perform the code review and/or code analysis based on the organization's secure coding standards, and record and triage all discovered issues and recommended remediations in the development team's workflow or issue tracking system." | `run-checks.sh`; `checks-result.json` | **PARTIAL** | Performing and recording are covered, with the coverage assertion that makes a scanner which opened one file out of thirty-three visible instead of green. Triage into a workflow or issue tracking system is not: the spec's own scope section puts being a ticket tracker out of scope |
| PW.8.2 | "Scope the testing, design the tests, perform the testing, and document the results, including recording and triaging all discovered issues and recommended remediations in the development team's workflow or issue tracking system." | `checks.yaml` `when` scoping; `checks-result.json` | **PARTIAL** | Same split as PW.7.2, and the same reason |
| PS.1.1 | "Store all forms of code – including source code, executable code, and configuration-as-code – based on the principle of least privilege so that only authorized personnel, tools, services, etc. have access." | — | **NOT COVERED** | Access control over the repository is the repository host's, not this plugin's |
| PS.3.2 | "Collect, safeguard, maintain, and share provenance data for all components of each software release (e.g., in a software bill of materials [SBOM])." | — | **NOT COVERED** | No SBOM is produced. `req-trailer.sh` records a different provenance — which agreement a commit served, not which components a release contains — and the two must not be confused when answering a supply-chain question |
| RV.1.3 | "Have a policy that addresses vulnerability disclosure and remediation, and implement the roles, responsibilities, and processes needed to support that policy." | — | **NOT COVERED** | |
| RV.3.4 | "Review the SDLC process, and update it if appropriate to prevent (or reduce the likelihood of) the root cause recurring in updates to the software or in new software that is created." | learnings store | **PARTIAL** | The learnings store is a committed record of what was noticed, one file per learning so that "nobody has ever recorded one" and "there are none right now" stay distinguishable. It is not scoped to vulnerability root causes, and nothing forces a learning to change the process |

### SP 800-218A, and the thing it declined to require

SP 800-218A is the SSDF Community Profile for generative AI. It is the one
federal document positioned to create an obligation to record that code was
written by an AI, and it considered the question and declined it. From its
Scope:

> Practices and tasks in this Profile do not distinguish between human-written
> and AI-generated source code, because it is assumed that all source code
> should be evaluated for vulnerabilities and other issues before use.

Two consequences, and both belong in this document rather than in a footnote:

- **The Profile's object is building generative AI models, not building
  software with them.** The exact phrase "coding assistant" appears zero times
  in it — measured, not assumed.
- **No SSDF task asks who or what wrote the code.** So Productizer's requirement
  trailers, classification records and gate log are not an attestation of AI
  authorship in any framework's sense. They are a record this lifecycle keeps
  because it is useful; nothing recognises it. A claim that they satisfy an
  AI-authorship obligation would be a claim about an obligation that does not
  exist.

---

## EU AI Act — Regulation (EU) 2024/1689

### Read this before reading the rows: it may not apply at all

Nearly every obligation below sits in Chapter III, Section 2, which binds
providers of **high-risk** AI systems. Article 6 decides what is high-risk:

> 1. Irrespective of whether an AI system is placed on the market or put into
> service independently of the products referred to in points (a) and (b), that
> AI system shall be considered to be high-risk where both of the following
> conditions are fulfilled: (a) the AI system is intended to be used as a safety
> component of a product, or the AI system is itself a product, covered by the
> Union harmonisation legislation listed in Annex I; (b) the product whose safety
> component pursuant to point (a) is the AI system, or the AI system itself as a
> product, is required to undergo a third-party conformity assessment […]

> 2. In addition to the high-risk AI systems referred to in paragraph 1, AI
> systems referred to in Annex III shall be considered to be high-risk.

Annex III lists eight areas. Read in order, they are: biometrics; critical
infrastructure; education and vocational training; employment and workers'
management; access to essential private and public services; law enforcement;
migration, asylum and border control; and administration of justice and
democratic processes. **A general-purpose coding agent is not obviously in any
of them**, and Article 6(3) then carves out even an Annex III system that "does
not pose a significant risk of harm to the health, safety or fundamental rights
of natural persons", including where it "is intended to perform a narrow
procedural task".

So the honest statement is: whether Chapter III attaches to a coding agent is
**unresolved here**, and this document does not resolve it. What can be said
without guessing is that the obligations attach to *the software being built*
when that software is itself high-risk — which is a question about the product,
not about the tool that built it. Where a team is in that position, the rows
below say which of their obligations this lifecycle already produces evidence
for.

Two further facts, so nobody plans against a stale date. The general date of
application was 2 August 2026 — recital 40 of Regulation (EU) 2026/1744 records
it: "Article 113 of Regulation (EU) 2024/1689 establishes the dates of entry
into force and application of that Regulation, in particular that the general
date of application is 2 August 2026." That Regulation, of 8 July 2026, replaced
Article 113's third paragraph point (c) so that Chapter III, Sections 1, 2 and 3
apply from "2 December 2027 as regards AI systems classified as high-risk
pursuant to Article 6(2) and Annex III" and "2 August 2028 as regards AI systems
classified as high-risk pursuant to Article 6(1)". Slipped sixteen and
twenty-four months respectively — slipped, not cancelled.

### Rows

| Article | Obligation (verbatim, abridged where marked) | Artifact | Coverage | Note |
|---|---|---|---|---|
| Art. 9(1) | "A risk management system shall be established, implemented, documented and maintained in relation to high-risk AI systems." | — | **NOT COVERED** | There is no risk management system here, continuous or otherwise |
| Art. 10(2) | "Training, validation and testing data sets shall be subject to data governance and management practices appropriate for the intended purpose of the high-risk AI system." | — | **NOT COVERED** | No data governance, no training-data lineage, no dataset documentation |
| Art. 11(1) + Annex IV | "The technical documentation of a high-risk AI system shall be drawn up before that system is placed on the market or put into service and shall be kept up-to date. […] It shall contain, at a minimum, the elements set out in Annex IV." Annex IV, point 2(a): "the methods and steps performed for the development of the AI system, including, where relevant, recourse to pre-trained systems or tools provided by third parties and how those were used, integrated or modified by the provider". Annex IV, point 2(b), in part: "the key design choices including the rationale and assumptions made" | change log; classification records; commit trailers; spec *Design* and *Decision record* | **PARTIAL** | Two Annex IV elements out of a long list. Point 2(a) is genuinely evidenced — the change log is one row per commit to the spec, each classification record carries the spec commit and hash it was made against, and the trailer joins a commit to the requirement it served. Point 2(b) is evidenced by the *Design* section and the *Decision record*, which exists precisely to hold the rationale rather than the restatement. Every other Annex IV element, and all of point 1, is absent |
| Art. 12(1) | "High-risk AI systems shall technically allow for the automatic recording of events (logs) over the lifetime of the system." | — | **NOT COVERED** | The gate log records this lifecycle's own gate decisions. It is not a runtime log of an AI system's inferences, and the two are not interchangeable |
| Art. 14(1) | "High-risk AI systems shall be designed and developed in such a way, including with appropriate human-machine interface tools, that they can be effectively overseen by natural persons during the period in which they are in use." | — | **NOT COVERED** | The publish and deploy gates are human oversight of the *build*, exercised before an artefact reaches an audience. Article 14 is about oversight of the deployed system while it runs, which is a different design problem with different failure modes |
| Art. 17(1)(b)–(d) | "(b) techniques, procedures and systematic actions to be used for the design, design control and design verification of the high-risk AI system; (c) techniques, procedures and systematic actions to be used for the development, quality control and quality assurance of the high-risk AI system; (d) examination, test and validation procedures to be carried out before, during and after the development of the high-risk AI system, and the frequency with which they have to be carried out" | `checks.yaml`; acceptance criteria table; review stage; gates | **PARTIAL** | These three sub-points are the strongest EU fit in the document: the checks stage is a written, committed, reviewed statement of which procedures run, when they are triggered, and what must have been covered for a pass to count. The rest of Article 17 is not: (a) regulatory-compliance strategy, (f) data management, (g) the Article 9 risk management system, (h) post-market monitoring, (i) serious-incident reporting are all absent |
| Art. 43 | "the provider shall opt for one of the following conformity assessment procedures based on: (a) the internal control referred to in Annex VI; or (b) the assessment of the quality management system and the assessment of the technical documentation, with the involvement of a notified body, referred to in Annex VII." | — | **NOT COVERED** | Conformity assessment is a procedure a provider runs, sometimes with a notified body. Nothing here performs, prepares or substitutes for it |
| Art. 72(1) | "Providers shall establish and document a post-market monitoring system in a manner that is proportionate to the nature of the AI technologies and the risks of the high-risk AI system." | — | **NOT COVERED** | |
| Art. 73(1)–(2) | "Providers of high-risk AI systems placed on the Union market shall report any serious incident to the market surveillance authorities of the Member States where that incident occurred. […] not later than 15 days after the provider or, where applicable, the deployer, becomes aware of the serious incident." | — | **NOT COVERED** | No incident reporting to any authority, and no mechanism that could become one |

---

## SOC 2 — AICPA Trust Services Criteria

**Provenance caveat, stated first because it changes how much weight these rows
carry.** The AICPA's own download page for *2017 Trust Services Criteria (With
Revised Points of Focus — 2022)* is gated and returns no PDF to a plain request.
The document quoted below is TSP section 100 itself, retrieved as a PDF from a
third-party content CDN, and it is the **red-lined version** — the edition that
renders the 2022 revisions as tracked changes. The criterion text quoted here
was checked line by line for redline artefacts and is clean; the *points of
focus*, which is where most of the redlining lands, are not quoted at all. This
is a copy of the primary document from a host that is not the publisher. Treat
it as one step short of the AICPA's own file.

Criteria are quoted at criterion level. Points of focus are not mapped.

| Criterion | Obligation (verbatim) | Artifact | Coverage | Note |
|---|---|---|---|---|
| CC8.1 | "The entity authorizes, designs, develops or acquires, configures, documents, tests, approves, and implements changes to infrastructure, data, software, and procedures to meet its objectives." | classification records; rulings; spec change log; `checks.yaml`; acceptance table; publish and deploy gates | **PARTIAL** | Read the verbs one at a time. *Authorizes* — an intent is classified against the whole spec, and a contradiction stops until a person rules. *Documents* — the change log, the spec delta and the classification record. *Tests* — the checks stage. *Approves* — the gate is a `PreToolUse` hook, so nothing reaches an audience or production without a person. Not covered: *configures*, *acquires*, and every change to infrastructure or to data |
| CC3.1 | "COSO Principle 6: The entity specifies objectives with sufficient clarity to enable the identification and assessment of risks relating to objectives." | living spec; `validate-spec.py` | **PARTIAL** | Clarity is mechanised rather than asserted: five EARS patterns, one `shall` per requirement, a named system before the `shall`, and a linter that reports a second `shall` as a separate requirement. Risk identification and assessment against those objectives is not here |
| CC5.3 | "COSO Principle 12: The entity deploys control activities through policies that establish what is expected and in procedures that put policies into action." | constitution; `checks.yaml`; gates | **PARTIAL** | The constitution is the policy tier and each principle carries a `Checked by` line, precisely because a principle nobody checks is a slogan. The procedures that put it into action are the checks stage and the gates. Scoped to this lifecycle's controls, not to the entity's |
| CC2.1 | "COSO Principle 13: The entity obtains or generates and uses relevant, quality information to support the functioning of internal control." | `checks-result.json`; the four renderings in the views | **PARTIAL** | The result file is evidence rather than a summary — argv, version, exit code, trigger, covered and not covered — so a reader can tell "the pass found nothing" from "the pass loaded no rules". The rendering vocabulary keeps four states apart: a number when a file was read, `—` when it does not exist, `?` when it exists and could not be parsed, `n/a` when the question does not apply |
| CC4.1 | "COSO Principle 16: The entity selects, develops, and performs ongoing and/or separate evaluations to ascertain whether the components of internal control are present and functioning." | `run-checks.sh` hollow detection; `missing-tool-reported`; `cannot-run-coverage` | **PARTIAL** | *Present and functioning* is the exact question these mechanisms answer: a check that could not run blocks whatever its severity, an absent declared tool is reported missing rather than skipped, and a check that exited zero having examined less than it declared is a failure. What is evaluated is this lifecycle's controls, not the entity's internal control as a whole |
| CC7.1 | "To meet its objectives, the entity uses detection and monitoring procedures to identify (1) changes to configurations that result in the introduction of new vulnerabilities, and (2) susceptibilities to newly discovered vulnerabilities." | `checks.yaml`; `run-checks.sh` | **PARTIAL** | Productizer is the harness, not the detector. It declares which scanners run, refuses a change that triggered no check at all, and records what each one covered. The detection itself is the declared tool's, and the quality of the answer is the tool's quality |
| CC6.1 | "The entity implements logical access security software, infrastructure, and architectures over protected information assets […]" (abridged) | — | **NOT COVERED** | |
| CC7.4 | "The entity responds to identified security incidents by executing a defined incident-response program […]" (abridged) | — | **NOT COVERED** | |
| CC9.2 | "The entity assesses and manages risks associated with vendors and business partners." | — | **NOT COVERED** | |
| Availability, Processing Integrity, Confidentiality, Privacy categories | — | — | **NOT COVERED** | Whole categories. Productizer produces nothing for any of the four |

---

## ISO/IEC 42001:2023 — UNVERIFIED

**This entire section is unverified against the standard, and the reason is that
the standard is paywalled and has not been read.**

What that means in practice, stated plainly rather than hedged:

- **No control text is quoted here, because none has been read.** Every other
  section of this document quotes the obligation. This one cannot, and inventing
  a plausible sentence would be worse than the gap.
- **Titles come from a named third party.** The control titles below were read
  from ISMS.online's *ISO 42001 Annex A Controls Explained*
  (`https://www.isms.online/iso-42001/annex-a-controls/`, retrieved 2026-09-02),
  which lists 38 controls under nine objectives numbered A.2 to A.10. A second
  third-party listing checked the same day also says 38. **That agreement is not
  verification** — two paraphrases agreeing with each other is not either of them
  agreeing with the standard, and consultancy paraphrases of this Annex are known
  to disagree elsewhere.
- **The publisher's own site could not be read either.** `iso.org` returned HTTP
  403 to a plain request, so not even the clause list was obtainable from the
  publisher.
- **Do not present any of this to an assessor as a mapping.** It is a pointer to
  where to look after buying the standard.

| Control (title only, third-party sourced) | Artifact | Coverage |
|---|---|---|
| A.2.2 AI policy | constitution | **UNVERIFIED** |
| A.3.2 AI roles and responsibilities | `checks.yaml` owner; waiver authority; ruling decider | **UNVERIFIED** |
| A.5.2 AI system impact assessment process | — | **UNVERIFIED — and nothing here produces one** |
| A.6.2.2 AI system requirements and specification | living spec | **UNVERIFIED** |
| A.6.2.3 Documentation of AI system design and development | spec *Design*; change log; classification records | **UNVERIFIED** |
| A.6.2.4 AI system verification and validation | `checks.yaml`; acceptance criteria table | **UNVERIFIED** |
| A.6.2.8 AI system recording of event logs | gate decision log | **UNVERIFIED — and the object differs**: the gate log records this lifecycle's decisions, not an AI system's events |
| A.7.5 Data provenance | — | **UNVERIFIED — and nothing here produces one** |
| A.8.4 Communication of incidents | — | **UNVERIFIED — and nothing here produces one** |

---

## What Productizer does not cover

This section is the credibility of the rest of the document. A map that claims
everything is worth nothing, and the honest inventory of gaps is longer than the
inventory of matches.

**Risk classification of an AI system.** Nothing here decides whether a system is
high-risk under Article 6, whether it falls in an Annex III area, or whether the
Article 6(3) derogation applies. That determination is the provider's, it must be
documented before the system is placed on the market, and Productizer neither
performs it nor prompts for it.

**Data governance and training-data lineage.** No dataset inventory, no
provenance records, no quality criteria, no preparation or labelling logs, no
SBOM. Article 10 of the AI Act, SSDF PS.3.2 and the whole of ISO 42001's A.7
group are untouched.

**Model cards and model documentation.** Productizer documents a *change* and the
requirement it served. It documents no model.

**Bias, fairness and disparate-impact testing.** MEASURE 2.11 is `NOT COVERED`
and there is nothing adjacent to it here. A team reading the acceptance criteria
table as evidence of fairness testing would be reading it wrongly.

**Impact assessment on individuals, groups or society.** MAP 5.1, and ISO 42001's
A.5 group. There is no impact assessment process, no trigger for one, and no
template.

**Incident reporting to authorities.** Article 73's fifteen-day, ten-day and
two-day clocks have no counterpart here. Neither does any mechanism for
detecting that a reportable incident occurred.

**Post-market monitoring.** Article 72, MANAGE 4.1. The lifecycle's last gate is
the deploy gate; after that it observes nothing.

**Human-oversight design for a deployed AI system.** Article 14 asks for
oversight *of the running system, by its design*. Productizer's gates are
oversight *of the build*, before release. Conflating them would produce a
compliance claim that fails the first time somebody asks who is watching the
system in production.

**Conformity assessment.** Article 43, Annexes VI and VII. Not performed, not
prepared for, not substituted.

**Runtime logging of an AI system's inferences.** Article 12. The gate log is a
log of decisions this lifecycle made, and it is not the record Article 12 asks
for.

**Access control, incident response, vendor risk, business continuity.** SOC 2
CC6, CC7.4, CC9.2 and the Availability category. These belong to the
organisation's security programme.

**Any assurance that what is recorded is true.** This is the gap most likely to
be misread, so it is stated last and plainly. The checks stage asserts that a
requirement *has* a row in the acceptance criteria table; it does not assert that
the row is true — the spec says so about itself, in the acceptance row for the
requirement that governs it. A classification record proves which spec commit it
was made against; it does not prove which ids were in front of the classifier.
The end-to-end recall of contradiction classification — the plugin's central
claim — is unmeasured, and `references/measurement.md` says so. Every artifact in
this document is a record of what a process did. None of them is a warrant that
the process was right.

## What was not established

Recorded because an explicit list of what could not be shown is worth more than
the map above.

- **Whether a general-purpose coding agent is an Annex III high-risk system.**
  Article 6 and Annex III were read in full; neither settles it. Nothing here
  decides it either way.
- **Whether the Commission's Article 6(5) guidelines have been published.**
  Article 6(5) required them "no later than 2 February 2026", together with a
  list of practical examples of high-risk and not-high-risk use cases. That list
  is the document which would answer the question above in practice. It was not
  fetched and its status is unknown here.
- **ISO/IEC 42001 control text, and the control count.** Not read. The section
  above says what was read instead and from whom.
- **The AICPA TSC as published by the AICPA.** What was read is a copy of TSP
  section 100 from a third-party CDN, in its red-lined edition.
- **Whether any of these mappings would satisfy an assessor.** Nobody has
  assessed them. That is the whole reason the word *evidences* is used and the
  word *compliant* is not.
