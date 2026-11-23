#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh hooks/root-cause-lib.sh
# probe_D1360.sh — повод, закрытый сверенной строкой `manual-` журнала исходов (без `chain-ok` в журнале стража),
#   напоминания «исхода не видно» не даёт и строки `none` не получает; повод без исхода по-прежнему называется.
#
# Повод (22 ноября 2026, D1360, скептик opus M1 по 4182b947). Сессия 4b061a57: `manual-3208497512` (`disproved`,
# `toks: correction:2502792115`) закрыл повод в ходе 2741907583, `chain-ok` страж не записал (следующей записи с правом
# на отказ не было), и в ходе 1412929087 хук на Stop записал `none` по тому же поводу: закрытость он судил только по
# `rc_chain_ok_tokens`, а `scripts/outcome.sh` — и по сверенной строке `manual-`, и отбил бы исход «уже принят».
# Проверка результата: bash hooks/tests/fixtures/probe_D1360.sh → 0 — закрытый молчит, открытый назван, исход этого хода
#   записан `recorded`; 1 — иначе; 2 — не измерено (нет хука, jq, python3; контроль не назвал открытый).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/declared-problem-recorded.sh"
[ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
    || { echo "нет хука, jq или python3 — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
W=$(cd "$W" && pwd -P)
SID="d1360probe"; STATE="$W/state"; mkdir -p "$STATE"
USER_TEXT="дальше"; TURN_KEY=$(printf '%s\n' "$USER_TEXT" | cksum | awk '{print $1}')
NOW=$(date -u +%s); T_TURN=$((NOW - 600))
iso() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
T="$W/t.jsonl"
{ printf '{"type":"user","message":{"role":"user","content":"старое"},"timestamp":"2026-01-01T00:00:00Z"}\n'
  printf '{"type":"user","message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$(iso "$T_TURN")"; } > "$T"
TOK='correction:2502792115'; TOKR='rework:/x/b.sh:1'
OLD_TS='2026-01-01T00:00:00Z'; THIS_TS=$(iso $((NOW - 60)))
# manual <ts> <исход> <довод> <токен> — строка журнала исходов в форме `rc_log_outcome` (ключ перед сигналом).
manual() { printf '{"ts":"%s","key":"manual-%s","signal":"%s","outcome":"%s","ref":"%s","v":2,"toks":["%s"]}\n' \
    "$1" "$RANDOM" "${4%%:*}" "$2" "$3" "$4"; }
# journal <якорь прошлого хода> <якорь этого хода> <строка хода> — журнал стража: повод жив в прошлом ходе 111 и в этом.
journal() { printf '%s\n' "outfrom|turn:111|$1|" "live|turn:111|${TOK}|${W}|" "turn:111|actor:|${TOK}|" \
    "outfrom|turn:${TURN_KEY}|$2|" "live|turn:${TURN_KEY}|${TOK}|${W}|" "live|turn:${TURN_KEY}|${TOKR}|${W}|" "$3"; }
# judge <журнал стража> <журнал исходов> ; печатает очередь напоминаний, журнал исходов остаётся в $STATE
judge() {
    printf '%s' "$1" > "$STATE/five-whys-${SID}.seen"
    # Строка журнала исходов кончается переводом строки, как у `rc_log_outcome`: без него запись хука приклеилась бы к ней.
    : > "$STATE/outcome-${SID}.jsonl"; [ -z "$2" ] || printf '%s\n' "$2" > "$STATE/outcome-${SID}.jsonl"
    : > "$STATE/stop-signals-${SID}.txt"; rm -f "$STATE"/*declared-problem* 2>/dev/null
    ( cd "$W" && printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s","cwd":"%s"}' "$SID" "$T" "$W" \
      | STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$W/BACKLOG.md" bash "$HOOK" >/dev/null 2>&1 )
    cat "$STATE/stop-signals-${SID}.txt" 2>/dev/null
}
pair() { grep "\"key\":\"${TURN_KEY}\",\"signal\":\"$1\"" "$STATE/outcome-${SID}.jsonl" 2>/dev/null | jq -r '.outcome' 2>/dev/null | paste -sd, -; }
LINE1="turn:${TURN_KEY}|actor:|${TOK}|"
# Контроль: повод без исхода — напоминание и `none`.
open=$(judge "$(journal 0 0 "$LINE1")" "")
grep -q 'исхода не видно' <<< "$open" && [ "$(pair correction)" = none ] \
    || { echo "открытый повод не назван — рамка не умеет сказать «да»; не измерено"; exit 2; }
rc=0
# expect <тишина|напоминание> <что подано> <очередь> [вид, который обязан стоять в «поводы:»] [вид, которого там быть не должно]
expect() {
    if grep -q 'исхода не видно' <<< "$3"; then got=напоминание; else got=тишина; fi
    if [ "$got" != "$1" ]; then echo "$2: $got, а ждали «$1»"; rc=1; return 1; fi
    if [ -n "${4:-}" ] && ! grep -q "поводы: [^)]*$4" <<< "$3"; then echo "$2: в «поводы:» нет $4"; rc=1; return 1; fi
    if [ -n "${5:-}" ] && grep -q "поводы: [^)]*$5" <<< "$3"; then echo "$2: в «поводы:» назван закрытый $5"; rc=1; return 1; fi
    echo "$2: $got"
}
# Закрыт в прошлом ходе: строка исхода после якоря первого хода повода (0), до якоря этого хода (1).
expect тишина "закрыт строкой manual- в прошлом ходе" \
    "$(judge "$(journal 0 1 "$LINE1")" "$(manual "$OLD_TS" disproved "опровергнуто" "$TOK")")" \
    && { [ -z "$(pair correction)" ] || { echo "закрыт в прошлом ходе: строка исхода хода «$(pair correction)», а ждали никакой"; rc=1; }; }
expect напоминание "строка manual- отвергнута сверкой" \
    "$(judge "$(journal 0 1 "$LINE1")" "$(manual "$OLD_TS" fixed "D99999 записано" "$TOK")")" correction
expect напоминание "строка manual- о другом поводе того же вида" \
    "$(judge "$(journal 0 1 "$LINE1")" "$(manual "$OLD_TS" disproved "опровергнуто" "correction:999")")" correction
# Строка старше первого хода повода: якорь хода 111 — 1, строка исхода — первая, окно её не берёт (D1243).
expect напоминание "строка manual- старше первого хода повода" \
    "$(judge "$(journal 1 1 "$LINE1")" "$(manual "$OLD_TS" disproved "опровергнуто" "$TOK")")" correction
expect напоминание "в строке хода закрытый manual- и открытый повод другого вида" \
    "$(judge "$(journal 0 1 "turn:${TURN_KEY}|actor:|${TOK}|${TOKR}|")" "$(manual "$OLD_TS" disproved "опровергнуто" "$TOK")")" rework correction
# Закрыт в этом же ходе: напоминания нет, а исход хода хук записывает `recorded` (turn_outcome_verified) — терять нельзя.
expect тишина "закрыт строкой manual- в этом же ходе" \
    "$(judge "$(journal 0 0 "$LINE1")" "$(manual "$THIS_TS" disproved "опровергнуто" "$TOK")")" \
    && { [ "$(pair correction)" = recorded ] || { echo "закрыт в этом же ходе: строка исхода хода «$(pair correction)», а ждали recorded"; rc=1; }; }
exit "$rc"
