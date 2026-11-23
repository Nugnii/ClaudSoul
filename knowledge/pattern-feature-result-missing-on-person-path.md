---
name: pattern-feature-result-missing-on-person-path
description: "Функция проверена по пути данных (роут, тест, запись в базе) и выкачена, а результата нет там, где его ищет человек: в уведомлении нет ссылки, в карточке «Готово» нет PDF, кликабелен только бейдж, кнопки слиплись. 10.11.2026 владелец сам нашёл пять таких мест после выкаток"
type: pattern
outcome: error
confidence: 1
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-11
source_cases: [case-2026-11-10-owner-found-result-gaps-after-release.md, case-2026-11-10-new-entry-point-fixed-siblings-left-on-old-screen.md]
source_session: ""
status: active
promotion_tier: 2
scope: universal

domain: [web_ui, crm, product_quality]
situation: "приёмка новой функции перед «готово» или выкаткой"
trigger: "функция создаёт результат (документ, ссылку, переход), видимый на нескольких поверхностях"
stakes: "владелец находит пробелы сам, доверие к «готово» падает, выкатки идут лишними кругами"
actors: [owner, agent, operator]
environment: production
circumstances: "тесты зелёные, проверка глазами шла по одной поверхности — той, где функция сделана"
purpose: new_feature
method: "unit-тесты роута и Playwright по одному экрану"
tags: [ux-acceptance, entity-surfaces, compile-2026-11-11]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: improve_quality
urgency: next_session
availability: has_alternatives
related: [pattern-class-closure-without-a-carrier-count]
edges:
  - specializes: pattern-inside-out-blindness.md
origin: solo
provenance_log:
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: результат функции отсутствовал на поверхности, где его ищет владелец (B570-B583)"
    trigger_case: case-2026-11-10-owner-found-result-gaps-after-release.md
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: результат функции отсутствовал на поверхности, где его ищет владелец (B570-B583)"
    trigger_case: case-2026-11-10-new-entry-point-fixed-siblings-left-on-old-screen.md
    session: ""
---

Перед «готово» перечисли поверхности, где человек встретит сущность новой функции: уведомление, карточка воронки на итоговой стадии, строка списка, окно. На каждой проверь, что результат есть и до него доходит клик: ссылка, документ, переход. Перечень строй поиском компонентов, показывающих сущность, а не по памяти.

**Why:** ProjectA, 10.11.2026, реплики владельца после выкаток. В Telegram «нет ссылки ни на переход в воронку, ни на переход к заявке» (B570). В строке заявки кликабелен только бейдж (B575). «Интеграции» — «убогая пелена» (B580), на широком экране поля во всю ширину (B583). Кнопки окна заявки без отступов (B581). В карточке задачи «Готово» «нет самого результата», то есть PDF фактуры (B582). Тесты всех этих функций были зелёными.

**How to apply:** в план приёмки UI-функции добавь строку «поверхности сущности: N, проверены: N». Проверяй на ширине экрана владельца (2000+ px) и на узкой.

**Limitations:** серверные изменения без новой видимой сущности.
