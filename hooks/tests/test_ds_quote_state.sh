#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_ds_quote_state.sh — вид `full` (как его берут стражи) держит состояние кавычек: местный вызов не прячется «в
# кавычки» из-за апострофа внутри "…", экранированной \" или апострофа в комментарии, а закавыченное снимается (D1015).
#
# Результат: `_ds_view full` по входу JSON держит местный вызов видимым во всех формах стороны (а), снимает форму во
#            всех формах стороны (б); вход в 600 КБ одной строкой и многими — быстрее потолка
# Проверка результата: bash hooks/tests/test_ds_quote_state.sh даёт 0
#
# Узкая часть D1015 (решение владельца 23 октября 2026). Прежде `ds_unquoted_command` снимал пары двумя заменами без
# состояния; замер по корпусу 3000 настоящих команд — вид терял слова кода в 24, у 20 причина в кавычках. Формы
# ложного начала heredoc и `#42"` в многострочной строке — другие ступени вида, здесь не судятся (D1015 открыт).
# Имя инструмента собрано из переменной: страж отсутствующего инструмента судит текст команды.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"
PASS=0; FAIL=0
t=timeout
RE="(^|[;|&(]|&&|\|\|)[[:space:]]*$t[[:space:]]+[0-9]"
view() { _ds_view full "$(jq -cn --arg c "$1" '{command: $c}')"; printf '%s' "$_DS_V"; }
keep() {  # keep <нога> <команда> — местный вызов обязан остаться виден
    if grep -qE "$RE" <<< "$(view "$2")"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$1]: вид потерял местный вызов: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-90)"; fi
}
drop() {  # drop <нога> <команда> — форма обязана быть снята
    if grep -qE "$RE" <<< "$(view "$2")"; then FAIL=$((FAIL+1)); echo "FAIL [$1]: форма не снята: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-90)"
    else PASS=$((PASS+1)); fi
}
# (а) местный вызов не теряется
keep A1 "$(printf "echo \"it's\"; %s 5 true; echo 'done'" "$t")"
keep A2 "$(printf 'echo "a \\" b"; %s 5 true; echo "c"' "$t")"
keep A3 "$(printf 'echo \\"; %s 5 true; echo "x"' "$t")"
keep A4 "$(printf "echo ok # it's fine\n%s 5 true\necho 'x'" "$t")"
keep A5 "$(printf "%s 5 true # don't forget" "$t")"
keep A6 "$(printf "echo \$'it\\\\'s'; %s 5 true" "$t")"
keep A7 "$(printf 'echo "a;b"; %s 5 true' "$t")"
keep A8 "$(printf 'grep -c "#" f; %s 5 true' "$t")"
keep A9 "$(printf 'x=a#b; %s 5 true' "$t")"
# Формы финального скептика второй редакции: `$(` внутри "…" открывает область команды со своими кавычками;
# экранированный разделитель перед `#` комментария не открывает.
keep A10 "$(printf 'ls | while read f; do echo "x: $(grep -m1 '"'"'^t:'"'"' "$f"|sed '"'"'s/"//g'"'"')"; done\n%s 5 true' "$t")"
keep A11 "$(printf 'for f in a; do echo "$(echo '"'"'a"b'"'"')"; done; %s 5 true' "$t")"
keep A12 "$(printf 'echo a\\;#b; %s 5 true' "$t")"
# Код в `"$(…)"` исполняется и потому виден: снятие всей области прятало верные предупреждения (замер вердиктов).
keep A13 "$(printf 'printf "%%s\\n" "$(%s 5 date -u -r "$(stat -f %%m "$f")")"' "$t")"
# Строка с `#…` в начале строки внутри многострочной строки — не комментарий (D1039, часть 1).
keep A14 "$(printf 'echo "line one\n#42"; %s 5 true' "$t")"
# (б) закавыченное и комментарий снимаются
drop B1 "$(printf 'ssh host "\n%s 5 true\n"' "$t")"
drop B2 "$(printf "ssh host '\n%s 5 true\n'" "$t")"
drop B3 "$(printf 'git commit -m "fix: %s 5 now works"' "$t")"
drop B4 "$(printf "ssh host 'psql -c \"select \\\\\"x\\\\\" from t\"; %s 5 true'" "$t")"
drop B5 "$(printf 'echo "it\\"s %s 5 true"' "$t")"
drop B6 "$(printf 'echo ok # %s 5 true' "$t")"
drop B7 "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: don'"'"'t break it\n%s 5 inside the message\nEOF\n)"' "$t")"
# `" #` внутри апострофов — не комментарий: срез кавычки сдвигал разбор, и закавыченное ниже обнажалось (корпус).
drop B8 "$(printf 'x "$(f '"'"'echo "x" # c'"'"')"\nq '"'"'a; %s 5 true'"'"'' "$t")"
# Цена линейна, а не квадратична. Абсолютный потолок падал под нагрузкой набора (финальный скептик D1015: 768 КБ за
# 16 с при десяти соседях), поэтому судится ОТНОШЕНИЕ: вход в четыре раза больше обязан стоить меньше чем в девять раз
# дороже (линейный разбор — около 4, квадратичный — около 16). Потолок 120 с остаётся на катастрофу.
_now() { python3 -c 'import time; print("%.3f" % time.time())'; }
cost_ratio() {  # cost_ratio <нога> <программа awk, печатающая N повторов>
    local leg="$1" prog="$2" a b t0 t1 t2
    a=$(awk -v N=5000 "$prog"); b=$(awk -v N=20000 "$prog")
    t0=$(_now); view "$a" >/dev/null; t1=$(_now); view "$b" >/dev/null; t2=$(_now)
    if awk -v x="$t0" -v y="$t1" -v z="$t2" 'BEGIN { s = y - x; l = z - y; exit !(l < 120 && (s < 0.05 || l / s < 9)) }'; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$leg]: вход ×4 стоил $(awk -v x="$t0" -v y="$t1" -v z="$t2" 'BEGIN { printf "%.2f с против %.2f с", z - y, y - x }')"; fi
}
cost_ratio C1 'BEGIN { for (i = 0; i < N; i++) printf "echo \"line %d with words\"; x=1\n", i }'
cost_ratio C2 'BEGIN { for (i = 0; i < N; i++) printf "echo \"word %d\"; ", i }'
echo "test_ds_quote_state: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
