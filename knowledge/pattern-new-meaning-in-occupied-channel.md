---
name: pattern-new-meaning-in-occupied-channel
description: "Новое значение (код возврата, код выхода) добавлено в канал, у которого уже есть читатели — в том числе установленные редакции прежней версии; каждый читатель понимает его по-своему или как поломку, и верный новый ответ ломает соседей"
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-28
source_cases: [case-2026-09-19-new-return-code-seizes-a-channel-that-has-owners.md, case-2026-10-25-new-exit-code-broke-installed-consumer.md]
source_session: ""
status: active

domain: [tooling, interfaces, api_design, versioning]
situation: "у прибора появляется новый ответ, и его хотят выразить новым значением существующего канала (код возврата, код выхода, поле)"
trigger: "правка добавляет новое значение в канал, который читают другие программы"
stakes: "читатель, не знающий значения, понимает его по-своему (находка, поломка, «выполнено») — верная починка ломает соседей и установленные копии"
actors: [agent, script, hook, installed_consumer]
environment: "инструменты с несколькими вызывающими; репозиторий и установка в разных редакциях"
circumstances: "новый ответ сам верен — отдельное состояние просится в отдельный провод, и это затмевает вопрос, кто ещё читает провод"
purpose: "добавить ответ, не изменив контракт тех, кто читает канал"
method: "перепись читателей канала ДО правки — поиском по вызывающим в репозитории и в установленной копии; свободного значения нет или читатели в другой редакции — ответ в другой канал (текст в известном коде, stderr, отдельное поле)"
tags: [exit-code, return-code, channel-owners, backward-compatibility, installed-edition]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: avoid_regression
urgency: before_action
availability: has_alternatives

related: [pattern-keep-list-drifts-from-its-consumers]
edges:
  - similar_to: pattern-keep-list-drifts-from-its-consumers

modification_history: []
provenance_log: []
fragile: false

origin: solo
preceded_artifact: "no"
promotion_tier: 2
scope: universal
origin_domain: tooling
---

Канал с несколькими читателями — общая собственность. Новое значение в нём меняет контракт у каждого читателя, поэтому
перепись читателей (в репозитории и в установленных редакциях) стоит до правки. Свободного значения нет — новый ответ
идёт в другой канал: текст в известном коде, stderr, отдельное поле.

**Why:** два случая в ClaudSoul. 19 сентября 2026: код 3 «отчёт неполон» у `scripts/defect-class-carriers.py` —
читателей оказалось четверо, бегун замеров счёл замер выполненным и обнулил срок, тест покраснел, подмена накрыла код 2
(`case-2026-09-19-new-return-code-seizes-a-channel-that-has-owners`). 25 октября 2026: код выхода 5 «вид не знает» был
верен, но установленный потребитель прежней редакции знает только 0/3/4 и прочее читает поломкой
(`case-2026-10-25-new-exit-code-broke-installed-consumer`). Оба раза — ответ ушёл в текст при прежнем коде.

**How to apply:** признак — правка добавляет `exit N` / `return N` / новое значение поля, которого раньше не было.
Перед ней — `grep` по вызывающим в репозитории и в `~/.claude` (установленная копия); в тексте починки — число читателей
по переписи, а не «читается одним».

**Limitations:** канал с одним читателем в том же коммите и без установленных копий расширяется свободно.
