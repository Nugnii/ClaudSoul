# ClaudSoul

**Your agent's memory can be wrong — and this one knows it.** A correction becomes a rule with a confidence score. Contradictions are kept rather than overwritten. Unused rules sink out of recall. And a rule that has proven itself enough times is put back in front of the agent at the moment it is about to be broken — not left in a config file it read an hour ago.

56 hooks on Claude Code lifecycle events, 23 commands, a knowledge base that scores and decays, and an MCP server for semantic search over it — organised as a seven-layer cognitive architecture.

**At a glance:** 63 active hooks, 23 skills, 16 inter-layer bridges, 27 domain nodes — tests green.

[![tests](https://github.com/Nugnii/ClaudSoul/actions/workflows/tests.yml/badge.svg)](https://github.com/Nugnii/ClaudSoul/actions/workflows/tests.yml)
[![version](https://img.shields.io/badge/version-1.32.0-blue)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-9%20tools-8A2BE2)](https://modelcontextprotocol.io/)

[Русская версия](README.ru.md) · [Architecture](docs/architecture.md) · [Hooks and commands](docs/reference.md) · [Changelog](CHANGELOG.md) · [Roadmap](PLAN.md)

<sub><b>About this repository.</b> It is published as a squashed snapshot of the working tree — one commit per release. The development history is not publishable: session logs and internal documents are interleaved through it. The commit count you see here describes the publishing method, not the age or the activity of the project.</sub>

![One knowledge base rendered live: 287 nodes, 1086 edges. Amber spheres are principles, cyan are patterns, violet are cases, green are entities from the encyclopedic contour. Node size encodes confidence multiplied by impact; edges are relations between items.](docs/assets/knowledge-universe.png)

<sub>The author's base after four months, rendered live from <code>~/.claude/global-lessons/</code> by the MCP server's <code>open_graph</code>. 417 items in the base; the graph draws 287 of them as nodes and 1086 edges, of which 64 come from explicit relation files. A fresh install starts with 37 seed items and grows from your own sessions. (UI shown in Russian; the graph itself is language-agnostic.)</sub>

---

## The problem it solves

You correct your agent. It agrees. Next session it makes the same mistake, because the correction lived in a transcript that no longer exists.

The usual fix is to write a rule into `CLAUDE.md`. That works until the file grows past the point where every rule is loaded and none is followed. A rule in a file is a rule the model may or may not act on — and by the time it matters, that file was read at the start of the session, thousands of tokens ago.

ClaudSoul treats a correction as evidence rather than as text:

- **Written down as a case**, with the situation it happened in, not just the lesson.
- **Recalled by situation, not by topic.** Nine context anchors — `domain`, `situation`, `trigger`, `stakes`, `actors`, `environment`, `circumstances`, `purpose`, `method` — are recorded with every item; activation on the first mutating tool call scores eight of them (`actors` is recorded for the reader, and by design not scored: at activation time the actor is always the agent). A rule about broken deploys surfaces during a deploy, not on every prompt.
- **Gains and loses confidence.** Confirmations raise it; contradictions weaken, narrow or branch it by the reason for the mismatch — the rule is wrong, the scope is too broad, or the context is different; disuse pushes it down the recall ranking (FSRS-style).
- **Delivered at the moment of the action.** A rule promoted to `blocker: true` carries machine-readable `detection_signals` — tool, path, size, regex — evaluated *before* the tool call. The rule arrives in the agent's reasoning exactly when it is about to be broken.

That last step is the point of the whole system: a rule the agent read an hour ago is weaker than a rule that arrives as its hand is already moving.

There is an explicit ladder of how embedded a rule is: text in a config file → situational injection → a targeted marker right before the action → a harness refusal. A fix after an incident is not allowed to stay on the first rung — text that holds only through being read measurably does not hold. Climbing a rung is an explicit decision, but the knowledge announces its own readiness: once its confirmation counter reaches the escalation threshold, the weekly digest names it as a candidate for the next rung.

**What this does not do:** by default `blocker: true` does not hard-stop the call — it is a silent marker into the agent's context, deliberately ([the hook says so in its own header](hooks/blocker-tier-check.sh)), because noise is its own failure mode; only a signal marked `enforcement: deny` refuses the call to the agent, and the user is never asked. 9 hooks *do* interrupt: 4 ask you to confirm (`bash-cost-detector`, `user-correction-guard`, `bulk-copy-guard`, `internal-doc-leak-guard`) and 5 refuse outright (`playwright-cli-guard`, `rules-write-bypass`, `skill-name-ascii-guard`, `five-whys-gate`, `blocker-tier-check` on a `deny` signal). Promotion to `blocker: true` is also an explicit decision, never automatic on a counter — each one costs time on every tool call.

## One correction, traced end to end

The chain the system is built to produce. This is the narrowest of the three chains in the author's base — and the only one where a before/after series exists at all. That is the honest reason it is the example.

**April 24.** The agent wrote a word with half the letters in Latin and half in Cyrillic. A rule forbidding exactly this was already in memory and was loaded every session. It did not fire. A human caught it.

**The diagnosis was not "typo".** A rule that only a human can enforce is a broken rule. It was filed as a knowledge-action gap — one more instance of an existing pattern.

**The same day**, the case became a mechanism: `hooks/output-language-check.sh`, a hook that reads the agent's own finished reply and looks for such words itself.

**The next day the mechanism was caught being weak** — it warned too late to matter. It was rebuilt the day after rather than declared done.

**Since then the machine catches them, not the human:** 185 findings over five months.

| Month | Findings | Sessions | Per session |
|---|---:|---:|---:|
| 2026-04 (from the 24th) | 10 | 19 | — |
| 2026-05 | 81 | 55 | **1.47** |
| 2026-06 | 66 | 101 | 0.65 |
| 2026-07 | 9 | 41 | 0.22 |
| 2026-08 | 19 | 120 | **0.16** |

Sessions are counted from the L6 telemetry (`intrusiveness-history.jsonl`, 336 unique sessions over the span). The session registry counts 384 for the same period, which would make the fall steeper, not shallower — the more conservative denominator is the one used here.

**Three caveats, because the number is only as good as they allow.**

1. **The instrument was defective inside the measurement window.** Commit `1846dfb` (August 8) fixed a transcript extractor that had been feeding `output-language-check` the wrong slice of the reply. Part of the July and early-August fall is the instrument, not the improvement, and the logs cannot say how much. The May-to-June fall predates that defect.
2. **This is one author's single base, not a controlled experiment.** A preregistered ablation protocol exists ([docs/ablation-protocol.md](docs/ablation-protocol.md)) and has produced no data.
3. **The counter is the hook itself.** The hook was rebuilt during the period. A detector that changes cannot cleanly measure a change.

The claim that survives all three: this class of error is now found by a machine 185 times, and it used to be found by a person. The size of the improvement is not established.

## Install

```bash
git clone https://github.com/Nugnii/ClaudSoul.git
cd ClaudSoul
./install.sh
```

Required: Claude Code, `jq`, `python3`, `git`. Optional: `uv` (enables the MCP server), macOS (enables three scheduled background agents; on Linux the installer prints the cron equivalents instead of installing them).

`install.sh` ends by running `scripts/smoke-test.sh`, which checks the deployment across seven categories. The first effect appears in your **next new session**, not immediately.

> **Read this before installing.** This is not a sandboxed plugin: `install.sh` rewrites `~/.claude/CLAUDE.md` between explicit markers, merges hook commands into `~/.claude/settings.json`, registers a user-level MCP server, and on macOS installs three launchd agents. Both edited files are backed up with a timestamp.
>
> **It is reversible.** `./install.sh --dry-run` prints every change it would make and writes nothing. `./uninstall.sh` does the same for removal, and `./uninstall.sh --apply` removes it — hooks, skills, the `CLAUDE.md` block, the settings entries, the launchd agents and the MCP registration. Ownership is decided by comparing against this repository, so hooks and skills you installed yourself are left alone. **Your knowledge base is never deleted**: `~/.claude/global-lessons/` is your work, not the program's files.

## When it fits

**It fits if:**

- You work with Claude Code across many sessions on the same codebases.
- You keep correcting the same class of mistake and want that to stop.
- You want a rule delivered at the moment of the action, not at the top of the session.
- You are comfortable with an installer that edits your global Claude Code configuration.

**It does not fit if:**

- **You want a drop-in plugin.** This is not one, and it is not in the official plugin directory.
- **You use another harness.** The hooks are Claude Code lifecycle events and do not port.
- **You need team memory.** The base is a local directory of Markdown files, one per machine.
- **You need proof of effect before adopting.** See the three caveats above. That proof does not exist yet.

## How it works

Seven cognitive layers. The status column says what actually runs, not what is designed.

| # | Layer | Question it answers | Status |
|---|---|---|---|
| 1 | Persistence | What did we do, when, where? | Implemented — `SESSION.md`, session registry, narrative brief |
| 2 | Knowledge | Which case, pattern or principle applies here? | Implemented — anchors, confidence, FSRS ranking, blocker tier |
| 3 | Communication | What does the interlocutor actually need? | Partial — intent-gap classification runs; live extraction of decision patterns does not |
| 4 | Thought trajectory | Where is this conversation heading? | Partial — predictions are written by rule into `SESSION.md`, and code scores their accuracy by type (the L4↔L5 bridge); no engine generates them |
| 5 | Meta-cognition | Are we learning correctly? | Implemented — health metrics, trends, weekly audit |
| 6 | Prediction | Is this hypothesis worth voicing now? | Implemented — 4D intrusiveness gate, budget, silence debt |
| 7 | Co-cognition | Did the agent contribute a hypothesis, or only execute? | Emergent — 62 items recorded with `origin: co-cognition`; the disagreement loop has code (72% of 345 events resolved), the layer itself has none |

Full architecture, including what is missing in each layer: [docs/architecture.md](docs/architecture.md).

The layers are connected by bridges: a skill like "predicted — now score the accuracy" lives not in a layer but on the intersection of two (in that example, trajectory and meta-cognition). Every bridge carries a status — implemented, formalised, or only designed; the index is [bridges/_index.md](bridges/_index.md).

### What the layers are counted off

Not a feature list — an attempt to cover what a person does while learning on the job.
Only capabilities that stand on a mechanism are listed, with what it produced on live data
(snapshot 2026-08-25).

| Human capability | Mechanism | Live measurement |
|---|---|---|
| Recall the rule before starting | `knowledge-activator`, 9 anchors, PreToolUse | 13,506 injections; leader `principle-verify-before-acting`, 1,114 |
| Recognise a familiar pit in advance | `blocker-tier-check` + `detection-signals-lib` | 395 pre-action markers across 241 sessions |
| Pull the hand back from a destructive command | `trust-guard`, PreToolUse[Bash] | 38 firings |
| Take a failure apart and write it down | `error-tracker` → `five-whys-gate` → `/learn` | 192 of 266 recorded cases came from a failure |
| Turn separate incidents into a rule | promotion rules, `source_cases` field | 266 cases → 37 patterns, 10 principles; lineage on 46 of 47 |
| Pick the work up after a break | `narrative-compose`, gap ≥ 8 h | 22 briefs, each line citing a commit |
| Re-assess your own state on a schedule | `knowledge-audit-digest`, weekly | 18 consecutive digests, no gaps |

**What it leaves out.** A single case is the narrowest delivery path: generalisations get
three injection slots, a case gets one — the orphan-case slot. The fallback door — semantic
search — opens only when keyword scoring returns almost nothing, and it almost never does:
the pattern base grew from 8 to 37, scoring always finds something. The price of that door
is measured — 1,348 case injections through June 2026, then **zero for the next two months** (the
window before the slot). The second step of
generalisation is slow: 10 principles across 37 patterns, with ten weekly digests between the ninth and the tenth. Learning
from success is the weaker half — 37 success cases against 192 failures. And almost nothing has ever
been retired: `contradicted_count` is non-zero on 1 item out of 417, so the decay machinery has had
almost nothing to act on.

### The knowledge lifecycle

```
correction / failure / clean success
        │
        ▼
  /learn  ──▶  case-YYYY-MM-DD-slug.md         confidence 1, 9 anchors
        │
        │  2+ similar cases (or one with high impact)
        ▼
      pattern-*.md                             confidence 2+
        │
        │  holds across domains
        ▼
      principle-*.md                            confidence 3+
        │
        ├── confirmed ──────▶ confidence +1
        ├── contradicted ───▶ rule is wrong:     weaken, then deprecate
        │                     scope too broad:   narrow the scope
        │                     different context: branch — both rules kept, neither overwritten
        ├── unused ─────────▶ FSRS penalty: sinks in recall ranking
        │                     (fresh → due → overdue → critical)
        └── confirmed 5+ times, measurable signals, outcome:error
                            ──▶ eligible for `blocker: true`
                                promoted by an explicit decision, never by threshold
```

Cases are never deleted on promotion; they remain the evidence a pattern points back to.

### What runs on its own, and what you have to ask for

**On its own.** Session start: registry, six startup signals, and after a break longer than eight hours a narrative brief — "where I am and how I got here", each line citing a commit. Every prompt: current time, interlocutor-state classification, deferred alerts. First mutating tool call: the base is scored across the anchors, three generalisations plus one orphan case enter the agent's context silently, and the whole top six is written to the injection log. Before shell calls: destructive-command guard, repeat-failure detector, five-whys gate, changelog and module-doc reminders. On stop: session finalization, a re-run of the verification commands of debt items closed this session — a red one is named while the session is still alive — uncaptured-lesson prompts, and a timestamp canary that detects when instructions have drifted out of context.

Of the 63 hooks, 56 are wired to Claude Code events, three run on a schedule, and four are called by other scripts or by hand.

**On request.** New knowledge is created only by an explicit command — `/learn` (30 seconds, mid-flow), `/retro` (a why-chain to root cause), `/compile` (batch-consolidate drafts), `/knowledge-audit` (health of the base). The automation proposes, reminds, collects drafts into `_drafts/` and moves the bookkeeping fields — confirmation counters and the fragility flag; the records themselves are yours to create.

## Root-cause analysis

A repeated mistake is fixed where it arose, not where it was noticed — and the system carries a single analysis doctrine for every case (`hooks/root-cause-lib.sh`). The order is strict: first collect where else the same symptom is visible, each site with an address; then descend with why-chains from several maximally different sites, along two lines — along execution ("why did it break here") and along the data ("where did the wrong input come from"). Converging chains prove the manifestations are related, not that the root is found: there can be several roots, each with its own fix. A found root gets its siblings hunted — places built the same way where the symptom is not yet visible and the tests are green — and the map of what rests on the root becomes the regression checklist after the fix.

Triggers for an analysis come from the world, not only from failed commands: a red CI run for the system's own commit, a revert, a closed debt item whose invariant stopped holding. Every trigger gets a recorded outcome — including "the guard fired for nothing": the false-positive share is measured the same way as the catch share.

## The system measures itself

Every measurement has a deadline and a command — the registry is `scripts/measurements.tsv`; an overdue measurement does not wait to be remembered: `scripts/measurement-due.sh` names it and runs it. A technical-debt item carries its own verification command, and its reading is recomputed by a mechanism at turn boundaries — readings are computed, not remembered. Closed items are re-verified at session stop and weekly, and the archiver refuses to move an item whose own check runs red: a "done" that stopped being true is named and returns to work. Numbers in documents are checked against the world through a claims registry, the age of a mechanism's description against the date of the mechanism's last change, and a dependency index answers "what rests on the thing I am changing": change behaviour, and a guard demands a decision about the state documents in the same commit.

## The second contour: knowledge about the world

Besides knowledge from its own failures and successes (case → pattern → principle), the knowledge layer carries an encyclopedic contour: entities, facts and relations — facts with a source and a validity window. It is filled by explicit commands: `/ingest` extracts from a document, `/enrich` fetches from the web through a source-tier ranking — a conflicting value is recorded as a contradiction, never as an overwrite — and `/wiki` assembles an entity page. The contours look at each other: the activator searches for analogies between patterns of one domain and entities of another and offers them as hypotheses to evaluate, not as rules. The green nodes in the graph at the top of this page come from here.

Domains, in turn, are not flat tags but a graph with typed relations; walking the graph weighs which knowledge fits the situation.

## How it differs from agent memory tools

| | ClaudSoul | Typical memory layer |
|---|---|---|
| Contradiction | weakens, narrows or branches by the reason for the mismatch — never a silent overwrite | stale entry replaced with the latest value |
| Recall | scored by nine situational anchors | semantic similarity over stored text |
| Structure | `case → pattern → principle`, with promotion thresholds | flat notes, or one level of distillation |
| Forgetting | FSRS penalty to recall ranking; contradictions degrade the rule | rarely modelled |
| Delivery | confirmed rules arrive before the tool call, not at session start | passive context |
| Self-observation | hooks on the agent's own output and its own predictions | hooks on tools, if any |

Honest note on that first row: the branch path — the one where both values genuinely survive — has **zero recorded executions**. See Limitations.

How the disagreement works when it happens: a high-confidence item that contradicts the current action arrives marked ⚡ and must receive a recorded outcome — confirmed, outdated, not applicable, applicable-but-not-followed. The counters are moved by a mechanical script, not by editing the file by hand; without recorded outcomes confidence "freezes", and this is the only way it gets calibrated.

Neighbours worth knowing: [mem0](https://github.com/mem0ai/mem0) and [Letta](https://github.com/letta-ai/letta) for memory as infrastructure, [basic-memory](https://github.com/basicmachines-co/basic-memory) for Markdown-native recall, and Claude Code's own Auto Memory. Confidence-scored learning is not unique — the neighbours have it too. Keeping the disagreement instead of resolving it is still unusual — but here it is a design, not yet a demonstrated behaviour.

## MCP server

Semantic search and visualisation over the base via [Model Context Protocol](https://modelcontextprotocol.io/) — sqlite-vec plus fastembed, no external service.

`search_knowledge` · `reindex_knowledge` · `knowledge_stats` · `get_knowledge` · `knowledge_graph` · `open_graph` · `open_dashboard` · `brain_export` · `brain_import`

The graph at the top of this page is `open_graph`. There is also a metrics dashboard, and export/import to move your base between your own machines.

> `brain_import` runs someone else's code. A brain archive carries executable hooks and skills; importing overwrites yours. It defaults to a dry run and applies nothing until you pass `dry_run: false`. Use it for your own archives only.

## Limitations

Measured by the system on itself, and published in the same file as its successes.

- **The knowledge-to-action gap is real and quantified.** Of 415 items (measured 2026-08-31), 100% are stored, 54 (13.0%) have ever reached the agent's context, and 4 (1.1%) stand in the way of an action. Of those four, one expresses a rule rather than a list. Storing is easy; acting is not.
- **`contradicted_count` has moved off zero exactly once** (1 item of 417, on 28 Aug 2026). A counter that only goes up measures nothing; the refutation loop exists in code and has a single record — the contradiction column in the table above is still closer to design than to evidence.
- **The ablation measurement has produced no data.** Protocol and harness are written; not one completed pair exists.
- **Layers 3 and 4 are partial; layer 7 is emergent rather than engineered.**
- **CI runs on Linux only.** `.github/workflows/tests.yml` uses `ubuntu-latest` for both jobs. macOS is verified locally by the author, not by the badge above. Three scheduled agents and `open_graph` are macOS-only.
- **One harness.** The hooks are Claude Code lifecycle events. Nothing here ports as-is.

What is planned against these gaps: [PLAN.md](PLAN.md).

## Reference

Full generated tables — every hook with its trigger, every command with what it does — are in [docs/reference.md](docs/reference.md). Both are generated from source by `scripts/regen-readme-skills.sh` and are never edited by hand.

The short version of what you will actually type:

| Command | When |
|---|---|
| `/learn` | You just learned something. 30 seconds, mid-flow. |
| `/retro` | Something broke. A why-chain to root cause, 2–5 minutes. |
| `/knowledge-audit` | Weekly. Health of the base: decay, reliability, gaps. |
| `/compile` | Accumulated raw notes into knowledge candidates, deduped against the base. |
| `/save` | Long session. Writes progress to `SESSION.md`. |
| `/init-project` | A new project, or auditing whether an existing one drifted. |

## Contributing

The public repository is a release snapshot: a single squash commit, republished on every release. Issues and pull requests filed there survive it — the publishing script force-pushes over the existing history and falls back to recreating the repository if it finds something in that history that must not be public, or if the history could not be verified. Discussions and issues are the channel; the private working history is not published, so a PR is reviewed and applied by hand rather than merged.

Two directions are worth more than features:

- **Evidence.** The weakest part of this project is proof of effect. If you run it and can measure anything — errors repeated, turns to a fix, corrections per session — that beats a new hook.
- **Portability.** Hooks target bash 3.2 and handle both BSD and GNU coreutils. Reports of anything that breaks outside macOS are welcome.

Before a pull request: `bash hooks/tests/run_all.sh` and `cd mcp-server && uv run python -m pytest -q`. Conventions are in [docs/development.md](docs/development.md), architecture decisions in [docs/decisions.md](docs/decisions.md).

Every number in this file that has a source is listed in `scripts/doc-claims.tsv` together with the command that computes it; `bash scripts/docs-refresh-claims.sh --check` runs before every release and every publication, and the At-a-glance counts are additionally held by a CI guard (`scripts/count-stats.sh`).

## License

[MIT](LICENSE).

## Author

Kanstantsin Berseneu — [@Nugnii](https://github.com/Nugnii).
