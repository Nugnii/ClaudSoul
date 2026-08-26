---
name: Статус конвейера — не ответ на вопрос
description: "Потребитель с ранним выходом (grep -q, head, sed -n 1p) убивает producer'а SIGPIPE, и под set -o pipefail статус пайплайна — это статус УБИТОГО, а не нашедшего. «Найдено» приходит как 141 и читается как «не найдено». Отказ тем вероятнее, чем выше нагрузка, поэтому дефект выглядит непостоянством среды, а не ошибкой кода."
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-25
source_cases:
  - case-2026-04-15-grep-set-e-crash.md
  - case-2026-04-22-pipefail-head-jq-jsonl.md
  - case-2026-08-11-assertion-answer-from-broken-pipe.md
source_session: ""
status: active
promotion_tier: 2
scope: universal
instrument_verdict: covered   # признак синтаксический; страж hooks/tests/test_assert_no_sigpipe.sh
preceded_artifact: "no"

# Контекстные якоря
domain: [bash, shell_scripting, hooks, testing, ci_cd, tooling]
situation: статус конвейера используется как ответ на вопрос — в условии if, в присваивании, в проверке
trigger: "потребитель с ранним выходом под set -o pipefail, статус пайплайна потребляется"
stakes: ответ инвертируется молча и непостоянно — проверка перестаёт различать соблюдение и нарушение, а вина уезжает на среду
actors: [agent, ci_runner, hook]
environment: любая оболочка с pipefail; вероятность отказа растёт с нагрузкой машины и объёмом вывода producer'а
circumstances: код детерминирован, вход детерминирован, отказ воспроизводится только под конкуренцией за процессор
purpose: чтобы «есть ли строка» отвечал тот, кто искал, а не тот, кого убили
method: убрать конвейер — herestring (`grep -q "$n" <<< "$h"`) либо чтение из файла; ответ берётся у потребителя напрямую
tags: [pipefail_sigpipe, early_exit_consumer, false_negative, flaky_by_load, herestring, syntactic_guard]

# Demand-компоненты
need: keep_the_answer_from_being_the_status_of_a_killed_producer
urgency: when_relevant
availability: unique

related:
  - pattern-measurement-validity.md
  - pattern-subject-of-measurement-mismatch.md
  - pattern-shell-portability.md
  - case-2026-08-11-absence-claim-from-truncated-listing.md
  - principle-verify-before-acting.md
edges:
  - specializes: principle-verify-before-acting.md
  - similar_to: case-2026-08-11-absence-claim-from-truncated-listing.md
  - similar_to: pattern-shell-portability.md

modification_history:
  - date: 2026-08-11
    change: created
    reason: "три независимых кейса одной формы (04-15 grep+set -e, 04-22 pipefail+head+jq, 08-11 утверждения тестов) плюс два живых случая из BACKLOG D50 (launchctl 07-31, count-stats 08-08); tier 2 — триггеры смежные, родителя-принципа для класса не было, промоушен подтверждён собеседником"
provenance_log:
  - date: 2026-08-11
    kind: reinforced
    reason: "механизм доказан замером, а не рассуждением: на фикстуре 3 КБ в тишине 0 ложных ответов из 400, под нагрузкой 8 из 2000 — все восемь с кодом 141; опровергнута прежняя оценка охвата, по которой встроенный producer (echo \"$var\") считался безопасным"
    trigger_case: case-2026-08-11-assertion-answer-from-broken-pipe.md
  - date: 2026-08-11
    kind: reinforced
    reason: "свод по хукам подтвердил охват: 114 мест в 30 файлах, включая две строки knowledge-capture-reminder, ради которых заводился D50"
    trigger_case: case-2026-08-11-assertion-answer-from-broken-pipe.md
  - date: 2026-08-25
    kind: reinforced
    reason: "Прогнал mcp-тесты с 'tail -1', получил строку DeprecationWarning и прочитал её как успех. Реально было '2 failed, 119 passed'. Два падения от моих же правок пролежали незамеченными до следующей проверки."
---

Если статус конвейера — это ОТВЕТ (условие `if`, присваивание, `&& exit`), потребителю нельзя выходить раньше producer'а. Под `set -o pipefail` такой пайплайн возвращает 141 — статус убитого SIGPIPE producer'а, — и «нашёл» приходит как «не нашёл». Писать `grep -q "$needle" <<< "$haystack"` или читать из файла; конвейер оставлять только там, где статус не потребляется.

**Why:** три независимых случая одной формы. 2026-04-15: `grep` без совпадения под `set -e` уронил хук. 2026-04-22: `| head -3` после `jq` дал 141 и оборвал consumer. 2026-08-11: помощник утверждения `echo "$haystack" | grep -q "$needle"`, скопированный в 66 файлов тестов из 93, четыре дня давал красные прогоны CI на детерминированной фикстуре — три сессии искали причину в локали, реализации awk и стороже по таймауту. Плюс два живых случая вне тестов: `launchctl list | grep -q` (дефект выглядел как «две трети заданий выгружены») и `count-stats.sh … | head -1` (скрипт умер до секции патча, патч молча не состоялся). Общее у всех: код детерминирован, а отказ приходит от планировщика — поэтому обвиняют среду.

**How to apply:** признак синтаксический, не оценочный — искать потребителя с ранним выходом (`grep -q`, `head`, `sed -n '1p'`, `read` одной строкой) в пайплайне, чей статус потребляется, при включённом `pipefail`. Особая бдительность в двух местах: помощники утверждений в тестах (одна строка тиражируется копированием во все файлы сюиты) и ранние `… && exit 0` в хуках (там инверсия ответа тихо отключает исключение или защиту). Правило держится стражем, а не текстом: этот же запрет дважды писали комментарием в коде и он возвращался третьим путём.

**Limitations:** не про потребителей, читающих вход до конца (`grep -c`, `wc`, `sort`) — они SIGPIPE не вызывают. Не повод снимать `pipefail`: он ловит настоящие отказы в середине конвейера, и снятие поменяло бы редкую ложь на постоянную слепоту. Намеренное воспроизведение дефекта (отрицательный контроль в тесте) — законное исключение и помечается явно. Вероятность отказа мала на незагруженной машине: отсутствие воспроизведения в тишине ничего не опровергает, проверять под нагрузкой.
