---
name: Knowledge in the world, not in the head — правило в механизме, не в памяти
description: Надёжное правило embedded в механизм системы, который активируется на семантическую акцию. Правило-в-тексте полагается на то, что агент/человек прочитает и применит его — это память-как-ресурс, которая системно ненадёжна. Fix после инцидента = embedded mechanism + formulation, а не только formulation
type: principle
outcome: design_rule
confidence: 5
impact: 5
intensity: 0                # заполнено 2026-10-23 задним числом: сюрприз при записи не фиксировался, активатор и так читал 0
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-17
source_cases:
  - case-2026-08-28-rule-about-tree-shape-without-a-checker.md
  - case-2026-08-28-reminder-fired-and-was-read-and-changed-nothing.md
  - case-2026-08-25-signal-counts-without-naming.md
  - case-2026-08-25-cleanup-belongs-to-event-not-period.md
  - case-2026-08-25-blocker-scoped-to-wrong-tool.md
  - case-2026-07-29-signal-enumerates-cannot-predicate.md
  - case-2026-04-24-text-rule-reinforcement-as-self-violation.md
  - case-2026-08-27-post-incident-analysis-goes-to-memory-not-mechanism.md
  - case-2026-08-21-third-reminder-means-missing-mechanism.md
  - case-2026-08-21-rule-drift-visible-only-from-outside.md
  - case-2026-08-18-repeated-credential-stumble-env.md
  - case-2026-08-08-session-throttle-downgrades-hook-to-text-rule.md
  - case-2026-08-08-fabricated-time-canary.md
  - case-2026-06-21-repeated-rejected-pause-suggestion.md
  - case-2026-04-23-memory-without-action-gate.md
  - case-2026-04-23-model-vs-system-source-blindness.md
  - case-2026-04-23-text-rule-vs-mechanism.md
  - case-2026-04-24-install-drift-silent-safeguards.md
  - case-2026-04-24-proof-of-active-needs-noise-calibration.md
  - case-2026-07-07-doc-counters-rot-generate-from-source.md
  - case-2026-04-24-alphabet-mixing-self-detection-failure.md
  - case-2026-05-05-claudsoul-blindness-from-home.md
  - case-2026-06-21-rules-pointer-must-be-mechanism.md
  - case-2026-09-01-accurate-red-instrument-made-optional.md
  - case-2026-09-01-own-rule-about-own-metadata-without-checker.md
  - case-2026-10-23-measurement-after-risky-transfer-left-on-memory.md
source_session: ""
provenance_traced: low
status: active

# Контекст
domain: [system_design, cognitive_science, agent_architecture, interaction_design, metacognition]
situation: "post_incident_rule_design, defense_mechanism_engineering"
trigger: "proposing_text_rule_as_fix_for_memory_failure"
stakes: "recursive_blindness_each_fix_reintroduces_same_failure_mode"
actors: [agent, interlocutor, knowledge_system, rule_system]
environment: "any_rule_based_system"
circumstances: "long_lived_rule_with_activation_gap"
purpose: "make_rules_reliably_active"
method: "embed_in_mechanism_not_text"
tags: [don_norman, affordance, external_cognition, knowledge_action_gap, mechanism_over_memory]

# Demand
need: reliable_rule_activation_without_depending_on_recall
urgency: universal_background_principle
availability: foundational

# Связи
related:
  - pattern-inside-out-blindness.md
edges:
  - generalizes: pattern-inside-out-blindness.md
  - parent_of: case-2026-04-23-memory-without-action-gate.md
  - parent_of: case-2026-04-23-model-vs-system-source-blindness.md
  - parent_of: case-2026-04-23-text-rule-vs-mechanism.md

