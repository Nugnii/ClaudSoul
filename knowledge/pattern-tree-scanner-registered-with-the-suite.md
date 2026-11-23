---
name: "Сканер дерева заводится в реестр «всегда» тем же коммитом"
description: "Тест, чей предмет — дерево целиком, не выбирается выборочным прогоном по правкам и краснеет впервые в CI; строка в реестре «всегда» с датой наблюдения — часть коммита, добавляющего сканер"
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-16
source_cases: [case-2026-09-13-tree-scanner-outside-the-selective-run.md]
source_session: ""
status: active
domain: [testing, ci_cd]
situation: "добавлен тест, обходящий всё дерево (git ls-files, все файлы класса)"
trigger: "выборочный прогон зелёный, CI красный на этом тесте"
stakes: "коммит-догонялка на каждом новом сканере; красный CI владельцу"
actors: [agent]
environment: "run_all --changed + always-run.tsv (имя ⇥ причина с датой)"
circumstances: "два случая за сутки 13 сентября 2026: beac9d6, 006a06d"
purpose: "learning"
method: "строка в always-run.tsv тем же коммитом; при красном CI на негонявшемся тесте первым делом проверить реестр"
tags: [always-run, selective-run, tree-scanner, ci]
need: avoid_regression
urgency: when_relevant
availability: unique
related: [pattern-guard-scope-blindness, pattern-piecewise-day-full-suite-first-on-ci]
edges: [specializes: pattern-guard-scope-blindness]
origin: solo
preceded_artifact: n/a
promotion_tier: 2
scope: universal
origin_domain: testing
modification_history: []
provenance_log:
  - date: 2026-09-19
    kind: reinforced
    reason: "инжект a3ce33b8:6526-6527 (13.09 11:10), через час :6956 дописана строка test_live_home_in_tests.sh в always-run.tsv с причиной и датой; обе половины одним коммитом 0b0f765. Различение проверено по 18 новым test_*.sh окна"
    session: ""
  - date: 2026-10-04
    kind: reinforced
    reason: "два сканера дерева вне реестра «всегда»: выборочный прогон зелёный, CI красный на 25436b4e; внесены в реестр"
    session: ""
  - date: 2026-10-19
    kind: reinforced
    reason: "test_completion_gate_open_items судит живой BACKLOG.md, но не стоял в always-run: выборочный прогон дважды не выбрал его, CI 39243993781 красный на открытом D1006 с зелёной «Проверкой»; добавлен в реестр вместе с test_backlog_item_shape"
    session: ""
  - date: 2026-11-16
    kind: reinforced
    reason: "test_reply_readers_registry судит живое дерево, но не стоял в always-run.tsv — новый читатель hooks/lib/rework_red_run.py (54fd56a2) прошёл выборочный прогон, покраснел только полный набор; внесён 3c3428ce"
    session: ""
fragile: false
blocker: false
instrument_verdict: inexpressible   # «тест обходит дерево» по форме цикла дал 1 из 10 (hooks/tests/always-run.tsv); роль теста решает только перечень форм, ложный отказ пришёлся бы на обычные тесты
instrument_assessed: 2026-11-10
---

Тест с предметом «дерево целиком» регистрируется в реестре «всегда» выборочного прогона тем же коммитом, что и сам тест; иначе первый красный придёт из CI.

**Why:** 13 сентября 2026 дважды: `test_lib_prefix_guard` (CI beac9d6) и `test_md_trailing_newline` (CI 006a06d) — оба сканеры дерева, оба не выбраны прогоном по правкам, оба зелёные локально и красные в CI. Реестр требует дату наблюдения — строка без даты отвергнута `test_run_all_changed` (566960e). Родня `pattern-guard-scope-blindness`: область выборочного прогона (правки) уже предмета сканера (дерево). Заведён паттерном по решению владельца 13 сентября 2026 (tier 2).

**How to apply:** в коммит с новым `test_*.sh`, обходящим дерево, входит строка `always-run.tsv` с причиной и датой; проверка формы — `test_run_all_changed` T2.

**Limitations:** тесты одного механизма выбираются индексом связей и в реестр не заводятся.
