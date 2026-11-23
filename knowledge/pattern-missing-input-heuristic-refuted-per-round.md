---
name: Нужного входа нет в данных — правило-эвристика опровергается скептиком по контрпримеру за круг
description: Когда ответ требует поля или связи, которых в данных нет, любая правка подменяет вход правилом-эвристикой; у каждого правила свой набор контрпримеров, скептик находит их по одному за круг, и круги не сходятся. Решение — вопрос владельцу ДО кода (поле, правило или «отложить»), а не следующее правило
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-11
source_cases:
  - case-2026-10-05-heuristic-sign-instead-of-field-misclassifies-money.md
  - case-2026-10-11-rule-chosen-where-data-has-no-link.md
source_session: ""
status: active

domain: [agent_design, verification, data_modeling, workflow]
situation: "починка, где ответ должен различать записи или связывать их, а различающего поля/связи в схеме нет"
trigger: "скептик опровергает правило правки контрпримером, правка следующего круга — снова правило"
stakes: "регрессы (в т.ч. в деньгах), часы агентного времени, ложное «закрыто»"
actors: [agent, skeptic_agent, owner]
environment: multi_agent_workflow
circumstances: "пункт помечен агентским; предлагаемая починка сама формулирует правило"
purpose: bugfix
method: "до кода: перечислить входы ответа и проверить, однозначен ли он по данным"
tags: [missing_input, heuristic_rule, owner_decision, skeptic_rounds]

volatile_anchors: []
self_altering: ""
outcome_signals: []

need: avoid_regression
urgency: when_relevant
availability: has_alternatives

promotion_tier: 2
scope: universal
origin_domain: projecta
valid_for: []
invalid_for: []
pending_for: []
per_speaker_state: {}
modification_history: []
provenance_log: []
fragile: false
blocker: false

related:
  - pattern-rework-expands-subject-beyond-owner-decision.md
  - case-2026-09-17-skeptic-found-a-defect-in-every-first-fix.md
edges:
  - generalizes: case-2026-10-05-heuristic-sign-instead-of-field-misclassifies-money.md
  - generalizes: case-2026-10-11-rule-chosen-where-data-has-no-link.md
  - similar_to: pattern-rework-expands-subject-beyond-owner-decision.md

origin: solo
trigger_for_co_cognition: ""
bridge_layer: ""
preceded_artifact: n/a
---

Перед правкой, чей ответ должен различать или связывать записи, перечисли входы ответа и спроси: однозначен ли
он по ДАННЫМ (есть поле, связь, метка)? Нет — это выбор правила, и он принадлежит владельцу: вопрос с вариантами
и ценой («поле — миграция на колонку», «правило X ошибается вот здесь», «отложить — носителей N»), а не код.
Тест, проверяющий только согласованность (сумма по окнам = окно, путь A = путь B), выбор правила не различает —
его выполняет любое последовательное правило.

**Why:** два случая в ProjectA.
- B28 (2026-10-05): ногу перекрытия отличали от корректировки оператора соседством id/времени вместо поля
  происхождения; скептик — пять падающих тестов в обе стороны, неверный курс; владелец выбрал поле.
- B463 (2026-10-10/11): строка импорта абонплаты не ссылается на операцию; «ответ не зависит от окна» чинился
  выбором, какую «Абонплату» строка представляет: два правила — два круга скептика opus с регрессами (отменённая
  «Возвратом», оплата из плюса, легаси-нога; нога «Абонентка» со своей строкой, +500 zł); владелец — «отложить».
- Третий след — в паттерне `pattern-rework-expands-subject-beyond-owner-decision` (PESEL-строка листа:
  «единственный снятый» на месте отсутствующего входа).

**How to apply:**
- признак до кода: предлагаемая починка сама формулирует правило («по всем операциям месяца», «по соседству») —
  перечисли входы и проверь однозначность по данным;
- признак после круга: скептик пишет «по данным неотличимо» или два теста требуют противоположного — круги
  остановить, вопрос владельцу, а не следующее правило;
- в денежной логике эвристика вместо поля недопустима; в отчётах — допустима только с названным пределом и
  решением владельца;
- носителей на проде 0 — честный вариант «отложить», его надо предлагать.

**Limitations:** если данные задают ответ, а код его считает неверно, — это обычный дефект реализации, круги
скептика законны (pattern-multi-round-adversarial-review). Механизм пока текстовый — пункт ClaudSoul D523.
