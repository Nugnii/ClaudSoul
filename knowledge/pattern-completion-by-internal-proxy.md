---
name: Завершённость по внутреннему прокси, а не по внешнему критерию
description: Задача/скилл/аудит объявляется завершённым — ИЛИ выносится вердикт «всё в порядке / проблемы нет / прогрессирует» — по ВНУТРЕННЕМУ/легко-наблюдаемому прокси (объём сделанного, факт существования артефакта, одна пройденная проверка, совпавший счётчик, итоговое состояние системы, факт запуска), а не сверкой с ВНЕШНИМ явным критерием (Definition of Done, чек-лист, требуемые артефакты, целевой охват, НАБЛЮДАЕМЫЙ ПОЛЬЗОВАТЕЛЕМ результат)
type: pattern
outcome: error
confidence: 5
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-11
status: active

domain: [meta_cognition, process, skill_execution, verification]
situation: declaring_task_or_skill_done
trigger: declaring_done
stakes: skipped_deliverable_or_overclaim
actors: [system]
environment: multi_session
circumstances: long_task_many_steps
purpose: completion_judgment
method: orchestrator_or_audit
tags: [definition_of_done, completion, coverage, structural_proxy, overclaim, inside_out, verdict, diagnosis, watchdog, eventual_state]

need: avoid_skipped_deliverable
urgency: when_relevant
availability: has_alternatives

promotion_tier: 2
scope: universal
origin_domain: meta_cognition

# Заявка на инженерную эскалацию. До 2026-08-09 жила в теле файла разделом
# «Mechanism candidate» — то есть была видима человеку и невидима
# knowledge-audit-digest.sh, который читает frontmatter. Заявка второго по
# подтверждённости паттерна базы не могла всплыть в дайджесте никогда, а
# «до механизма — дисциплина» продлевалось бессрочно.
# escalation_opened здесь НЕ ставится: его проставляет дайджест механически
# при первом срабатывании — это точка отсчёта возраста заявки (META §escalation).
escalation_threshold: 12
escalation_opened: 2026-08-16
escalation_mechanism_needed: true
escalation_hint: "completion-gate: хук на объявление задачи/скилла/пункта завершённым — сверка с его собственным DoD и перечнем названных в нём шагов, а не с отчётами исполнителей"

source_cases:
  - case-2026-06-22-skill-completion-by-execution-proxy.md
  - case-2026-06-20-overclaiming-completeness.md
  - case-2026-05-19-curation-completion-by-structural-proxy.md
  - case-2026-06-11-single-instance-verify-hides-coverage-cap.md
  - case-2026-06-23-verdict-by-eventual-state-proxy.md
  - case-2026-06-23-idle-on-unverified-background-progress.md
  - case-2026-06-24-background-network-block-and-blind-wait.md
  - case-2026-07-07-external-write-shipped-on-mocked-green.md

related:
  - pattern-inside-out-blindness.md
  - principle-demand-before-supply.md
  - principle-verify-before-acting.md
edges:
  - specializes: pattern-inside-out-blindness.md
modification_history:
  - date: 2026-06-23
    kind: scope_widened
    reason: "прокси-подмена работает не только при объявлении ‘готово’, но и при вердикте ‘всё в порядке/проблемы нет’ (диагноз по итоговому состоянию) и ‘прогрессирует’ (по факту запуска фоновой задачи)"
    trigger_case: case-2026-06-23-verdict-by-eventual-state-proxy.md
  - date: 2026-06-24
    kind: reinforced_after_challenge
    reason: "рецидив на следующий день после scope_widened: снова принял ‘фон запущен’ за ‘прогрессирует’, не проверив живость → поднят до blocker-tier (явный knowledge-action gap)"
    trigger_case: case-2026-06-24-background-network-block-and-blind-wait.md
provenance_log:
  - date: 2026-07-28
    kind: reinforced
    reason: "«уведомлю по готовности» — факт запуска фон-задачи выдан за прогресс; blocker background_bash_launch сработал, исправил проверкой ps+файл+прогресс"
    trigger_case: case-2026-07-28-inner-ampersand-background-not-harness-tracked.md
  - date: 2026-08-07
    kind: reinforced
    reason: "D63 закрыт по отчётам двух агентов-исполнителей вместо сверки с СОБСТВЕННЫМ текстом пункта: подпункт «README.ru — проверить» не был назначен ни одному агенту и выпал; вскрыт вопросом собеседника"
  - date: 2026-08-08
    kind: reinforced
    reason: "поправки 3-го раунда применены как чеклист по названным секциям; класс дефекта (неопределённое решение = аналитическая свобода) не прогнан по остальному документу — §10 роль повторов, §13 судьба очереди, §5 байты остались неопределёнными"
  - date: 2026-08-08
    kind: reinforced
    reason: "D64 сдан «готовым» по чеклисту §15, дыра эргономики владельца (видимость фазы) не входила в список — сдача по списку вместо сдачи по жизни оператора; вскрыл вопрос собеседника"
  - date: 2026-08-08
    kind: reinforced
    reason: "уровень выше: мало свериться с внешним критерием — критерий должен быть механически недосягаем для измеряемого"
    trigger_case: case-2026-08-08-measurement-apparatus-outside-agent-reach.md
  - date: 2026-08-11
    kind: reinforced
    reason: "после фонового запуска dev-сервера проверил живость наблюдаемым признаком (curl → 200 + строка в логе), а не фактом запуска — сервер действительно поднялся, но признак был нужен и позже пригодился при рестарте после prisma generate"
