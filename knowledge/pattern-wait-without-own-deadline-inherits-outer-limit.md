---
name: pattern-wait-without-own-deadline-inherits-outer-limit
description: "Ожидание внутри долгого прогона без собственного срока (locator.evaluate с actionTimeout 0, networkidle на странице с SSE, until-цикл по метке успеха) наследует предел всего прогона: часы простоя без строки в журнале либо вечный цикл. Четыре случая за пять дней (ProjectA, 12–16.11.2026)"
type: pattern
outcome: error
confidence: 3
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-22
source_cases: [case-2026-11-14-locator-wait-without-deadline-hangs-run.md, case-2026-11-12-networkidle-never-with-sse.md, case-2026-11-16-networkidle-never-settles-sse.md, case-2026-11-15-wait-loop-on-killed-producer-orphaned.md, case-2026-11-17-networkidle-carried-over-from-login-recipe.md, case-2026-11-18-networkidle-never-on-sse-pages.md]
source_session: ""
status: active
domain: [testing, playwright, long-runs, shell]
situation: "долгий прогон (обход интерфейса, набор тестов, фоновый цикл) содержит ожидания"
trigger: "ожидание элемента, состояния сети или метки в выводе без собственного срока"
stakes: "часы простоя без строки в журнале; прогон «идёт», а работы нет"
actors: [agent, system]
environment: "local_dev, Playwright, фоновые задачи"
circumstances: "общий предел прогона большой (минуты—часы); actionTimeout по умолчанию 0; страницы держат SSE"
purpose: "дождаться готовности перед замером"
method: "locator.evaluate, waitForLoadState('networkidle'), until grep -q <метка>"
tags: [timeout, deadline, networkidle, SSE, actionTimeout, until-loop, B645, B658]
need: "save_time"
urgency: "when_relevant"
availability: "has_alternatives"
related: []
edges:
  - similar_to: case-2026-09-13-wait-loop-matched-itself-and-never-exited.md
  - similar_to: pattern-progress-visibility-long-async.md
  - similar_to: pattern-own-background-process-outlives-its-purpose.md
origin: solo
preceded_artifact: n/a
promotion_tier: 2
scope: universal
origin_domain: testing
provenance_log:
  - date: 2026-11-22
    kind: reinforced
    reason: "/compile 22.11.2026, принято владельцем: повтор после записи паттерна, переносчик — рецепт входа без срока (88 строк в 80 файлах web/tests)"
    trigger_case: case-2026-11-17-networkidle-carried-over-from-login-recipe.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "/compile 22.11.2026, принято владельцем: повтор после записи паттерна, переносчик — рецепт входа без срока (88 строк в 80 файлах web/tests)"
    trigger_case: case-2026-11-18-networkidle-never-on-sse-pages.md
    session: ""
---

У каждого ожидания внутри долгого прогона — свой срок, меньше общего предела, и условие выхода, покрывающее неуспех
(элемент исчез, продюсер убит, поток событий не смолкает). Ожидание без своего срока наследует предел всего прогона.

**Why:** четыре случая за пять дней. 14 ноября (B645): `locator.evaluate` по области окна, которое кнопка «Отмена» закрыла, —
ожидание без срока (actionTimeout 0); четыре части обхода простояли 2 часа при пределе 4 ч, браузеры на 0,1 % процессора,
нашлось только по вопросу владельца «каков прогресс». 12 и 16 ноября: `waitForLoadState('networkidle')` на странице с открытым
потоком SSE не наступает — тест висел до общего предела 5 минут. Второй раз это случилось потому, что запись от 12 ноября
лежала черновиком в `_drafts/`, а их активатор знаний не читает. 15 ноября: `until grep -q "Test Files"` по выводу прогона,
убитого кодом 144, — метка успеха не появится никогда.

**How to apply:** в приборе долгого прогона — `actionTimeout`/`timeout` у каждого ожидания; вместо `networkidle` — ожидание
конкретного элемента или адреса; цикл ожидания выходит и по концу продюсера, и по своему сроку.
После записи паттерна случаев ещё два (17 и 18 ноября), и пришли они не через мысль «жду готовности страницы», а через
копию соседнего рецепта входа. Переносчик в ProjectA — `waitForLoadState("networkidle").catch(() => {})`: 88 строк в 80
файлах web/tests (замер 22.11.2026; со сроком — 47). Чинить носитель (общий помощник входа или правило линта), а не
каждую новую спеку: пока источник копий без срока, текст паттерна повтор не держит.

**Limitations:** короткий тест с маленьким общим пределом — потеря невелика, но правило то же.
