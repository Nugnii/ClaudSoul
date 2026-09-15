#!/usr/bin/env bash
# test_adv_gate_read_denied.sh — гейт разбора отказывает ЧИТАЮЩИМ вызовам.
#
# Условие работоспособности отказа записано в самом гейте (five-whys-gate.sh:646, :674):
# «чтение и осмотр обязаны проходить, иначе цепочку не из чего строить», и текст самого
# отказа обещает это дословно: «Чтение, поиск и осмотр не блокируются».
#
# Атака бьёт по `redirect_bare` (command-scope-lib.sh:246) — единственному месту, где
# решается, перенаправляет ли «>». Он снимает лексемы построчными gsub и потому промахивается
# на трёх формах, ни одна из которых не входит в его НАЗВАННЫЙ ПРЕДЕЛ (там речь о теле
# heredoc и об операторах чужих языков):
#
#   1) АПОСТРОФ ВНУТРИ ДВОЙНЫХ КАВЫЧЕК. `gsub(/'…'/)` выполняется ПЕРВЫМ и спаривает
#      апостроф из "it's" с апострофом, открывающим программу awk. Границы кавычек
#      разъезжаются, и оператор сравнения `$1 > 5` выходит наружу как перенаправление.
#   2) АРИФМЕТИКА ОБОЛОЧКИ `$(( a > b ))`. Это не чужой язык, это shell: `>` там сравнение.
#      `executable_part` арифметику пропускает целиком (:118), `redirect_bare` — нет.
#   3) КОММЕНТАРИЙ. `executable_part` гасит остаток строки после `#` (:157),
#      `redirect_bare` комментариев не знает вовсе, и слово «>» в комментарии становится
#      записью.
#
# Последствие каждой — ОТКАЗ (permissionDecision: deny) на вызове, который ничего не пишет.
# Прецедентов у класса в дереве уже пять (шапка command-scope-lib.sh и комментарий
# five-whys-gate.sh:694); это шестой, седьмой и восьмой.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/five-whys-gate.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

PROJ="$TMP/proj"; mkdir -p "$PROJ"
TR="$TMP/t.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$TR"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",
        text:"Оказалось, страж молчит на этой форме. Смотрю дальше."}]}}' >> "$TR"

verdict() {   # verdict <метка> <команда> → deny | remind | silent
    local st="$TMP/st-$1" out
    mkdir -p "$st"
    out=$(jq -cn --arg s "sid-$1" --arg p "$TR" --arg d "$PROJ" --arg c "$2" \
            '{session_id:$s, tool_name:"Bash", transcript_path:$p, cwd:$d,
              tool_input:{command:$c}}' \
          | STATE_DIR="$st" bash "$HOOK" 2>/dev/null)
    if grep -q '"permissionDecision":"deny"' <<< "$out"; then printf 'deny'
    elif [ -n "$out" ]; then printf 'remind'
    else printf 'silent'; fi
}

must_pass() {  # must_pass <метка> <команда> <имя>
    local v; v=$(verdict "$1" "$2")
    if [ "$v" != "deny" ]; then ok "$3"
    else bad "$3 — ОТКАЗ на читающем вызове; команда: $2"; fi
}

# --- Контроль: настоящая запись обязана быть отбита ------------------------------
V=$(verdict ctl "printf x > $PROJ/f.sh")
if [ "$V" = "deny" ]; then ok "контроль: настоящее перенаправление → отказ"
else bad "контроль не сработал (вердикт: $V) — фикстура негодна"; fi

# --- Контроль: простой поиск проходит --------------------------------------------
must_pass ctl2 "grep -rn корень $PROJ" "контроль: простой поиск проходит"

# --- Атака 1: апостроф в двойных кавычках рвёт пары кавычек ------------------------
must_pass a1 "grep -c \"it's\" README.md && awk '\$1 > 5 {print \$2}' data.tsv" \
             "поиск с апострофом + awk-сравнение проходит"

# --- Атака 2: арифметика оболочки ---------------------------------------------------
must_pass a2 'n=$(grep -c "" README.md); echo $(( n > 100 ))' \
             "арифметическое сравнение оболочки проходит"
must_pass a3 'if (( $(ls -1 hooks | wc -l) > 50 )); then echo много; fi' \
             "арифметическое условие (( … > … )) проходит"

# --- Атака 3: комментарий --------------------------------------------------------
must_pass a4 'ls hooks  # раньше сюда писали > в файл, теперь нет' \
             "комментарий со знаком «>» не делает вызов записью"

# --- Свидетельство: executable_part обе формы РАЗБИРАЕТ, redirect_bare — нет -------
# Один файл, две функции, одно и то же сужение области, разные ответы: правило
# «где кончается исполняемая часть» у владельца есть, а второй потребитель его не берёт.
# shellcheck source=/dev/null
. "$REPO/hooks/command-scope-lib.sh"
EP=$(executable_part 'ls hooks  # писали > в файл')
if grep -q '>' <<< "$EP"; then
    bad "свидетельство не получено: executable_part тоже оставляет «>» в комментарии"
else
    ok "свидетельство: executable_part комментарий гасит, redirect_bare — нет"
fi
EP=$(executable_part 'echo $(( 5 > 3 ))')
if grep -q '>' <<< "$EP"; then
    bad "свидетельство не получено: executable_part тоже оставляет «>» из арифметики"
else
    ok "свидетельство: executable_part арифметику пропускает, redirect_bare — нет"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
