#!/usr/bin/env bash
# test_stop_context_restart.sh — «Проверка результата» stop-context-restart.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/stop-context-restart.sh (режим --check) читает запись замера:
#            записи нет — 1 «НЕ ИЗМЕРЕНО»; запись свежа, о нынешней версии CLI и с вердиктом
#            «additionalContext перезапускает, systemMessage нет» — 0; иной вердикт — 1; запись
#            старше порога — 1 «УСТАРЕЛО»; запись о другой версии CLI — 1; неизвестный аргумент — 2.
#            Режим --measure здесь не гоняется: он поднимает сессии и стоит денег.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного. Запись
# подкладывается через STATE_DIR. Команда БЕРЁТСЯ из шапки инструмента, как в
# test_split_provenance_log.sh.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/stop-context-restart.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *stop-context-restart.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
S="$TMP/state"; mkdir -p "$S"
NOW=$(date +%s)
# Версия CLI берётся у самого инструмента тем же способом: сверка идёт с `claude --version`.
CLI=$(claude --version 2>/dev/null | awk '{print $1}'); CLI="${CLI:-1.0.0}"
GOOD=additionalContext_restarts_systemMessage_does_not
rec() {   # date epoch cli verdict
    jq -n --arg d "$1" --argjson e "$2" --arg c "$3" --arg v "$4" \
        '{date:$d, epoch:$e, cli_version:$c, verdict:$v}' > "$S/stop-context-restart.json"
}
run_tool() {
    OUT=$(cd "$REPO" && STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: записи нет — 1 «НЕ ИЗМЕРЕНО», не зелено -----------------------------------------------
rm -f "$S/stop-context-restart.json"; run_tool
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'НЕ ИЗМЕРЕНО: записи нет'

# --- T2: свежая запись о нынешнем CLI с ожидаемым вердиктом — 0 --------------------------------
rec "2026-09-12 10:00" "$NOW" "$CLI" "$GOOD"; run_tool
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 "вердикт: $GOOD (замер 2026-09-12 10:00, CLI $CLI)"

# --- T3: иной вердикт — 1 -------------------------------------------------------------------
rec "2026-09-12 10:00" "$NOW" "$CLI" additionalContext_does_NOT_restart; run_tool
[ "$RC" -eq 1 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'вердикт: additionalContext_does_NOT_restart'

# --- T4: запись старше порога — 1 «УСТАРЕЛО» ---------------------------------------------------
rec "2026-06-01 10:00" "$(( NOW - 100 * 86400 ))" "$CLI" "$GOOD"; run_tool
[ "$RC" -eq 1 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'УСТАРЕЛО: записи 100 дней'

# --- T5: запись о другой версии CLI — 1 (только если claude доступен: сверять есть с чем) ------
if command -v claude >/dev/null 2>&1; then
    rec "2026-09-12 10:00" "$NOW" "0.0.0" "$GOOD"; run_tool
    [ "$RC" -eq 1 ] && ok || bad T5 "rc=$RC — $OUT"
    has T5 'УСТАРЕЛО: запись о версии 0.0.0'
    # T5b: версия того же мажора, но иная — тоже устарела (условие — полное равенство, не мажор)
    rec "2026-09-12 10:00" "$NOW" "${CLI}.9" "$GOOD"; run_tool
    [ "$RC" -eq 1 ] && ok || bad T5b "версия того же мажора сошла за нынешнюю: rc=$RC — $OUT"
    has T5b "УСТАРЕЛО: запись о версии ${CLI}.9"
else
    echo "T5 пропущена: нет claude, сверять версию не с чем"
fi

# --- T6: неизвестный аргумент — 2 -------------------------------------------------------------
OUT=$(cd "$REPO" && STATE_DIR="$S" bash "$TOOL" --bogus 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T6 "rc=$RC — $OUT"
has T6 'неизвестный аргумент'

echo ""
echo "stop-context-restart tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
