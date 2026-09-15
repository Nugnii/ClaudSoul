---
name: Независимый критик в свежем контексте, несколько раундов — один раунд пропускает
description: Перед выпуском артефакта гнать адверсариальную проверку раундами (~3), каждый раунд новым критиком, не видевшим прошлых правок; собственный фильтр автора и один раунд оставляют дефекты
type: pattern
outcome: success
confidence: 2
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-13
source_cases:
  - case-2026-09-13-coverage-unit-named-only-in-round-three.md
  - case-2026-06-21-adversarial-verify-caught-defects.md
  - case-2026-07-06-adversarial-multi-round-fresh-critic.md
source_session: ""
status: active

domain: [agent_design, workflow, multi_agent, quality_assurance]
situation: review_before_ship
trigger: output_looks_ready_or_passed_one_round
stakes: plausible_but_wrong_ships
actors: [agent, subagent_skeptic, user]
environment: multi_agent_workflow
circumstances: author_blind_to_own_defects
purpose: quality_gate
method: multi_round_adversarial_with_fresh_context

need: improve_quality
urgency: when_relevant
availability: has_alternatives

promotion_tier: 2
scope: universal
origin_domain: agent_design

modification_history: []
fragile: false
blocker: false

related:
  - case-2026-06-21-adversarial-verify-caught-defects.md
  - case-2026-07-06-adversarial-multi-round-fresh-critic.md
  - pattern-completion-by-internal-proxy.md
  - case-2026-06-29-review-finding-dismissed-by-reframe.md
edges:
  - caused_by: pattern-completion-by-internal-proxy.md
  - similar_to: principle-verify-before-acting.md
provenance_log:
  - date: 2026-08-21
    kind: reinforced
    reason: "case-2026-08-18-inline-disposition-xss: stored XSS пойман adversarial /code-review high до деплоя, не автором правки"
  - date: 2026-08-23
    kind: reinforced
    reason: "три раунда на одном предмете: раунд 2 дал 8 новых атак после закрытия 17, раунд 3 — ещё 6, причём первая в каждом раунде была регрессией от починки предыдущего. Свежий критик находил то, чего не видел ни автор правки, ни предыдущий критик"
    trigger_case: case-2026-08-23-narrow-fix-breaks-common-form.md
  - date: 2026-08-23
    kind: reinforced
    reason: "три раунда сошлись не в пустой раунд, а в смену способа проверки: цепочка «почему» показала, что предмет — парсер, а проверялся примерами. Раунды дали 31 находку и остановились не по исчерпанию, а по смене инструмента"
    trigger_case: case-2026-08-23-examples-vs-oracle-in-parser-review.md
  - date: 2026-08-25
    kind: reinforced
    reason: "Три раунда противника по одному предмету: каждый дал новое, раунды 2 и 3 били в то, что чинил предыдущий. Без второго и третьего раунда 15 находок из 22 остались бы в коде."
  - date: 2026-08-27
    kind: reinforced
    reason: "прогон 26-27 августа: раунд 1 закрыл шесть атак и выглядел исчерпывающим, раунд 2 свежим критиком дал blocker (вердикт переворачивался stuck→focus, а не терялся), раунд 3 — ещё семь, включая отсутствующий turn-guard у классификатора состояния. Каждый следующий критик находил не остатки, а другой срез"
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "три раунда прожарки свидетелей D282 принесли три класса по одному шву: входы, пороги, единица предиката"
    trigger_case: case-2026-09-13-coverage-unit-named-only-in-round-three.md
    session: ""