# gradation
promotion_tier: 3
scope: universal
origin_domain: cognitive_science
modification_history: []
provenance_log:
  - date: 2026-07-28
    kind: reinforced
    reason: "publish-public.sh: повторяемую чувствительную зачистку встроили в инструмент+гейт (archive→exclude→redact→forbidden на собранном дереве), а не вычищали руками каждый релиз"
    trigger_case: case-2026-07-27-secret-scan-refs-not-branch.md
  - date: 2026-08-21
    kind: reinforced
    reason: "case-2026-08-18-repeated-credential-stumble-env: пользователь сам потребовал перенести кред из памяти в .env после повторного спотыкания"
  - date: 2026-08-25
    kind: reinforced
    reason: "Замер с владельцем и сроком (measurement-due.sh) заведён против правила 'держится на чьей-то памяти' — и сам не имеет автозапуска, то есть держится на чьей-то памяти. Просрочка 9 дней обнаружена вопросом собеседника, а не механизмом."
  - date: 2026-08-27
    kind: reinforced
    reason: "Разбор промаха ушёл в память агента, хотя для правила существовал хук five-whys-gate, заведённый по трём напоминаниям; поправка собеседника: «так это не правило, делали же хук»"
    trigger_case: case-2026-08-27-post-incident-analysis-goes-to-memory-not-mechanism.md
    session: ""
  - date: 2026-08-28
    kind: contradicted
    reason: "Обещание «уровень 3 механически неотвратим» опровергнуто замером: blocker-tier-check только инжектит, и знание уровня 3 дало 5 нарушений из 19 — больше любого другого. Знание не отменено: три уровня верны, неверна оценка надёжности третьего и отсутствие четвёртого."
    session: ""
  - date: 2026-08-28
    kind: reinforced
    reason: "Уровень 3 как инжект подтверждён третий раз за сутки: гейт разбора сработал, был прочитан и не изменил действия. Починка — отказ, то есть уровень 4 из таблицы, добавленной в тот же день."
    session: ""
  - date: 2026-08-28
    kind: reinforced
    reason: "Правило именования скиллов жило на уровне 1 (текст в CLAUDE.md) БЕЗ сверщика вообще: следовали ему 2 из 23, расхождение заметил человек, не механизм. Случай добавляет к лестнице уровень ниже первого — правило, чья истинность не проверяется ничем"
    trigger_case: case-2026-08-28-rule-about-tree-shape-without-a-checker.md
    session: ""
  - date: 2026-10-23
    kind: reinforced
    reason: "замер после переноса D1035 лёг строкой в SESSION.md; владелец: «я забуду замерить»; реестр замеров со сроком был под рукой"
    trigger_case: case-2026-10-23-measurement-after-risky-transfer-left-on-memory.md
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 12–16.11: линт удержал eqeqeq с первого раза; правила-тексты памяти проекта (селекторы из DOM, свой сервер гашу сам) нарушены 4 и 3 раза; урок networkidle повторился из непромоутленного черновика"
    session: ""
instrument_verdict:
  decision: "не заводится"
  why: "Момент уже занят механизмом, и его собственный замер — готовое доказательство рода C для этого класса. `hooks/fix-level-check.sh` (уровень 2, Stop/UserPromptSubmit/PreCompact/PreToolUse) сканирует ответ агента на пост-инцидентную фразу уровня 1 и в заголовке несёт урок v1.13.3: придуманный словарь дал ДЕВЯТЬ срабатываний за 214 сессий и НОЛЬ на настоящих поправках. Словарь пришлось брать из задокументированных проявлений — то есть класс как речь неотличим от жанра пост-инцидентного разговора. Неразличима не фраза, а отношение: «нуждается ли ЭТО правило в механизме». Проверил структурный вариант, свободный от речи, — «правка правил без правки механизма»: по истории `rules/CLAUDE.md` 53 коммита с добавлением, 24 не называют адреса вида `.sh`/`.py`/`hooks/`/`scripts/`; спот-чек этих 24 показал, что большинство механизм всё же называет — прозой, по имени («relative-date-check», «changelog-reminder», «timestamp-inject»), а часть законно не нуждается в нём вовсе (правило о когнитивных слоях, «документ состояния ≠ хроника»). Ложный класс больше настоящего, признак стал бы фоном ровно там, где принцип требует обратного. УСЛОВИЕ: когда блок правила обязан нести машиночитаемую строку «Проверка результата:» — договор, который уже держат заголовки хуков (`rules-write-bypass.sh`: «Результат:» + «Проверка результата: bash hooks/tests/drift-check.sh | grep -q '^OK|правила'») и пункты BACKLOG. Тогда признак «в rules/CLAUDE.md добавлен блок правила без строки «Проверка»» вычислим построчно, имеет одно последствие («правило уезжает уровнем 1: его истинность не проверяется ничем») и адрес отказа в git commit."
  dated: "2026-09-06"
---

## Формулировка

**Если правило опирается на то, что future-you (или future-человек) вспомнит его применить в нужный момент — оно хрупко.** Надёжное правило embedded в механизм, который:

1. Детектирует ситуацию автоматически по наблюдаемым сигналам (tool call, file path, diff content, state change)
2. Инжектирует правило в контекст ТОГО МОМЕНТА, когда оно релевантно, а не в general system prompt
3. Активируется на **семантическую акцию** (что делается), а не только на **ключевую фразу** (как названо)

Критерий различения:
- **Правило-в-тексте** (knowledge in the head): formulation записана в docs, rules/CLAUDE.md, памяти. Активация = «человек/агент вспомнил применить». Failure mode: silent drift, правило лежит годами и не срабатывает
- **Правило-в-механизме** (knowledge in the world): formulation + signal/behavior path. Активация = система сама подаёт правило в нужный момент. Failure mode: detection_signals не покрывают все проявления (но это observable и fixable)

## Почему это работает

