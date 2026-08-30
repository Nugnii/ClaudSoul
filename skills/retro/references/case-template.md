# Case Template for /retro

> Шаблон под ГЛУБОКУЮ ретроспективу: полный таймлайн (`## Context`, `## Chain of
> reasoning`, `### Attempt 1..N`). Лёгкий вариант для быстрого захвата —
> `skills/learn/references/case-template.md`. Развилка намеренная (retro vs learn),
> не дубль. Канон YAML-якорей (9 anchors, demand, edges) — `knowledge/META.md`;
> этот файл — рендеринг под /retro, при изменении схемы в META.md обновить оба.

Save to `~/.claude/global-lessons/` as `case-YYYY-MM-DD-brief-name.md`.

```markdown
---
name: [short descriptive name]
description: [one-line summary]
type: case
outcome: error|success|communication
confidence: 1
impact: 1-5
intensity: 0                # Surprise factor (0-5): 0=ожидаемо, 5=полная неожиданность
confirmed_count: 1
contradicted_count: 0
last_confirmed: [today]
source_cases: []
source_session: ""         # $CLAUDE_CODE_SESSION_ID; переменной нет → пусто, НЕ выдумывать
status: active

# Контекстные якоря — извлечь автоматически из контекста
domain: []
situation: ""
trigger: ""
stakes: ""
actors: []
environment: ""
circumstances: ""
purpose: ""
method: ""
tags: []

# Demand-компоненты (кому и зачем нужно это знание)
need: ""
urgency: ""
availability: ""

# Реляционные веса (если применимо)
critical_anchors: []
weight_modifiers: ""

# Связи
related: []
edges: []

# Bridge metadata (optional — fill if knowledge relates to inter-layer bridge)
origin: ""                 # solo | co-cognition | trajectory_pivot
trigger_for_co_cognition: "" # What triggered co-thinking: analogy, contradiction, question, predictive_miss
bridge_layer: ""           # Which bridge activated: L2-L3, L4-L7, etc.
preceded_artifact: ""      # yes | no | n/a — существовало ли знание РАНЬШЕ артефакта,
                            # который на него ссылается. Не путать с `origin`: тот про то,
                            # КАК инсайт родился (в одиночку / совместно / из поворота),
                            # а это про направление причинности. Замер 2026-07-29: 0 из 8
                            # хуков построены из знания, существовавшего до них.
---

## Context
[What was being built/fixed, what technology/stack]

## What went wrong
[Brief description]

## Chain of reasoning
### Attempt 1
- **Hypothesis:** ...
- **Action:** ...
- **Result:** ...
- **Correct reasoning?** Yes/No — ...

### Attempt N (final, working)
- **Hypothesis:** ...
- **Action:** ...
- **Result:** ...
- **Correct reasoning?** Yes/No — ...

## Root cause
[The actual underlying issue]

## Missed signal
[What I should have noticed earlier]

## Extracted rule
[One clear, actionable rule for next time]
```
