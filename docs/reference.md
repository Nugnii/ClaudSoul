# Reference — hooks and commands

Generated from source by `scripts/regen-readme-skills.sh`. Do not edit the tables by hand: hook descriptions come from the `# en:` line in each hook's header, command descriptions from `description_en` in each `SKILL.md` frontmatter. Edit those, then regenerate.

Back to [README](../README.md).

## Hooks

Hooks are shell scripts wired into Claude Code lifecycle events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `Stop`, `SessionEnd`). They detect, inject and log without being invoked.

9 of them can actually interrupt a call, in two different ways. 4 raise `permissionDecision: ask` and hand the choice to you — `bash-cost-detector`, `user-correction-guard`, `bulk-copy-guard`, `internal-doc-leak-guard`. 5 return `deny` and refuse the agent without disturbing you: `playwright-cli-guard`, `rules-write-bypass`, `five-whys-gate`, `skill-name-ascii-guard` and `blocker-tier-check` — the last one only for knowledge whose signal carries `enforcement: deny`. Everything else writes silently into the agent's context and leaves the decision to it — noise is its own failure mode.

<!-- HOOKS-TABLE:START -->

| Hook | When it fires and what it does |
|-----|-------------------------------|
| `ablation-phase-guard` | while a measurement phase is active, injects a per-session signal and guards the installed policy surface from deploys; nobody has to remember. |
| `accepted-alternative-gap` | Stop hook — detects "your variant is better" acceptance in the assistant's last reply and demands the same gap analysis as external-correction-gap. |
| `auto-scanner` | launchd (every 4h): read-only scan of projects, findings written to scan-results.md for the next session. |
| `backfill-compliance` | restores the DEPENDENT VARIABLE from archived transcripts (offline, read-only). |
| `backfill-intrusiveness` | one-off backfill of gentle/proactive events from ~/.claude/projects/*/*.jsonl archived transcripts. |
| `backlog-reading-refresh` | PostToolUse on backlog writes and reads — item readings are recomputed on write and checked against the world on read. |
| `backlog-touch-check` | PreToolUse on file edits — the file is named in an open backlog item. |
| `backlog-vanish-check` | PreToolUse[Bash] on `git commit`: a debt item must not vanish without a trace. |
| `bash-cost-detector` | PreToolUse[Bash]: detects destructive commands (rm -rf, git push --force, DROP) and raises the silence_cost signal for the L6 gate. |
| `blocker-tier-check` | PreToolUse: silent 🛑 marker for knowledge with `blocker: true` when the action matches the pattern's detection_signals. |
| `bridge-health-digest` | monthly mechanical digest for 16 inter-layer bridges. |
| `budget-gate` | PreToolUse[Edit\|Write\|MultiEdit\|NotebookEdit]: an unsolicited edit made on an exhausted proactive budget is told to become a question instead (ADR-010 phase 2). |
| `bulk-copy-guard` | PreToolUse: ask user before bulk copy/move/rsync operations. |
| `changelog-reminder` | PreToolUse[Bash] on `git commit`: quietly reminds to add a CHANGELOG entry when code changed. |
| `ci-check-reminder` | PostToolUse[Bash]: after `git push`, reminds to check the run for THIS commit. |
| `claude-md-size-check` | PreToolUse[Bash] on `git commit`: quietly warns when CLAUDE.md grows past the context-cost threshold. |
| `claudsoul-context-pointer` | UserPromptSubmit: injects the project CLAUDE.md status section when ClaudSoul is mentioned from outside its directory. |
| `code-review-reminder` | PreToolUse[Bash] on `git commit`: a large code diff heading into a commit without an adversarial run — instructs to tell the interlocutor about `/adversary`. |
| `declared-problem-recorded` | Stop hook — a problem named in the answer must reach a durable carrier. |
| `decompose-detector` | UserPromptSubmit: pre-execution router — suggests /decompose for multi-step requests, /grilling for open-decision/vague ones. |
| `doc-impact-check` | PreToolUse[Bash] on `git commit`: names describing documents; demands a decision on state docs when behaviour changed. |
| `docs-family-check` | PreToolUse blocker-tier: on a version bump, checks the 5-doc family is covered by the commit. |
| `enrich-suggester` | UserPromptSubmit: hint when a recently-modified entity is sparse (fewer than 3 attributes). |
| `error-tracker` | PreToolUse[Bash]: warns before a retry when 2+ of the last 6 tool calls failed. |
| `external-correction-gap` | UserPromptSubmit: external review detection — demands a gap analysis (catchable by own knowledge?) before accepting third-party corrections. |
| `five-whys-gate` | PreToolUse: a repeat signal fired but no why-chain was stated — demands the 5 Whys. |
| `fix-level-check` | detects post-incident text-rule fixes in the agent's own reply and reminds to lift them to a mechanism (activator/blocker) |
| `inquiry-gap` | a user QUESTION gets an answer first — not a build; if the question exposes a missing mechanism, gap analysis comes before any construction. |
| `internal-doc-leak-guard` | PreToolUse: prevent writing internally-marked content to externally-shared paths (lawyer / counsel / advisor folders). |
| `intrusiveness-tracker` | UserPromptSubmit: maintains L6 intrusiveness gate state, classifies the interlocutor's state (focus/idle/stuck/exploration). |
| `itr-event-detector` | UserPromptSubmit: finds a gentle suggestion in the assistant's prior turn, classifies whether the user accepted or ignored it, and logs the outcome — without this the L6 budgets never accumulate. |
| `knowledge-activator` | PreToolUse[Bash\|Edit\|Write]: injects SESSION.md and relevant knowledge from global-lessons on the first tool call. |
| `knowledge-audit-digest` | weekly mechanical audit of global-lessons. |
| `knowledge-capture-reminder` | PostToolUse[Bash]: reminds to collect material after N commits without a draft. |
| `knowledge-counter-bump` | mechanical increment of a knowledge item's confirmed/contradicted counters. |
| `knowledge-frontmatter-check` | PostToolUse[Write\|Edit\|MultiEdit]: reports broken YAML frontmatter right after a knowledge file is written. |
| `knowledge-link-symmetry` | PostToolUse on knowledge writes — a case→pattern edge gets its back-reference written. |
| `metrics-collector` | called by auto-scanner / /knowledge-audit: computes knowledge-base health metrics, writes state/metrics.md. |
| `module-doc-check` | PreToolUse[Bash] on `git commit`: a NEW module staged without its module doc — quiet reminder. |
| `output-language-check` | post-output scanner for mixed-alphabet tokens. |
| `partial-read-guard` | PostToolUse[Read]: states how much of a file was actually read, in lines. |
| `pending-alerts-surface` | UserPromptSubmit: поднимает отложенное видимым каналом. |
| `playwright-cli-guard` | PreToolUse: blocks throwaway Playwright scripts in favour of the /playwright-cli skill. |
| `pre-compact-finalizer` | PreCompact: snapshots the chunk boundary before context compaction. |
| `pre-compact-handoff` | PreCompact: preserves the thread of work before context compaction. |
| `quality-gate-check` | PreToolUse: skill-contract guard on `git commit`. |
| `reformulation-tracker` | UserPromptSubmit: cascading verification of predictions (FORWARD/PROPOSAL/BACKWARD), logs the outcome and prompts to record the gap. |
| `relative-date-check` | Stop/PreCompact: flags relative time expressions ("вчера", "на днях", "час назад") written without an absolute date or clock-time anchor next to them; surfaces the correction plus the current date and time on the next turn. |
| `response-tracker` | PostToolUse: records the agent's REACTION after the system warned it about something. |
| `revert-signal` | PostToolUse[Bash]: a revert or a repeated hotfix of the same file becomes an analysis trigger. |
| `rework-detector` | PostToolUse: third rework cycle on the same file while every run looks green. |
| `rules-write-bypass` | PreToolUse[Bash] — the installed rules file may only be written through the merge library. |
| `session-collector` | Stop: reminds to record uncaptured lessons via /learn, finalises the session in the registry, cleans ephemeral state. |
| `session-end` | SessionEnd: finalises the session in the registry on exit/clear/logout and removes it from active/. |
| `session-start` | SessionStart: registers the session in the registry on startup/resume/clear/compact for cross-session visibility. |
| `skill-name-ascii-guard` | PreToolUse[Bash] — a skill directory named outside ASCII is denied, not merely flagged. |
| `skill-review-check` | PreToolUse: skill-review gate on `git commit`. |
| `timestamp-canary-check` | Stop hook — verifies the last reply starts with the injected timestamp; alerts user+agent when the canary died (context drift). |
| `timestamp-inject` | injects the user's current local time each prompt; the reply must start with it — a cheap context-drift canary. |
| `trust-guard` | PreToolUse: a destructive command issued without explicit user authorization in the recent turns is met with a question first (affect prosthetic #1 — the brake the architecture does not have). |
| `user-correction-guard` | PreToolUse: pause when user just corrected me, before I do another tool action. |

<!-- HOOKS-TABLE:END -->

## Commands

Skills are user-invocable workflows installed into `~/.claude/commands/`.

<!-- SKILLS-TABLE:START -->

| Command | What it does |
|---------|-----------|
| `/adversary` | Adversarial code review: a subagent in a clean context proves the code breaks, reproduces every attack as a failing test, and fixes nothing. Rounds, each with a fresh critic. Call before commit, deploy, handoff — especially when you are sure it is ready. |
| `/bridge-health` | Monitors all 16 bridges (15 inter-layer plus one within-layer): status, activity metrics, health of links between cognitive layers. |
| `/compile` | Batch consolidation of accumulated raw material into knowledge candidates — reads _drafts/SESSION/_capture, extracts 3-7 items, dedupes against the base (NEW/UPDATE/CONTRADICTS), writes drafts. |
| `/decompose` | Decomposes a task before execution: scope → steps → dependencies → plan. For tasks longer than 3 steps. |
| `/enrich` | Web enrichment of an entity from tier sources. Conflicts go into contradiction, nothing is overwritten. /enrich <name\|slug> or \"update X\". |
| `/entity` | Shows what the ClaudSoul knowledge base knows about an entity (person, company, concept, event) — attributes, links, sources. |
| `/grilling` | Relentless interview over a decision tree: surface silent assumptions in a plan/idea before acting. Rounds over the frontier, each question with a recommended answer, facts fetched by the agent itself. /grilling <plan or idea>. |
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
