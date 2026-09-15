# Case Template for /learn

> Шаблон под БЫСТРЫЙ захват (30с): терсно — `**Why** / **How to apply** /
> **Limitations**`. Глубокий вариант с полным таймлайном —
> `skills/retro/references/case-template.md`. Развилка намеренная (learn vs retro),
> не дубль. Канон YAML-якорей (9 anchors, demand, edges) — `knowledge/META.md`;
> этот файл — рендеринг под /learn, при изменении схемы в META.md обновить оба.

Save to `~/.claude/global-lessons/` as `case-YYYY-MM-DD-brief-name.md`.

```yaml
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

# Контекстные якоря — извлечь автоматически из:
# - CLAUDE.md текущего проекта → domain
# - Текущее действие → situation, trigger
# - Последствия → stakes
# - Участники → actors
# - Среда выполнения → environment
# - Условия/ограничения → circumstances
# - Зачем → purpose
# - Каким способом → method
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

[Правило — конкретное, actionable]

**Why:** [что произошло]

**How to apply:** [когда и где это правило срабатывает]

**Limitations:** [когда НЕ применять]
```

**impact** шкала:
- 1 — неудобство, потеря пары минут
- 2 — потеря 10-30 минут работы
- 3 — баг в продакшене или серьёзная переделка
- 4 — потеря данных или простой сервиса
- 5 — необратимые последствия (удаление продовых данных, безопасность)

## Session registry update

After writing/updating knowledge, record in session registry:

```bash
# Created new case
source ~/.claude/hooks/session-registry-lib.sh 2>/dev/null && \
  sr_update_knowledge "created" "case-YYYY-MM-DD-brief-name.md" 2>/dev/null || true

# Reinforced existing knowledge
sr_update_knowledge "updated" "pattern-name.md" 2>/dev/null || true

# Contradicted existing knowledge
sr_update_knowledge "contradicted" "pattern-name.md" 2>/dev/null || true
```
