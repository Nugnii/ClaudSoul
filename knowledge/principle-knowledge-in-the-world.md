---
name: Knowledge in the world, not in the head — правило в механизме, не в памяти
description: Надёжное правило embedded в механизм системы, который активируется на семантическую акцию. Правило-в-тексте полагается на то, что агент/человек прочитает и применит его — это память-как-ресурс, которая системно ненадёжна. Fix после инцидента = embedded mechanism + formulation, а не только formulation
type: principle
outcome: design_rule
confidence: 5
impact: 5
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-25
source_cases:
  - case-2026-08-21-third-reminder-means-missing-mechanism.md
  - case-2026-08-21-rule-drift-visible-only-from-outside.md
  - case-2026-08-18-repeated-credential-stumble-env.md
  - case-2026-08-08-session-throttle-downgrades-hook-to-text-rule.md
  - case-2026-08-08-fabricated-time-canary.md
  - case-2026-06-21-repeated-rejected-pause-suggestion.md
  - case-2026-04-23-memory-without-action-gate.md
  - case-2026-04-23-model-vs-system-source-blindness.md
  - case-2026-04-23-text-rule-vs-mechanism.md
  - case-2026-04-24-install-drift-silent-safeguards.md
  - case-2026-04-24-proof-of-active-needs-noise-calibration.md
  - case-2026-07-07-doc-counters-rot-generate-from-source.md
  - case-2026-04-24-alphabet-mixing-self-detection-failure.md
  - case-2026-05-05-claudsoul-blindness-from-home.md
  - case-2026-06-21-rules-pointer-must-be-mechanism.md
status: active

# Контекст
domain: [system_design, cognitive_science, agent_architecture, interaction_design, metacognition]
situation: "post_incident_rule_design, defense_mechanism_engineering"
trigger: "proposing_text_rule_as_fix_for_memory_failure"
stakes: "recursive_blindness_each_fix_reintroduces_same_failure_mode"
actors: [agent, interlocutor, knowledge_system, rule_system]
environment: "any_rule_based_system"
circumstances: "long_lived_rule_with_activation_gap"
purpose: "make_rules_reliably_active"
method: "embed_in_mechanism_not_text"
tags: [don_norman, affordance, external_cognition, knowledge_action_gap, mechanism_over_memory]

# Demand
need: reliable_rule_activation_without_depending_on_recall
urgency: universal_background_principle
availability: foundational

# Связи
related:
  - pattern-inside-out-blindness.md
edges:
  - generalizes: pattern-inside-out-blindness.md
  - parent_of: case-2026-04-23-memory-without-action-gate.md
  - parent_of: case-2026-04-23-model-vs-system-source-blindness.md
  - parent_of: case-2026-04-23-text-rule-vs-mechanism.md

# gradation
promotion_tier: 3
scope: universal
origin_domain: cognitive_science
modification_history: []
provenance_log:
  - date: 2026-07-28
    kind: reinforced
    reason: "publish-public.sh: повторяемую чувствительную зачистку встроили в инструмент+гейт (archive→exclude→redact→forbidden на собранном дереве), а не вычищали руками каждый релиз"
    trigger_case: case-2026-07-27-secret-scan-refs-not-branch.md
  - date: 2026-08-21
    kind: reinforced
    reason: "case-2026-08-18-repeated-credential-stumble-env: пользователь сам потребовал перенести кред из памяти в .env после повторного спотыкания"
  - date: 2026-08-25
    kind: reinforced
    reason: "Замер с владельцем и сроком (measurement-due.sh) заведён против правила 'держится на чьей-то памяти' — и сам не имеет автозапуска, то есть держится на чьей-то памяти. Просрочка 9 дней обнаружена вопросом собеседника, а не механизмом."
---

## Формулировка

**Если правило опирается на то, что future-you (или future-человек) вспомнит его применить в нужный момент — оно хрупко.** Надёжное правило embedded в механизм, который:

1. Детектирует ситуацию автоматически по наблюдаемым сигналам (tool call, file path, diff content, state change)
2. Инжектирует правило в контекст ТОГО МОМЕНТА, когда оно релевантно, а не в general system prompt
3. Активируется на **семантическую акцию** (что делается), а не только на **ключевую фразу** (как названо)

