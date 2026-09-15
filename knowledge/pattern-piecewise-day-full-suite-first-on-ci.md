---
name: "День по частям: полный набор впервые запускает CI"
description: "Партии коммитятся с выборочными зелёными прогонами, полный набор на чистом дереве не гоняется ни разу, и первым полным прогоном дня становится CI — красный по тому, что выпало между партиями"
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-13
source_cases: [case-2026-08-31-ci-first-full-run-of-piecewise-day.md, case-2026-09-12-conditional-commit-add-inside-branch-left-docs-behind.md]
source_session: ""
status: active
domain: [git, ci_cd]
situation: "день из нескольких партий с выборочными прогонами"
trigger: "коммит партии после зелёного выборочного набора"
stakes: "красный CI своего коммита, ложная картина у читателя документов"
actors: [agent, ci]
environment: "local_dev, ci_cd"
circumstances: "полный набор дорог, партии коммитятся по мере готовности"
purpose: "hotfix"
method: selective_test_runs
tags: [CI, piecewise, git_add]
need: avoid_regression
urgency: immediate
availability: common_knowledge
related: [case-2026-08-27-claimed-closure-vs-counted-closure]
edges: []
origin: solo
preceded_artifact: n/a
promotion_tier: 2
scope: universal
origin_domain: git
modification_history: []
provenance_log: []
fragile: false
blocker: false
---

Выборочный прогон партии не заменяет полного прогона на чистом дереве; перед последним push дня (или после каждой партии, чей коммит собирался не с первой попытки) гоняется полный набор либо хотя бы `git status` читается целиком и сверяется с составом коммита.

**Why:** 31 августа 2026 день коммитился частями со своими зелёными тестами, полный набор не запускался, CI покраснел первым. 12 сентября 2026 условный коммит из двух попыток оставил документы предыдущей партии в рабочем дереве (`git add` стоял внутри ветки первой попытки); локальные выборочные прогоны были зелёными, CI покраснел на числах документов. Оба раза дефект жил МЕЖДУ партиями, где выборка не смотрит.

**How to apply:** `git add` нужного — первым безусловным шагом, условие решает только про `git commit`; после красной попытки коммита — `git status --short` целиком перед повтором; последний push дня — после полного набора либо после явного решения владельца его пропустить. Страж CHANGELOG в момент коммита («код в staged, CHANGELOG не добавлен») — повод остановиться.

**Limitations:** правило о ГРАНИЦЕ партий, а не о том, чтобы гонять полный набор на каждый коммит — это измеренно дорого (12 минут на прогон).
