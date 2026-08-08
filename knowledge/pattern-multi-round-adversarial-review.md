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
last_confirmed: 2026-07-23
source_cases:
  - case-2026-06-21-adversarial-verify-caught-defects.md
  - case-2026-07-06-adversarial-multi-round-fresh-critic.md
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
