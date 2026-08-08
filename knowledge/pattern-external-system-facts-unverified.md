---
name: Факты внешней системы не проверяются до проектирования интеграции
description: Проектируя интеграцию/зеркало/порт внешней системы (Make, SendPulse, wFirma, Google), агент строит модель по предположению о возможностях и поведении этой системы вместо проверки её фактической структуры (поля API, возможности UI, авторитетная автоматизация-источник). Результат — разворот плана, лишние миграции/деплои. Специализация inside-out-blindness на внешние системы.
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-07
source_cases:
  - case-2026-06-25-design-before-external-source.md
  - case-2026-06-26-sendpulse-webhook-assumed-capability.md
status: active

# Контекстные якоря
domain: [integration, api_design, verification, projecta]
situation: "designing_integration_or_mirror_of_external_system"
trigger: "assume_external_system_capability_or_field_semantics"
stakes: "rework, extra_migration, deploy_churn, wrong_data_model"
actors: [agent, owner, external_service]
environment: production
circumstances: "authoritative_external_source_exists_but_unread"
purpose: "new_feature, port_behavior"
method: "codebase_first_design_against_assumptions"
tags: [source_of_truth, external_system, assumption, design_before_verify, make_com, sendpulse, wfirma]

# Demand
need: avoid_rework
urgency: when_relevant
availability: has_alternatives

# Promotion & scope
promotion_tier: 2
scope: universal
origin_domain: integration
modification_history:
  - date: 2026-06-30
    kind: branched
    reason: "Извлечён из 2 кейсов (Make + SendPulse) как узкая специализация inside-out-blindness на внешние системы"
    trigger_case: case-2026-06-26-sendpulse-webhook-assumed-capability.md
  - date: 2026-08-07
    kind: reinforced
    reason: "оценка agent-reach 2026-08-02: не поверил README (64k звёзд) — сверка через gh api подтвердила звёзды и вскрыла перехват имени на PyPI; правило применено и окупилось"
fragile: false

# Связи
related:
  - pattern-inside-out-blindness.md
  - principle-verify-before-acting.md
  - case-2026-06-14-externalize-config-before-scale.md
  - case-2026-06-23-validate-provider-controlled-identifiers.md
edges:
  - specializes: pattern-inside-out-blindness.md
  - similar_to: principle-verify-before-acting.md
---

## Правило

Когда задача — воспроизвести/зеркалить поведение внешней системы или переиспользовать поле под неё: ДО проектирования получить и прочитать авторитетный источник (саму внешнюю систему — её API/UI/доки/существующий код-зеркало/автоматизацию-источник) и проверить каждое допущение о её возможностях. Внешняя система — это спецификация, а не деталь реализации.

## Почему

Два проявления за неделю, обе — ProjectA, разные внешние системы:
- **case-2026-06-25 (Make):** спланировал словарь алиасов и переиспользовал поле `workDescription` по внутренней модели кода, не запросив Make-сценарий (источник правды) и задокументированную роль поля → разворот плана + 2-я миграция/деплой.
- **case-2026-06-26 (SendPulse):** спроектировал webhook исходя из того, что в SendPulse «можно прописать заголовки» и «потоки не пересекутся» — обе посылки про реальную систему ложны.

Корень общий с `pattern-inside-out-blindness` (фокус на внутренней структуре, внешний контекст выпадает), но триггер уже и распознаваемее: момент «проектирую под внешнюю систему». Проектное правило §10.2 уже фиксирует это требование — паттерн объясняет, почему оно нарушается.

## Как применять

1. Признал, что строишь интеграцию/зеркало/порт внешней системы → СТОП перед дизайном.
2. Выпиши список допущений о внешней системе («у неё есть поле X», «она умеет заголовки», «потоки не столкнутся»).
3. Проверь каждое: прочитай её API/UI/доки/код-зеркало или сделай пробный запрос.
4. Только потом проектируй модель.

## Scope

Universal (техническая интеграция, не зависит от собеседника). Кандидат на дальнейшее обобщение, если проявится на не-ProjectA проекте.
