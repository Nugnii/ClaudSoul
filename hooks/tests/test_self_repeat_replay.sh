#!/usr/bin/env bash
# СУДИТ: scripts/self-repeat-replay.py
# test_self_repeat_replay.sh — свидетель реплея маркера повтора (D325).
# Результат: реплей на подложном корпусе называет произнесения и долю без разбора отдельно до и после
#            границы, отвечает 1 при перевесе «без разбора» после границы и 2 без корпуса; словарь
#            берёт у библиотеки, а не держит свой.
# Проверка результата: bash hooks/tests/test_self_repeat_replay.sh даёт 0
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/self-repeat-replay.py"
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# Команда — из шапки инструмента, не своя копия.
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" | sed -E 's/ (даёт 0|—|печатает).*//')
case "$CMD" in *self-repeat-replay.py*) ;; *) echo "FAIL: команда шапки не запускает инструмент: $CMD"; exit 1 ;; esac
TMP=$(mktemp -d)   # временное уберёт система; раннер бьёт SIGKILL, trap не спасает (D360)
C="$TMP/corpus"; mkdir -p "$C"
line() {  # line <файл> <тип> <дата> <текст>
    jq -cn --arg t "$2" --arg d "$3" --arg x "$4" \
      '{type:$t, timestamp:($d + "T10:00:00Z"), message:{role:$t, content:[{type:"text", text:$x}]}}' >> "$1"
}
A="$C/aaaaaaaa-0000-0000-0000-000000000001.jsonl"; : > "$A"
line "$A" user 2026-09-01 "чини"
line "$A" assistant 2026-09-01 "Это третий раз за день, когда тест падает на той же строке. Чиню."
line "$A" user 2026-09-01 "дальше"
line "$A" assistant 2026-09-01 "Второй раз подряд та же ошибка. Почему падает — читается старый индекс (mcp-server/indexer.py:231). Почему старый — add шёл после. Почему не поймали — тест брал фикстуру."
line "$A" user 2026-09-01 "ок"
line "$A" assistant 2026-09-01 "Собрал материал за сессию в черновик, подтверждение счётчика записано."
B="$C/bbbbbbbb-0000-0000-0000-000000000002.jsonl"; : > "$B"
line "$B" user 2026-09-14 "чини"
line "$B" assistant 2026-09-14 "Это уже четвёртый раз за сессию — тот же класс. Правлю."
line "$B" user 2026-09-14 "дальше"
line "$B" assistant 2026-09-14 "Тот же класс, что утром. Чиню строку."
run() { (cd "$ROOT" && env FWG_REPLAY_CORPUS="$C/*.jsonl" SELF_REPEAT_SINCE=2026-09-13 SELF_REPEAT_MIN_N="${1:-10}" bash -c "$CMD" 2>&1); }
OUT=$(run); RC=$?
[ "$RC" = 0 ] && ok || bad "T1" "на подложном корпусе ниже порога ожидался код 0, получен $RC: $OUT"
case "$OUT" in *"до 2026-09-13: произнесений 2, без разбора в том же ходе 1 (50%)"*) ok ;; *) bad "T1b" "доля ДО границы не та: $OUT" ;; esac
case "$OUT" in *"с  2026-09-13: произнесений 2, без разбора в том же ходе 2 (100%)"*) ok ;; *) bad "T1c" "доля ПОСЛЕ границы не та: $OUT" ;; esac
case "$OUT" in *"произнесений 4)"*) ok ;; *) bad "T1d" "ложные формы («за сессию», «подтверждение») посчитаны маркером или настоящие потеряны: $OUT" ;; esac
OUT=$(run 2); RC=$?
[ "$RC" = 1 ] && ok || bad "T2" "перевес «без разбора» после границы при n ≥ порога обязан давать 1, получен $RC"
case "$OUT" in *"[замер: находки, не сбой]"*) ok ;; *) bad "T2b" "находка не помечена: $OUT" ;; esac
OUT=$(cd "$ROOT" && env FWG_REPLAY_CORPUS="$TMP/none/*.jsonl" bash -c "$CMD" 2>&1); RC=$?
[ "$RC" = 2 ] && ok || bad "T3" "без корпуса ожидался код 2, получен $RC: $OUT"
# Словарь — у библиотеки: подменённый RC_SELF_REPEAT_RE меняет счёт, значит своей копии у реплея нет.
OUT=$(cd "$ROOT" && env FWG_REPLAY_CORPUS="$C/*.jsonl" SELF_REPEAT_SINCE=2026-09-13 RC_SELF_REPEAT_RE='никогда-не-встретится' bash -c "$CMD" 2>&1); RC=$?
[ "$RC" = 2 ] && ok || bad "T4" "с подменённым словарём контроль обязан упасть кодом 2 (реплей читает словарь у библиотеки), получен $RC: $OUT"
echo "self-repeat replay: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
