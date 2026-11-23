---
name: Параллельные исполнители слепы друг к другу — пересечения ловит только скан по итогу
description: Когда несколько агентов или сессий параллельно производят однородный выход, они независимо создают одно и то же (обороты, синонимичные записи); увидеть это можно лишь проходом по содержимому всех результатов после схождения веток
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-20
source_cases:
  - case-2026-11-23-shared-index-staged-blob-replaced-by-parallel-add.md
  - case-2026-10-20-parallel-branches-took-the-same-root-number.md
  - case-2026-09-30-parallel-dispatch-by-item-not-by-root.md
  - case-2026-06-21-dedup-by-content-not-index-during-parallel-sessions.md
  - case-2026-07-06-parallel-producers-cross-scan.md
  - case-2026-10-01-shared-test-db-read-as-flake.md
source_session: ""
status: active

domain: [agent_design, workflow, multi_agent, knowledge_management, content]
situation: parallel_production_over_series
trigger: fanout_agents_or_sessions_producing_homogeneous_output
stakes: quality_degradation, base_pollution, repetition_visible_to_audience
actors: [agent, subagents, parallel_sessions]
environment: multi_agent_workflow, multi_session
circumstances: producers_share_instructions_but_not_output
purpose: batch_produce_or_edit_series
method: cross_scan_by_content_after_join

need: improve_quality
urgency: when_relevant
availability: unique

promotion_tier: 2
scope: universal
origin_domain: agent_design

modification_history: []
provenance_log:
  - date: 2026-08-08
    kind: reinforced
    reason: "шесть параллельных экстракторов знаний независимо принесли одно и то же обсуждение двумя путями (черновик + SESSION.md)"
    trigger_case: case-2026-08-08-ablation-by-symmetric-shadows.md
  - date: 2026-09-09
    kind: reinforced
    reason: "вторую сессию в том же репозитории обнаружил скан git status по итогу, а не заранее: 6 её коммитов и 7 незакоммиченных файлов появились незамеченными"
    session: ""
  - date: 2026-09-30
    kind: reinforced
    reason: "ProjectA 2026-09-30: параллельные ветки по пунктам с общим носителем корня (B67/B68 cabinet-guard.ts, B58/B69 sheets-mirror-service.ts) независимо переписали одно место, пересечение увидено только при слиянии"
    trigger_case: case-2026-09-30-parallel-dispatch-by-item-not-by-root.md
    session: ""
  - date: 2026-10-01
    kind: reinforced
    reason: "ProjectA 2026-10-01: сессия-2 и агенты сессии-1 на одних тестовых базах; взаимная очистка прочитана как флейк"
    trigger_case: case-2026-10-01-shared-test-db-read-as-flake.md
    session: ""
  - date: 2026-10-20
    kind: reinforced
    reason: "B501 и B494–B498: две параллельные ветки независимо взяли один номер корня R130; поймал git merge-tree"
    trigger_case: case-2026-10-20-parallel-branches-took-the-same-root-number.md
    session: ""
fragile: false
blocker: false

related:
  - case-2026-06-21-dedup-by-content-not-index-during-parallel-sessions.md
  - case-2026-07-06-parallel-producers-cross-scan.md
  - pattern-inside-out-blindness.md
edges:
  - specializes: pattern-inside-out-blindness.md
instrument_verdict: inexpressible   # исполнитель не видит выход соседа: пересечение видно только при сведении по содержимому, во входе одного вызова чужого нет
instrument_assessed: 2026-11-10
---

Когда несколько агентов или сессий параллельно производят **элементы одной серии** —
после схождения веток обязателен отдельный проход по содержимому всех результатов на
пересечения. Одинаковая инструкция плюс одна модель дают одинаковый выход, и ни один
исполнитель не видит этого по конструкции.

**Why:** два подтверждения в разных доменах.
(1) 2026-06-21, база знаний: параллельные сессии создали синонимичные записи под разными
именами; дедуп по индексу имён их не поймал, нужен был поиск по содержимому
([[case-2026-06-21-dedup-by-content-not-index-during-parallel-sessions]]).
(2) 2026-07-06, текстовый контент: шесть редакторов правили шесть постов параллельно и
независимо внесли одни и те же связки («И вот тут», «обиднее всего»); каждый пост
по отдельности стал лучше, серия — хуже. Поймано скан-проходом по всей пачке
([[case-2026-07-06-parallel-producers-cross-scan]]).

Общее: **пересечение существует только на уровне серии, а исполнитель видит лишь свой
элемент.** Проверка на уровне элемента бессильна по определению, сколько её ни усиливай.

**How to apply:** в любом `parallel(items.map(...))` над однородной серией — финальная
стадия: собрать все выходы, просканировать по содержимому (формулировки, приёмы, имена,
структуры), вычистить повторы. Реестр уже использованного, передаваемый следующим
исполнителям, снижает частоту, но проверку по итогу не отменяет.

**Limitations:** не применять к независимым артефактам без общего потребителя — повтор
оборота в двух не связанных проектах никого не задевает. На больших сериях сканировать по
ключевым местам (начала, концовки, заголовки), а не весь объём.
