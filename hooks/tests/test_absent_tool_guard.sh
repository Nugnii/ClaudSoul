#!/usr/bin/env bash
# СУДИТ: hooks/absent-tool-guard.sh
# test_absent_tool_guard.sh — свидетель стража отсутствующего инструмента.
# Предмет: отказ ровно там, где инструмента НЕТ на этой машине; молчание там, где он есть,
# где форма другая и где событие не Bash. Замена названа в тексте отказа.
# Пробные команды нарочно на ASCII: страж переносимости судит ЛИТЕРАЛ, и кириллица вплотную
# к синтаксису оболочки в фикстуре отбивается им же (проверено отказом 14 сентября 2026).
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/absent-tool-guard.sh"
# Каталог состояния — ПЕСОЧНИЦА с первой строки. Первый прогон этого свидетеля написал
# `absent-tool-fired-nosid.jsonl` в живой ~/.claude: ноги звали стража до того, как песочница
# создавалась в T6, и журнал ушёл по умолчанию хука.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

run() {  # run <command> [tool]
    printf '{"tool_name":"%s","tool_input":{"command":%s}}' "${2:-Bash}" \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | bash "$HOOK" 2>/dev/null
}
# Утверждение о ТИШИНЕ названо ролью, а не формой: судья стражей (test_guards_provable.sh)
# читает словарь именованных утверждений, и голое `[ -z "$O" ]` в него не входит. Расширять
# его словарь значило бы растить перечень форм — корень R3; имя роли дешевле и честнее.
assert_empty() { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: ${1:0:120}"; }

decision() { printf '%s' "$1" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])
except Exception: print("")' 2>/dev/null; }

# ОБЕ СТОРОНЫ НА ЛЮБОЙ МАШИНЕ (D1302, скептик opus M2, 16 ноября 2026). Ноги ниже выбирают ожидание по `command -v
# timeout`, и после обновления macOS 27.2.1, поставившего `/usr/bin/timeout`, сторона «отказ, когда команды нет» здесь
# не судилась вовсе: мутант стража с мёртвым шаблоном проходил 31/0. Где `timeout` есть, свидетель один раз прогоняет
# себя с путём поиска без него (`hooks/tests/path-without.sh`) — там судится отказ, — и продолжает на обычном пути.
if command -v timeout >/dev/null 2>&1 && [ -z "${ATG_WITHOUT_TIMEOUT:-}" ]; then
    . "$HOOK_DIR/tests/path-without.sh"
    path_without "$TMP/farm" timeout gtimeout || { echo "FAIL: подготовка — каталог без timeout"; exit 1; }
    if ATG_WITHOUT_TIMEOUT=1 PATH="$TMP/farm" /bin/bash "$0"; then ok; else bad NOTIMEOUT "сторона «команды нет» красна (вывод выше)"; fi
fi

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ, и он условный: отказ ожидается ТОЛЬКО если инструмента нет.
# Иначе нога судила бы не стража, а машину, на которой её запустили.
O=$(run 'timeout 900 bash run_all.sh')
if command -v timeout >/dev/null 2>&1; then
    assert_empty "$O" T1
else
    [ "$(decision "$O")" = "deny" ] && ok || bad T1 "timeout absent, no refusal: ${O:0:120}"
    grep -qF "run_with_timeout" <<< "$O" && ok || bad T1b "replacement not named"
    grep -qF "12101" <<< "$O" && ok || bad T1c "measurement behind the signal not shown"
fi

# T2 — форма без числа не судится: слово в журнале, переменной, прозе.
O2=$(run 'echo "outcome: timeout" >> journal.txt')
assert_empty "$O2" T2

# T3 — инструмент, который ЕСТЬ, не отбивается.
O3=$(run 'grep -c . /dev/null')
assert_empty "$O3" T3

# T4 — не Bash: предмет чужой.
O4=$(run 'timeout 5 sleep 1' 'Edit')
assert_empty "$O4" T4

# T5 — вторая форма реестра судится СВОЕЙ проверкой, а не общим списком.
O5=$(run 'cat -A f.txt')
if cat -A /dev/null >/dev/null 2>&1; then
    assert_empty "$O5" T5
