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
last_confirmed: 2026-08-08
source_cases:
  - case-2026-06-21-dedup-by-content-not-index-during-parallel-sessions.md
  - case-2026-07-06-parallel-producers-cross-scan.md
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

modification_history:
  - date: 2026-08-08
    kind: reinforced
    reason: "шесть параллельных экстракторов знаний независимо принесли одно и то же обсуждение двумя путями (черновик + SESSION.md)"
    trigger_case: case-2026-08-08-ablation-by-symmetric-shadows.md
fragile: false
blocker: false

related:
  - case-2026-06-21-dedup-by-content-not-index-during-parallel-sessions.md
  - case-2026-07-06-parallel-producers-cross-scan.md
  - pattern-inside-out-blindness.md
edges:
  - specializes: pattern-inside-out-blindness.md
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
