#!/usr/bin/env bash
# test_five_whys_gate.sh — гейт разбора причин обязан говорить на повторе и молчать,
# когда разбор уже сделан.
#
# Повод — три напоминания собеседника за три недели об одном и том же приёме. Механизма
# не было; текстовое правило («назови 2-3 версии причины» в глобальных правилах) закрывало
# ощущение разбора шириной перебора вместо глубины цепочки.
#
# Проверяется не «работает ли скрипт», а три места, где он может соврать молча:
# промолчать при повторе (ради чего заведён), загореться там, где разбор уже произнесён
# (тогда он фон), и загореться без сигнала повтора вообще (тогда он шум на каждой правке).
# Отдельно — повтор в УСПЕХАХ: именно с этой поправки собеседника всё началось, и гейт,
# слушающий только провалы, воспроизвёл бы исходную слепоту.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/five-whys-gate.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"

ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
assert_silent() {
    if [ -z "$1" ]; then ok "$2"; else bad "$2 — ожидалась тишина, получено: $1"; fi
}

# Транскрипт: реплика собеседника, затем ответ агента с заданным текстом.
mk_transcript() {   # mk_transcript <файл> <текст ответа>
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    jq -cn --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}

call() {  # call <sid> <tool> [transcript]
    local sid="$1" tool="$2" tr="${3:-}"
    jq -cn --arg s "$sid" --arg t "$tool" --arg p "$tr" \
        '{session_id:$s, tool_name:$t, transcript_path:$p}' \
      | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null
}

TR_NO="$TMP/no.jsonl";  mk_transcript "$TR_NO"  "Правлю строку, сейчас будет зелено."
TR_YES="$TMP/yes.jsonl"; mk_transcript "$TR_YES" \
  "Почему упало — читался старый индекс. Почему старый — add шёл после. Почему не поймали — тест брал фикстуру."

# --- 1. Сигнала повтора нет — гейт молчит на любой правке.
assert_silent "$(call s1 Edit "$TR_NO")" "без сигнала повтора → тишина (не шум на каждой правке)"

# --- 2. Полоса провалов, разбора нет → горит.
touch "$STATE_DIR/error_streak_fired_s2"
OUT=$(call s2 Edit "$TR_NO")
grep -q "Признак повторяется" <<<"$OUT" && ok "полоса провалов без разбора → горит" \
                                        || bad "промолчал на полосе провалов: $OUT"
grep -q "полоса упавших команд" <<<"$OUT" && ok "названо, ЧТО именно повторяется" \
                                          || bad "не назван вид повтора"

# --- 3. Повтор в УСПЕХАХ (третий заход на файл) — тоже сигнал.
#     Гейт, слушающий только провалы, воспроизвёл бы слепоту, с которой всё началось.
printf '{"file":"a.sh"}\n' > "$STATE_DIR/rework-fired-s3.jsonl"
OUT=$(call s3 Write "$TR_NO")
grep -q "повторные заходы на один файл" <<<"$OUT" \
    && ok "повтор в успехах засчитан наравне с провалами" \
    || bad "успехи не считаются повтором: $OUT"

# --- 4. Разбор произнесён (три «почему») → молчит.
touch "$STATE_DIR/error_streak_fired_s4"
assert_silent "$(call s4 Edit "$TR_YES")" "цепочка «почему» в ответе → тишина"

# --- 5. Одно «почему» — не цепочка.
touch "$STATE_DIR/error_streak_fired_s5"
TR_ONE="$TMP/one.jsonl"; mk_transcript "$TR_ONE" "Почему упало — не тот путь. Чиню."
OUT=$(call s5 Edit "$TR_ONE")
grep -q "Признак повторяется" <<<"$OUT" && ok "одно «почему» не считается разбором" \
                                        || bad "одиночное «почему» приняло за цепочку"

# --- 6. Дедуп: тот же сигнал второй раз → молчит; новый сигнал → снова горит.
touch "$STATE_DIR/error_streak_fired_s6"
OUT=$(call s6 Edit "$TR_NO"); [ -n "$OUT" ] || bad "первое срабатывание не случилось"
assert_silent "$(call s6 Edit "$TR_NO")" "тот же сигнал повторно → тишина (не фон)"
printf '{"file":"b.sh"}\n' > "$STATE_DIR/rework-fired-s6.jsonl"
OUT=$(call s6 Edit "$TR_NO")
grep -q "Признак повторяется" <<<"$OUT" && ok "новый сигнал → говорит снова" \
                                        || bad "новый сигнал проигнорирован"

# --- 7. Чужие инструменты и пустой вход.
touch "$STATE_DIR/error_streak_fired_s7"
assert_silent "$(call s7 Read "$TR_NO")" "не-правящий инструмент игнорируется"
assert_silent "$(printf '' | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null)" "пустой вход → тишина"

# --- 8. Нет транскрипта — сигнал всё равно важнее: горит.
touch "$STATE_DIR/error_streak_fired_s8"
OUT=$(call s8 Edit "")
grep -q "Признак повторяется" <<<"$OUT" \
    && ok "без транскрипта гейт не глохнет (ошибка в сторону напоминания)" \
    || bad "без транскрипта промолчал: $OUT"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
