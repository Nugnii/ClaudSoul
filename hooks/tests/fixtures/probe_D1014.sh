#!/usr/bin/env bash
# СУДИТ: hooks/backlog-reading-refresh.sh
# probe_D1014.sh — касание бэклога не держит ход, пока сверяются показания (D1014).
#
# Коды: 0 — хук на чтении BACKLOG.md вернулся за 5 с и запустил сверку фоном (замок полосы с живым
#       владельцем в своей группе процессов), хотя сверка показаний здесь идёт дольше; 1 — хук ждал
#       сверку (дефект D1014) либо вернулся, ничего не запустив; 2 — рамка не поднялась либо сверка здесь
#       укладывается в 5 с: ждать нечего, предмета нет (раннер CI без корпуса расшифровок).
# Названный предел: запуск судится по ФОРМЕ — замок с живой группой владельца. Хук, кладущий его без
# работы, пробу позеленит; работу прогона судят ноги T17–T34 свидетеля test_backlog_reading_refresh.sh.
# Условие снятия: у прогона появится собственный след работы (журнал витков) — тогда проба судит его.
# Песочница: каталог состояния и журнал устаревших чтений — во временной папке, живые не трогаются.
# Срок — у владельца, `hooks/timeout-lib.sh` (`run_with_timeout`, код 124, снятие дерева): своя копия
# ограничителя была бы родом K. Вход хуку подаётся ВНУТРИ команды: ограничитель ставит её фоном, а фоновая
# команда без управления заданиями получает пустой ввод — хук молча вышел бы, и проба зеленела бы ложно.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
REPO=$(cd "$REPO" 2>/dev/null && pwd) || exit 2
[ -f "$REPO/BACKLOG.md" ] && [ -f "$REPO/scripts/backlog-refresh-readings.sh" ] \
    && [ -f "$REPO/hooks/backlog-reading-refresh.sh" ] && [ -f "$REPO/hooks/timeout-lib.sh" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
# shellcheck source=/dev/null
. "$REPO/hooks/timeout-lib.sh"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" || exit 2

# Положительный контроль: та же сверка, что хук зовёт на чтении, сама по себе дольше срока.
run_with_timeout 5 env BACKLOG_FILE="$REPO/BACKLOG.md" CLAUDSOUL_REPO="$REPO" STALE_JOURNAL="$T/stale.jsonl" \
    bash "$REPO/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1
[ $? -eq 124 ] || exit 2

jq -cn --arg f "$REPO/BACKLOG.md" '{tool_name: "Read", tool_input: {file_path: $f}, session_id: "probe-D1014"}' \
    > "$T/in" || exit 2
run_with_timeout 5 env STATE_DIR="$T/state" BRR_TRUSTED_ROOT="$REPO" \
    sh -c 'exec bash "$0" < "$1"' "$REPO/hooks/backlog-reading-refresh.sh" "$T/in" >/dev/null 2>&1
rc=$?
# Вернувшийся в срок хук обязан был ЗАПУСТИТЬ сверку: иначе пробу зеленит хук, не делающий ничего
# (финальный скептик D1014). Прогон снимается сразу после замера — полная сверка живого дерева не должна
# жить после пробы: гейт гонит «Проверку» на границе хода. Снятие обязано ПРОЙТИ: прогон вне своей группы
# (без `set -m`) пережил бы пробу, а `kill` такой группы не найдёт и скажет об этом кодом.
pid=$(awk 'NR == 1 { print $1 }' "$T/state/backlog-reading-refresh-check.lock/owner" 2>/dev/null)
case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
kill -KILL -- "-$pid" 2>/dev/null || exit 1
[ "$rc" -ne 124 ]
