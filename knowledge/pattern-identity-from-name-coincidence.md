---
name: Идентичность или связь людей выводится из совпадения имени, хотя имя — не идентификатор
description: "Агент отождествляет двух людей или выводит их родство/связь из совпадения имени или фамилии, когда совпадение поддержано контекстной рифмой (общий город, тема, деньги). Имя — слабый идентификатор, но используется как сильный. Маркеры неопределённости в источнике («может быть», «или не он», однофамилец) игнорируются, склейка выдаётся как факт и тиражируется."
type: pattern
confidence: 1
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-13
source_cases: [case-2026-08-11-kinship-inferred-from-surname.md, case-2026-08-13-identity-conflated-by-first-name.md]
source_session: ""
status: active

promotion_tier: 2
scope: universal
origin_domain: entity_resolution

domain: [entity_resolution, data_analysis, business_advisory, osint, multi_agent_orchestration]
situation: "resolving_person_mentions_across_sources_or_synthesizing_dossiers"
trigger: "name_or_surname_match_plus_context_rhyme_treated_as_identity_or_kinship"
stakes: "false_person_identity_or_relation_propagated_as_fact"
actors: [agent, subagent, orchestrator]
environment: "archive_analysis, osint, workflow_synthesis"
circumstances: "source_uncertainty_marker_ignored, homonym_or_namesake_possible, no_stronger_identifier_checked"
purpose: "map_people_relations_entities"
method: "narrative_bridging_of_two_mentions_via_shared_name_field"
tags: [name_collision, identity_conflation, entity_resolution, namesake, propagation_before_verification]

need: reduce_risk
urgency: when_relevant
availability: unique

related: [pattern-unobservable-narrated-as-fact.md, pattern-false-obviousness.md, principle-verify-before-acting.md]
edges:
  - generalizes: case-2026-08-11-kinship-inferred-from-surname.md
  - generalizes: case-2026-08-13-identity-conflated-by-first-name.md
  - similar_to: pattern-unobservable-narrated-as-fact.md
modification_history: []
fragile: false
---

# Идентичность из совпадения имени

**Наблюдение (2 кейса за трое суток, один проект).**
- `case-2026-08-11-kinship-inferred-from-surname` — родство двух людей выведено из общей фамилии.
- `case-2026-08-13-identity-conflated-by-first-name` — два разных человека склеены в одного по общему имени + контекстной рифме (Кипр, деньги Влада), выдано с суммой «~100 тыс.», растиражировано по 5 файлам.

Смежное (OSINT, 2026-08-13/14): maigret по нику `vlad.gramovich` вернул десятки «его» профилей, где сайты усекли ник по точке до `vlad` — чужие люди; и однофамилец `Uladzislau Hramovich` (DevOps EPAM) — другой человек. Тот же механизм на другом носителе идентификатора.

**Механизм.** Имя/фамилия/ник — слабый идентификатор. Модель повышает его до сильного, когда совпадение поддержано контекстной рифмой (общий город, тема, сумма). Маркеры неопределённости в источнике («может быть», «или не он», «однофамилец») систематически игнорируются — и агентом при склейке, и оркестратором при тираже.

**How to apply.**
1. Отождествление двух упоминаний человека — утверждение, требующее опоры **сильнее имени**: роль+организация, контакт, прямое подтверждение источника. Совпадение имени/фамилии/ника само по себе — не опора.
2. Есть маркер неопределённости в источнике → склейку не делать: две сущности + ребро `possibly_same_as`, не `same_as`.
3. Оркестратору/синтезатору: конструкция «Имя (Другое_имя)» или «X = Y» в отчёте агента, не процитированная из источника рядом, — стоп-сигнал перед тиражом.
4. OSINT: доверять только точному совпадению полного идентификатора; усечённые/однофамильные хиты — кандидаты, не факты.

**Scope.** Universal — механизм не зависит от собеседника (entity resolution, OSINT, синтез досье). Промоушен в principle — при подтверждении в домене за пределами анализа людей.
