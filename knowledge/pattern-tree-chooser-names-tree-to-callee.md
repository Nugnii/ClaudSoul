---
name: pattern-tree-chooser-names-tree-to-callee
description: "Вызываемый получает окружение вызывающего целиком и работает в его мире: корень дерева из унаследованной переменной, путь его состояния, журнал под его замком, GIT_DIR ловушки git. Кто выбрал дерево, тот называет его вызываемому явно; приватные переменные вызывающего снимаются, окружение передаётся по белому списку"
type: pattern
outcome: error
confidence: 3
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-23
source_cases: [case-2026-10-25-witness-inherits-caller-repo-var.md, case-2026-10-20-check-inherited-callers-state-dir.md, case-2026-11-04-executor-private-env-leaks-into-judged-check.md, case-2026-11-08-hook-spawned-job-inherits-git-dir.md]
source_session: ""
status: active

domain: [tooling, hooks, testing, environment]
situation: "хук или свидетель вычисляет корень своего дерева и зовёт инструмент, у которого корень по умолчанию — из переменной среды"
trigger: "вызывающий вычислил корень (ROOT), вызываемый читает корень из унаследованной переменной"
stakes: "проверка судит не то дерево: без переменной зелено, с переменной, выставленной кем-то другим, — красно или ложно зелено"
actors: [agent, hook, script, witness]
environment: "инструменты с корнем из переменной среды (CLAUDSOUL_REPO и подобные), вызываемые из хуков и тестов"
circumstances: "в обычном прогоне переменной нет, дефект виден только в окружении стража или другой сессии"
purpose: "вызываемый работает в том дереве, которое выбрал вызывающий"
method: "выбравший дерево передаёт его вызываемому явно — аргументом или переменной в строке вызова; чинить у вызывающего, а не unset в тесте; нога — прогон с переменной, указывающей на чужое дерево"
tags: [env-inheritance, repo-root, frame, callee-root]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: avoid_regression
urgency: when_relevant
availability: has_alternatives

related: [pattern-verification-frame-mismatch]
edges:
  - similar_to: pattern-verification-frame-mismatch

modification_history:
  - date: 2026-11-11
    kind: scope_widened
    reason: "/compile: не только корень дерева — любое приватное окружение вызывающего (STATE_DIR, CG_* с журналом под замком, GIT_DIR/GIT_INDEX_FILE ловушки)"
    trigger_case: case-2026-11-04-executor-private-env-leaks-into-judged-check.md
provenance_log:
  - date: 2026-11-10
    kind: reinforced
    reason: "D1284: test_impact_inject строил свою песочницу, но вызовы хука шли с унаследованным CLAUDSOUL_REPO клона сверки архива — прибор карты читал кэш клона; починка — свидетель снимает переменную"
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: вызываемый унаследовал приватное окружение вызывающего"
    trigger_case: case-2026-10-20-check-inherited-callers-state-dir.md
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: вызываемый унаследовал приватное окружение вызывающего"
    trigger_case: case-2026-11-04-executor-private-env-leaks-into-judged-check.md
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: вызываемый унаследовал приватное окружение вызывающего"
    trigger_case: case-2026-11-08-hook-spawned-job-inherits-git-dir.md
    session: ""
  - date: 2026-11-15
    kind: reinforced
    reason: "15.11.2026 D1295: probe_D1258 выбирала клон через cd, а named-limits.py брал корень из унаследованной CLAUDSOUL_REPO — контроль судил дерево вызывающего (с переменной 1, без 0); починено у вызывающего: CLAUDSOUL_REPO=$1 в строке вызова"
    session: ""
  - date: 2026-11-23
    kind: reinforced
    reason: "D1366 (23.11.2026): то же устройство в рамке сверщика архива после коммита — проба D1045 выбрала песочницу и не назвала её прибору, test_external_events и test_docs_family_a2_denies унаследовали CLAUDSOUL_REPO клона; 7 «Проверок» архива красны только там"
    session: ""
fragile: false

origin: solo
preceded_artifact: "no"
promotion_tier: 2
scope: universal
origin_domain: tooling
instrument_verdict: candidate   # признак: файл выбирает дерево (`ROOT=`, `rev-parse --show-toplevel`, `cd "$1"`) и зовёт прибор дерева, читающий `CLAUDSOUL_REPO`, без корня в строке вызова; проявление 15.11.2026 — probe_D1258 (D1295)
instrument_assessed: 2026-11-15
---

Кто выбрал дерево, тот называет его вызываемому явно. Вызываемый, берущий корень из унаследованной переменной, работает в
дереве того, кто эту переменную выставил.

**Why:** ClaudSoul, 25 октября 2026, два события одного устройства. D1076: хук коммита вычислял `ROOT` и звал
`$ROOT/scripts/dep-index.py`, а индексатор брал корень из `CLAUDSOUL_REPO` — с переменной 19 красных ног
`test_doc_impact_check.sh`. D1074: свидетель сроков унаследовал `CLAUDSOUL_REPO` вызывающего. Брат —
`hooks/impact-inject.sh` (D1072). Оба — в `case-2026-10-25-witness-inherits-caller-repo-var`. Подкласс
`pattern-verification-frame-mismatch`: проверка исполняется не в том экземпляре, только рамку подменяет среда.

**How to apply:** признак — в одном файле вычисляется корень (`ROOT=…`, `rev-parse --show-toplevel`) и рядом зовётся
инструмент, читающий корень из среды. Передать корень в строке вызова (`CLAUDSOUL_REPO="$ROOT" cmd` или аргумент); нога
свидетеля — прогон с переменной на чужое дерево.

**Шире корня дерева (с 11.11.2026).** Тот же механизм у любой приватной переменной вызывающего. 20.10: вызванная
проверка взяла STATE_DIR вызывающего (`case-2026-10-20-check-inherited-callers-state-dir`). 04.11 (D1204): completion-gate
передал судимой команде свои `CG_*`, вложенный гейт ждал его замок на каждом вызове — 143 с вместо 4
(`case-2026-11-04-executor-private-env-leaks-into-judged-check`). 08.11 (D1249): процесс из post-commit унаследовал
GIT_DIR и GIT_INDEX_FILE ловушки (`case-2026-11-08-hook-spawned-job-inherits-git-dir`). Правило: при subprocess, фоновом
запуске или вызове из ловушки git назови, какие переменные вызываемому нужны; свои (путь состояния, журнал под замком,
GIT_DIR) сними явно (`env -u`, `_env.pop`). Нога — удержать замок или выставить чужой GIT_DIR и прогнать вызываемого.

**Limitations:** если переменная — объявленный способ выбрать дерево извне (вызывающий её и выставил), наследование
законно; дефект — когда вызывающий выбрал дерево сам и не передал. PATH, HOME и локаль — общий мир, их не снимать.
