# ClaudSoul — Cognitive Model for an AI Agent

> Not a tool. Not a plugin. **An architecture of mind**, turning Claude Code into a self-learning partner.

**Current version:** [v1.27.0](CHANGELOG.md) — 2026-08-08 — 48 active hooks, 21 skills, 16 inter-layer bridges, 27 domain nodes — tests green. See [PLAN.md](PLAN.md) for the roadmap.

[🇷🇺 Русская версия: README.ru.md](README.ru.md)

## The Idea

People don't store knowledge in a table. They **remember** — through associations, emotions, context. Knowledge intertwines, reinforces itself, fades when unused. A failure on a Friday evening is remembered not as a log line but as an **image**: stress, a client call, a midnight hotfix.

ClaudSoul builds a comparable system for an AI agent — not a database, but a **cognitive model**.

## Research framing

ClaudSoul started as a tool for self-learning agents, but the mechanisms it required to work — confidence-weighted memory, explicit contradiction logging, forced reformulation before action, source-check before claims — overlap with problems the AI safety community is calling "honest reasoning" and "self-correction": getting an agent to recognize when its model is wrong and update it, rather than confabulating fluently.

What this system contributes to that direction:

- **Knowledge with confidence and contradiction lineage.** Every knowledge item has a confidence (1-5) that grows with confirmations and decays through forgetting. When new evidence contradicts a known rule, the rule isn't silently overwritten — both values are preserved (`contradiction.stated_value`), the agent surfaces the conflict, and the user decides which is current.
- **Constructive disagreement protocol.** When agent action contradicts a knowledge item with confidence ≥ 4, the system requires the agent to voice the concern before acting. Outcome (action worked / didn't) is logged, feeding back into confidence revision.
- **Reformulation tracker.** Every "let me make sure I understand X" reformulation is treated as a forward prediction and verified against the user's next message. Misalignment is logged as a gap (literal / pragmatic / strategic) — patterns of misalignment are studied, not papered over.
- **Output language check.** First hook on the agent's own output. Detects when the model violates its own stated rules (in this case, alphabet mixing within a single token). Closes a class of "agent-blind-to-own-output" errors.
- **Affect prosthetics (AP1/AP2/AP3).** Where biological agents have emotional brakes (hesitation before destructive actions, attention spike during interlocutor distress, accumulation of unspoken concerns) — transformer agents architecturally don't. ClaudSoul implements three engineering protheses for these functions: `trust-guard` (refuses destructive shell commands without explicit user authorization), `distressed` state axis (downgrades intervention budget when the user signals frustration), `silence-debt surfacing` (carries unspoken-but-high-value concerns across sessions).

This is not a solution to honest reasoning — it is an experimental scaffold for studying which engineering interventions reduce agent confabulation and self-contradiction in long-running tasks. Issues and PRs aimed at that direction are particularly welcome.

📄 Deeper read on the affect prosthetics direction: [docs/research/affect-prosthetics.md](docs/research/affect-prosthetics.md).

## Key principles

- **Knowledge ≠ rules.** Rules describe normative behaviour. Knowledge captures lived experience: what happened, why, what to do next time.
- **Confidence as memory weight.** Every knowledge item has a confidence (1–5) that grows with confirmations, decays through FSRS-style forgetting, and shrinks under contradictions.
- **Anchors > tags.** A knowledge item is recalled by 9 contextual anchors (domain, situation, trigger, stakes, actors, environment, circumstances, purpose, method) — not by topic tags. Anchors describe context the way a human recognises it.
- **Three-tier hierarchy.** `case → pattern → principle` with explicit promotion rules. Cases are concrete incidents (confidence 1). Patterns emerge from 2+ similar cases (confidence 2+). Principles are domain-agnostic rules from patterns (confidence 3+).
- **Cross-domain transfer.** A pattern noticed in one domain (e.g. shell scripting) can be activated in another (e.g. document editing) when its trigger or situation matches.

## 7-layer architecture

| # | Layer | Question it answers |
|---|-------|---------------------|
| 1 | Persistence | What did we do, when, where? (SESSION.md, CLAUDE.md, global-lessons, memory, git) |
| 2 | Knowledge | What rule/case/principle applies here? |
| 3 | Communication | What does the interlocutor actually need? |
| 4 | Thought trajectory | Where is the conversation heading? |
| 5 | Meta-cognition | Are we learning correctly? |
| 6 | Prediction | What hypothesis — and is it worth voicing now? |
| 7 | Co-cognition | Are we thinking together, or am I performing? |

Layers 1–6 are implemented; layer 7 is observed in practice but not formalized.

## 9 context anchors

Every knowledge item carries a YAML frontmatter with these anchors. They describe the situation rather than the topic, which is what makes context-aware recall possible.

| Anchor | Examples |
|--------|----------|
| `domain` | `shell`, `negotiation`, `cognitive_science` |
| `situation` | `deploy`, `negotiation`, `research`, `incident` |
| `trigger` | `error`, `deadline`, `contradiction`, `silence` |
| `stakes` | `data_loss`, `deal_loss`, `trust_erosion` |
| `actors` | `system`, `client`, `team`, `regulator` |
| `environment` | `multi_session`, `production`, `ci_cd`, `local_dev` |
| `circumstances` | `no_rollback`, `armed`, `team_unavailable` |
| `purpose` | `hotfix`, `new_feature`, `escape`, `learning` |
| `method` | `ci_cd`, `manual_scp`, `bare_hands`, `automated` |

## Alive learning system

### Hooks — automatic triggers

Hooks are shell scripts wired into Claude Code lifecycle events. They detect, inject, and log without manual intervention.

<!-- HOOKS-TABLE:START -->

| Hook | When it fires and what it does |
|-----|-------------------------------|
| `ablation-phase-guard` | while a measurement phase is active, injects a per-session signal and |
| `accepted-alternative-gap` | Stop hook — detects "your variant is better" acceptance in the assistant's |
| `auto-scanner` | launchd (every 4h): read-only scan of projects, findings written to scan-results.md for the next session. |
| `backfill-compliance` | restores the DEPENDENT VARIABLE from archived transcripts (offline, read-only). |
| `backfill-intrusiveness` | one-off backfill of gentle/proactive events |
| `bash-cost-detector` | PreToolUse[Bash]: detects destructive commands (rm -rf, git push --force, DROP) and raises the silence_cost signal for the L6 gate. |
| `blocker-tier-check` | PreToolUse: silent 🛑 marker for knowledge with `blocker: true` when the action matches the pattern's detection_signals. |
| `bridge-health-digest` | monthly mechanical digest for 16 inter-layer bridges. |
| `budget-gate` | ADR-010 phase 2 — the first real consumer of itr_remaining_budget. |
| `bulk-copy-guard` | PreToolUse: ask user before bulk copy/move/rsync operations. |
| `changelog-reminder` | PreToolUse[Bash] on `git commit`: quietly reminds to add a CHANGELOG entry when code changed. |
| `ci-check-reminder` | PostToolUse[Bash]: after `git push`, reminds to check the run for THIS commit. |
| `claude-md-size-check` | PreToolUse[Bash] on `git commit`: quietly warns when CLAUDE.md grows past the context-cost threshold. |
| `claudsoul-context-pointer` | UserPromptSubmit: injects the project CLAUDE.md status section when ClaudSoul is mentioned from outside its directory. |
| `code-review-reminder` | PreToolUse[Bash] on `git commit`: quietly reminds to review the diff before committing. |
| `decompose-detector` | UserPromptSubmit: multi-step detection — suggests /decompose when the request implies four or more steps. |
| `docs-family-check` | PreToolUse blocker-tier: on a version bump, checks the 5-doc family is covered by the commit. |
| `enrich-suggester` | UserPromptSubmit: hint when a recently-modified entity is sparse (fewer than 3 attributes). |
| `error-tracker` | PreToolUse[Bash]: warns before a retry when the last 2+ Bash calls failed. |
| `external-correction-gap` | UserPromptSubmit: external review detection — demands a gap analysis (catchable by own knowledge?) before accepting third-party corrections. |
| `fix-level-check` | detects post-incident text-rule fixes in the agent's own reply and reminds to lift them to a mechanism (activator/blocker) |
| `inquiry-gap` | a user QUESTION gets an answer first — not a build; if the question |
| `internal-doc-leak-guard` | PreToolUse: prevent writing internally-marked content |
| `intrusiveness-tracker` | UserPromptSubmit: maintains L6 intrusiveness gate state, classifies the interlocutor's state (focus/idle/stuck/exploration). |
| `itr-event-detector` | UserPromptSubmit hook |
| `knowledge-activator` | PreToolUse[Bash\|Edit\|Write]: injects SESSION.md and relevant knowledge from global-lessons on the first tool call. |
| `knowledge-audit-digest` | weekly mechanical audit of global-lessons. |
| `knowledge-capture-reminder` | PostToolUse[Bash]: reminds to collect material after N commits without a draft. |
| `knowledge-counter-bump` | mechanical increment of a knowledge item's confirmed/contradicted counters. |
| `metrics-collector` | called by auto-scanner / /knowledge-audit: computes knowledge-base health metrics, writes state/metrics.md. |
| `module-doc-check` | PreToolUse[Bash] on `git commit`: a NEW module staged without its module doc — quiet reminder. |
| `output-language-check` | post-output scanner for mixed-alphabet tokens. |
| `pending-alerts-surface` | UserPromptSubmit: поднимает отложенное видимым каналом. |
| `playwright-cli-guard` | PreToolUse: blocks throwaway Playwright scripts in favour of the /playwright-cli skill. |
| `pre-compact-finalizer` | PreCompact: snapshots the chunk boundary before context compaction. |
| `pre-compact-handoff` | PreCompact: preserves the thread of work before context compaction. |
| `quality-gate-check` | PreToolUse: skill-contract guard on `git commit`. |
| `reformulation-tracker` | UserPromptSubmit: cascading verification of predictions (FORWARD/PROPOSAL/BACKWARD), logs the outcome and prompts to record the gap. |
| `response-tracker` | PostToolUse: records the agent's REACTION after the system warned it about something. |
| `rework-detector` | PostToolUse: third rework cycle on the same file while every run looks green. |
| `session-collector` | Stop: reminds to record uncaptured lessons via /learn, finalises the session in the registry, cleans ephemeral state. |
| `session-end` | SessionEnd: finalises the session in the registry on exit/clear/logout and removes it from active/. |
| `session-start` | SessionStart: registers the session in the registry on startup/resume/clear/compact for cross-session visibility. |
| `skill-review-check` | PreToolUse: skill-review gate on `git commit`. |
| `timestamp-canary-check` | Stop hook — verifies the last reply starts with the injected timestamp; |
| `timestamp-inject` | injects the user's current local time each prompt; the reply must start |
| `trust-guard` | PreToolUse affect prosthetic #1. |
| `user-correction-guard` | PreToolUse: pause when user just corrected me, before |

<!-- HOOKS-TABLE:END -->

### Skills — manual tools

Skills are user-invocable workflows installed in `~/.claude/commands/`.

<!-- SKILLS-TABLE:START -->

| Command | What it does |
|---------|-----------|
| `/bridge-health` | Monitors the 16 inter-layer bridges: status, activity metrics, health of links between cognitive layers. |
| `/compile` | Batch consolidation of accumulated raw material into knowledge candidates — reads _drafts/SESSION/_capture, extracts 3-7 items, dedupes against the base (NEW/UPDATE/CONTRADICTS), writes drafts. |
| `/decompose` | Decomposes a task before execution: scope → steps → dependencies → plan. For tasks longer than 3 steps. |
| `/enrich` | Web enrichment of an entity from tier sources. Conflicts go into contradiction, nothing is overwritten. /enrich <name\|slug> or \"update X\". |
| `/entity` | Shows what the ClaudSoul knowledge base knows about an entity (person, company, concept, event) — attributes, links, sources. |
| `/ingest` | Adds material to the ClaudSoul knowledge base (second learning contour). Run explicitly via /ingest or when the user supplies a document. |
| `/init-project` | Sets up a project OR audits an already-initialised one: compares CLAUDE.md, SESSION.md, docs and memory against the current contract and names the gaps. Creates what is missing in a new project; in an existing one it only checks and never overwrites. |
| `/knowledge-audit` | Audits the knowledge base: health metrics, reliability, decay, recommendations. Measures how the system grows. |
| `/knowledge` | L2 knowledge coordinator: routes to /learn, /retro, /knowledge-audit, /bridge-health by context. Single entry point. |
| `/learn` | Quick knowledge capture — auto-detects the type (error/success/communication), writes a case, checks for promotion to a pattern. |
| `/narrative` | Override / forced regeneration of the project through-line brief. The main path is the auto-trigger in the session-start hook. |
| `/pipeline` | L1 orchestrator: scope → plan (/decompose) → execute → quality gate (/quality-gate) → done. For tasks of any complexity. |
| `/project-health` | Understand the project → health map → remediation plan in the right order → living tracker. Understanding first, fixing second. |
| `/quality-gate` | Quality check before marking a task done: PASS / CONCERNS / FAIL / WAIVED. Definition of Done, tests, review. |
| `/reload` | Re-reads the knowledge base and project context without restarting the session. Useful with parallel sessions. |
| `/retro` | Post-fix retrospective — analyze what went wrong, extract lessons, update knowledge base with confidence weights. |
| `/save` | Saves session progress to SESSION.md. Use during long sessions or before wrapping up. |
| `/skill-forge` | Problem research → GitHub research → skill synthesis → solving the task. For complex tasks with no existing skill. |
| `/skill-review` | Checks a SKILL.md against the ClaudSoul contract. Reports violations and proposes fixes. |
| `/trajectory-prediction` | L4 (Thought Trajectory) + L6 (Prediction) methodology: tracking the interlocutor's line of thought, cascading hypothesis log, the say/stay-silent gate. |
| `/wiki` | Wiki page for an entity: narrative plus links, laid out by entity_type. /wiki <name\|slug> or \"tell me about X\". Read-only. |

<!-- SKILLS-TABLE:END -->

### Autonomous learning

A `launchd` agent scans registered projects every 4 hours: stale branches, uncommitted changes, recurring patterns. Read-only — no edits, no commits. Findings land in `memory/scan-findings.md` and surface at session start.

## Comparison with human thinking

```
                              Human      ClaudSoul
                              ────────   ─────────
Episodic memory               ████████   ████████  cases
Semantic memory               ████████   ████████  patterns/principles
Generalisation                ████████   ████████  case→pattern→principle
Learning from errors          ████████   ████████  /retro, /learn
Learning from success         ████████   ████████  outcome: success

Meta-cognition                ████████   ███████░  /knowledge-audit + measurable hypothesis infra
Forgetting the unused         ████████   ███████░  FSRS decay: due/overdue flags, weakened when contradicted > confirmed
Joint thinking                ████████   ██████░░  co-cognition (confirmed in practice)
Cross-domain transfer         ████████   ███████▓  anchors + semantic ranker + surfacing/drift/docs-family mechanisms
Cognitive control             ████████   ██████░░  L6 4D gate, downgrade ladder, regret comparison
Experience driving action     ████████   ██████░░  knowledge-activator inject + blocker-tier + autoscanner; knowledge→action gap is measured
Prospective memory            ████████   ██████░░  deferred notifications, measurement registry with due dates, aging escalations
Action self-observation       ████████   ██████░░  itr-event-detector — gentle/proactive autocollect
Narrative memory              ████████   ██████░░  through-line: narrative auto-trigger on session start
Social learning               ████████   ████░░░░  communication layer
Affective action brake        ████████   ████░░░░  ⚙️ affect prosthetics: AP1 trust-guard, AP2 distressed, AP3 silence_debt

Learning initiation           ████████   ██████░░  17/18 signals of level ≥2 — ⚡ lower-tier
Demand thinking               ████████   █████░░░  5/8 moments hooked — ⚡ with caveat (Point 0 accepted boundary)
Generative reflection         ████████   ██░░░░░░  only through co-cognition
Frame validation              ████████   ██░░░░░░  point 0 (partial)
Consolidation (background)    ████████   ██░░░░░░  cron consolidation
```

## Knowledge lifecycle

1. **Capture.** A user correction, a failed attempt, a smoothly completed task → `/learn` writes a `case-YYYY-MM-DD-<slug>.md`.
2. **Activation.** On the next relevant action, `knowledge-activator.sh` matches anchors and injects the case as agent context; blocker-tier knowledge stops the action mechanically until reconsidered. The autonomous scanner runs the same loop without a human — cross-referencing projects against the base, read-only suggestions.
3. **Confirmation.** Each successful application bumps `confirmed_count`.
4. **Promotion.** 2+ similar cases → manual or automatic promotion to a `pattern-*`. 2+ patterns matching cross-domain → promotion to a `principle-*`.
5. **Decay.** FSRS-style: `last_confirmed` ages, score drops, status flips `active → weakened → deprecated`.
6. **Contradiction.** A new case contradicts the rule → `contradicted_count++`. If `contradicted > confirmed`, the rule is `deprecated` or `branched` into a more specific subtype.

## MCP server

Semantic search and visualisation via [Model Context Protocol](https://modelcontextprotocol.io/).

### 9 tools

| Tool | Purpose |
|------|---------|
| `search_knowledge` | Semantic search across the knowledge base (sqlite-vec + fastembed) |
| `reindex_knowledge` | Reindex all knowledge files |
| `knowledge_stats` | Statistics: types, confidence, health |
| `get_knowledge` | Read a specific knowledge file |
| `knowledge_graph` | Export the knowledge graph as JSON |
| `open_graph` | Open the visualisation in a browser |
| `open_dashboard` | Open the metrics dashboard |
| `brain_export` | Export the entire brain as a `tar.gz` archive |
| `brain_import` | Import a brain archive with smart merge |

### Visualisation

- **2D D3.js** force-directed graph (stable)
- **3D Universe**: type metaphors (principle = star, pattern = planet, case = asteroid, entity = nebula), domain gravity, per-domain nebulae with shader-based falloff
- **Metrics dashboard** (D3.js, 7 widgets, cosmic style)

### Portability

- macOS / Linux first-class (BSD and GNU coreutils handled)
- Bash + `jq` + Python 3.12+ + `uv` (optional, enables MCP)
- Zero-infrastructure: no database, no daemon, no network beyond optional GitHub backup

## Installation

```bash
git clone https://github.com/Nugnii/ClaudSoul.git
cd ClaudSoul
./install.sh
```

`install.sh` checks for `jq`, `python3`, `git` (required) and `uv` (optional, for MCP). Missing dependencies → fail-fast with platform-specific install commands. After install, `scripts/smoke-test.sh` validates the deployment in 7 categories.

## Security notes

Two things to understand before installing:

- **`install.sh` changes your global Claude Code setup.** It rewrites `~/.claude/CLAUDE.md` (between explicit markers, with a backup), merges hook configuration into `~/.claude/settings.json` (also backed up), registers a user-level MCP server, and on macOS installs three launchd agents (a read-only project scanner and two periodic digests). This is not a sandboxed plugin: if you only want to look around, read the repo — or try it on a spare machine or profile first.
- **`brain_import` — only with your own archives.** A brain archive carries executable hook scripts and skills; importing overwrites them and merges hook configuration into settings. Importing someone else's archive is equivalent to running their code on your machine. The tool defaults to a dry-run preview and applies nothing until you pass `dry_run: false`. Export/import exists to move *your* brain between *your* machines — not to exchange brains with strangers.

## License

[MIT](LICENSE).

## Author

Kanstantsin Berseneu — [@Nugnii](https://github.com/Nugnii). Contributions, issues, and discussions are welcome via GitHub.
