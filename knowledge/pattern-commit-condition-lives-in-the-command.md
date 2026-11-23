---
name: "Условие коммита живёт в команде, а не в голове"
description: "Состав и условие коммита решаются состоянием индекса, кодом набора и кодом шага правки; когда они читаются глазами или предполагаются, коммит уходит не тем и не тогда — шесть случаев за три дня"
type: pattern
outcome: error
confidence: 3
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-22
source_cases: [case-2026-09-12-conditional-commit-add-inside-branch-left-docs-behind.md, case-2026-09-13-commit-without-pathspec-took-the-whole-index.md, case-2026-09-13-commit-condition-read-with-eyes-not-code.md, case-2026-09-13-commit-shipped-after-edit-script-failed.md, case-2026-09-13-refresh-touched-files-outside-the-commit-pathspec.md, case-2026-09-19-add-by-directory-swept-in-what-the-owner-kept-out.md, case-2026-10-11-git-state-assumed-after-chained-command-three-slips.md, case-2026-10-11-eslint-tail-blank-and-chained-commit.md, case-2026-10-18-add-all-swept-parallel-session-wip.md]
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
edges: [specializes: pattern-piecewise-day-full-suite-first-on-ci, similar_to: case-2026-11-08-edit-and-commit-in-one-parallel-batch.md]
origin: solo
preceded_artifact: n/a
promotion_tier: 2
scope: universal
origin_domain: git
modification_history:
  - date: 2026-10-11
    kind: scope_widened
    reason: "условие коммита — не только состав индекса и код набора, но и ВЕТКА: отменённый стражем git switch -c оставил коммиты в main"
    trigger_case: case-2026-10-11-git-state-assumed-after-chained-command-three-slips.md
provenance_log:
  - date: 2026-09-19
    kind: reinforced
    reason: "git add по каталогу загрёб шесть неотслеживаемых документов: ограничение жило словами, команда шаблоном"
    trigger_case: case-2026-09-19-add-by-directory-swept-in-what-the-owner-kept-out
    session: ""
  - date: 2026-10-08
    kind: reinforced
    reason: "2026-10-08 ProjectA: python-правка пометок растяжки упала на assert (заголовок теста с обратной кавычкой), а следующая строка (vitest; git add && commit) шла через перевод строки без &&/set -e — в ветку ушли 3 теста без it.fails; исправлено amend, дальше set -e и проверка «N expected fail» перед коммитом. Брат: «! grep» по несуществующим файлам в «Проверке» пункта = ложный зелёный, закрыт test -f"
    session: ""
  - date: 2026-10-11
    kind: reinforced
    reason: "ProjectA 2026-10-11: ветка коммита (отменённый git switch -c) и состав индекса (git add с несуществующим путём и 2>/dev/null) жили в голове — 2 коммита в main, 1 коммит со старой версией теста"
    trigger_case: case-2026-10-11-git-state-assumed-after-chained-command-three-slips.md
    session: ""
  - date: 2026-10-12
    kind: reinforced
    reason: "цепочка eslint …; git commit закоммитила тест с ошибкой no-unused-vars в ветке B321"
    trigger_case: case-2026-10-11-eslint-tail-blank-and-chained-commit.md
    session: ""
  - date: 2026-10-18
    kind: reinforced
    reason: "Site_ProjectA 2026-10-18: git add -A в копии с параллельными сессиями забрал чужие 12 файлов в коммит «выкаченного состояния» — условие «только свои правки» жило в голове, а команда брала всё"
    trigger_case: case-2026-10-18-add-all-swept-parallel-session-wip.md
    session: ""
  - date: 2026-11-18
    kind: reinforced
    reason: "18.11.2026, ClaudSoul D1324: вставка записи в CHANGELOG упала ассертом, а коммит шёл в той же команде не через && от шага — коммит 3d7dd519 ушёл без записи журнала, дописана 53e1da6b; знание было в контексте и не применено"
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "ProjectA 2026-11-22: git commit отказан стражем merge-root-gate, цепочка через «;» дошла до архиватора и git add BACKLOG*; git commit без pathspec — коммит af28388b0 «chore(backlog)» унёс всю починку B731 мимо стража; снято git reset --soft"
    session: ""
fragile: false
blocker: false
instrument_verdict: covered   # D1298, по формам класса: ветка — отказ hooks/denied-branch-commit-guard.sh; состав индекса — отказ hooks/git-add-sweep-guard.sh; набор по изменённым (D528) — подсказка hooks/affected-tests-reminder.sh; «шаг; git commit» (2ccd3da, 7f64003, ProjectA 8 и 12 октября; 93 из 5 829 коммитов корпуса после шага-условия) и коммит в пакете с правкой, которая не легла (D1248; 18 в корпусе) — подсказка hooks/commit-condition-notice.sh. Отказ для двух последних невозможен или неточен: пакет пишется на диск после своих хуков (замер 15 ноября 2026), а «шаг; коммит» ломается, только если шаг упал
instrument_assessed: 2026-11-15
---

Состав и условие коммита — это состояние индекса, код набора и код шага правки; они читаются командой, а не глазами.

**Why:** шесть случаев за три дня (11–13 сентября 2026), одно устройство: `git add` внутри ветки оставил документы вне индекса (adc0129); `git commit -F -` без путей забрал весь индекс (dfc9479); коммит в одной строке с чтением итога набора ушёл при красном наборе (2ccd3da чинил); перечень путей из памяти не включил файлы, тронутые `docs-refresh run` (c525ee7, 0a65ace); коммит после упавшего шага python-правки при обещающей строке doc-state (7f64003). Во всех шести условие или состав коммита существовали в голове — и не существовали в команде.

**How to apply:** правка `|| exit 1`; тесты `|| exit 1`; `SUITE_RC=$?` и коммит внутри `if [ "$SUITE_RC" -eq 0 ]`; `git add <перечень> && git commit -- <перечень>`, перечень пополняется выводом генераторов; `git diff --cached --stat` перед коммитом в той же команде. Ветка — тоже условие: `[ "$(git branch --show-current)" = <ветка> ] &&` перед коммитом; после отклонённого стражем вызова перечитать, какие шаги (в том числе `git switch -c`) не исполнились (2026-10-11, ProjectA). Заведён паттерном по решению владельца 13 сентября 2026 (tier 2, триггеры смежные).

**Limitations:** к интерактивному коммиту одного файла после осмотра diff не относится.
