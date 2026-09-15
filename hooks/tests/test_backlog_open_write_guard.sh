#!/usr/bin/env bash
# test_backlog_open_write_guard.sh — страж записи открытого пункта с зелёной или отсутствующей «Проверкой» (D264).
# Результат: новый или изменённый открытый пункт с зелёной «Проверкой» отбивается с именем; без строки
#            «Проверка» — тоже; красный проходит; закрытый пункт, неизменённые пункты, чужие файлы,
#            битый payload — тишина; срыв бюджета — не отказ, а контекст и журнал; отказ пишет журнал.
# Проверка результата: bash hooks/tests/test_backlog_open_write_guard.sh даёт 0
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/backlog-open-write-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
PROJ="$TMP/proj"; mkdir -p "$PROJ"; STATE="$TMP/state"
BL="$PROJ/BACKLOG.md"
cat > "$BL" <<'EOF'
# BACKLOG

- ☐ **D10** красный открытый пункт, не меняется
  **Проверка.** `false` → 0
- ☐ **D11** открытый пункт с зелёной проверкой уже на диске (не наш предмет, пока не меняется)
  **Проверка.** `true` → 0
- ☑ **D12** закрытый
  **Проверка.** `true` → 0
EOF
edit() {  # edit <old> <new> [sid] → вывод хука
    jq -cn --arg f "$BL" --arg o "$1" --arg n "$2" --arg s "${3:-s1}" \
        '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
    | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
write() { # write <content> [sid]
    jq -cn --arg f "$BL" --arg c "$1" --arg s "${2:-s1}" \
        '{session_id:$s, tool_name:"Write", tool_input:{file_path:$f, content:$c}}' \
    | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
denied() { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
# Тишина — своим утверждением, а не `[ -z ]`: прувер стражей (test_guards_provable) требует у теста
# отказывающего хука и проверку срабатывания, и проверку тишины в узнаваемой форме.
assert_silent() { if [ -z "${1:-}" ]; then ok; else bad "$2" "ожидалась тишина, получено: $1"; fi; }
# --- T1: новый открытый пункт с зелёной проверкой — отказ с именем ---
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D13** новый зелёный\n  **Проверка.** `true` → 0\n- ☑ **D12** закрытый')
denied "$OUT" && ok || bad "T1" "новый открытый пункт с зелёной проверкой прошёл: $OUT"
grep -q "D13" <<< "$OUT" && ok || bad "T1b" "пункт не назван в отказе: $OUT"
grep -q "зелёная" <<< "$OUT" && ok || bad "T1c" "вид не назван: $OUT"
# --- T2: новый открытый пункт с красной проверкой — проходит ---
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D14** новый красный\n  **Проверка.** `false` → 0\n- ☑ **D12** закрытый')
assert_silent "$OUT" "T2 красный открытый пункт отбит"
# --- T3: новый открытый пункт без строки «Проверка» — отказ ---
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D15** без критерия\n  **Род.** нет\n- ☑ **D12** закрытый')
denied "$OUT" && grep -q "D15" <<< "$OUT" && grep -q "нет строки" <<< "$OUT" && ok || bad "T3" "пункт без «Проверки» прошёл или не назван: $OUT"
# --- T4: правка закрытого пункта с зелёной проверкой — проходит (открытых не касается) ---
OUT=$(edit "- ☑ **D12** закрытый" "- ☑ **D12** закрытый, переименован")
assert_silent "$OUT" "T4 правка закрытого пункта отбита"
# --- T5: неизменённый открытый пункт с зелёной проверкой на диске не судится при чужой правке ---
OUT=$(edit "# BACKLOG" "# BACKLOG проекта")
assert_silent "$OUT" "T5 неизменённый пункт D11 отбит при правке заголовка"
# --- T6: Write целиком — судятся только изменённые: команда D10 стала зелёной → отказ; D11 не бежит ---
# Первая замена — через python, не `sed 0,/re/`: адрес 0 знает только GNU sed (pattern-shell-portability).
NEWC=$(python3 -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); s = s.replace("**D10** красный открытый пункт, не меняется", "**D10** стал зелёным", 1).replace("`false` → 0", "`true` → 0", 1); sys.stdout.write(s)' "$BL")
T0=$(date +%s); OUT=$(write "$NEWC"); T1=$(( $(date +%s) - T0 ))
denied "$OUT" && grep -q "D10" <<< "$OUT" && ok || bad "T6" "изменённая на зелёную проверка не отбита при Write: $OUT"
grep -q "D11" <<< "$OUT" && bad "T6b" "неизменённый D11 попал в отказ при Write" || ok
# --- T7: закрытие пункта в той же правке (☐ → ☑) с зелёной проверкой — проходит ---
OUT=$(edit "- ☐ **D10** красный открытый пункт, не меняется" "- ☑ **D10** закрыт с показанием")
assert_silent "$OUT" "T7 закрытие пункта в правке отбито"
# --- T8: срыв бюджета — не отказ, а контекст; журнал видом timeout ---
OUT=$(OPEN_WRITE_TIMEOUT=1 STATE_DIR="$STATE" bash -c 'jq -cn --arg f "'"$BL"'" '"'"'{session_id:"s8", tool_name:"Edit", tool_input:{file_path:$f, old_string:"- ☑ **D12** закрытый", new_string:"- ☐ **D16** долгий\n  **Проверка.** `sleep 5` → 0\n- ☑ **D12** закрытый"}}'"'"' | bash "'"$HOOK"'" 2>/dev/null')
denied "$OUT" && bad "T8" "срыв бюджета выдан за зелёную: $OUT" || ok
grep -q "не уложилась" <<< "$OUT" && ok || bad "T8b" "срыв бюджета не назван контекстом: $OUT"
grep -q '"kind":"timeout"' "$STATE"/backlog-open-write-fired-s8.jsonl 2>/dev/null && ok || bad "T8c" "срыв не записан в журнал"
# --- T9: журнал отказа — семейство *-fired-*, вид green, имя пункта ---
grep -q '"kind":"green"' "$STATE"/backlog-open-write-fired-s1.jsonl 2>/dev/null && grep -q '"item":"D13"' "$STATE"/backlog-open-write-fired-s1.jsonl && ok || bad "T9" "отказ не записан в журнал семейства fired"
# --- T10: MultiEdit — правка, вносящая зелёный открытый пункт, отбита ---
OUT=$(jq -cn --arg f "$BL" '{session_id:"s10", tool_name:"MultiEdit", tool_input:{file_path:$f, edits:[{old_string:"# BACKLOG", new_string:"# BACKLOG"}, {old_string:"- ☑ **D12** закрытый", new_string:"- ☐ **D17** зелёный через MultiEdit\n  **Проверка.** `true` → 0\n- ☑ **D12** закрытый"}]}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
denied "$OUT" && grep -q "D17" <<< "$OUT" && ok || bad "T10" "MultiEdit с зелёным открытым пунктом прошёл: $OUT"
# --- T11: чужой файл и битый payload — тишина ---
OUT=$(jq -cn --arg f "$PROJ/README.md" '{session_id:"s11", tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
assert_silent "$OUT" "T11 чужой файл вызвал вывод"
OUT=$(printf 'не json' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null); assert_silent "$OUT" "T11b битый payload вызвал вывод"
# --- T12: диск не тронут ни одним вызовом (страж только судит) ---
grep -q '^- ☐ \*\*D10\*\* красный открытый пункт, не меняется$' "$BL" && ok || bad "T12" "страж изменил файл на диске"
echo "backlog open write guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
