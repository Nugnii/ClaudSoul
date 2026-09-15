---
name: "Мутация, которая не исполнялась, ничего не доказывает"
description: "Зелёная мутационная проверка читается как сила теста, пока не показано, что мутация была применена и исполнена под тестом; три кейса — замена не применилась, мутация ничего не меняет, мутант вне исполняемого пути"
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-13
source_cases: [case-2026-08-22-unapplied-mutation-reads-as-proof.md, case-2026-09-07-mutation-that-changes-nothing-proves-nothing.md, case-2026-09-12-mutant-outside-executed-path-proves-nothing.md]
source_session: ""
status: active
domain: [testing, verification]
situation: "проверка различающей способности теста мутантом"
trigger: "мутант прошёл зелёным"
stakes: "ложная уверенность в тесте: слабость читается как сила"
actors: [agent]
environment: local_dev
circumstances: "мутация делается строковой заменой или в копии дерева"
purpose: "learning"
method: mutation_testing
tags: [mutation, negative_control]
need: improve_quality
urgency: when_relevant
availability: has_alternatives
related: [pattern-discrimination-not-demonstrated]
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

Зелёный мутант доказывает слабость теста только после того, как показано, что мутация (1) применилась к файлу, (2) изменила поведение и (3) исполнялась на пути, который тест реально проходит. Без этих трёх проверок зелёный мутант — не данные.

**Why:** три кейса с разными механизмами одного исхода: 22 августа 2026 строковая замена не нашла строку и молча не применилась; 7 сентября 2026 мутация не меняла поведения (три раза за сутки, каждый раз по своей причине); 12 сентября 2026 мутант стоял внутри аргумента, который поддельная утилита под тестом не исполняет. Во всех трёх «прошёл мутант» читалось как утверждение о тесте.

**How to apply:** перед чтением зелёного мутанта — три вопроса с адресами: диффом показать, что файл изменился; прогоном показать, что мутант отвечает иначе, чем оригинал, на том же входе; назвать путь исполнения под тестом (что подделано, что исполняется) и убедиться, что мутированная строка на нём. Годный мутант краснит тест; зелёный годный мутант — находка о тесте; зелёный негодный — находка о мутанте.

**Limitations:** не заменяет положительный контроль теста (нога, красная на настоящем дефекте) — мутант проверяет различающую способность, не полноту.
