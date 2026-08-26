---
name: Shared-invariant contract — один авторитетный источник правила
description: "Если инвариант применяется в 2+ компонентах, его дублирующие реализации (code-code или code-docs) неизбежно расходятся. Нужна одна authoritative implementation, которую вызывают все стороны."
type: pattern
outcome: error
confidence: 5
impact: 5
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-09
source_cases:
  - case-2026-04-20-ascii-default-test-blindness.md
  - case-2026-06-20-status-numbers-in-n-places-drift.md
  - case-2026-06-23-sort-direction-convention-drift.md
status: active

domain: [system_design, software_architecture, code_contract]
situation: "multi_component_pipeline, shared_rule_application"
trigger: "duplicate_implementation_of_same_rule, documentation_as_contract"
stakes: "silent_drift, latent_bugs, broken_cross_component_invariant"
actors: [agent, developer]
environment: "any_multi_component_system"
circumstances: "evolving_components, async_changes, docs_as_only_contract"
purpose: "prevent_regression, maintainability"
method: "extract_shared_library"
tags: [shared_invariant, single_source_of_truth, DRY, contract, drift]

need: "prevent_silent_divergence"
urgency: "when_designing"
availability: "has_alternatives"

critical_anchors: [trigger, situation]
weight_modifiers: ""

related:
  - pattern-inside-out-blindness.md
  - principle-verify-before-acting.md
edges:
  - similar_to: pattern-inside-out-blindness.md
  - specializes: principle-completeness-over-speed.md
  - specializes: principle-single-source-of-truth.md

promotion_tier: 2
scope: universal
origin_domain: software_architecture
effective_contradicted: 0.0
contradiction_log: []
modification_history:
  - date: 2026-06-20
    kind: scope_widened
    reason: "обобщён до principle-single-source-of-truth (подтверждён кросс-доменно: код → доки → числа → конфиг)"
    trigger_case: case-2026-06-20-status-numbers-in-n-places-drift.md
provenance_log:
  - date: 2026-08-09
    kind: reinforced
    reason: "ClaudSoul to_lower ×3 (sed / jq / шаблон), третья копия промахивалась; канон в hooks/portable-lib.sh + страж test_case_folding_portable.sh"
    trigger_case: 4862f8c
  - date: 2026-08-09
    kind: reinforced
    reason: "ClaudSoul depth_ratio ×3 (metrics-collector / audit-digest / SKILL.md) тремя формулами → ложное 4% при коридоре 10-20%; единое определение"
    trigger_case: 5c26087
fragile: false

origin: solo
trigger_for_co_cognition: ""
bridge_layer: ""
---

**Паттерн:** Правило (инвариант), применяемое в нескольких компонентах, стремится расходиться, если у него нет **ОДНОГО authoritative source**, который вызывают все стороны. Документация в качестве контракта между реализациями — хрупкая форма связи: один компонент эволюционирует, другой — нет, документация не ловит drift.

**Подтверждённые кейсы:**

1. **v1.1.6 Slugify contract** — правило слагификации (Unicode preserve vs ASCII-транслит) имело две реализации: в `_slugify()` integrate (code) и в `extract-guide.md §2` (documentation для Claude-extractor). Документация была неполной (не указывала Unicode-поведение явно), реализация использовала `re.UNICODE` — drift проявился только при реальном Unicode-входе. Фикс: CLI `ingest.cli slug <name>` стал единственным authoritative source — и extractor, и любой внешний вызов получают один результат.

2. **v1.1.7 FSRS formula** — формула стабильности `7 × (1 + cc × 0.5) × (1 + (impact-1) × 0.25)` жила в `knowledge/META.md` (documentation) и в `/knowledge-audit` SKILL (как inline-формула в Step 3). Third implementation планировался в knowledge-activator — вместо трёх копий была создана `hooks/fsrs-lib.sh` как единственный источник. SKILL теперь `source'ит` библиотеку, knowledge-activator тоже. META.md ссылается на библиотеку как на канон.

