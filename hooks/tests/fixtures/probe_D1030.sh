#!/usr/bin/env bash
# СУДИТ: scripts/outcome-share.sh hooks/rework-detector.sh
# probe_D1030.sh — прибор исходов не одобряет стража по его ярлыкам, а журнал переработки несёт время.
#
# Повод (23 октября 2026, разбор D1029): прибор считал успехом и отказ стража, и его снятие чтениями и
# выносил «уровень соответствует» — ни одного `none` из 24 и 21 записей в сессиях, где владелец видел
# починку симптомов, а переработка тех же файлов шла до глубины 7–8. Мера действия миром (повтор после
# починки) — следующий пункт; здесь — честность вердикта и время в журнале, без которого её не построить.
# Журнал создаёт НАСТОЯЩИЙ писатель (хук исполняется), а не рука пробы: две редакции меры, написанные по
# форме, которой писатель не производит, опровергнуты скептиком.
#
# Код: 0 — обе стороны держат; 1 — нога красная; 2 — нечем мерить.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
OS="$REPO/scripts/outcome-share.sh"; RD="$REPO/hooks/rework-detector.sh"
[ -f "$OS" ] && [ -f "$RD" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
RED=0
mkdir -p "$T/state" "$T/os"
# Писатель: правка → прогон → правка — второй заход пишет строку журнала переработки.
ed() { jq -cn '{session_id:"p1", tool_name:"Edit", tool_input:{file_path:"/repo/x.sh"}}' | STATE_DIR="$T/state" bash "$RD" >/dev/null 2>&1; }
run() { jq -cn '{session_id:"p1", tool_name:"Bash", tool_input:{command:"bash test.sh"}}' | STATE_DIR="$T/state" bash "$RD" >/dev/null 2>&1; }
ed; run; ed
RF=$(ls "$T/state"/rework-fired-p1*.jsonl 2>/dev/null | head -1)
[ -n "$RF" ] || exit 2
grep -qE '^\{"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z","path":"/repo/x\.sh","cycles":[0-9]+\}$' "$RF" \
    || { echo "КРАСНАЯ: строка журнала переработки без времени первым полем: $(head -1 "$RF")"; RED=1; }
# Прибор: у срода только ярлыки решения стража — одобрения быть не должно.
for i in 1 2 3; do
    printf '{"ts":"2026-10-22T18:0%s:00Z","key":"k%s","signal":"rework","outcome":"looked","ref":"x.sh"}\n' "$i" "$i"
done > "$T/os/outcome-s1.jsonl"
OUT=$(OUTCOME_SHARE_MIN_N=1 STATE_DIR="$T/os" bash "$OS" 2>/dev/null)
grep -q 'rework:' <<< "$OUT" || exit 2
grep -q 'уровень соответствует' <<< "$OUT" && { echo "КРАСНАЯ: прибор одобряет стража по ярлыкам решения"; RED=1; }
grep -q 'миром не измерено' <<< "$OUT" || { echo "КРАСНАЯ: прибор не называет, что действие миром не измерено"; RED=1; }
exit "$RED"
