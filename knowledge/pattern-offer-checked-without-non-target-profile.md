---
name: pattern-offer-checked-without-non-target-profile
description: "Призыв и его условие-фильтр проверяются критиком без профилей клиента и не-клиента: критик судит хук и логику и не видит, что на призыв откликнутся нецелевые, а слово-фильтр («есть свой заказчик») примеряет на себя и не-клиент"
type: pattern
outcome: error
confidence: 1
impact: 3
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-11
source_cases: [case-2026-11-03-adversarial-check-without-customer-profile-misses-targeting.md, case-2026-11-03-cta-on-broad-topic-invites-non-target-free-help.md, case-2026-11-03-qualifier-word-non-target-also-claims.md]
source_session: ""
status: active
promotion_tier: 2
scope: universal

domain: [marketing, copywriting, adversarial_review]
situation: "сценарии, реклама, призыв к действию"
trigger: "призыв на тему шире клиента; фильтр в одно слово"
stakes: "поток бесплатных запросов от нецелевых, нагрузка на команду"
actors: [owner, agent, adversarial_critic]
environment: content_production
circumstances: "критик получил общий портрет зрителя, а не профили клиента и не-клиента"
purpose: lead_generation
method: "раунды хейтера"
tags: [cta, targeting, hater-review, compile-2026-11-11]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: improve_quality
urgency: when_relevant
availability: has_alternatives
related: [case-2026-11-03-owner-reaction-taken-as-recipe-no-craft-method]
edges:
  - similar_to: pattern-discrimination-not-demonstrated.md
origin: solo
provenance_log:
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: призыв Reels проверен без профиля не-клиента (03.11)"
    trigger_case: case-2026-11-03-cta-on-broad-topic-invites-non-target-free-help.md
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: призыв Reels проверен без профиля не-клиента (03.11)"
    trigger_case: case-2026-11-03-qualifier-word-non-target-also-claims.md
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "compile 2026-11-11: призыв Reels проверен без профиля не-клиента (03.11)"
    trigger_case: case-2026-11-03-adversarial-check-without-customer-profile-misses-targeting.md
    session: ""
---

Адверсариальной проверке призыва дают два профиля: целевого клиента и самого вероятного не-клиента, который увидит ролик. Критик отвечает на вопрос «кто напишет на этот призыв и откажем ли мы ему». Условие-фильтр проверяется тем же не-клиентом: примерит ли он его на себя.

**Why:** Reels ProjectA, 03.11.2026. Три раунда хейтера с общим портретом зрителя разобрали хуки и голос и пропустили главное: призывы «напишите — разберём» звали строителей и таксистов за бесплатным разбором. Это сказал владелец. Фильтр «есть свой заказчик» не помог: у курьера Wolt и водителя Bolt заказчик есть. Четвёртый раунд с профилями клиента и не-клиента нашёл оба дефекта сразу.

**How to apply:** перед критикой призыва выпиши признак клиента, которого нет у не-клиента (договор B2B, фактура, своя фирма). Фильтр строй на этом признаке, а не на слове, которое подходит обоим.

**Limitations:** не нужен охватному контенту без призыва.
