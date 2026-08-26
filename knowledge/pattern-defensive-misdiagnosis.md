---
name: Сигнал о своей ошибке диагностируется как дефект инструмента, а не проверкой своих данных
description: "Когда сигнал указывает на возможную СВОЮ ошибку (детектор сработал, собеседник поправил, вывод не сходится), диагностика инстинктивно уходит на внешнее — инструмент, косвенный признак, «баг системы» — вместо прямого предмета: своих данных, своего входа, своего поведения. Защитная презумпция «я прав, ошибается инструмент». Дорого: часы уходят на починку исправного, пока реальный дефект — своё поведение."
type: pattern
confidence: 1
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-25
source_cases: [case-2026-08-16-blamed-detector-not-own-input.md, case-2026-08-16-indirect-count-vs-code-truth.md]
source_session: ""
status: active

promotion_tier: 2
scope: universal
origin_domain: meta_cognition

domain: [meta_cognition, debugging, self_learning_system]
situation: "signal_suggests_own_error_diagnosis_turns_to_external_tool"
trigger: "detector_fires_or_user_corrects_or_output_mismatches_agent_blames_tool_before_checking_own_input"
stakes: "hours_fixing_a_correct_tool_while_real_defect_is_own_behavior"
actors: [agent]
environment: "debugging, self_learning_system, tool_output_review"
circumstances: "defensive_presumption_of_own_correctness, indirect_or_external_object_checked_instead_of_direct_own_input"
purpose: "preserve_presumption_of_own_correctness"
method: "read_tool_logic_or_indirect_metric_instead_of_own_data_first"
tags: [defensive_misdiagnosis, blame_the_tool, subject_of_measurement, detector_trust, ego_protection, affect]

need: reduce_risk
urgency: immediate
availability: unique

related: [pattern-detector-wired-to-failure.md, pattern-subject-of-measurement-mismatch.md, principle-verify-before-acting.md, principle-affect-as-engineering.md, pattern-inside-out-blindness.md]
edges:
  - generalizes: case-2026-08-16-blamed-detector-not-own-input.md
  - generalizes: case-2026-08-16-indirect-count-vs-code-truth.md
  - similar_to: pattern-detector-wired-to-failure.md
  - similar_to: pattern-subject-of-measurement-mismatch.md
  - caused_by: principle-affect-as-engineering.md
modification_history: []
fragile: false
provenance_log:
  - date: 2026-08-25
    kind: reinforced
    reason: "Критик сказал '13 строк справочника обрываются, баг в генераторе'. Я собирался править regen-readme-skills.sh. Контракт оказался документирован в шапке partial-read-guard.sh:3-5: первая строка НАМЕРЕННО самодостаточна, генератор берёт ровно её. Дефект в данных (11 шапок нарушают контракт), а не в инструменте. Диагноз 'сломан инструмент' был бы неверен."
---

# Защитная мисдиагностика: винить инструмент, не свой вход

**Наблюдение (2 кейса за один день, один проект).**
- `case-2026-08-16-blamed-detector-not-own-input` — канарейка таймштампа сработала верно (я пропустил `🕐`), а я 4 хода чинил «баг стража», проверяя его логику, но не свой первый блок.
- `case-2026-08-16-indirect-count-vs-code-truth` — заявил «счётчик системы завышает» по своему grep pending-строк; чтение кода показало, что система считает верно — я мерил не тот предмет своим же grep.

Общий механизм: сигнал указывал на **мою** ошибку, а диагностика ушла на **внешнее** (логика инструмента, косвенная метрика), минуя прямой предмет — мои данные / мой вход / моё поведение.

**Почему это отдельный паттерн, а не только `subject-of-measurement-mismatch`.** Там корень — «мерю не тот объект». Здесь добавляется **направление ошибки**: объект смещается систематически ОТ себя К инструменту, потому что «инструмент неправ» дешевле для эго, чем «я неправ». Это affect-функция (`principle-affect-as-engineering`): защитный инстинкт, которого архитектурно нет как тормоза, — поэтому чтение правила его не заменяет.

**How to apply.**
1. Сигнал о возможной своей ошибке (детектор сработал, собеседник поправил, вывод не сошёлся) → **первым делом проверить ВХОД**: свои данные, свой вывод, своё поведение — ровно тот предмет, который сигнал измеряет. Логику инструмента — только после.
2. Ловить у себя фразу-презумпцию «это ложное срабатывание / баг / инструмент ошибается» ДО того, как проверен свой вход, — это маркер защитной мисдиагностики, а не вывод.
3. Если чинишь инструмент дольше одной проверки, а он на вид исправен — остановиться и спросить: «а не мои ли данные — реальный дефект?»

**Диагностический тест.** Мой метод проверки измеряет тот же предмет, что и сигнал? (Канарейка про первый блок — я проверял последний; счётчик про открытые записи — я грепал строки.) Расхождение предмета = красный флаг.

**Scope.** Universal — механизм не зависит от собеседника, это когнитивно-аффективный паттерн самой диагностики. Промоушен в principle — при подтверждении вне self-learning-домена.