else
    [ "$(decision "$O5")" = "deny" ] && ok || bad T5 "cat -A broken here, no refusal"
fi

# T6 — ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: страж спрашивает МАШИНУ, а не помнит ответ.
# Инструмент появляется в PATH — отказ обязан исчезнуть.
printf '#!/bin/sh\nexit 0\n' > "$TMP/timeout"; chmod +x "$TMP/timeout"
O6=$(PATH="$TMP:$PATH" run 'timeout 900 bash run_all.sh')
assert_empty "$O6" T6

# T7 — отказ ПИШЕТСЯ в журнал семейства `*-fired-*`: без него точность уровня 4 измерена
# один раз при заведении и больше никогда. Журнал кладётся в песочницу, живой ~/.claude тест
# не трогает.
JDIR="$STATE_DIR"; mkdir -p "$JDIR"
O7=$(printf '{"session_id":"T7SID","tool_name":"Bash","tool_input":{"command":"timeout 900 true"}}' \
    | STATE_DIR="$JDIR" bash "$HOOK" 2>/dev/null)
if command -v timeout >/dev/null 2>&1; then
    [ ! -s "$JDIR/absent-tool-fired-T7SID.jsonl" ] && ok || bad T7 "инструмент есть, а журнал записан"
else
    grep -q '"key":"timeout"' "$JDIR/absent-tool-fired-T7SID.jsonl" 2>/dev/null && ok \
        || bad T7 "отказ не записан в журнал: точность больше не измерима"
    # Ноги «не пишет в живой каталог» здесь нет намеренно: сравнение временного каталога с
    # живым тавтологично, а владелец правила один — hooks/tests/test_live_home_in_tests.sh (род K).
fi

# T8 (D1006, 20 октября 2026): команда с переводом строки и кавычками даёт ОДНУ разбираемую запись. Прежний
# printf с `tr -d '"\\'` переводы строк не трогал, и многострочная команда рвала JSONL: в живом журнале было 16
# неразбираемых строк из 78, и замер точности (`signal-precision.sh`) их не видел.
if ! command -v timeout >/dev/null 2>&1; then
    python3 -c 'import json; print(json.dumps({"session_id": "T8SID", "tool_name": "Bash",
        "tool_input": {"command": "timeout 900 python3 - <<PY\nprint(\"a\")\nPY"}}))' \
        | STATE_DIR="$JDIR" bash "$HOOK" >/dev/null 2>&1
    python3 -c 'import json, sys
lines = [x for x in open(sys.argv[1], encoding="utf-8").read().split("\n") if x]
assert len(lines) == 1, lines
rec = json.loads(lines[0])
assert "\n" in rec["cmd"] and "print(\"a\")" in rec["cmd"], rec' "$JDIR/absent-tool-fired-T8SID.jsonl" 2>/dev/null \
        && ok || bad T8 "многострочная команда порвала запись журнала: $(head -c 200 "$JDIR/absent-tool-fired-T8SID.jsonl" 2>/dev/null)"
fi

# T9–T16 (D1012): судится вид «только оболочка» владельца (`hooks/detection-signals-lib.sh`), а не сырой текст.
# Форма в теле кавычек для удалённой машины, в теле heredoc, которое пишется в файл, и в закавыченном аргументе —
# не местный вызов: тишина на любой машине. Форма в позиции команды — местный вызов: отказ там, где инструмента
# нет. Позиция — грамматика владельца (`DS_CMD_POS_RE`): `{`, `then`, `do` тоже открывают команду.
O9=$(run "$(printf 'ssh host "\ntimeout 5 true\n"')")
assert_empty "$O9" T9
O10=$(run "$(printf 'cat > job.sh <<EOF\ntimeout 5 true\nEOF')")
assert_empty "$O10" T10
O11=$(run 'for c in "echo ok; timeout 5 true" b; do echo "$c"; done')
assert_empty "$O11" T11
O14=$(run "ssh host 'echo \$(timeout 5 true)'")
assert_empty "$O14" T14
O12=$(run 'echo ok; timeout 5 true')
O13=$(run 'x="$(timeout 5 true)"; echo "$x"')
O15=$(run 'f() { timeout 5 true; }')
O16=$(run 'if true; then timeout 5 true; fi')
if command -v timeout >/dev/null 2>&1; then
    assert_empty "$O12" T12; assert_empty "$O13" T13; assert_empty "$O15" T15; assert_empty "$O16" T16