Классическая концепция Don Norman: *"The user should not need to remember X; the environment should remind them of X."* В LLM-системах это усиливается:
- Context декодируется токен за токеном; релевантность правила в момент генерации не гарантирована, даже если правило присутствует в system prompt
- Defensive narrative после инцидента активен кратковременно — правило, добавленное «на волне» post-mortem, через N сессий теряет контекстную салиентность
- Память-как-ресурс accumulates — N правил в system prompt → снижение attention per rule

Embedded mechanism обходит все три:
- Signal генерируется инфраструктурой, не LLM attention
- Inject происходит на конкретном tool call, не в general session init
- Механизм сохраняет эффективность независимо от количества других правил

## Эвристика «fix после инцидента»

Три уровня исправления, в порядке возрастания embedded-ness:

| Уровень | Форма | Надёжность | Когда применять |
|---------|-------|------------|-----------------|
| 1. Text rule | Правило в docs/rules/CLAUDE.md/memory | Низкая | Черновик формулировки, до реализации механизма |
| 2. Activator injection | Правило в knowledge-base с anchors, попадает в inject при context match | Средняя | Правило ситуативное, context-dependent |
| 3. Blocker-tier detection | Detection signals + PreToolUse/PostToolUse hook с silent inject | **Измерена, не «высокая»** — см. ниже | Проверенный knowledge-action gap, confirmed_count ≥ 5 |
| 4. Отказ через harness | `permissionDecision: "deny"` либо `"ask"` — вызов не проходит без решения | Единственный уровень, который нельзя не заметить | Класс, где ложное срабатывание дешевле пропуска |

**Надёжность уровня 3 измерена 2026-08-28, и она не «высокая».** Самое нарушаемое знание
базы — `pattern-shell-portability` (confidence 5, `blocker: true`, сигналы написаны) — дало
**5 случаев «уместно и не применено» из 19**, больше любого другого. Причина в механизме, а
не в знании: `blocker-tier-check.sh` заканчивается `additionalContext` и `exit 0`, то есть
уровень 3 — адресный инжект, а не гейт. По всей системе: **из 53 хуков отказывает ровно
один** (`playwright-cli-guard`, `permissionDecision: "deny"`), спрашивает один
(`bulk-copy-guard`, `"ask"`), остальные 51 инжектят текст.

Отсюда четвёртая строка таблицы. Она не «лучше» третьей по умолчанию: отказ по совпадению
с текстом команды иногда ошибётся, и цена ложного срабатывания реальна. Но называть третий
уровень неотвратимым нельзя — это обещание, которого он не даёт, и оно стоило пяти
нарушений одного знания.

Нарушения знаний уровня 3 теперь считаются отдельно: раздел «Уровень не помог» в
`state/knowledge-instrument.md` (до 2026-08-28 такое знание выпадало из очереди как «уже
гейт», и его нарушения были невидимы).

Fix после инцидента, который остаётся на уровне 1 — это **не fix**, это описание проблемы. Минимально embedded fix = уровень 2 (knowledge-activator injects on trigger match). Для повторяющихся паттернов — уровень 3.

## Escalation mechanism

Правило принципа требует escalation: если blocker-tier pattern (уровень 3) продолжает подтверждаться, значит detection_signals неполны или есть новое измерение. Система должна **сама** заявить о необходимости engineering-итерации, а не полагаться на замечание человеком.

Embedded реализация: pattern с `escalation_threshold: N`. При `confirmed_count >= N` — `knowledge-audit-digest.sh` emit's секцию «Engineering escalation needed», hint попадает в `state/audit-hint.txt`, session-start инжектит в startup-signals. Это рекурсивная защита: механизм surface'ит необходимость следующего уровня защиты, не полагаясь на memory-as-resource.

## Anti-patterns

- **"Я добавлю напоминание в CLAUDE.md"** — это уровень 1, не engineering
- **"Я запомню не делать X"** — это самая нижняя точка, no-op
- **"Мы добавим правило в team handbook"** — уровень 1 для людей, такой же failure mode
- **"Покроем тестами"** — может быть уровнем 2-3, если тест запускается на релевантное action

Что работает:
- **Hook detects signal → injects reminder**
- **Lint rule enforces pattern**
- **Type system prevents error class**
- **Default configuration makes right thing easy, wrong thing hard**

## Применение в ClaudSoul

Принцип проявлен в архитектуре:
- `blocker-tier-check.sh` + `detection_signals` — реализация уровня 3
- `knowledge-activator.sh` + anchors — реализация уровня 2
- `rules/CLAUDE.md` — уровень 1, используется только для формулировок, не как единственный носитель

Escalation: `knowledge-audit-digest.sh` §«Engineering escalation needed» (v1.5.5-alpha+1) — механизм, который сам заявляет о необходимости следующего уровня.

## Границы

Принцип не требует всегда делать уровень 3. Уровень соответствует уровню риска: тривиальная рекомендация — ok уровень 1. Критическое правило, многократно нарушенное — требует уровня 3. Промежуточное — уровень 2. Но fix после подтверждённого инцидента никогда не должен оставаться на уровне 1.