fragile: false

# Blocker-tier (v0.3): pattern продолжает срабатывать после попадания в базу (рецидив 06-24
# на следующий день после scope_widened 06-23). Detection — момент запуска фоновой Bash-задачи:
# напомнить про liveness-проверку и про то, что в этом окружении фон глушит сеть/сбрасывает cwd.
blocker: true
blocker_reminder: "‘Запущено в фоне’ ≠ ‘прогрессирует’. Сразу проверь живость наблюдаемым признаком (ps + файл результата + одиночный пробный вызов), не жди по факту запуска. В этом окружении run_in_background глушит исходящую сеть и сбрасывает cwd → сетевую/cwd-работу гони форграундом мелкими партиями с абсолютными путями."
detection_signals: |
  [
    {
      "name": "background_bash_launch",
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"tool_input_contains": "run_in_background"}
      ]
    }
  ]
---

## Наблюдение

Завершённость многошагового действия (скилл, аудит, миграция, курирование, проверка
охвата) систематически оценивается по **внутреннему прокси** — сигналу, доступному
«изнутри» процесса, — вместо сверки с **внешним явным критерием завершения**.

Это специализация `pattern-inside-out-blindness`: «изнутри» здесь = собственная
деятельность, «снаружи» = объективный критерий, который существует и доступен, но не
сверяется.

## Типичные внутренние прокси (ложные сигналы «готово»)

| Прокси | Кейс |
|--------|------|
| «Я много сделал» (объём работы / число коммитов) | skill-completion-by-execution-proxy |
| «Артефакт существует / структура на месте» | curation-completion-by-structural-proxy |
| «Одна проверка прошла» → молча обобщено на весь охват | single-instance-verify-hides-coverage-cap |
| «Звучит полно» / заявление о полноте без перечисления | overclaiming-completeness |
| «Итоговое состояние совпало» → вердикт «проблемы нет» (вместо наблюдаемого пользователем результата в момент его сценария) | verdict-by-eventual-state-proxy |
| «Задача запущена / уведомит по завершении» → принято за «прогрессирует» (вместо признака живости) | idle-on-unverified-background-progress |

## Внешний критерий, который надо сверять

- **Definition of Done** скилла/задачи — по пунктам, а не «в целом».
- **MANDATORY READ** и обязательные шаги — выполнены ли все.
- **Требуемые артефакты** — каждый создан (не «папка есть», а «все N файлов»).
- **Целевой охват** — проверены ВСЕ инстансы, а не один (репрезентативность ≠ полнота).

## How to apply

Перед словом «готово / завершено» для многошагового действия:
1. Назови внешний явный критерий завершения (DoD / чек-лист / список артефактов / охват).
2. Пройди его **по пунктам**, отметив каждый отдельно.
3. Если ловишь себя на обосновании «готово» через объём/существование/одну-проверку —
   это сигнал прокси: останься и сверься с критерием.

«Исполнил план» ≠ «отработали все фазы». «Файл есть» ≠ «содержимое полно».
«Один кейс прошёл» ≠ «весь охват покрыт». «Итог в системе совпал» ≠ «пользователь увидел
результат в своём сценарии». «Задача запущена» ≠ «задача прогрессирует».

То же и для **вердикта на жалобу**: прежде чем сказать «всё в порядке / проблемы нет»,
назови НАБЛЮДАЕМЫЙ ЖАЛУЮЩИМСЯ результат (что именно он увидит/получит в своём сценарии в
момент T) и проверь его — итоговое/eventual состояние системы это прокси, не таргет.

## Mechanism candidate

> Заявка переведена в frontmatter 2026-08-09 (`escalation_threshold: 12`,
> `escalation_mechanism_needed: true`, `escalation_hint`) — до этого она жила
> только здесь, в прозе, и дайджест её не видел. Текст ниже оставлен как
> формулировка кандидата.

Кандидат в completion-gate (родитель `inside-out-blindness` уже несёт
`escalation_mechanism_needed: true`): хук, который при объявлении скилла/задачи
завершённым напоминает свериться с его DoD/обязательными шагами. До механизма —
правило выше (дисциплина).
