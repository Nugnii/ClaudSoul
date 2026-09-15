#!/usr/bin/env bash
# test_declared_problem_channel.sh — сверщик говорит в канал, который читает ход.
#
# Результат: сообщение сверщика попадает в очередь `pending-alerts.txt`; дроссель держит
#            повтор того же СОСТАВА и пропускает изменившийся
# Проверка результата: bash hooks/tests/test_declared_problem_channel.sh даёт 0
#
# Повод. Внутреннее измерение (`hooks/error-tracker.sh:44-47`): «15 срабатываний прежней
# версии ушли в один только `systemMessage`, и ни на одно из них ход не отреагировал —
# записи `hook_system_message` в поток сообщений не попадают». Сверщик исхода и
# completion-gate печатали ровно туда: срабатывали, но не действовали, а в VSCode этот
# канал не рендерится вовсе. Прямой `additionalContext` на Stop незаконен — он
# перезапускает ход, — поэтому канал общая очередь, которую показывает
# `pending-alerts-surface.sh` на следующем UserPromptSubmit.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/declared-problem-recorded.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1));
       echo "FAIL: $1"; echo "   ожидалось: [$2]  получено: [$3]"; fi; }

# Помощника берём ИЗ ХОКА, а не переписываем: копия правила у потребителя — род K.
HELPER="$TMP/helper.sh"
cp "$ROOT/hooks/throttle-lib.sh" "$TMP/"   # dpr_surface ищет дроссель рядом с собой, затем в ~/.claude — на CI пусто
awk '/^dpr_surface\(\) \{/,/^\}/' "$HOOK" > "$HELPER"
[ -s "$HELPER" ] || { echo "FAIL: dpr_surface не извлечён — признак устарел"; exit 1; }

STATE="$TMP/state"; mkdir -p "$STATE"
SID=t1
# shellcheck source=/dev/null
. "$HELPER"

queued() { wc -l < "$STATE/pending-alerts.txt" 2>/dev/null | tr -d ' '; }

dpr_surface "turn:discovery:1" "сообщение А" >/dev/null 2>&1
ck "сообщение попало в очередь" "1" "$(queued)"

dpr_surface "turn:discovery:1" "сообщение А" >/dev/null 2>&1
ck "тот же состав — дроссель держит" "1" "$(queued)"

dpr_surface "turn:discovery,rework:2" "сообщение Б" >/dev/null 2>&1
ck "изменившийся состав — звучит заново" "2" "$(queued)"

ck "текст сообщения дошёл целиком" "сообщение Б" "$(tail -1 "$STATE/pending-alerts.txt")"

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
