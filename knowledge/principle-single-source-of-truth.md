---
name: Единый источник истины — один факт в N местах дрейфует без авторитетного источника
description: "Любой факт (правило, инвариант, статус, число, конфиг), представленный в 2+ местах, неизбежно расходится, если одно из них не авторитетно, а остальные не производятся из него или не сверяются стражем. Фикс — единый источник + страж, не разовая синхронизация."
type: principle
outcome: error
confidence: 5
impact: 5
intensity: 1
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-14
source_cases:
  - case-2026-04-20-ascii-default-test-blindness.md
  - case-2026-06-20-status-numbers-in-n-places-drift.md
  - case-2026-06-20-hook-dependency-install-drift.md
  - "ClaudSoul: страж чисел (test_doc_counts) покрывал только английский README → README.ru.md и CLAUDE.md дрейфанули там, где стража нет (2026-06-21); фикс — расширить страж на все копии, не синхронизировать руками"
  - "ClaudSoul: lean-список (F1/F2/F5·G3·H5·I1/I2·K1/K2) задан в каноне И повторён списком в шаблоне rules-output.md — шаблон уронил F2/H5 (2026-06-21); фикс — единый авторитетный список в каноне, шаблон ссылается (compile-2026-06-21-update-single-source-lean-list-drift)"
  - case-2026-07-15-retire-migration-source-on-truth-switch.md
provenance_traced: low
status: active
instrument_verdict: invented   # сигнал по имени файла механически работает (22 попадания на hooks/*-lib.sh), но выведен не из проявлений: в кейсах дефект возникал при написании ВТОРОЙ копии факта, а путь файла об этом ничего не говорит
instrument_assessed: 2026-07-29

domain: [system_design, software_architecture, documentation, knowledge_management, ci_cd, data_modeling]
situation: "same_fact_or_rule_represented_in_multiple_places"
trigger: "duplicate_representation_of_one_fact_status_number_invariant"
stakes: "silent_drift, false_mental_model, latent_bugs, broken_invariant"
actors: [agent, developer]
environment: "any_multi_artifact_system"
circumstances: "manually_maintained_duplicates, docs_as_contract, async_changes"
purpose: "prevent_regression, maintainability, honest_artifacts"
method: "designate_authoritative_source_plus_derive_or_guard"
tags: [single_source_of_truth, drift, DRY, guard_test, autogenerate, dont_sync_by_hand]

need: "prevent_silent_divergence"
urgency: "when_designing"
availability: "foundational"

related:
  - pattern-shared-invariant-contract.md
  - pattern-inside-out-blindness.md
  - principle-knowledge-in-the-world.md
edges:
  - generalizes: pattern-shared-invariant-contract.md
  - similar_to: pattern-inside-out-blindness.md

promotion_tier: 3
scope: universal
origin_domain: software_architecture
effective_contradicted: 0.0
contradiction_log: []
modification_history: []
fragile: false

origin: co-cognition
trigger_for_co_cognition: "contradiction"
bridge_layer: "L2-L3"
provenance_log:
  - date: 2026-08-14
    kind: reinforced
    reason: "индексная строка MEMORY.md разошлась с телом памяти; правда была в теле"
    trigger_case: case-2026-08-10-index-line-drifts-from-body.md
---

**Принцип:** Один и тот же факт — правило/инвариант (код), статус компонента, число, формат, конфиг — представленный в **2+ местах**, дрейфует, если нет **одного авторитетного источника**, из которого остальные **производятся** (генерация/импорт/source) либо с которым **сверяются стражем** (тест/`--check`). Разовая синхронизация лечит симптом; корень — в дублировании представления без единого источника.

**Почему это принцип, а не паттерн (cross-domain):** подтверждено в шести независимых проявлениях через РАЗНЫЕ домены:
- **Код-инварианты:** slugify (code ↔ docs), формула FSRS (3 копии) → shared-библиотека.
- **Документация-статус:** Контур 2 (`architecture.md` «спроектирован» ↔ `CLAUDE.md` «работает»); статус моста L2↔L2 (frontmatter ↔ индекс).
- **Числа:** хуки/скиллы/тесты во всех 5 доках → `count-stats.sh` + страж.
- **Конфиг/seed:** счётчики seed (`knowledge/` ↔ рабочая база) → `regen-seed.py` + страж.
- **Зависимости ↔ список установки:** новая зависимость хука ↔ фиксированный список фикстуры.

Фикс одинаков во всех доменах: **единый источник + страж**. Страж `test_doc_counts` позже поймал изменение 24→25 хуков — механизм окупился вне момента написания. Это и делает наблюдение принципом, а не доменным паттерном.

**Как применять:**
1. Видишь факт/статус/число в 2+ местах → **не синхронизировать руками**. Спросить: «кто авторитетен?» Ответ «документация/память» — запах.
2. Сделать остальные **производными** (генератор, `source`, указатель) ИЛИ добавить **страж** (тест сверки/`--check`, падающий при расхождении).
3. Документация как контракт между реализациями — хрупкая форма (тест её не валит).
4. Маркеры high-risk: serialize↔deserialize, producer↔consumer, extractor↔integrator, UI-validator↔API-validator, статус в доке↔реальность кода, число в N доках, зависимость↔список установки.

**Limitations:**
- Случайное совпадение (одинаковое значение в несвязанных модулях без общей причинности) — НЕ единый инвариант, унифицировать не надо (создаст лишний coupling).
- Исторические/датированные записи (changelog, roadmap) намеренно «заморожены» — синхронизировать НЕ надо, это разные снимки во времени, а не один факт.
- Слишком агрессивная унификация → coupling. Проверить: правило действительно общее (общая причинность) или два места применяют похожее правило к разным вещам.

**Специализации:** `pattern-shared-invariant-contract` — частный случай для инвариантов между компонентами кода (этот принцип обобщает его на доки/статусы/числа/конфиги).
