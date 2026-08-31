---
name: env-read-timing
description: Управляющий env-флаг/секрет должен существовать в process.env ДО точки, где код его читает (старт фреймворка / загрузка модуля / setup теста); иначе читается пустое значение
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-06-20
source_cases:
  - case-2026-06-18-instrumentation-env-gate-timing.md
  - case-2026-06-20-module-load-env-capture-test.md
status: active

# Контекстные якоря
domain: [next.js, testing, local_dev]
situation: "startup_gate, unit_test_auth, config_read"
trigger: "env_read_before_set, gate_not_firing, empty_secret_despite_set"
stakes: "dev_blocked, false_test_failure, silent_misconfig"
actors: [system]
environment: "local_dev, ci_cd, production"
circumstances: "env_in_dotfile_only, module_level_const, framework_startup_hook"
purpose: "feature_dev, feature_test"
method: "npm_dev, vitest"
tags: [env_loading, env_timing, module_load, startup_gate, vitest, hoist, instrumentation, process_env]

need: avoid_silent_misconfig
urgency: when_relevant
availability: has_alternatives

# Связи
related: [principle-verify-before-acting.md, pattern-check-build-config.md]
edges:
  - generalizes: case-2026-06-18-instrumentation-env-gate-timing.md
  - generalizes: case-2026-06-20-module-load-env-capture-test.md

# Promotion & scope (v1.0.9)
promotion_tier: 2
scope: universal
origin_domain: "next.js"
effective_contradicted: 0.0
contradiction_log: []

# Modification lineage (v1.0.8)
modification_history: []
fragile: false
---

**Паттерн:** Код читает env в ФИКСИРОВАННЫЙ момент — хук старта фреймворка (`instrumentation.register()`), загрузка модуля (top-level `const X = process.env.Y`), setup теста. Значение обязано присутствовать в `process.env` ДО этого момента. Если оно появляется позже — читается пустое/устаревшее, и поведение выглядит как «флаг/секрет не задан», хотя он «задан» (просто не там и не тогда).

**Why (2 проявления одного механизма):**
- `case-2026-06-18`: `instrumentation.register()` стартовал раньше загрузки `.env.local` → `process.env.DISABLE_QUEUE` ещё undefined → гейт не сработал → dev-сервер поднял BullMQ без Redis и завис.
- `case-2026-06-20`: `lib/bot-auth.ts` захватил `BOT_API_SECRET` в module-level const на импорте → тест выставил `process.env` в `beforeEach` (после импорта) → const заморожен как `""` → ложный 401.

**How to apply:**
- Управляющий флаг фоновой инфраструктуры → в окружение процесса (npm-скрипт `"dev": "DISABLE_QUEUE=1 next dev"` / CI / launchd), не только в `.env*`.
- Юнит-тест читает env, а тестируемый модуль берёт его в module-const → ставь env через `vi.hoisted(() => { process.env.Y = ... })` (до импортов), ЛИБО перенеси чтение env в тело функции (call-time — корректнее и в рантайме).
- Диагностика: поведение «как будто env пустой» при заданном значении → заподозри тайминг чтения относительно установки; проверь наличие ожидаемого лог-маркера гейта (его отсутствие = ветка не выполнилась).

**Limitations:** В проде env обычно присутствует к старту процесса — там module-load/startup чтение безопасно (нужно поднимать инфраструктуру, freeze секрета — норма). Паттерн про точки, где env может ЕЩЁ или УЖЕ не быть в нужный момент: dev-старт, изоляция теста, поздняя загрузка dotfile.
