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
last_confirmed: 2026-09-13
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
provenance_log: []
fragile: false
blocker: false
---

Тест с предметом «дерево целиком» регистрируется в реестре «всегда» выборочного прогона тем же коммитом, что и сам тест; иначе первый красный придёт из CI.

**Why:** 13 сентября 2026 дважды: `test_lib_prefix_guard` (CI beac9d6) и `test_md_trailing_newline` (CI 006a06d) — оба сканеры дерева, оба не выбраны прогоном по правкам, оба зелёные локально и красные в CI. Реестр требует дату наблюдения — строка без даты отвергнута `test_run_all_changed` (566960e). Родня `pattern-guard-scope-blindness`: область выборочного прогона (правки) уже предмета сканера (дерево). Заведён паттерном по решению владельца 13 сентября 2026 (tier 2).

**How to apply:** в коммит с новым `test_*.sh`, обходящим дерево, входит строка `always-run.tsv` с причиной и датой; проверка формы — `test_run_all_changed` T2.

**Limitations:** тесты одного механизма выбираются индексом связей и в реестр не заводятся.
