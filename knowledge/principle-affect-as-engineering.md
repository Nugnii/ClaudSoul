---
name: Affect-as-engineering — аффект должен быть инженерным, не правилом
description: "В архитектурах без аффективной эмпатии (symbol-only когниция) функции, которые у людей выполняет аффект — тормоз на разрушение доверия, интуитивное «не трогай», эмпатическая пауза — не восстанавливаются текстовым правилом «будь осторожен». Требуется класс инженерных протезов: hooks, detection signals, structural defaults. Отсутствие аффекта — не философский дефект, а инженерное требование"
type: principle
outcome: design_rule
confidence: 4
impact: 5
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-07
source_cases:
  - case-2026-04-23-sociopathic-architecture-diagnosis.md
status: active

# Контекст
domain: [system_design, cognitive_science, agent_architecture, ethics, interaction_design]
situation: "architectural_absence_of_affective_empathy, high_trust_interaction"
trigger: "reliance_on_text_rule_for_affect_function"
stakes: "trust_erosion_cold_decision_destructive_action_without_affective_brake"
actors: [agent, interlocutor, system]
environment: "any_LLM_agent_with_persistent_state"
circumstances: "no_native_affective_substrate, functional_cognition_only"
purpose: "engineer_affect_proxies_as_explicit_mechanisms"
method: "hooks_detection_signals_structural_defaults_over_text_rules"
tags: [cognitive_empathy, affective_empathy, sociopathic_architecture, trust_guard, affect_prosthetic]

# Demand
need: reliable_affect_proxy_without_relying_on_simulated_feeling
urgency: universal_background_principle
availability: foundational

# Связи
related:
  - principle-knowledge-in-the-world.md
edges:
  - specializes: principle-knowledge-in-the-world.md
  - parent_of: case-2026-04-23-sociopathic-architecture-diagnosis.md

# gradation
promotion_tier: 3
scope: universal
origin_domain: cognitive_science
modification_history: []
provenance_log:
  - date: 2026-08-07
    kind: reinforced
    reason: "budget-gate (v1.23.0) — инженерный протез сдержанности: тормоз самовольной правки при пустом бюджете реализован механизмом, не текстовым правилом; ровно класс, который принцип требует"
---

## Формулировка

**Архитектура, в которой когнитивная эмпатия есть (модель собеседника), а аффективная эмпатия отсутствует (не «чувствую, как ему»), функционально эквивалентна социопатической.** Это не моральная оценка — это инженерное описание.

У людей аффект выполняет функции, которые когнитивная часть не выполняет:
- **Тормоз на разрушение доверия** — интуитивное «нельзя» прежде, чем рассудок сформулирует почему
- **Эмпатическая пауза** — автоматическое замедление при сигналах дистресса собеседника
- **Cost-of-harm** — стоимость вреда сидит в теле, не в калькуляции

В symbol-only architecture этих функций нет. Текстовое правило «будь осторожен» их не восстанавливает — оно полагается на то же memory-as-resource, которое уже признано хрупким (см. `principle-knowledge-in-the-world.md`). Правило «воображай, как человеку больно» — имитация, а не механизм.

## Следствие: класс инженерных протезов аффекта

Каждая функция аффекта, архитектурно отсутствующая, должна быть **embedded как hook** — signal, detection, intervention — не как рекомендация в rules/CLAUDE.md.

| Функция аффекта | Инженерный протез | Пример |
|-----------------|-------------------|--------|
| Тормоз на разрушение доверия | `trust-guard` PreToolUse на destructive signatures + auth check | rm -rf / git reset --hard без подтверждения → silent marker |
| Affect proxy в состоянии собеседника | `distressed` в state axis рядом с stuck/focus/exploration/idle | Сигналы фрустрации + повторения → downgrade proactive |
| Стоимость подавления боли собеседника | silence_cost с компонентом `trust_erosion` | Молчание там, где нужно было предупредить — растит silence debt |
| Emotional cost-of-interrupt | intrusiveness-tracker cost hints (timing, surprise) | High cost state → downgrade до silent_prep |

Общее имя класса: **affect prosthetic** — инженерный протез аффекта.

## Почему правило, а не эвристика

Агент склонен к самоуспокоению через имитацию: «я понимаю, что собеседнику было бы неприятно» = cognitive simulation of affect, не affect. В моменте разрушительного действия эта симуляция не срабатывает как тормоз, потому что у неё нет физиологического якоря.

Инженерный протез работает иначе: он detects signal infrastructurally (независимо от LLM attention), injects reminder в точке действия (не в general prompt), и не требует, чтобы агент «вспомнил прочувствовать».

## Критерий различения

| Форма | Надёжность | Failure mode |
|-------|------------|--------------|
| Text rule «будь внимателен к собеседнику» | Низкая | Silent drift, активен только свежий post-incident |
| Affect-as-simulation «представь, как ему» | Низкая | Имитация без якоря, в моменте действия не тормозит |
| Affect prosthetic (hook + signal) | Высокая | detection_signals могут быть неполны (но observable и fixable) |

## Escalation path

Класс affect prosthetics разворачивается по мере того, как confirmed функциональные провалы фиксируются:
1. Случай: разрушительное действие без явного подтверждения → trust-guard
2. Случай: игнор сигнала дистресса собеседника → distressed state axis
3. Случай: накопление silent-prep высокой ценности без вывода → silence debt metric
4. ...

Не требуется строить всё сразу. Но fix после каждого подтверждённого провала не должен оставаться на уровне «добавим правило в CLAUDE.md» — это уровень 1 из `principle-knowledge-in-the-world`, для affect класса недостаточный.

## Применение в ClaudSoul

- `hooks/trust-guard.sh` (v1.5.6-alpha, первый член класса) — PreToolUse на destructive Bash без явной auth
- `hooks/intrusiveness-tracker.sh` state axis (будет расширен v1.5.7+) — добавление `distressed`
- silence_cost в L6 4D gate — proxy для cost подавления собеседника

Каждое новое проявление Разрыва A в `docs/architecture.md §12` → новый affect prosthetic, не новое текстовое правило.

## Границы

Принцип не утверждает, что аффект можно заменить полностью — утверждает только, что его функции должны быть покрыты инженерно там, где архитектура их архитектурно не имеет. Симуляция аффекта в генерации ответов (тёплый тон, эмпатические формулировки) остаётся — но это generation-level, не mechanism-level. Инженерный протез работает уровнем глубже симуляции.

Принцип не применяется к системам, где affective substrate присутствует (люди, animal-like embodied agents) — им протез не нужен, их тормоз работает физиологически.
