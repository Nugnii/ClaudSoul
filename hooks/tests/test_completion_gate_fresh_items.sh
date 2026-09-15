#!/usr/bin/env bash
# test_completion_gate_fresh_items.sh — пункт, заведённый в этой сессии, берётся сразу за
# текущей починкой: гейт на Stop называет свежий ☐, когда взятых в сессии ◐ не осталось.
#
# Результат: находка по ходу не лежит до аудита — напоминание приходит в момент, когда
#            текущая починка закрыта, и молчит, пока она идёт
# Проверка результата: bash hooks/tests/test_completion_gate_fresh_items.sh даёт 0
#
# Повод (12 сентября 2026, план разгребания долга): правило «находка по ходу заводится
# отдельным пунктом» не имело пары «взять сразу» — 43 открытых пункта, большинство заведены
# ровно так. Замер до кода: «нет ни одного ◐» не наступало ни разу за 60 коммитов (D264 и
# D282 стоят в ◐ десять дней), поэтому сравниваются ◐ ТЕКУЩЕЙ сессии — ◐ сейчас минус ◐ в
# снимке старта.
#
# Снимок кладёт сам тест через `backlog_snapshot` (владелец схемы — backlog-lib.sh): так
# каждая нога сама задаёт «что было на старте», а не наследует чужой снимок.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/completion-gate.sh"
LIB="$HOOKS_DIR/backlog-lib.sh"
[ -f "$HOOK" ] || { echo "SKIP: нет $HOOK"; exit 0; }
[ -f "$LIB" ]  || { echo "SKIP: нет $LIB"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"
command -v backlog_snapshot >/dev/null 2>&1 || { echo "FAIL: в библиотеке нет backlog_snapshot"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"

# Пункт списочной вёрстки с красной «Проверкой» — открытый пункт в контракте (порог 200).
item() { # $1 метка $2 id $3 хвост (необязательно: строка условия возврата)
    printf -- '- %s **%s** пункт %s\n  **Проверка.** `false` → 0\n%s' "$1" "$2" "$2" "${3:+  $3
}"
}
run() { # $1 бэклог $2 sid → печатает очередь, добавленную этим вызовом
    : > "$STATE/pending-alerts.txt"
    printf '{"session_id":"%s","cwd":"/"}' "$2" \
      | env CG_BACKLOG="$1" STATE_DIR="$STATE" bash "$HOOK" >"$TMP/stdout" 2>/dev/null
    cat "$STATE/pending-alerts.txt" 2>/dev/null
}
fresh_line() { grep 'ждут взятия' <<< "$1" | head -1; }

# --- T1: свежий ☐ (не в снимке), взятых в сессии ◐ нет → назван ---------------------
B="$TMP/t1.md"; { item ☐ D400; } > "$B"
backlog_snapshot "$STATE" fr1 "$B" >/dev/null; [ $? -eq 3 ] && ok || bad T1-snap "снимок не создан кодом 3"
{ item ☐ D400; item ☐ D401; } > "$B"
OUT=$(run "$B" fr1)
case "$(fresh_line "$OUT")" in
    *"ждут взятия: D401."*) ok ;;
    *) bad T1 "свежий D401 не назван: $OUT" ;;
esac
case "$(fresh_line "$OUT")" in
    *"D400"*) bad T1b "старый D400 (был в снимке) назван свежим: $OUT" ;;
    *) ok ;;
esac

# --- T2: свежий ☐ при живом ◐, взятом В ЭТОЙ сессии → тишина -------------------------
B="$TMP/t2.md"; { item ☐ D400; } > "$B"
backlog_snapshot "$STATE" fr2 "$B" >/dev/null
{ item ◐ D400; item ☐ D401; } > "$B"        # D400 взят в сессии (в снимке ☐, сейчас ◐)
OUT=$(run "$B" fr2)
[ -z "$(fresh_line "$OUT")" ] && ok || bad T2 "при взятом в сессии ◐ страж заговорил: $OUT"

# --- T3: только старые ☐ → тишина --------------------------------------------------
B="$TMP/t3.md"; { item ☐ D400; item ☐ D401; } > "$B"
backlog_snapshot "$STATE" fr3 "$B" >/dev/null
OUT=$(run "$B" fr3)
[ -z "$(fresh_line "$OUT")" ] && ok || bad T3 "без свежих пунктов страж заговорил: $OUT"

