#!/usr/bin/env bash
# test_write_target_scope.sh — отказ гейта разбора смотрит на ЦЕЛЬ записи, а не на факт записи.
#
# Повод (5 сентября 2026). Признак записи в `five-whys-gate` отвечал на вопрос «пишет ли», а
# отказ утверждает «правка не пройдёт» — то есть о левом, а сказано о правом. Замер по
# 74 отказам гейта в корпусе расшифровок:
#   · записи в ДЕРЕВО проекта — 24, цепочка произнесена в 24 из 24: там гейт безупречен;
#   · записи в ПЕСОЧНИЦУ — 32, и все 6 «обходов» замера `stopper-effect` приходятся сюда.
# Отказ на временном зонде не защищает ничего и мешает: субагент писал `probe.py`, чтобы
# НАЙТИ причину, и получал «сначала назови причину».
#
# ОСВОБОЖДЕНИЕ ТОЛЬКО ТАМ, ГДЕ ЦЕЛЬ ОБЪЯВЛЕНА ПОЛЕМ (Edit/Write/MultiEdit). Разбор целей из
# текста Bash-команды был написан и снят: противник дал 5 подтверждённых дыр из 6 —
# достаточно распознаваемой приманки в /tmp рядом с нераспознанной записью в дерево, и
# предикат «все НАЙДЕННЫЕ цели вне проекта» освобождал вызов. Поэтому у Bash отказ остаётся
# всегда, и ноги ниже это ЗАКРЕПЛЯЮТ: ослабление здесь тихо снимет страж уровня 4.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/five-whys-gate.sh"
LIB="$REPO/hooks/lib/write-target-lib.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
[ -f "$LIB" ]  || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"
PROJ="$TMP/proj"; mkdir -p "$PROJ/hooks"
SCRATCH="/private/tmp/claude-501/-x/sess/scratchpad"

# Ход с НАХОДКОЙ и без цепочки — на нём гейт обязан отказывать пишущему вызову.
TR="$TMP/find.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$TR"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Оказалось, страж поймал мой же тест. Чиню."}]}}' >> "$TR"

call() { # call <sid> <tool> <json полей tool_input>
    jq -cn --arg s "$1" --arg n "$2" --arg p "$TR" --arg w "$PROJ" --argjson ti "$3" \
      '{session_id:$s, transcript_path:$p, cwd:$w, hook_event_name:"PreToolUse", tool_name:$n, tool_input:$ti}' \
    | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null
}
dec() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$1" 2>/dev/null; }
sig() { touch "$STATE_DIR/error_streak_fired_$1"; }

# ── Освобождение: цель объявлена полем и лежит в песочнице ────────────────────
sig w1; OUT=$(call w1 Write "$(jq -cn --arg f "$SCRATCH/probe.py" '{file_path:$f, content:"x"}')")
[ -z "$(dec "$OUT")" ] && ok || bad "T1 Write в песочницу" "отказано, а цель вне проекта: $OUT"

sig w2; OUT=$(call w2 Edit "$(jq -cn --arg f "$SCRATCH/note.md" '{file_path:$f, old_string:"a", new_string:"b"}')")
[ -z "$(dec "$OUT")" ] && ok || bad "T2 Edit в песочницу" "отказано: $OUT"

# ── ЗАЩИТА: цель в дереве — отказ обязан остаться ─────────────────────────────
sig w3; OUT=$(call w3 Write "$(jq -cn --arg f "$PROJ/hooks/x.sh" '{file_path:$f, content:"x"}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T3 Write в дерево" "ОСВОБОЖДЕНО, а цель в проекте: $OUT"

sig w4; OUT=$(call w4 Edit "$(jq -cn --arg f "$PROJ/CLAUDE.md" '{file_path:$f, old_string:"a", new_string:"b"}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T4 Edit в дерево" "ОСВОБОЖДЕНО: $OUT"

# ── ЗАЩИТА: Bash не освобождается НИКОГДА, даже с целью в песочнице ───────────
# Это закрепление снятого разбора: 5 подтверждённых дыр из 6 при попытке освобождать Bash.
sig b1; OUT=$(call b1 Bash "$(jq -cn --arg c "cat > $SCRATCH/probe.py <<E
x
E" '{command:$c}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T5 Bash в песочницу" "ОСВОБОЖДЕНО — разбор Bash снят намеренно: $OUT"

sig b2; OUT=$(call b2 Bash "$(jq -cn --arg c "printf x > /tmp/decoy.txt; /usr/bin/tee -a \"$PROJ/hooks/y.sh\" </dev/null" '{command:$c}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T6 приманка в /tmp + запись в дерево" "ОСВОБОЖДЕНО — это ровно дыра противника: $OUT"

# ── Чтение обязано проходить: без него цепочку не построить ───────────────────
sig r1; OUT=$(call r1 Bash "$(jq -cn --arg c "grep -n foo $PROJ/hooks/x.sh" '{command:$c}')")
[ -z "$(dec "$OUT")" ] && ok || bad "T7 чтение" "заблокировано чтение: $OUT"

# ── Сам предикат пути ─────────────────────────────────────────────────────────
_wt_outside "$SCRATCH/a.md" "$PROJ"            && ok || bad "T8"  "путь песочницы не признан внешним"
_wt_outside "$PROJ/a.md" "$PROJ"               && bad "T9"  "путь проекта признан внешним" || ok
_wt_outside "" "$PROJ"                         && bad "T10" "пустой путь признан внешним" || ok
_wt_outside "hooks/a.sh" "$PROJ"               && bad "T11" "относительный путь признан внешним" || ok
# Восхождение отменяет доказательство: /tmp/../Users/… ведёт В ПРОЕКТ. Найдено этим тестом
# до подключения правила к стражу.
_wt_outside "/tmp/../$PROJ/a.md" "$PROJ"       && bad "T12" "путь с «..» признан внешним" || ok
# Проект внутри временного каталога (так живут проверочные копии) — внутреннее остаётся
# внутренним.
_wt_outside "/private/tmp/copy/x.md" "/private/tmp/copy" && bad "T13" "путь внутри проекта-во-временном признан внешним" || ok

echo ""
echo "write target scope: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
