---
name: pattern-parallel-tool-batch-not-atomic
description: "Параллельные вызовы одного ответа исполняются и отказывают поштучно, а агент рассуждает о пакете как о целом: коммит уходит без отказавшего Edit, повтор пакета после частичного отказа второй раз вставляет то, что уже легло"
type: pattern
outcome: error
confidence: 1
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-21
source_cases: [case-2026-11-08-edit-and-commit-in-one-parallel-batch.md, case-2026-11-10-partially-refused-edit-batch-resent-whole.md, case-2026-11-21-fact-recorded-in-same-batch-as-its-action.md]
source_session: ""
status: active
promotion_tier: 2
scope: universal

domain: [agent_tooling, git, editing]
situation: "несколько вызовов инструментов в одном ответе"
trigger: "отказ одного вызова пакета (страж, устаревший old_string)"
stakes: "коммит без части правки, дублированная вставка"
actors: [agent, guard]
environment: local_dev
circumstances: "вызовы пакета зависят друг от друга, а отказ отдельного вызова виден только в его результате"
purpose: editing
method: "параллельные Edit и Bash в одном ответе"
tags: [tool-batch, partial-failure, compile-2026-11-11]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: avoid_regression
urgency: immediate
availability: has_alternatives
related: [pattern-commit-condition-lives-in-the-command, pattern-string-replace-must-prove-single-landing]
edges:
  - similar_to: pattern-commit-condition-lives-in-the-command.md
  - similar_to: pattern-string-replace-must-prove-single-landing.md
origin: solo
provenance_log:
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: пакет параллельных вызовов отказал частично"
    trigger_case: case-2026-11-08-edit-and-commit-in-one-parallel-batch.md
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: пакет параллельных вызовов отказал частично"
    trigger_case: case-2026-11-10-partially-refused-edit-batch-resent-whole.md
    session: ""
  - date: 2026-11-21
    kind: reinforced
    reason: "21.11.2026: запись в память о файле автозапуска ушла одним пакетом с Write этого файла; Write отбит стражем, в памяти остался адрес несуществующего файла — поправлено следующей правкой"
    session: ""
---

Действие, которое зависит от успеха другого вызова (коммит после Edit, публикация после правки), ставится в следующий ход, а не в тот же пакет. После частичного отказа пакета повторяются только отказавшие вызовы. Перед повтором вставки «после якоря» проверь, не легла ли она уже.

**Why:** 08.11.2026 (ClaudSoul, D1248): Edit CHANGELOG и git commit ушли одним пакетом. Edit отказал на устаревшем old_string, а коммит собрал индекс без записи. 10.11.2026 (ProjectA): три Edit в пакете, третий отбит стражем. После снятия отказа повторены все три, и вставка второго легла дважды; дубль нашёл Playwright в strict mode.

**How to apply:** если в пакете был отказ, перечисли, какие вызовы прошли, и повтори только остальные. Вставку по якорю, который остаётся в файле, считай перед повтором (`grep -c`).

**Limitations:** независимые чтения и поиски в одном пакете безопасны.
