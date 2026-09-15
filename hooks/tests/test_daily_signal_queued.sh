#!/usr/bin/env bash
# test_daily_signal_queued.sh — суточный повтор знания не гейтит ход, а один раз в сутки ложится в
#                               очередь отложенных уведомлений (D358).
# Результат: при трёх подтверждениях одного знания за сутки поперёк сессий гейт разбора молчит в
#            ходе (ни напоминания, ни отказа) и пишет строку с именем знания в pending-alerts.txt;
#            второй ход тех же суток строку не дублирует; двух подтверждений мало; мутант гейта без
#            записи в очередь так же молчит, но строки не даёт — нога читает очередь, а не тишину.
# Проверка результата: bash hooks/tests/test_daily_signal_queued.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$(cd "$DIR/.." && pwd)"
HOOK="$HOOKS/five-whys-gate.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
TMP=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"
TR="$TMP/tr.jsonl"
jq -cn '{type:"assistant", timestamp:"2026-09-13T06:00:00Z", message:{role:"assistant", content:[{type:"text", text:"Правлю дальше."}]}}' > "$TR"
OUTC="$STATE_DIR/disagreement-outcomes.jsonl"
NOW_D=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
seed() {  # seed <знание> <число подтверждений>
    : > "$OUTC"; local i
    for i in $(seq 1 "$2"); do
        jq -cn --arg s "s$i" --arg d "$NOW_D" --arg k "$1" '{session:$s, knowledge:$k, outcome:"confirmed_knowledge", date:$d}' >> "$OUTC"
    done
}
call() {  # call <хук> <sid> → stdout хука на пишущей команде Bash
    jq -cn --arg s "$2" --arg p "$TR" '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"echo x > f.txt"}}' \
      | STATE_DIR="$STATE_DIR" bash "$1" 2>/dev/null
}
Q="$STATE_DIR/pending-alerts.txt"
# T1: три подтверждения → в ходе тишина, в очереди строка с именем знания
seed pattern-x.md 3; rm -f "$Q"
OUT=$(call "$HOOK" sid-1)
[ -z "$OUT" ] && ok || bad "T1a" "суточный факт дал вывод в ходе: ${OUT:0:160}"
grep -q "pattern-x" "$Q" 2>/dev/null && ok || bad "T1b" "очередь без строки о pattern-x: $(cat "$Q" 2>/dev/null)"
# T2: второй ход тех же суток (другая сессия) — строка не дублируется
call "$HOOK" sid-2 >/dev/null
[ "$(grep -c "pattern-x" "$Q" 2>/dev/null)" = 1 ] && ok || bad "T2" "строка продублирована: $(cat "$Q")"
# T3: другое знание за те же сутки — своя строка
seed pattern-y.md 3
call "$HOOK" sid-3 >/dev/null
grep -q "pattern-y" "$Q" 2>/dev/null && ok || bad "T3" "второе знание в очередь не попало"
# T4: двух подтверждений мало — ни строки, ни вывода
seed pattern-z.md 2
OUT=$(call "$HOOK" sid-4)
[ -z "$OUT" ] && ! grep -q "pattern-z" "$Q" 2>/dev/null && ok || bad "T4" "два подтверждения дали строку или вывод"
# T5: мутант без записи в очередь — так же молчит в ходе, но строки не даёт (нога читает очередь)
mkdir -p "$TMP/hooks"; cp -R "$HOOKS"/. "$TMP/hooks/"
M="$TMP/hooks/five-whys-gate.sh"
sed -i.bak 's|>> "\$STATE/pending-alerts.txt" 2>/dev/null \|\| true|>/dev/null|' "$M" && rm -f "$M.bak"
grep -q 'pending-alerts.txt" 2>/dev/null || true' "$M" && bad "T5" "мутант не собрался" || true
seed pattern-m.md 3; rm -f "$Q"; rm -f "$STATE_DIR"/daily-fired-*.jsonl
OUT=$(call "$M" sid-5)
[ -z "$OUT" ] && [ ! -s "$Q" ] && ok || bad "T5" "мутант: вывод «${OUT:0:80}», очередь «$(cat "$Q" 2>/dev/null)»"
echo "daily signal queued: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