3. **2026-06-20 оздоровление ClaudSoul — паттерн всплыл ×4 за сессию** (см. `case-2026-06-20-status-numbers-in-n-places-drift.md`): статус Контура 2 (architecture vs CLAUDE.md), счётчики seed, статус моста L2↔L2 (frontmatter vs index), числа документов (хуки/скиллы/тесты в 5 доках). Каждый раз фикс — единый источник (`regen-seed.py`, `count-stats.sh`) + страж-тест (`test_seed_integrity`, `test_bridge_status_consistency`, `test_doc_counts`). Страж `test_doc_counts` позже **поймал** изменение 24→25 хуков — подтверждение, что механизм работает не только в момент написания.

4. **2026-06-23 ProjectA sort-direction drift** (см. `case-2026-06-23-sort-direction-convention-drift.md`): конвертация направления сортировки `AntD "ascend"/"descend" → "asc"/"desc"` имела авторитетный источник — хелпер `prismaDir()` + тип `SortFilters.sortOrder: "ascend"|"descend"`. Prisma-путь (`buildOrderBy`) вызывал `prismaDir` и работал. Но **параллельный in-memory путь** сортировки захардкодил сравнение `=== "asc"` (Prisma-формат, не AntD) → всегда `false` → направление всегда убывающее, сортировка визуально «не работала». Дубль конвертации в code-code (не code-docs). Усугубил **слабый тип** (`sortOrder: string` вместо строгого union) — компилятор не поймал сравнение-всегда-`false`. Фикс — вызвать канон / строгий тип как страж.

**Why:** Документация между реализациями — это "эксплицитный invariant-as-prose". Она:
- Не исполняется (тест не может её провалить)
- Не валидируется (линтер её не ловит)
- Не синхронизируется автоматически при изменении одной стороны

Единственный authoritative source — это:
- Shared library function (import/source в обеих сторонах)
- Canonical tool CLI (subprocess из обеих сторон)
- Shared config schema (validated at both sides)

**How to apply:**

1. **При дизайне pipeline / multi-component система:** перед написанием второй реализации правила — спросить: «Где единственный authoritative source?» Если ответ «в документации» — это запах. Извлечь в shared-библиотеку ДО второй реализации.

2. **При ревизии существующего кода:** если находишь правило, которое «должно быть одинаковое» в двух местах, проверить:
   - Есть ли автоматический тест, проверяющий parity? (если нет — это drift-bomb)
   - Что случится, если одна сторона эволюционирует? (если ничего не сломается — это тихий drift)

3. **Маркеры high-risk инвариантов:**
   - Сериализация ↔ десериализация (формат данных)
   - Producer ↔ consumer (формат сообщений)
   - Extractor ↔ integrator (slug, schema)
   - Validator в UI ↔ validator в API
   - Конвертер значения (направление/единицы/статус) вызывается в одном пути, но дублируется вручную в параллельном (in-memory/computed) пути — вдвойне опасно, если поле-носитель типизировано как `string`, а не строгий union (компилятор не ловит дрейф формата)

4. **Тест на shared-invariant contract:**
   - Может ли тест подать одинаковый вход обеим сторонам и проверить equality?
   - Если нет — извлечь в библиотеку, чтобы тест мог стать тривиальным.

**Limitations:**
- Не все правила нужно унифицировать. Случайное совпадение (`MAX_RETRIES = 3` в двух несвязанных модулях) — не shared invariant, это совпадение. Shared invariant = правило с общей causation, изменение которой в одном месте требует изменения в другом.
- Слишком агрессивная унификация создаёт coupling. Проверить — действительно ли правило общее, или два компонента применяют похожее правило к разным вещам.

**Связь с pattern-inside-out-blindness:** Shared-invariant contract — это часто следствие inside-out blindness (компонент спроектирован "изнутри", без вопроса "кто ещё применяет это правило?"). Но это отдельный паттерн: даже агент, который учёл external context, может забыть извлечь правило в shared-библиотеку.
