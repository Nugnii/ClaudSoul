---
name: "Условие коммита живёт в команде, а не в голове"
description: "Состав и условие коммита решаются состоянием индекса, кодом набора и кодом шага правки; когда они читаются глазами или предполагаются, коммит уходит не тем и не тогда — шесть случаев за три дня"
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-13
source_cases: [case-2026-09-12-conditional-commit-add-inside-branch-left-docs-behind.md, case-2026-09-13-commit-without-pathspec-took-the-whole-index.md, case-2026-09-13-commit-condition-read-with-eyes-not-code.md, case-2026-09-13-commit-shipped-after-edit-script-failed.md, case-2026-09-13-refresh-touched-files-outside-the-commit-pathspec.md]
source_session: ""
status: active
domain: [git, agent_design, ci_cd]
situation: "коммит в конце длинной команды или после генераторов и наборов"
trigger: "условие или состав коммита не выражены кодом в той же команде (нет &&/if/pathspec, перечень путей из памяти)"
stakes: "коммит с чужим составом или при красном наборе; история лжёт; следующий коммит чинит предыдущий; красный CI"
actors: [agent]
environment: "git в цепочках агента: python-правки, docs-refresh, run_all --changed, git add/commit"
circumstances: "adc0129, dfc9479, 2ccd3da, c525ee7, 0a65ace, 7f64003 — 11–13 сентября 2026"
purpose: "learning"
method: "каждый шаг цепочки заканчивается кодом; коммит внутри if по коду набора; git commit -- <пути> с перечнем из вывода генераторов; git diff --cached --stat перед коммитом"
tags: [commit, gate, pathspec, pipeline, index]
need: avoid_regression
urgency: when_relevant
availability: unique
related: [pattern-piecewise-day-full-suite-first-on-ci, pattern-verification-frame-mismatch]
edges: [specializes: pattern-piecewise-day-full-suite-first-on-ci]
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

Состав и условие коммита — это состояние индекса, код набора и код шага правки; они читаются командой, а не глазами.

**Why:** шесть случаев за три дня (11–13 сентября 2026), одно устройство: `git add` внутри ветки оставил документы вне индекса (adc0129); `git commit -F -` без путей забрал весь индекс (dfc9479); коммит в одной строке с чтением итога набора ушёл при красном наборе (2ccd3da чинил); перечень путей из памяти не включил файлы, тронутые `docs-refresh run` (c525ee7, 0a65ace); коммит после упавшего шага python-правки при обещающей строке doc-state (7f64003). Во всех шести условие или состав коммита существовали в голове — и не существовали в команде.

**How to apply:** правка `|| exit 1`; тесты `|| exit 1`; `SUITE_RC=$?` и коммит внутри `if [ "$SUITE_RC" -eq 0 ]`; `git add <перечень> && git commit -- <перечень>`, перечень пополняется выводом генераторов; `git diff --cached --stat` перед коммитом в той же команде. Заведён паттерном по решению владельца 13 сентября 2026 (tier 2, триггеры смежные).

**Limitations:** к интерактивному коммиту одного файла после осмотра diff не относится.