else
    [ "$(decision "$O12")" = "deny" ] && ok || bad T12 "timeout нет, местный вызов после ';' не отбит: ${O12:0:120}"
    [ "$(decision "$O13")" = "deny" ] && ok || bad T13 "timeout нет, подстановка в двойных кавычках не отбита: ${O13:0:120}"
    [ "$(decision "$O15")" = "deny" ] && ok || bad T15 "timeout нет, вызов в теле функции '{ …; }' не отбит: ${O15:0:120}"
    [ "$(decision "$O16")" = "deny" ] && ok || bad T16 "timeout нет, вызов после 'then' не отбит: ${O16:0:120}"
fi

# T17–T21 (D1053, D1054): подстановку в теле `<<EOF` без кавычек у метки раскрывает местная оболочка — отказ;
# у `<<'EOF'` тело — данные. `if` открывает позицию команды, `{` без пробела — нет. Библиотека, падающая на
# подключении под `set -u`, стража не выключает: судится сырой текст.
O18=$(run "$(printf "cat > r.txt <<'EOF'\nsize: \$(timeout 5 true)\nEOF")")
assert_empty "$O18" T18
O20=$(run 'echo {timeout 5}')
assert_empty "$O20" T20
O17=$(run "$(printf 'cat > r.txt <<EOF\nsize: $(timeout 5 true)\nEOF')")
O19=$(run 'if timeout 5 true; then :; fi')
mkdir -p "$TMP/broken"; cp "$HOOK" "$HOOK_DIR/detection-signals-lib.sh" "$TMP/broken/"
echo ': "$D1054_UNSET_PROBE"' >> "$TMP/broken/detection-signals-lib.sh"
O21=$(HOOK="$TMP/broken/absent-tool-guard.sh" run 'timeout 5 true')
if command -v timeout >/dev/null 2>&1; then
    assert_empty "$O17" T17; assert_empty "$O19" T19; assert_empty "$O21" T21
else
    [ "$(decision "$O17")" = "deny" ] && ok || bad T17 "timeout нет, подстановка в теле <<EOF не отбита: ${O17:0:120}"
    [ "$(decision "$O19")" = "deny" ] && ok || bad T19 "timeout нет, вызов после 'if' не отбит: ${O19:0:120}"
    [ "$(decision "$O21")" = "deny" ] && ok || bad T21 "timeout нет, при сломанной библиотеке страж молчит: ${O21:0:120}"
fi

