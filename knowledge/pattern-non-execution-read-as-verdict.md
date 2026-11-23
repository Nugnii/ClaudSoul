---
name: "Неисполнение читается как вердикт"
description: "Канал, который несёт и «не исполнилось», и «исполнилось, ответ — нет» (код возврата, красный тест, пустая сводка), читают как вердикт о предмете. Три носителя в двух проектах: код возврата зависшей команды, 19 оборвавшихся агентов как «0 находок», красный тест за 1–5 мс при остановленной базе"
type: pattern
outcome: error
confidence: 3
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-28
source_cases: [case-2026-09-13-execution-failure-read-as-verdict.md, case-2026-09-14-failed-executors-read-as-zero-findings.md, case-2026-10-04-red-from-blindness-read-as-defect.md, case-2026-10-21-missing-log-line-fed-by-the-same-channel.md, case-2026-10-22-guard-fired-but-hint-never-delivered.md, case-2026-10-28-tool-without-input-answered-clean.md]
source_session: ""
status: active
domain: [testing, verification, tooling, orchestration]
situation: "механизм выносит суждение о предмете по каналу, который несёт и срыв исполнения, и честный отрицательный ответ"
trigger: "красный результат, ненулевой код или пустая сводка пришли тем же значением, что и вердикт, и прочитаны как вердикт"
stakes: "починка предмета, которого сбой не касался; ложное «чисто» или ложное «красно» о непроверенном"
actors: [agent, test_runner, subagents]
environment: multi_project
circumstances: "исполнение могло сорваться до предмета: таймаут, остановленная среда, оборванный исполнитель, падение рамки вызова"
purpose: "avoid_regression"
method: "развести два значения канала до чтения вердикта: неисполнение получает свой код или пометку и считается отдельно; читатель сперва проверяет, что исполнение было"
tags: [execution_failure, verdict, exit_code, silent_zero, test_duration, fail_open]
need: avoid_regression
urgency: when_relevant
availability: unique
related: [pattern-discrimination-not-demonstrated, pattern-check-judges-method-not-result, pattern-frame-without-a-positive-control]
edges: []
origin: solo
preceded_artifact: "n/a"
promotion_tier: 2
scope: universal
origin_domain: testing
modification_history: []
provenance_log:
  - date: 2026-10-05
    kind: reinforced
    reason: "13 сентября 2026, ClaudSoul: код возврата зависшей и незапустившейся команды читался как красная проверка, предмет никто не проверял"
    trigger_case: case-2026-09-13-execution-failure-read-as-verdict.md
    session: ""
  - date: 2026-10-05
    kind: reinforced
    reason: "14 сентября 2026, ClaudSoul: 19 оборвавшихся агентов из 32 прочитаны сводкой как 0 находок"
    trigger_case: case-2026-09-14-failed-executors-read-as-zero-findings.md
    session: ""
  - date: 2026-10-05
    kind: reinforced
    reason: "4 октября 2026, ProjectA: красный тест за 1–5 мс при остановленном Docker прочитан как дефект"
    trigger_case: case-2026-10-04-red-from-blindness-read-as-defect.md
    session: ""
  - date: 2026-10-05
    kind: reinforced
    reason: "5 октября, CI 37370842884 для 9aed5e9e: статус failure, а обе задачи отменены — «job was not acquired by Runner» 15 минут, ни один тест не исполнился; сигнал ci-red прочитал неисполнение как красный вердикт"
    session: ""
  - date: 2026-10-21
    kind: reinforced
    reason: "blalb 2026-10-21: строка журнала писалась из того же уведомления, что и значок; недоставка (AppKit suspended) прочитана как «события не было»"
    trigger_case: case-2026-10-21-missing-log-line-fed-by-the-same-channel.md
    session: ""
  - date: 2026-10-22
    kind: reinforced
    reason: "22.10 D1026: диспетчер записи командой прочитал неразбираемый ответ стража как «пройдено», а разбор D1024 — след срабатывания как «подсказку проигнорировали»"
    trigger_case: case-2026-10-22-guard-fired-but-hint-never-delivered.md
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "реестр родов без git: «носителей 0» кодом 0 — отказ источника прочитан как вердикт (D1168)"
    trigger_case: case-2026-10-28-tool-without-input-answered-clean.md
    session: ""
fragile: false
instrument_verdict: inexpressible   # срыв исполнения и честное «нет» приходят одним значением канала и различимы лишь при исполнении (корень R6, проба по поведению); статическая форма `|| echo 0` — 74 совпадения при 0 из 5 носителей (ROOTS.md, R6)
instrument_assessed: 2026-11-10
---

# Неисполнение читается как вердикт

Канал, который несёт и «не исполнилось», и «исполнилось, ответ — нет» (код возврата, красный тест, пустая сводка), разводится на два значения ДО чтения вердикта: неисполнение получает свой код или пометку и считается отдельно. Читатель сперва проверяет, что исполнение было (время, первая строка ошибки, число запустившихся), и только потом читает ответ.

**Why:** 13 сентября 2026 (ClaudSoul, `case-2026-09-13-execution-failure-read-as-verdict`) код возврата зависшей и незапустившейся команды читался как «проверка красная», хотя предмет никто не проверял. 14 сентября 2026 (ClaudSoul, `case-2026-09-14-failed-executors-read-as-zero-findings`) 19 агентов из 32 оборвались на лимите модели, а сводка превратила их отсутствие в «0 находок». 4 октября 2026 (ProjectA, `case-2026-10-04-red-from-blindness-read-as-defect`) тесты краснели за 1–5 мс при остановленном Docker, и ошибка подключения к базе пришла тем же красным, что вердикт «дефект».

**How to apply:** перед чтением ответа спроси, какие ещё состояния приходят тем же значением: таймаут, команда не найдена (127), падение оболочки, остановленная среда, оборванный исполнитель. Подай в ту же рамку заведомо зелёный вход: не зеленеет — рамка судит себя, а не предмет. В сводке печатай рядом с результатом три числа: запущено, исполнилось, сорвалось; при ненулевом третьем результат называется «не измерено», а не итогом. У красного теста смотри время и первую строку ошибки: ошибка подключения или инициализации, либо время короче, чем нужно, чтобы дойти до предмета, значит «не исполнено» — подними среду и перемерь.

**Limitations:** разводить стоит там, где исходы лечатся разным: если и «красное», и «не исполнено» ведут к одному действию (не закрывать, не переносить), достаточно развести сообщение, а не поведение. Быстрый красный бывает и настоящим, например тест, падающий на первой же проверке без всякой среды: время и первая строка ошибки — признаки, а не доказательство, решает повтор с поднятой средой.
