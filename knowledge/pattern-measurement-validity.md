---
name: Валидность измерения — контролируй нужную переменную
description: Проверка или замер без контроля нужной переменной даёт ложный вывод — потолок скрыт happy-path'ом или конфаунд маскирует/инвертирует эффект
type: pattern
outcome: error
confidence: 5
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-23
source_cases:
  - case-2026-06-11-benchmark-confound-cache-reset.md
  - case-2026-06-11-single-instance-verify-hides-coverage-cap.md
  - case-2026-06-19-headless-proxy-blind-to-cursor-render.md
  - case-2026-06-20-tune-symptom-not-measure-root.md
  - case-2026-07-06-partial-verify-set-skips-changed-logic-suite.md
  - "ProjectA пагинация контрагентов (2026-07-05): POSITIVE application — верификация фикса мерила ПОКРЫТИЕ (последняя стр.93 достижима, сумма всех страниц=611=total, КА с 15 связями представлен целиком), а не happy-path «стр.1 грузится»; потеря/недостижимость строк была бы поймана. Прямой echo case-2026-06-11-single-instance-verify-hides-coverage-cap (тот же класс — cap 50 скрыт наивной проверкой). Без отдельного case-файла (сессия)."
  - case-2026-07-25-null-instrument-reads-as-negative-result.md
  - "ClaudSoul v1.11.0 (2026-07-25): конфаунды самоизмерения — counter-only-grows (contradicted_count=0 во всех 265 знаниях: писателя отрицательного исхода не существовало) + hold-out (инжектируемое знание собирает подтверждения через собственный инжект). База измеряла свою надёжность полуформулой. Без отдельного case-файла (сессия)."
  - case-2026-07-29-verification-frame-loop.md
  - case-2026-08-09-test-harness-load-manufactures-failures.md
  - case-2026-08-09-severity-needs-reachability-in-the-real-environment.md
  - case-2026-08-23-check-never-ran-looks-like-check-passed.md
status: active
instrument_verdict: inexpressible   # все восемь проявлений настоящие, но признак виден только ПОСЛЕ замера — когда результат сравнили с контролем; до действия неотличимо от корректного измерения
instrument_assessed: 2026-07-29

# Контекстные якоря
domain: [verification, testing, performance, next.js, system_design, browser_rendering]
situation: verification_or_measurement
trigger: "measurement_without_controlling_variable, single_instance_verify, ab_confound"
stakes: wrong_conclusion
actors: [system]
environment: production
circumstances: uncontrolled_variable
purpose: validation
method: verification
tags: [measurement, benchmark, verification, isolate_variable, coverage, confound, happy_path]

# Demand-компоненты
need: avoid_wrong_conclusion
urgency: when_relevant
availability: has_alternatives

# v1.0.9
promotion_tier: 2
scope: universal
origin_domain: verification
effective_contradicted: 0.0
contradiction_log: []
modification_history:
  - date: 2026-06-19
    kind: scope_widened
    reason: "3-й тип невалидного замера — инструмент в принципе не способен воспроизвести/отрисовать симптом (headless не рисует системный курсор → frac=0 ложно «починено»); невоспроизводимость = сигнал о причине вне кода"
    trigger_case: case-2026-06-19-headless-proxy-blind-to-cursor-render.md
  - date: 2026-06-20
    kind: scope_widened
    reason: "Диагностический сигнал: ПОСТОЯННЫЙ/одинаковый остаток симптома при РАЗНЫХ входах = причина вне той переменной, которую крутишь. Не замерял источник перелива → 5 деплоев подгонки высоты таблицы, а виноват body margin 8px (константа 16px на всех страницах была уликой)"
    trigger_case: case-2026-06-20-tune-symptom-not-measure-root.md
provenance_log:
  - date: 2026-07-28
    kind: reinforced
    reason: "null-instrument: молчание неработающего инструмента как отрицательный результат"
    trigger_case: case-2026-07-25-null-instrument-reads-as-negative-result.md
  - date: 2026-07-28
    kind: reinforced
    reason: "v1.11.0 конфаунды самоизмерения (counter-only-grows + hold-out)"
  - date: 2026-07-31
    kind: reinforced
    reason: "три отчёта из одиннадцати описывали причину неверно: корень глубже, обе половины утверждения опровергнуты замером, постановка требовала уточнения"
    trigger_case: /Users/user/.claude/global-lessons/case-2026-07-31-report-of-a-defect-is-a-hypothesis.md
  - date: 2026-08-01
    kind: reinforced
    reason: "рекомендация калибровки сравнивала p90 счётчика принятых с потолком, который расходуют игнорированные; доказательство — точное совпадение shrink_events=100 и gentle_ignored=100, лежавшее в отчёте три месяца"
    trigger_case: /Users/user/.claude/global-lessons/case-2026-08-01-counter-and-ceiling-are-different-quantities.md
  - date: 2026-08-01
    kind: reinforced
    reason: "три случая за сессию: замер исполнен, числа настоящие, предмет замера не тот, о котором утверждение (не тот файл / не то место / не та величина); отличие от родителя — переменные контролировались"
    trigger_case: /Users/user/.claude/global-lessons/case-2026-08-01-subject-of-measurement-vs-subject-of-claim.md
  - date: 2026-08-08
    kind: reinforced
    reason: "именованный конфаунд среды: полное плечо получает живую среду и собеседника, урезанное песочницу — плечи несимметричны"
    trigger_case: case-2026-08-08-ablation-by-symmetric-shadows.md
  - date: 2026-08-09
    kind: reinforced
    reason: "Нагрузка самого инструмента (4 воркера Playwright по проду) произвела 4 несуществующих отказа CLIENT_FETCH_ERROR; контрольный прогон в 1 поток — 4/4 зелёные. Новый source case case-2026-08-09-test-harness-load-manufactures-failures"
  - date: 2026-08-11
    kind: reinforced
    reason: "механизм подтверждён контролем переменной: тишина 0/400 против нагрузки 8/2000, и базовая ветка из HEAD отдельным рабочим деревом отделила мои падения от бывших до правки"
    trigger_case: case-2026-08-11-assertion-answer-from-broken-pipe.md
  - date: 2026-08-22
    kind: reinforced
    reason: "мутационная проверка не контролировала переменную «мутация применена» — зелёный засчитан как доказательство надёжности теста"
    trigger_case: case-2026-08-22-unapplied-mutation-reads-as-proof.md
  - date: 2026-08-23
    kind: reinforced
    reason: "замер достижимости по корпусу 20224 вызовов Bash отличил дефект от границы: bash -c с коммитом — 0 вхождений (закреплено тестом как граница), heredoc в подстановке — 113 живых, 34 с утечкой (blocker). Без замера обе выглядели одинаково"
    trigger_case: case-2026-08-23-narrow-fix-breaks-common-form.md
