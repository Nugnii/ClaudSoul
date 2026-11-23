---
name: "Единица покрытия проверки объявляется, иначе каждый раунд находит её заново"
description: "Проверка покрывает предмет в некоторой единице — вход, порог, условие предиката; пока единица не названа в методе, раунды критики закрывают уровень за уровнем, и один класс возвращается новыми входами"
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-30
source_cases: [case-2026-09-13-coverage-unit-named-only-in-round-three.md, case-2026-10-09-invariant-checked-inside-branches-not-at-command-entry.md, case-2026-10-30-declared-unit-executed-by-recall.md]
source_session: ""
status: active
domain: [testing, verification, agent_design]
situation: "проверка строится ногами по находкам критика или инцидентам"
trigger: "новый раунд или инцидент приносит тот же класс новыми входами"
stakes: "работа без остановки: 68 атак, три раунда по одному шву"
actors: [agent]
environment: "прожарка свидетелей D282; docs/development.md с правилом единицы"
circumstances: "раунд 1 — входы, 2 — пороги, 3 — условие предиката"
purpose: "learning"
method: "назвать единицу покрытия в методе проверки; раунд проверяет метод, а не входы; признак незакрытого корня — тот же класс новыми входами"
tags: [coverage, unit, predicate, rounds]
need: avoid_regression
urgency: when_relevant
availability: unique
related: [pattern-multi-round-adversarial-review, pattern-discrimination-not-demonstrated, pattern-witness-by-fixture-not-stub]
edges: [specializes: pattern-discrimination-not-demonstrated]
origin: solo
preceded_artifact: n/a
promotion_tier: 2
scope: universal
origin_domain: testing
modification_history: []
provenance_log:
  - date: 2026-09-27
    kind: reinforced
    reason: "2026-09-26/27 ProjectA: скептики B33/B34 не сходились (5→6→8, 3→4→4) — промпт перечислял весь автомат выплат/зеркала как область атак, каждый раунд приносил соседние старые дефекты; разделение «регрессия пункта / сосед» сняло блок с деплоя"
    session: ""
  - date: 2026-10-09
    kind: reinforced
    reason: "ProjectA R38: три круга — единица покрытия (вход команды) названа лишь на третьем"
    trigger_case: case-2026-10-09-invariant-checked-inside-branches-not-at-command-entry.md
    session: ""
  - date: 2026-10-30
    kind: reinforced
    reason: "D1073 и D1042, третьи круги 30.10: без прогона против объявленной единицы раунд скептика снова принёс класс — M1 в объявленной клетке"
    trigger_case: case-2026-10-30-declared-unit-executed-by-recall.md
    session: ""
fragile: false
blocker: false
---

Покрытие проверки объявляется единицей — вход, порог или условие предиката, — и записывается в метод; без этого каждый раунд критики закрывает лишь предыдущий уровень.

**Why:** 12–13 сентября 2026 три раунда прожарки свидетелей инструментов шли по одному шву: раунд 1 закрывал входы, раунд 2 — числовые пороги, раунд 3 назвал единицу (условие предиката). Признак был виден с раунда 2 — тот же класс приходил новыми входами, — но ответом были ноги, а не единица. Родня `pattern-multi-round-adversarial-review` (раунды приносят классы) и `pattern-discrimination-not-demonstrated` (различающая способность не показана): здесь не показана ЕДИНИЦА различения. Заведён паттерном по решению владельца 13 сентября 2026 при одном записанном кейсе с тремя проявлениями (tier 2).

**How to apply:** при первом же классе от критика спросить «какова единица покрытия?» и записать её в метод (docs/development.md, шапка теста); следующий раунд гонится против метода.

**Limitations:** одноразовые проверки без раундов — единица пишется в шапке и всё.
