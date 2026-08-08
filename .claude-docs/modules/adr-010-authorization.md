# Модуль: контур авторизации и бюджета вмешательства (ADR-010)

**Назначение.** Отличать правки под поручением собеседника от самовольных и делать бюджет проактивных действий действующим регулятором: авторизация — состояние задачи, не свойство предыдущей реплики.

**Файлы.** `hooks/authorization-lib.sh` (состояние + словари маркеров, единый источник), `hooks/budget-gate.sh` (PreToolUse-гейт: unsolicited-правка при пустом бюджете → advisory-инжект), `hooks/itr-event-detector.sh` (writer/reader состояния; события solicited), `scripts/ab-authorization-replay.sh` (A/B на корпусе).

**Зависимости.** portable-lib (to_lower), intrusiveness-state-lib (`itr_remaining_budget`, `itr_log_event`), hook-input-lib (фильтр синтетики), lib/backfill-replay-one.sh (реплей для A/B; authorization-lib в его фиксированном списке).

**Правила.** Поручение/продолжение в реальной реплике взводит состояние; гасит только следующая реальная реплика не-продолжение. Синтетические user-строки состояние не трогают (по построению). Solicited-события бюджет не тратят. Гейт молчит: под авторизацией, без файла состояния, повторно за сессию. Изменения семантики классификатора — только после A/B-реплея (`AUTH_ONESHOT_ONLY=1` — измерительная ручка, боевой путь её не ставит). Тесты: test_authorization_state, test_budget_gate, test_itr_event_detector, test_backfill.
