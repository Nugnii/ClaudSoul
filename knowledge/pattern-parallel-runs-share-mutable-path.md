---
name: pattern-parallel-runs-share-mutable-path
description: "Параллельные прогоны (тесты, фаззы, пробы) читают или пишут один и тот же изменяемый путь — каталог, файл входа, тестовую базу; результат одного портит другой молча, и прогон даёт мнимый регресс или мнимую чистоту, а одиночный перезапуск чист"
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-30
source_cases:
  - case-2026-10-01-shared-test-db-read-as-flake.md
  - case-2026-10-30-parallel-probes-share-mutable-input.md
source_session: ""
status: active

domain: [testing, concurrency, measurement, multi_agent]
situation: "несколько прогонов одного прибора или набора идут одновременно — ради скорости или из соседних сессий"
trigger: "фоновый запуск N копий прогона либо красные, которые зелены одиночным прогоном"
stakes: "мнимый регресс тянет лишний круг починки и ложный пункт долга («флейк»); мнимая чистота пропускает дефект в коммит"
actors: [agent, background_jobs, parallel_sessions]
environment: "scratchpad, worktree, общая тестовая база, фоновые задачи"
circumstances: "общий путь не виден в команде запуска: он зашит в приборе (каталог по умолчанию, имя базы, файл входа), а судимый файл меняют во время прогона"
purpose: "показание прогона относится к своему входу, а не к сумме соседних"
method: "у каждого прогона свой каталог и свой вход (mktemp -d, своя база); судимый файл копируется до старта и не меняется до конца; расхождение параллельного прогона перепроверяется одиночным"
tags: [parallel-runs, shared-state, isolation, false-regression, flake]
volatile_anchors: []
self_altering: ""
outcome_signals: ["зелёный одиночно", "перезапуск чистый", "флейк"]

need: avoid_regression
urgency: before_action
availability: has_alternatives

related: [pattern-parallel-producers-blind-to-each-other, pattern-measurement-validity]
edges:
  - similar_to: pattern-parallel-producers-blind-to-each-other
  - specializes: pattern-measurement-validity

modification_history: []
provenance_log: []
fragile: false

origin: solo
preceded_artifact: "no"
promotion_tier: 2
scope: universal
origin_domain: testing
---

Параллельные прогоны не делят изменяемых путей. Каждому — свой каталог, свой вход и своя база; судимый файл копируется
до старта и до конца прогона не меняется. Красное, которое зелено одиночным прогоном, сперва проверяется на общий путь,
а потом уже называется флейком или регрессом.

**Why:** два случая. 1 октября 2026, ProjectA: вторая сессия получила 17–23 красных «на чистом дереве». Агенты первой сессии
гоняли vitest на тех же тестовых базах, и `cleanDatabase` соседа вытирал фикстуры (`case-2026-10-01-shared-test-db-read-as-flake`).
30 октября 2026, ClaudSoul, D1042: свои параллельные фаззы делили файл входа и каталог, куда новую редакцию библиотеки
положили после старта. Получился мнимый регресс на сиде 31, а перезапуск в своём каталоге прошёл чисто
(`case-2026-10-30-parallel-probes-share-mutable-input`).

**How to apply:** признак — фоновый запуск нескольких копий прибора либо «красный только в общем прогоне». До запуска
нужно назвать пути, которые прибор пишет и читает (каталог по умолчанию, имя базы, файл входа), и развести их.

**Limitations:** если общий ресурс и есть предмет проверки (гонка двух писателей), развести его нельзя. Тогда в отчёте
названо, что прогоны делили ресурс намеренно.