detection_signals:
  where: "команда Bash (tool_input.command) + счёт вызовов критика по расшифровке сессии (transcript jsonl)"
  form: "all_of: [ {\"tool_matches\":[\"Bash\"]}, any_of: [ {\"command_uses\":\"publish-public.sh\"}, {\"command_regex\":\"(^|[;&|(])[[:space:]]*npm[[:space:]]+publish([[:space:]]|$)\"}, {\"command_regex\":\"gh[[:space:]]+release[[:space:]]+create\"} ], {\"session_critic_rounds_lt\": 2} ] — новый предикат считается командой: jq -r 'select(.type==\"assistant\")|.message.content[]?|select(.type==\"tool_use\" and (.name==\"Skill\" or .name==\"Task\"))|(.input.skill // .input.subagent_type // \"\")' \"$TRANSCRIPT\" | grep -cE '^(adversary|хейтер|grilling|code-review)$'"
  consequence: "Наружу уходит артефакт, которого независимый критик не видел ни разу либо видел один раз: во всех замеренных прогонах второй раунд возвращал непустой улов (25 августа — 15 находок из 22 пришли из раундов 2 и 3), а публикация снимка необратима — он уже у чужих людей."
  counterexample: "git commit и git push origin рабочей ветки — 34 сессии из 40 замера, действие обратимое и внутреннее; признак их не ловит по построению, в перечне только publish-public.sh, npm publish, gh release create. Второй: повторный вызов publish-public.sh в той же сессии после первого инжекта (дроссель по сессии)."
  status: "ИЗМЕРЕНО 2026-09-06: сырая форма дала 74 срабатывания на 21658 вызовов Bash, из них ЛОЖНЫХ 38 (48,6% точность) — ловился сухой прогон publish-public.sh без --push, который знание само объявляет законной репетицией. Сужение до позиции команды И --push: 36 срабатываний, ложных 0. ГЛАВНОЕ: второе условие (session_critic_rounds_lt 2) НЕ СУЖАЕТ НИЧЕГО — во всех 9 сессиях с необратимой публикацией раундов критика ноль, то есть 35 из 35. Счётчик критиков проверен положительным контролем: в корпусе он видит 18 вызовов (code-review 11, противник 3, adversary 2, хейтер 2), просто ни один не пришёлся на сессию публикации. Правило не исполнялось ни разу."
---

Артефакт перед выпуском проходит **цикл «свежий критик → редактор»**, а не один проход.
Каждый раунд критик получает чистый контекст и не знает, что правили по его прошлым
замечаниям. Стоп — когда раунд возвращает только вкусовщину, либо два пустых раунда,
либо лимит ~3.

**Why:** два независимых подтверждения в разных доменах.
(1) 2026-06-21, код: отдельный агент-скептик в воркфлоу `/project-health` вернул 4 реальных
дефекта в синтезированном выводе, который выглядел корректным
([[case-2026-06-21-adversarial-verify-caught-defects]]).
(2) 2026-07-05..07-06, текстовый контент: шесть постов, прошедших собственный фильтр автора,
тут же отдали независимому критику ложную цену и самоподрывную фразу; дальше выяснилось,
что и одного раунда мало — все шесть постов дошли до **третьего** раунда с непустым уловом
(раунд 2 снёс штамп в хуке и мёртвые пруфы, раунд 3 заскоупил слишком широкий тезис)
([[case-2026-07-06-adversarial-multi-round-fresh-critic]]).

Механизм один: генератор склонен к самоподтверждению, а критик, помнящий свой прошлый
разбор, защищает уже сделанные выводы вместо того, чтобы перечитать заново.

**How to apply:** любой артефакт перед выпуском — пост, коммерческое предложение, ТЗ,
план рефакторинга, релиз. Критик — отдельный субагент с обратной презумпцией («по умолчанию
ищи дефекты»), не тот же контекст, что писал. Удары делить на факт/логика (чинить) и
манеру (сверять, чаще отклонять — см. [[case-2026-07-05-signature-style-not-defect]]).

**Limitations:** лимит раундов — защита от бесконечного цикла, а не цель: если второй раунд
пуст, третий не нужен. Чинить всё подряд под давлением критики — свой failure mode: текст
распухает, а голос стирается.