Критерий различения:
- **Правило-в-тексте** (knowledge in the head): formulation записана в docs, rules/CLAUDE.md, памяти. Активация = «человек/агент вспомнил применить». Failure mode: silent drift, правило лежит годами и не срабатывает
- **Правило-в-механизме** (knowledge in the world): formulation + signal/behavior path. Активация = система сама подаёт правило в нужный момент. Failure mode: detection_signals не покрывают все проявления (но это observable и fixable)

## Почему это работает

Классическая концепция Don Norman: *"The user should not need to remember X; the environment should remind them of X."* В LLM-системах это усиливается:
- Context декодируется токен за токеном; релевантность правила в момент генерации не гарантирована, даже если правило присутствует в system prompt
- Defensive narrative после инцидента активен кратковременно — правило, добавленное «на волне» post-mortem, через N сессий теряет контекстную салиентность
- Память-как-ресурс accumulates — N правил в system prompt → снижение attention per rule

Embedded mechanism обходит все три:
- Signal генерируется инфраструктурой, не LLM attention
- Inject происходит на конкретном tool call, не в general session init
- Механизм сохраняет эффективность независимо от количества других правил

## Эвристика «fix после инцидента»

Три уровня исправления, в порядке возрастания embedded-ness:

| Уровень | Форма | Надёжность | Когда применять |
|---------|-------|------------|-----------------|
| 1. Text rule | Правило в docs/rules/CLAUDE.md/memory | Низкая | Черновик формулировки, до реализации механизма |
| 2. Activator injection | Правило в knowledge-base с anchors, попадает в inject при context match | Средняя | Правило ситуативное, context-dependent |
| 3. Blocker-tier detection | Detection signals + PreToolUse/PostToolUse hook с silent inject | Высокая | Проверенный knowledge-action gap, confirmed_count ≥ 5 |

Fix после инцидента, который остаётся на уровне 1 — это **не fix**, это описание проблемы. Минимально embedded fix = уровень 2 (knowledge-activator injects on trigger match). Для повторяющихся паттернов — уровень 3.

## Escalation mechanism

Правило принципа требует escalation: если blocker-tier pattern (уровень 3) продолжает подтверждаться, значит detection_signals неполны или есть новое измерение. Система должна **сама** заявить о необходимости engineering-итерации, а не полагаться на замечание человеком.

Embedded реализация: pattern с `escalation_threshold: N`. При `confirmed_count >= N` — `knowledge-audit-digest.sh` emit's секцию «Engineering escalation needed», hint попадает в `state/audit-hint.txt`, session-start инжектит в startup-signals. Это рекурсивная защита: механизм surface'ит необходимость следующего уровня защиты, не полагаясь на memory-as-resource.

## Anti-patterns

- **"Я добавлю напоминание в CLAUDE.md"** — это уровень 1, не engineering
- **"Я запомню не делать X"** — это самая нижняя точка, no-op
- **"Мы добавим правило в team handbook"** — уровень 1 для людей, такой же failure mode
- **"Покроем тестами"** — может быть уровнем 2-3, если тест запускается на релевантное action

Что работает:
- **Hook detects signal → injects reminder**
- **Lint rule enforces pattern**
- **Type system prevents error class**
- **Default configuration makes right thing easy, wrong thing hard**

## Применение в ClaudSoul

Принцип проявлен в архитектуре:
- `blocker-tier-check.sh` + `detection_signals` — реализация уровня 3
- `knowledge-activator.sh` + anchors — реализация уровня 2
- `rules/CLAUDE.md` — уровень 1, используется только для формулировок, не как единственный носитель

Escalation: `knowledge-audit-digest.sh` §«Engineering escalation needed» (v1.5.5-alpha+1) — механизм, который сам заявляет о необходимости следующего уровня.

## Границы

Принцип не требует всегда делать уровень 3. Уровень соответствует уровню риска: тривиальная рекомендация — ok уровень 1. Критическое правило, многократно нарушенное — требует уровня 3. Промежуточное — уровень 2. Но fix после подтверждённого инцидента никогда не должен оставаться на уровне 1.
