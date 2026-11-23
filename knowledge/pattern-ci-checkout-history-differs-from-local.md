---
name: "Checkout CI не равен локальной истории git"
description: "Тест или прибор, читающий историю git, на раннере CI с checkout глубиной 1 судит усечённую историю: красен от среды (ProjectA, 12 прогонов подряд) или зелен от усечения (ClaudSoul, прибор не мог покраснеть)"
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-05
source_cases: [case-2026-09-19-shallow-checkout-passes-truncation-as-history.md, case-2026-10-04-shallow-ci-checkout-reds-history-test.md]
source_session: ""
status: active
domain: [ci_cd, git, testing]
situation: "тест или прибор читает историю git и исполняется на раннере CI"
trigger: "на CI красно или подозрительно зелено, а локально иначе"
stakes: "красный main неделями либо прибор, не способный покраснеть именно на CI"
actors: [agent, ci_runner]
environment: ci_cd
circumstances: "actions/checkout по умолчанию берёт дерево глубиной 1"
purpose: "avoid_regression"
method: "нужная глубина истории объявляется тестом и выдаётся workflow; прибор при усечённой истории отвечает «не измерено»"
tags: [shallow_clone, fetch_depth, github_actions, git_history, ci]
need: avoid_regression
urgency: when_relevant
availability: has_alternatives
related: [pattern-verification-frame-mismatch, case-2026-09-20-guard-alive-only-on-the-measuring-platform]
edges: []
origin: solo
preceded_artifact: "n/a"
promotion_tier: 2
scope: universal
origin_domain: ci_cd
modification_history: []
provenance_log:
  - date: 2026-10-05
    kind: reinforced
    reason: "19 сентября 2026, ClaudSoul: прибор уплывших адресов на дереве глубиной 1 не мог покраснеть, 0 против 11 на полной истории"
    trigger_case: case-2026-09-19-shallow-checkout-passes-truncation-as-history.md
    session: ""
  - date: 2026-10-05
    kind: reinforced
    reason: "4 октября 2026, ProjectA: git show на checkout глубиной 1 держал CI на main красным 12 прогонов, fetch-depth: 0 сделал его зелёным"
    trigger_case: case-2026-10-04-shallow-ci-checkout-reds-history-test.md
    session: ""
fragile: false
---

# Checkout CI не равен локальной истории git

Всё, что читает историю git (тест, прибор, сверка по коммитам), объявляет нужную глубину, и workflow CI её выдаёт: `fetch-depth: 0` либо нужное N. Пока не выдаёт, результат на раннере судит усечённую историю и бывает красным от среды либо зелёным от усечения. Разбор расхождения между CI и локальным прогоном начинается с глубины истории.

**Why:** 19 сентября 2026 (ClaudSoul, `case-2026-09-19-shallow-checkout-passes-truncation-as-history`) прибор «уплывших адресов» на дереве глубиной 1 не мог покраснеть: полная история давала 11 уплывших адресов, усечённая 0. 4 октября 2026 (ProjectA, `case-2026-10-04-shallow-ci-checkout-reds-history-test`) `git show <sha>` на таком checkout держал CI на main красным 12 прогонов, пока `fetch-depth: 0` (2bcf31b3) не сделал его зелёным.

**How to apply:** если в тесте или приборе есть `git show`, `git log`, `git blame`, `git describe`, `rev-list` или ссылка на прошлый коммит, проверь `fetch-depth` в workflow. Прибор, читающий историю, проверяет наличие `.git/shallow` и при усечении отвечает «не измерено», а не «чисто». Разбор красного или подозрительно зелёного CI начинай с вопроса, что на раннере отличается от локальной копии: глубина истории, файлы вне git, лимиты времени.

**Limitations:** `fetch-depth: 0` удлиняет checkout на большой истории; достаточно нужного N, если читается фиксированная глубина. Признак усечения — файл `.git/shallow`, а не «история из одного коммита». Тесту и прибору, читающим только рабочее дерево, правило не нужно.
