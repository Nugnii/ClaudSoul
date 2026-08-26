---
name: save
description: "Сохранить прогресс сессии в SESSION.md. Использовать при длинных сессиях или перед завершением работы."
description_en: "Saves session progress to SESSION.md. Use during long sessions or before wrapping up."
user-invocable: true
argument-hint: "[необязательно: краткое описание что сохранить]"
---

# Save Session Progress

**Type:** worker

Save the current state of work so it can be resumed in a new session without losing context.

## Process

1. Find or create `SESSION.md` in the current project root
2. Append a new entry with today's date and time
3. Include:
   - **What was done** this session (be specific — file names, features, fixes)
   - **Current state** — what works, what's broken, what's half-done
   - **Next steps** — what needs to happen next, in priority order
   - **Key decisions** — any non-obvious choices made and WHY
   - **Blockers** — anything that's stuck or needs the user's input
4. If there are uncommitted code changes, list them
5. Keep entries concise but complete — someone reading this cold should be able to continue the work

## Knowledge check (v0.2)

Before saving, scan the session for extractable knowledge:
- Were there **errors that took 2+ attempts**? → suggest `/retro`
- Were there **successful strategies** worth recording? → note in "Key insights"
- Were there **communication surprises** (intent gaps, wrong assumptions)? → note in "Key insights"
- Were there **key decisions** that future sessions need to know about? → capture the WHY

Add a `### Key insights` section if any non-obvious learnings emerged.

## Rules

- NEVER overwrite previous entries — always APPEND
- Use specific file paths and line references, not vague descriptions
- If the user gave a note, incorporate it
- If CLAUDE.md exists, update its "Current status" section too

## Definition of Done

- [ ] SESSION.md appended with current session state
- [ ] Uncommitted changes listed (if any)
- [ ] Knowledge check completed (errors/successes/insights noted)
- [ ] CLAUDE.md status section updated (if exists)

**Version:** 1.0.1
**Last Updated:** 2026-07-29