# T22–T27 (D1057, D1058): `)` в кавычках внутри `$(…)` тела `<<EOF` подстановку не закрывает, и кавычка обрезка не
# съедает вид — местный вызов после тела отбит, закавыченный пропущен; многострочная `$(…)` судится целиком; обрезок
# обратных кавычек с непарной кавычкой вид не портит. Библиотека, выходящая с 0 или с ошибкой awk в функции вида,
# стража не выключает.
B=$(printf "cat <<EOF > out\nn=\$(grep -c ')' f)\nEOF")
O22=$(run "$(printf '%s\ntimeout 5 sleep 1' "$B")")
O23=$(run "$(printf "%s\necho 'a; timeout 5 b'" "$B")")
assert_empty "$O23" T23
O24=$(run "$(printf "cat <<EOF > out\n\$(echo a\ntimeout 5 sleep 1)\nEOF")")
O25=$(run "$(printf "cat <<EOF > out\n\`echo it's\`\nEOF\ntimeout 5 sleep 1")")
mkdir -p "$TMP/exit0" "$TMP/awkerr"
cp "$HOOK" "$HOOK_DIR/detection-signals-lib.sh" "$TMP/exit0/"; cp "$HOOK" "$HOOK_DIR/detection-signals-lib.sh" "$TMP/awkerr/"
echo 'exit 0' >> "$TMP/exit0/detection-signals-lib.sh"
echo 'ds_shell_only() { awk "BEGIN {" </dev/null; }' >> "$TMP/awkerr/detection-signals-lib.sh"
O26=$(HOOK="$TMP/exit0/absent-tool-guard.sh" run 'timeout 5 true')
O27=$(HOOK="$TMP/awkerr/absent-tool-guard.sh" run 'timeout 5 true')
if command -v timeout >/dev/null 2>&1; then
    for o in "$O22" "$O24" "$O25" "$O26" "$O27"; do assert_empty "$o" T22-T27; done
else
    [ "$(decision "$O22")" = "deny" ] && ok || bad T22 "timeout нет, вызов после тела с ')' в кавычках подстановки не отбит: ${O22:0:120}"
    [ "$(decision "$O24")" = "deny" ] && ok || bad T24 "timeout нет, вызов в многострочной \$(…) тела не отбит: ${O24:0:120}"
    [ "$(decision "$O25")" = "deny" ] && ok || bad T25 "timeout нет, вызов после обрезка обратных кавычек не отбит: ${O25:0:120}"
    [ "$(decision "$O26")" = "deny" ] && ok || bad T26 "timeout нет, библиотека с 'exit 0' выключила стража: ${O26:0:120}"
    [ "$(decision "$O27")" = "deny" ] && ok || bad T27 "timeout нет, ошибка awk в ds_shell_only выключила стража: ${O27:0:120}"
fi

# T28–T30 (D1064): у разбора подстановки тела `<<EOF` грамматика кавычек та же, что у читателя вида: вложенная
# `"$(…"…)…"` и `$'…\'…'` обрезок не сдвигают — местный вызов после тела отбит; `(` во вложенной строке — данные,
# строка тела после неё не судится.
# T31–T32 (D1066): вложенный heredoc в `$(…)` тела судится кодом — подстановку тела внутреннего `<<IN` без кавычек
# исполняет местная оболочка, а `<<` в `(( … ))` heredoc не открывает; откатанная ветка «тело — данные» их прятала.
O28=$(run "$(printf 'cat > n <<EOF\nCount: $(echo "$(grep -c "fix)" /dev/null)")\nEOF\ntimeout 5 echo hi')")
O29=$(run "$(printf "cat <<EOF\n\$(echo \$'it\\\\'s') ; echo ')'\nEOF\ntimeout 5 echo hi")")
O30=$(run "$(printf 'cat <<EOF\n$(echo "$(echo "(")")\nplain; timeout 5 x\nEOF')")
O31=$(run "$(printf 'cat > o <<EOF\n$(cat <<IN\nv=$(timeout 5 echo hi)\nIN\n)\nEOF')")
O32=$(run "$(printf 'cat > o <<EOF\na=$( (( y = 1<<2 )); echo $y )\nb=$(timeout 5 echo hi)\nEOF')")
assert_empty "$O30" T30
if command -v timeout >/dev/null 2>&1; then
    for o in "$O28" "$O29" "$O31" "$O32"; do assert_empty "$o" T28-T32; done
else
    [ "$(decision "$O28")" = "deny" ] && ok || bad T28 "timeout нет, вызов после тела с вложенной \"\$(…\"…)\" не отбит: ${O28:0:120}"
    [ "$(decision "$O29")" = "deny" ] && ok || bad T29 "timeout нет, вызов после тела с \$'…\\'…' не отбит: ${O29:0:120}"
    [ "$(decision "$O31")" = "deny" ] && ok || bad T31 "timeout нет, вызов в теле внутреннего heredoc без кавычек не отбит: ${O31:0:120}"
    [ "$(decision "$O32")" = "deny" ] && ok || bad T32 "timeout нет, вызов после (( 1<<2 )) в подстановке тела не отбит: ${O32:0:120}"
fi

echo "test_absent_tool_guard: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
