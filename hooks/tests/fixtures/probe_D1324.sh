#!/usr/bin/env bash
# СУДИТ: hooks/intrusiveness-state-lib.sh hooks/intrusiveness-format-lib.sh
# probe_D1324.sh — обёртка командной строки библиотек интрузивности записывает событие, а не отвечает 0 впустую.
#
# Проверка результата: bash hooks/tests/fixtures/probe_D1324.sh → 0 — `intrusiveness-state-lib.sh log …` положил событие
#   в состояние сессии; 1 — ответ 0, а события нет (дефект); 2 — не измерено (нет jq).
# Положительный контроль: та же запись через `source` и `itr_log_event` событие кладёт — иначе 2 (сломана рамка).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v jq >/dev/null 2>&1 || { echo "нет jq — не измерено"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export ITR_STATE_DIR="$T/s" STATE_DIR="$T/s" HOME="$T/h"; mkdir -p "$ITR_STATE_DIR" "$HOME"
events() { jq '.events | length' "$ITR_STATE_DIR/intrusiveness-$1.json" 2>/dev/null || echo 0; }

bash -c 'source "$1/hooks/intrusiveness-state-lib.sh" && itr_log_event ctl override pending 4 "контроль"' _ "$REPO" >/dev/null 2>&1
[ "$(events ctl)" -ge 1 ] 2>/dev/null || { echo "рамка: itr_log_event через source не записал событие — не измерено"; exit 2; }

bash "$REPO/hooks/intrusiveness-state-lib.sh" log cli override pending 4 "через обёртку" >/dev/null 2>&1
n=$(events cli)
[ "${n:-0}" -ge 1 ] 2>/dev/null && { echo "событие записано обёрткой ($n)"; exit 0; }
echo "обёртка ответила, а событий в состоянии сессии: ${n:-0}"; exit 1
