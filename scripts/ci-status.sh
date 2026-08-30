#!/usr/bin/env bash
# ci-status.sh — состояние прогона ДЛЯ ЭТОГО коммита, а не «самого свежего».
# Результат: исход CI известен ДЛЯ ЭТОГО коммита, а не для самого свежего прогона
# Проверка результата: bash scripts/ci-status.sh <sha> печатает статус именно этого sha
#
#
# Повод, и он дорогой. Я дважды объявил собеседнику «CI зелёный», когда прогон был красным
# (v1.17.0 и v1.17.2). Причина не в CI: я опрашивал `gh run list -L 1`, то есть «самый
# свежий прогон». Сразу после `git push` самым свежим ещё числится ПРЕДЫДУЩИЙ — новый не
# успел зарегистрироваться. Цикл видел завершённый прошлый прогон, печатал его исход и
# выходил.
#
# Это ровно `pattern-subject-of-measurement-mismatch`, записанный за десять минут до
# инцидента: предмет замера («последний прогон») не тот, о котором утверждение («прогон
# моего коммита»). Отрицательного контроля здесь нет и быть не может — ответ приходит
# правдоподобный, просто о другом объекте.
#
# Поэтому здесь опрашивается прогон, чей `headSha` совпадает с проверяемым коммитом.
# Если такого прогона ещё нет — это НЕ «зелено», это «прогон не найден», отдельный код.
#
# Использование:
#   scripts/ci-status.sh              # для HEAD, ждать завершения
#   scripts/ci-status.sh <sha>        # для конкретного коммита
#   CI_WAIT=0 scripts/ci-status.sh    # не ждать, вернуть текущее состояние
#
# Коды возврата: 0 — успех; 1 — провал; 2 — прогон для коммита не найден либо не дождались.

set -uo pipefail

# Короткий SHA разрешается в полный ДО поиска: сравнение «начинается с» между двумя
# сокращениями разной длины даёт ложное несовпадение, и цикл ждёт прогон, который есть.
SHA="${1:-HEAD}"
SHA=$(git rev-parse "$SHA" 2>/dev/null || printf '%s' "$SHA")
[ -n "$SHA" ] || { echo "ci-status: не удалось определить коммит" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "ci-status: нужен gh" >&2; exit 2; }

WAIT="${CI_WAIT:-1}"
INTERVAL="${CI_POLL_INTERVAL:-20}"
MAX_TRIES="${CI_MAX_TRIES:-30}"

_lookup() {
    # Ищем среди последних прогонов ТОТ, чей headSha совпадает. `-L 1` не годится:
    # сразу после push самым свежим числится предыдущий прогон.
    gh run list -L 20 --json databaseId,headSha,status,conclusion \
        --jq '.[] | "\(.databaseId) \(.headSha) \(.status) \(if (.conclusion // "") == "" then "-" else .conclusion end)"' 2>/dev/null \
        | awk -v sha="$SHA" '$2 == sha { print $1, $3, $4; exit }' 
}

tries=0
while :; do
    row=$(_lookup)
    if [ -z "$row" ]; then
        [ "$WAIT" = "1" ] || { echo "прогон для ${SHA:0:7} не найден"; exit 2; }
        tries=$((tries + 1))
        [ "$tries" -ge "$MAX_TRIES" ] && { echo "прогон для ${SHA:0:7} не появился за $((MAX_TRIES * INTERVAL)) с"; exit 2; }
        sleep "$INTERVAL"
        continue
    fi
    # Разбор через `read` с умолчаниями, а не `set -- $row`: у только что созданного
    # прогона `conclusion` бывает ПУСТОЙ СТРОКОЙ, а `//` в jq подставляет только вместо
    # `null`. Поле исчезало, третий позиционный параметр не существовал, и скрипт падал
    # под `set -u` — то есть инструмент против ложного «зелено» сам сообщал провал.
    id=""; status=""; conclusion=""
    read -r id status conclusion <<EOF
$row
EOF
    : "${id:=неизвестен}"; : "${status:=unknown}"; : "${conclusion:=-}"
    if [ "$status" != "completed" ]; then
        [ "$WAIT" = "1" ] || { echo "прогон ${id} для ${SHA:0:7}: ${status}"; exit 2; }
        tries=$((tries + 1))
        [ "$tries" -ge "$MAX_TRIES" ] && { echo "прогон ${id} не завершился за $((MAX_TRIES * INTERVAL)) с"; exit 2; }
        sleep "$INTERVAL"
        continue
    fi
    echo "прогон ${id} для ${SHA:0:7}: ${conclusion}"
    [ "$conclusion" = "success" ] && exit 0
    echo "  подробности: gh run view ${id} --log-failed" >&2
    # Красный прогон СВОЕГО коммита — повод разбора (D200). Прежде исход печатался и
    # никуда не вёл: провал проверки на собственном коммите есть прямое свидетельство
    # дефекта, а контур разбора о нём не знал. Повод стоячий, отказа по нему не бывает.
    _RC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../hooks" 2>/dev/null && pwd)/root-cause-lib.sh"
    [ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
    if [ -f "$_RC_LIB" ]; then
        # shellcheck source=/dev/null
        . "$_RC_LIB"
        rc_note_event "${STATE_DIR:-$HOME/.claude/hooks/state}" "ci-red" \
            "прогон ${id} для ${SHA:0:7}: ${conclusion}"
    fi
    exit 1
done
