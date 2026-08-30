---
name: Worker independence — скиллы standalone, без обратной связи
description: Скиллы-workers не знают о вызывающем, не ссылаются на координатора, вызываются напрямую
type: principle
outcome: success
confidence: 3
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
source_cases: []
status: active

domain: [skill_architecture, agent_systems, software_design]
situation: designing_skill_system
trigger: creating_or_refactoring_skill
stakes: coupling_creep
actors: [agent, skill_system]
environment: multi_skill_system
circumstances: skills_growing_beyond_5
purpose: maintainability
method: architectural_constraint
tags: [decoupling, standalone, contract, levnikolaevich]

need: avoid_coupling
urgency: when_relevant
availability: unique

critical_anchors: [trigger, situation]
weight_modifiers: ""

related: []
edges:
  - similar_to: levnikolaevich/skill_contract.md
---

Worker-скиллы должны быть standalone-invocable: без `**Parent:**`, `**Coordinator:**`, без обратных ссылок на вызывающего, без peer-worker зависимостей в контракте.

**Why:** В levnikolaevich/claude-code-skills (120+ скиллов) этот принцип — ключевой для масштабирования. Обратная связь (worker знает о координаторе) создаёт coupling, который ломается при реорганизации иерархии. Top-down ownership: координаторы знают workers, workers не знают координаторов.

**How to apply:** При создании или рефакторинге скиллов ClaudSoul — проверять: можно ли вызвать скилл напрямую без контекста координатора? Если нет — это нарушение принципа.

**Limitations:** Не применяется к координаторам (L1/L2), которым по определению нужно знать о workers. Не запрещает workers упоминать форматы ввода/вывода, совместимые с другими скиллами.
