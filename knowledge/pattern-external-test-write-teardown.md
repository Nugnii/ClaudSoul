---
name: Проверка, мутирующая боевую внешнюю систему, закладывает уборку до первого запуска
description: Внешняя система-источник истины не различает прод-код и тест; её записи наблюдаемы людьми и не откатываются, а расчёт на ручную уборку постфактум не держится — владелец указывал на неубранные тестовые заявки четвёртый раз подряд
type: pattern
outcome: error
confidence: 1
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-11
source_session: ""
status: active

promotion_tier: 2
scope: universal
origin_domain: integrations

source_cases:
  - case-2026-06-24-clean-test-side-effects-external.md

domain: [integrations, testing, safety]
situation: тест или скрипт мутирует боевую внешнюю систему-источник истины
trigger: код проверки выполняет write в чужую боевую систему (wFirma, SendPulse, Google Drive)
stakes: мусор в боевой системе, видимый владельцу и клиентам, откату не подлежит
actors: [system, operator, external_service]
environment: production
circumstances: внешняя система не различает прод-код и тест; уборка постфактум ручная и пропускается при падении
purpose: безопасная интеграция
method: маркер тестовых сущностей + удаление в finally/afterEach + финальный assert «0 осталось»
tags: [external_mutation, teardown, cleanup, side_effects, safety]

need: avoid_polluting_production_external_systems
urgency: immediate
availability: unique

related:
  - case-2026-06-15-manual-gate-external-system-mutations
  - pattern-external-system-facts-unverified
  - principle-knowledge-in-the-world
edges:
  - similar_to: pattern-external-system-facts-unverified.md
  - similar_to: case-2026-06-15-manual-gate-external-system-mutations.md
  - specializes: principle-knowledge-in-the-world.md

modification_history: []
provenance_log:
  - date: 2026-08-11
    kind: reinforced
    reason: "нашёл и закрыл дыру: DISABLE_SENDPULSE стоял только в sendpulse-crm.ts, а sendpulse-telegram.ts (поиск контакта + ОТПРАВКА сообщения) им прикрыт не был — тест, дошедший до клиентского TELEGRAM-уведомления, написал бы живому человеку в боевой бот"
  - date: 2026-08-11
    kind: reinforced
    reason: "прод-спеки Playwright этой сессии закладывали уборку сразу: impersonate/stop в конце спеки, временные спеки удалены после прогона"
fragile: false
origin: solo
preceded_artifact: "no"
---

# Паттерн: уборка закладывается до первого запуска, а не после

**Правило.** Любая проверка, тест или скрипт, мутирующий боевую внешнюю систему, закладывает
уборку **до первого запуска**:

1. Тестовые сущности создаются с распознаваемым маркером (префикс `TEST_`, узнаваемое имя).
2. Удаляются в `finally` / `afterEach` / `afterAll` — так, чтобы уборка отработала и при
   падении, и при прерывании прогона.
3. Прогон заканчивается assert'ом «тестовых сущностей не осталось».

Автоматическая уборка невозможна (операция необратима) — **не создавать тестовую сущность в
боевой системе вообще**: мок или sandbox.

**Механизм.** Внешняя система-источник истины наблюдаема людьми и не откатывается:
выставленная фактура, созданный контрагент, заявка в CRM остаются там, где их видит
владелец и клиент. Расчёт на ручную уборку постфактум и на «я аккуратно» не держится —
владелец указывал на неубранные тестовые заявки **четвёртый раз подряд**. То есть правило
не удерживается как намерение и должно быть встроено в саму точку записи
(`principle-knowledge-in-the-world`: уровень 1 хрупок, механизм неотвратим).

**Limitations.** Не про обратимые внутренние операции и не про свою тестовую базу, которая
чистится общим `cleanDatabase`, — там гейт на каждый write избыточен. Правило про
необратимое и внешнее, наблюдаемое людьми.

**Границы промоушена, названные явно.** Основание — один кейс
(`case-2026-06-24-clean-test-side-effects-external`) с четырьмя повторами внутри него, то
есть промоушен идёт по клаузе META «1 кейс с impact ≥ 4 → кандидат в паттерн», а не по
«2+ независимых кейса». Поэтому `confidence: 1` и ожидание независимого подтверждения.

Сознательно **не** включён смежный класс «необратимая мутация внешней системы требует
отмашки оператора» (`case-2026-06-15-manual-gate-external-system-mutations`): у него другой
триггер (пропуск гейта на этапе проектирования) и другое средство (human-in-the-loop). Их
объединяла только общая наблюдение о среде, а не общий механизм отказа; отдельный
gate-паттерн заводить, когда появится второй независимый инцидент этого класса.