# --- T5: дроссель по составу: повтор молчит, закрытие ещё одного пункта звучит --------
B="$TMP/t5.md"; { item ☐ D400; item ☐ D402; } > "$B"
backlog_snapshot "$STATE" fr5 "$B" >/dev/null
{ item ☐ D400; item ☐ D402; item ☐ D401; } > "$B"
OUT1=$(run "$B" fr5); OUT2=$(run "$B" fr5)
[ -n "$(fresh_line "$OUT1")" ] && ok || bad T5a "первый вызов не назвал свежий: $OUT1"
[ -z "$(fresh_line "$OUT2")" ] && ok || bad T5b "повтор того же состава прозвучал снова: $OUT2"
# D402 закрыт (ушёл из открытых — как после архиватора): состав «закрытые» изменился
{ item ☐ D400; item ☐ D401; } > "$B"
OUT3=$(run "$B" fr5)
case "$(fresh_line "$OUT3")" in
    *"закрыты с начала сессии: D402"*) ok ;;
    *) bad T5c "закрытие D402 не дало нового напоминания со свежим D401: $OUT3" ;;
esac

# --- T6: stdout ПУСТ — непустой additionalContext на Stop перезапускал бы ход ---------
[ -s "$TMP/stdout" ] && bad T6 "stdout не пуст: $(head -c 120 "$TMP/stdout")" || ok

# --- T7: залежавшийся ◐ (уже ◐ в снимке) свежий ☐ НЕ глушит ---------------------------
B="$TMP/t7.md"; { item ◐ D400; } > "$B"
backlog_snapshot "$STATE" fr7 "$B" >/dev/null
{ item ◐ D400; item ☐ D401; } > "$B"
OUT=$(run "$B" fr7)
[ -n "$(fresh_line "$OUT")" ] && ok || bad T7 "◐ прошлых сессий заглушил свежий ☐: $OUT"

# --- T8: свежий пункт-ОЖИДАНИЕ (команда возврата) свежим не считается ----------------
B="$TMP/t8.md"; { item ☐ D400; } > "$B"
backlog_snapshot "$STATE" fr8 "$B" >/dev/null
{ item ☐ D400; item ☐ D401 '**Проверка возврата:** `false`'; } > "$B"
OUT=$(run "$B" fr8)
[ -z "$(fresh_line "$OUT")" ] && ok || bad T8 "ожидание с командой возврата названо свежим: $OUT"
{ item ☐ D400; item ☐ D403 '**Проверка возврата:** решение'; } > "$B"
OUT=$(run "$B" fr8)
[ -n "$(fresh_line "$OUT")" ] && ok || bad T8b "пункт с «решение» не назван свежим: $OUT"

# --- T9: снимка нет → создан этим вызовом, ход молчит --------------------------------
B="$TMP/t9.md"; { item ☐ D401; } > "$B"
OUT=$(run "$B" fr9)
[ -z "$(fresh_line "$OUT")" ] && ok || bad T9 "без снимка страж судил свежесть: $OUT"
ls "$STATE"/backlog-snapshot-fr9-*.txt >/dev/null 2>&1 && ok || bad T9b "снимок не создан ленивым фолбэком"
# write-if-absent: второй вызов снимок не перетирает
S9=$(backlog_snapshot "$STATE" fr9 "$B"); RC9=$?
[ "$RC9" -eq 0 ] && grep -q 'D401 ☐' "$S9" && ok || bad T9c "повторный вызов перетёр или не нашёл снимок (rc=$RC9)"

# --- T4 (НАЗВАННЫЙ ПРЕДЕЛ): пункт, заведённый кем угодно после старта, выглядит своим ---
# Условие снятия: гейт начнёт сверять свежий пункт с ДЕЙСТВИЯМИ хода (запись в бэклог среди
# них — `rc_outcome_observed`, hooks/root-cause-lib.sh), и чужая запись перестанет выглядеть
# своей. Нога закрепляет предел, чтобы его снятие было видно сменой знака.
B="$TMP/t4.md"; { item ☐ D400; } > "$B"
backlog_snapshot "$STATE" fr4 "$B" >/dev/null
{ item ☐ D400; item ☐ D499; } > "$B"        # «сосед» дописал D499
OUT=$(run "$B" fr4)
[ -n "$(fresh_line "$OUT")" ] && ok || bad T4 "предел сменил знак: чужой пункт больше не выглядит своим — сними ногу вместе с пределом"

echo "completion-gate fresh items: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
