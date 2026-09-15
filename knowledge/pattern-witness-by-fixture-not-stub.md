---
name: "Свидетель результата — фикстурой с одним дефектом, а не заглушкой"
description: "Заглушка exit 0 доказывает, что инструмент жив; что он считает объявленное, доказывает только свидетель на подложенном мире с одним известным дефектом — именно такие свидетели находят дефекты инструментов"
type: pattern
outcome: error
confidence: 1
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-13
source_cases: [case-2026-09-12-witness-by-fixture-finds-what-stub-cannot.md]
source_session: ""
status: active
domain: [testing, verification, hooks]
situation: "проверка контракта «Проверка результата» инструмента"
trigger: "у инструмента есть объявленная проверка, но нет свидетеля, красного на неверном счёте"
stakes: "зелёная проверка при неверном счёте: замер говорит о мире, которого не видел"
actors: [agent]
environment: "local_dev, ci_cd"
circumstances: "прибор-сверщик различает лишь мёртв/жив"
purpose: "learning"
method: fixture_test_from_declared_command
tags: [witness, fixture, stub, D282]
need: avoid_regression
urgency: when_relevant
availability: unique
related: [pattern-discrimination-not-demonstrated, pattern-fixture-form-not-taken-from-the-world, pattern-check-judges-method-not-result]
edges: [specializes: pattern-discrimination-not-demonstrated]
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

Свидетель результата инструмента строится ФИКСТУРОЙ: команда берётся из шапки инструмента и исполняется на подложенном мире, где известен ровно один дефект; на каждую сторону результата — нога «порча → красный с названной находкой» и нога «чистый мир → зелёный со знаменателем». Заглушка `exit 0` — только нижняя граница «жив».

**Why:** 12 сентября 2026 очередь инструментов без свидетеля закрыта шестнадцатью фикстурными свидетелями; два из них в первый прогон нашли дефекты инструментов, невидимые заглушке по построению (`knowledge-coverage.sh` — родитель = сам себе; `ab-authorization-replay.sh` — пустая выборка как один транскрипт, «Не измеряли» с кодом 0). Один кейс impact 4 — паттерн заведён кандидатом по решению владельца и ждёт подтверждения следующим случаем.

**How to apply:** мир подкладывается через рычаг пути (STATE_DIR, LESSONS_DIR, HOME, CLAUDE_HOME, корпус) либо подделку внешней утилиты в урезанном PATH со всеми её зависимостями; различающая способность показывается мутантом в копии дерева до коммита; форма фикстуры берётся из мира.

**Limitations:** фикстура крошечная — «считает мимо на большом дереве» не ловится; свидетель судит одну сторону за ногу, полноту сторон обеспечивает чтение инструмента, а не прибор.