fragile: false

# Связи
related:
  - principle-verify-before-acting.md
  - pattern-false-obviousness.md
  - pattern-inside-out-blindness.md
edges:
  - specializes: principle-verify-before-acting.md
  - generalizes: case-2026-06-11-benchmark-confound-cache-reset.md
  - generalizes: case-2026-06-11-single-instance-verify-hides-coverage-cap.md
---

## Pattern

Проверка/замер достоверны только если контролируют ту переменную, ради которой делаются.
Если в постановку прокралась неконтролируемая переменная — результат вводит в заблуждение,
а часто и **инвертирует** вывод. «Прошло/работает/быстрее» при таком замере ничего не доказывает.

## Manifestations (2 кейса, один корень)

1. **Скрытое покрытие (happy-path).** `case-2026-06-11-single-instance-verify-hides-coverage-cap`:
   фичу «зеркалить ВСЕ чаты» проверили на одном seed-клиенте — механизм подтвердился, но
   измеряли «работает ли», а не «сколько покрыто». Лимит в 50 из 459 вскрылся только в проде.
   Неконтролируемая переменная — **масштаб**.

2. **Конфаунд в A/B-тайминге.** `case-2026-06-11-benchmark-confound-cache-reset`: замер
   ускорения сборки — правка `next.config` (механизм доставки изменения) обнулила
   `.next/cache`, первый прогон стал холодным. Сравнили «оптимизация + cold» против
   «база + warm». Неконтролируемая переменная — **состояние кеша**; вывод инвертировался
   («оптимизация замедляет»).

3. **Прокси, неспособный увидеть симптом (v2026-06-19).** `case-2026-06-19-headless-proxy-blind-to-cursor-render`:
   визуальное мерцание курсора верифицировали headless-замером `elementFromPoint`/computed-`cursor`
   (frac=0 = «починено») и задеплоили 2 фикса. Но headless **вообще не рисует системный курсор** —
   прокси меряет DOM-хиттест, а не отрисовку. Неконтролируемая переменная — **способность инструмента
   воспроизвести симптом**. Невоспроизводимость в headless обоих движков = улика «причина вне кода»
   (среда: ОС/драйвер/расширение), а не «нужен замер получше».

## How to apply

Перед тем как доверять проверке/замеру — спроси: **«какую переменную я на самом деле меряю,
и что ещё изменилось вместе с ней?»**

- **Coverage/верификация:** проверяй на репрезентативном масштабе, не на одном happy-path
  экземпляре. Меряй **число/долю покрытия**, а не только «оно работает на одном».
- **Performance A/B:** меняй ОДНУ переменную. Если механизм изменения сбрасывает
  кеш/прогрев (правка конфига, рестарт, миграция) — **отбрось первый прогон, грей, сравнивай
  warm-vs-warm**.
- **Визуальный/render-симптом (курсор, шрифт, GPU-артефакт):** DOM/headless-прокси
  (`elementFromPoint`, computed `cursor`/стиль) НЕ меряет то, что рисует ОС/композитор —
  headless вообще не рисует системный курсор. «Прокси чист» ≠ «починено». Если симптом
  не воспроизводится в автоинструментах (тем более в нескольких движках) — это сигнал
  «причина вне кода» (среда: ОС/драйвер/расширение/масштаб); изолируй среду ДО правок кода.
- **Выбор НАБОРА верификации по классу изменения (не по поверхности батча):** зелёный
  ПОДнабор (tsc/lint/gate/smoke) даёт ложную уверенность, если пропущен слой, ассертящий
  ИМЕННО изменённую логику. Правка серверной валидации/авторизации → прогнать тесты, которые
  эту логику проверяют (полный unit-набор), а не только типы/линт/UI-smoke. Спроси: «какие
  тесты покрывают файлы, которые я правлю?» (echo case-2026-07-06 — setup-тест со слабым
  паролём проскочил, т.к. в батче сложности пароля прогнали tsc/lint/gate/Playwright, но не vitest).
- **Общий чек:** «единственное ли это изменение между A и B?» Если нет — изолируй или
  зафиксируй конфаунд явно прежде чем делать вывод.

## Rule

When you verify or benchmark, control the variable you actually care about: test at
representative scale (not one happy-path instance) and change exactly one thing at a time —
if the change also resets caches/warmup state, the first run is confounded and must be discarded.
