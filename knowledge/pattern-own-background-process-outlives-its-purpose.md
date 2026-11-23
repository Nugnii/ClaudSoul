---
name: pattern-own-background-process-outlives-its-purpose
description: "Процесс, поднятый агентом ради проверки (dev-сервер, цикл ожидания, фоновый прогон), переживает проверку: гашение отложено на «следующий шаг», а цикл ждёт только метку успеха. Три замечания владельца за четыре дня (ProjectA, 12/14/15.11.2026); правило в памяти проекта не удержало, рецепт с ловушкой сам сломался"
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-15
source_cases: [case-2026-11-12-own-dev-servers-left-running.md, case-2026-11-14-dev-server-outlived-check-second-time.md, case-2026-11-15-wait-loop-on-killed-producer-orphaned.md, case-2026-11-14-trap-pkill-kills-foreground-command.md]
source_session: ""
status: active
domain: [process_hygiene, dev-environment, background-tasks, agent_design]
situation: "агент поднимает фоновый процесс ради проверки: dev-сервер, цикл ожидания, долгий прогон"
trigger: "проверка закончилась (успехом, отказом или убийством продюсера), а процесс запущен отдельной задачей"
stakes: "trust_erosion; занятые порты и память; владелец сам ищет висящее"
actors: [agent, owner]
environment: "local_dev, фоновые задачи харнесса"
circumstances: "правило «свой сервер гашу сам» записано в памяти проекта текстом"
purpose: "проверить правку в браузере или прогоном"
method: "run_in_background отдельной командой, гашение — отдельным шагом «потом»"
tags: [dev-server, next-dev, orphan, wait-loop, run_in_background, ProjectA]
need: "avoid_regression"
urgency: "when_relevant"
availability: "has_alternatives"
related: [feedback_stop_own_servers]
edges:
  - similar_to: case-2026-09-13-wait-loop-matched-itself-and-never-exited.md
  - similar_to: pattern-process-check-sees-itself.md
  - similar_to: pattern-wait-without-own-deadline-inherits-outer-limit.md
origin: co-cognition
trigger_for_co_cognition: "замечания владельца 12.11 («ты не стопоришь сервера которые поднимаешь»), 14.11 («9 часов 40 минут уже висит твой таск»), 15.11 («зависло 2 процесса в фоне»)"
preceded_artifact: n/a
promotion_tier: 2
scope: universal
origin_domain: process_hygiene
escalation_threshold: 5
escalation_hint: "Фоновая проверка на Stop: задачи сессии без строки выхода и порты LISTEN, поднятые командами сессии, — строкой в очередь напоминаний. Предшественник — hooks/mcp-orphan-reap.sh (SessionEnd, сироты MCP по смерти родителя): признак другой, устройство «снять своё по признаку, чужое не трогать» то же"
escalation_mechanism_needed: true
---

Процесс, поднятый ради проверки, живёт ровно столько, сколько команда, которая его использует: подъём, ожидание готовности,
прогон и гашение — одна команда с ловушкой выхода; условие выхода цикла ожидания покрывает и неуспех продюсера (убит, упал),
а не только метку успеха. Итог хода называет свои живые процессы.

**Why:** три замечания владельца за четыре дня в ProjectA_NEW — 12 ноября («ты не стопоришь сервера которые поднимаешь. вон и сейчас
висит»), 14 ноября («9 часов 40 минут уже висит твой таск» — `next dev -p 3100` отдельной фоновой задачей), 15 ноября
(«зависло 2 процесса в фоне» — два цикла `until grep -q "Test Files"` по выводу прогона, убитого кодом 144). Правило лежало
в памяти проекта после первого раза и не удержало второй; рецепт с ловушкой, дописанный после второго, сам сломался:
`pkill -f "next dev -p 3100"` в ловушке убил команду переднего плана, в тексте которой стоял тот же образец
(pattern-process-check-sees-itself). Третий случай — другая форма того же рода: не сервер, а цикл ожидания.

**How to apply:** перед `run_in_background` назвать, какая команда погасит процесс и при каком исходе; если ответ «следующий
шаг» — это и есть дефект. Цикл ожидания: выход по метке успеха ИЛИ по признаку конца продюсера (строка выхода харнесса, `kill -0`).
Гасить по PID, а не по образцу текста команды.

**Limitations:** чужие процессы (не этой сессией запущенные — время старта, `cwd`) не трогать без слова владельца.
Долгоживущий сервер, который владелец просил оставить, — не этот случай.

**Эскалация.** Уровень 1 (текст в памяти проекта) не удержал трижды; по решению владельца 17 ноября 2026 заведён пункт долга
ClaudSoul на механизм (см. `escalation_hint`).
