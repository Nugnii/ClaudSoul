---
name: Полнота важнее скорости
description: Лучше сделать одну вещь полностью (все локали, все edge cases, все файлы), чем быстро но частично
type: principle
outcome: error
confidence: 5
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-09
source_cases:
  - "ProjectA: добавили перевод только в ru.json — у польских пользователей показались ключи"
  - "ProjectA: исправили баг в одном сервисе — тот же паттерн был в трёх других"
  - "ClaudSoul: скрипт уже содержал || true в scoring-блоке, но не в context extraction — тот же паттерн, не проверен при модификации"
  - "ClaudSoul: добавил content в SQL SELECT, обновил 1-й цикл распаковки row, пропустил 2-й — *_ захватил edges_json, 111 рёбер потеряны"
  - case-2026-04-25-operation-dispatch-incomplete-enumeration.md
  - case-2026-06-11-feature-to-shared-modal-missed-parallel-form.md
status: active
instrument_verdict: inexpressible   # происхождение кандидатов чистое, но признак «сделано частично» появляется лишь при сравнении с полным множеством (все локали, все ветки), которого в payload действия нет
instrument_assessed: 2026-07-29

# Контекстные якоря
domain: [software_development]
situation: "refactoring, bug_fix, i18n, api_change"
trigger: "partial_change, single_file_fix"
stakes: "inconsistency, user_facing_bug, technical_debt"
actors: [agent, system]
tags: [completeness, consistency, grep_after_change]

need: "prevent_partial_work_passed_as_complete"
urgency: "when_relevant"
availability: "foundational"

# Связи
related:
  - i18n-all-locales.md
edges: []
modification_history: []
provenance_log:
  - date: 2026-08-09
    kind: reinforced
    reason: "ProjectA ba320ab (08-09): переименование middleware.ts→proxy.ts синкалось лишь в одной из двух веток deploy.sh, на проде остался старый файл; 4 значения enum заведены без меток i18n → MISSING_MESSAGE"
---

**Принцип:** Когда делаешь изменение — примени его ко ВСЕМ затронутым местам, не только к первому найденному.

Проявления:
- i18n: добавил ключ → добавь во ВСЕ локали
- Баг-фикс: нашёл паттерн → проверь нет ли его в других файлах
- API: изменил формат → обнови ВСЕ клиенты
- Рефакторинг: переименовал → найди ВСЕ использования
- Enum-dispatch: добавил `if/elif` на enum → покрыть КАЖДОЕ значение явно (или явный fallthrough с обоснованием)
- Фича в «общий» компонент → есть ли ПАРАЛЛЕЛЬНАЯ дубль-реализация того же действия? (case-2026-06-11-feature-to-shared-modal-missed-parallel-form: пикер добавлен в `BalanceChangeModal`, но страница «Счета» имеет свою дубль-форму изменения баланса без него)

**Why:** Частичное изменение создаёт несогласованность, которая всплывёт позже в более сложном контексте.

**How to apply:**
1. После каждого изменения — grep по кодовой базе на аналогичные места. Задать себе вопрос: "Есть ли ещё места где это актуально?"
2. Для enum-dispatch: выписать таблицу `[значение enum] × [output структура / поведение]` ДО кода. Только так заметишь silent no-op для пропущенного значения.
3. Добавляя фичу в «общий»/«переиспользуемый» компонент — НЕ верь, что он единственная точка входа. grep по характерным хукам/полям действия (напр. `useBalanceChange`, `chargeItems`) → если есть параллельная дубль-форма того же действия, вынеси общее в shared-компонент и подключи во ВСЕ места. Project CLAUDE.md, явно называющий обе точки («`BalanceChangeModal`, инлайн-форма «Счета»»), — сигнал, который надо прочитать ДО реализации.

**Limitations:** Не блокирует итеративную разработку — можно делать частями, если каждая часть оставляет систему в рабочем состоянии.
