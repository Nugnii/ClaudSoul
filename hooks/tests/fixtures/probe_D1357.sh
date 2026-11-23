#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh
# probe_D1357.sh — повод, закрытый разбором в прошлом ходе (метка `chain-ok` журнала стража), напоминания «исхода не
#   видно» в следующем ходе не даёт; повод без исхода по-прежнему называется.
#
# Повод (22 ноября 2026, D1357, сессия ProjectA 9ea931f4). Повод `rework:…/test-ui-system-gate-stand.sh:1` закрыт в ходе
# 3101911555 (`chain-ok`, строка 33 журнала), в ходах 3764654277 и 2909120426 страж записал его снова, и напоминание
# на Stop (`hooks/declared-problem-recorded.sh:375`, `TURN_FINDS`) посчитало его поводом хода без исхода; `outcome.sh`
# по `rc_chain_ok_tokens` отвечал «исход уже принят» — снять напоминание было нечем.
# Проверка результата: bash hooks/tests/fixtures/probe_D1357.sh → 0 — закрытый повод молчит, открытый назван;
#   1 — закрытый назван или открытый промолчал; 2 — не измерено (нет хука, jq, python3; контроль не назвал открытый).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/declared-problem-recorded.sh"
[ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
    || { echo "нет хука, jq или python3 — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
SID="d1357probe"; STATE="$W/state"; mkdir -p "$STATE"
USER_TEXT="дальше"; TURN_KEY=$(printf '%s\n' "$USER_TEXT" | cksum | awk '{print $1}')
NOW=$(date -u +%s); T_TURN=$((NOW - 600))
ISO=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$T_TURN")
T="$W/t.jsonl"
{ printf '{"type":"user","message":{"role":"user","content":"старое"},"timestamp":"2026-01-01T00:00:00Z"}\n'
  printf '{"type":"user","message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$ISO"; } > "$T"
TOK='rework:/x/scripts/tests/test-ui-system-gate-stand.sh:1'
# judge <журнал> ; печатает очередь напоминаний
judge() {
    printf '%s' "$1" > "$STATE/five-whys-${SID}.seen"
    : > "$STATE/stop-signals-${SID}.txt"; rm -f "$STATE"/*declared-problem* 2>/dev/null
    printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$SID" "$T" \
      | STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$W/BACKLOG.md" bash "$HOOK" >/dev/null 2>&1
    cat "$STATE/stop-signals-${SID}.txt" 2>/dev/null
}
# Контроль: тот же повод без метки закрытия — напоминание есть.
open=$(judge "turn:${TURN_KEY}|actor:|${TOK}|
")
grep -q 'исхода не видно' <<< "$open" || { echo "открытый повод не назван — рамка не умеет сказать «да»; не измерено"; exit 2; }
# Случаи — по форме строки хода из мира: `turn:K|actor:A|tok1|tok2|…|` (hooks/five-whys-gate.sh:910), поводов в строке
# бывает несколько (2687 из 3513 строк журналов). Первая редакция пробы держала по одному поводу на строку, и пять
# неверных починок её проходили (скептик opus H1 по 4182b947): судился только третий столбец.
COR='correction:999'; TOKB='rework:/x/b.sh:1'; TOKZ='rework:/x/z.sh:1'; TOK12='rework:/x/scripts/tests/test-ui-system-gate-stand.sh:12'
rc=0
# expect <тишина|напоминание> <что подано> <очередь> [вид, который обязан стоять в «поводы:»] [вид, которого там быть не должно]
expect() {
    if grep -q 'исхода не видно' <<< "$3"; then got=напоминание; else got=тишина; fi
    if [ "$got" != "$1" ]; then echo "$2: $got, а ждали «$1»"; rc=1; return; fi
    if [ -n "${4:-}" ] && ! grep -q "поводы: [^)]*$4" <<< "$3"; then echo "$2: в «поводы:» нет $4"; rc=1; return; fi
    if [ -n "${5:-}" ] && grep -q "поводы: [^)]*$5" <<< "$3"; then echo "$2: в «поводы:» назван закрытый $5"; rc=1; return; fi
    echo "$2: $got"
}
expect тишина "закрыт в прошлом ходе" "$(judge "turn:111|actor:|${TOK}|
chain-ok|${TOK}|
turn:${TURN_KEY}|actor:|${TOK}|
")"
expect напоминание "закрыт первый повод строки, открыт второй" "$(judge "chain-ok|${TOK}|
turn:${TURN_KEY}|actor:|${TOK}|${COR}|
")" correction rework
expect напоминание "закрыт второй повод строки, открыт первый" "$(judge "chain-ok|${COR}|
turn:${TURN_KEY}|actor:|${TOK}|${COR}|
")" rework correction
expect тишина "закрыты все поводы строки" "$(judge "chain-ok|${TOK}|${COR}|
turn:${TURN_KEY}|actor:|${TOK}|${COR}|
")"
expect напоминание "закрыт другой файл того же вида" "$(judge "chain-ok|${TOKZ}|
turn:${TURN_KEY}|actor:|${TOK}|
")" rework
expect напоминание "закрыт повод, чей токен — начало открытого" "$(judge "chain-ok|${TOK}|
turn:${TURN_KEY}|actor:|${TOK12}|
")" rework
expect напоминание "закрыт файл второй позиции, открыт другой файл" "$(judge "chain-ok|${TOK}|
turn:${TURN_KEY}|actor:|${TOK}|${TOKB}|
")" rework
exit "$rc"
