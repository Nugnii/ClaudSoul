#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_adversary_d509r3_empty_lexeme_takes_previous.sh
#
# АТАКА (D509, противник, раунд 3): ПУСТАЯ лексема потока принимает значение ПРЕДЫДУЩЕЙ.
# _ds_compile раскрывает каждую лексему встроенным `printf -v tok '%b' "$tok"`. В bash 3.2
# (исполнитель на macOS) `printf -v` с пустым результатом пустую строку НЕ присваивает:
# переменная получает остаток внутреннего буфера от прошлого `printf -v`, то есть ПРЕДЫДУЩУЮ
# лексему (`tok=zz; printf -v tok %b b; printf -v tok %b ""` → tok=b). Пустыми бывают:
#   - имя сигнала: нет `name`, `"name": ""`, null, false, "\n" → печатается «S» — лексема,
#     стоящая перед именем; сигнала с таким именем в знании нет;
#   - значение листа: "", "\n", "\u0000" → значением становится КЛЮЧ листа:
#     `{"command_uses": ""}` проверяет, исполняет ли команда слово «command_uses»,
#     `{"tool_input_regex": ""}` — есть ли во входе слово «tool_input_regex».
# Прежняя редакция брала значения подстановкой $(jq -r …): пустое оставалось пустым, лист
# отвечал «нет» (`[ -z … ] && return 1`), имя печаталось пустой строкой.
#
# Ожидание: решения и печатаемое имя тождественны прежней редакции.
# Факт (bash 3.2): имя «S» вместо пустого; лист с пустым значением совпадает, когда вход
#           упоминает имя ключа; страж отказывает (deny) там, где прежняя молчала.
# На bash ≥ 4 `printf -v` присваивает пустое, и тест там зелёный.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
HOOK="$REPO/hooks/blocker-tier-check.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

T=$(mktemp -d)
OLD="$T/old-lib.sh"
git -C "$REPO" show 'a03e2c5f^:hooks/detection-signals-lib.sh' > "$OLD" 2>/dev/null || OLD=""
[ -s "${OLD:-/nonexistent}" ] || OLD=""

FAIL=0

# run <библиотека> <функция> <аргументы…> → "rc=N|вывод"
run() {
    local lib="$1"; shift
    bash -c '. "$1"; shift; out=$("$@" 2>/dev/null); printf "rc=%s|%s" "$?" "$out"' _ "$lib" "$@"
}

check() { # $1=метка $2=ожидание $3=факт
    if [ "$2" = "$3" ]; then
        echo "ok   $1: $3"
    else
        echo "FAIL $1: ждали [$(printf '%q' "$2")], получили [$(printf '%q' "$3")]"
        FAIL=1
    fi
}

# same <метка> <ожидание прежней редакции> <функция> <аргументы…>: новая = ожидание, и
# ожидание = прежняя редакция (если история git есть) — рамка доказывает, что ждёт верного.
same() {
    local label="$1" want="$2"; shift 2
    [ -z "$OLD" ] || check "$label: прежняя редакция" "$want" "$(run "$OLD" "$@")"
    check "$label" "$want" "$(run "$LIB" "$@")"
}

mkpat() { # $1=каталог $2=JSON блока
    mkdir -p "$1"
    printf -- '---\nname: pattern-adv\nblocker: true\nblocker_reminder: "напоминание"\ndetection_signals: |\n  %s\n---\nbody\n' \
        "$2" > "$1/pattern-adv.md"
}

# Положительные контроли: рамка умеет сказать «да» — имя печатается, непустое значение работает.
mkpat "$T/named" '[{"name":"sig","all_of":[{"tool_matches":["Bash"]}]}]'
same "контроль: имя печатается" "rc=0|sig" ds_evaluate "$T/named/pattern-adv.md" Bash '{"command":"ls"}' ""
same "контроль: command_uses frob" "rc=0|" ds_evaluate_node '{"command_uses":"frob"}' Bash '{"command":"frob --all"}' ""

# 1. Имени нет / пустое / null / false / "\n" — совпавший сигнал печатает пустую строку, а не «S».
for nm in '' '"name":"",' '"name":null,' '"name":false,' '"name":"\n",'; do
    mkpat "$T/nm" "[{${nm}\"all_of\":[{\"tool_matches\":[\"Bash\"]}]}]"
    same "имя [${nm}]" "rc=0|" ds_evaluate "$T/nm/pattern-adv.md" Bash '{"command":"ls"}' ""
done

# 2. Пустое значение листа не совпадает ни с чем — и тогда, когда вход упоминает имя ключа.
#    Лист стоит НЕ последним: хвостовую пустую лексему снимает подстановка $(…), и там она
#    честно пуста; ломается пустая лексема в середине потока.
same 'command_uses ""'      "rc=1|" ds_evaluate_node '{"all_of":[{"command_uses":""},{"tool_matches":["Bash"]}]}' Bash '{"command":"grep -rn command_uses hooks/"}' ""
same 'tool_input_regex ""'  "rc=1|" ds_evaluate_node '{"all_of":[{"tool_input_regex":""},{"tool_matches":["Edit"]}]}' Edit '{"file_path":"a.sh","new_string":"tool_input_regex"}' ""
same 'prompt_contains "\n"' "rc=1|" ds_evaluate_node '{"any_of":[{"prompt_contains":"\n"},{"tool_matches":["X"]}]}' Bash '{"command":"ls"}' "see prompt_contains"
same 'file_path_regex "\u0000"' "rc=1|" ds_evaluate_node '{"all_of":[{"file_path_regex":"\u0000"},{"tool_matches":["Edit"]}]}' Edit '{"file_path":"/x/file_path_regex.md"}' ""
# ...и через none_of решение переворачивается в обратную сторону.
same 'none_of: tool_input_contains ""' "rc=0|" \
    ds_evaluate_signal '{"name":"s","all_of":[{"none_of":[{"tool_input_contains":""}]},{"tool_matches":["Edit"]}]}' \
    Edit '{"file_path":"a.md","new_string":"tool_input_contains"}' ""

# 3. Достижимость: настоящий страж. Сигнал с отказом и пустым образцом не срабатывает никогда;
#    контроль — тот же сигнал с непустым образцом даёт deny на той же команде.
IN='{"session_id":"adv-d509r3-empty","tool_name":"Bash","tool_input":{"command":"grep -n tool_input_regex hooks/detection-signals-lib.sh"},"cwd":"/tmp"}'
hook_says() { # $1=каталог знаний $2=каталог состояния [$3=страж] → deny | blocker | silent
    local out
    out=$(printf '%s' "$IN" | BLOCKER_KNOWLEDGE_DIR="$1" BLOCKER_STATE_DIR="$2" bash "${3:-$HOOK}" 2>/dev/null)
    if grep -q '"permissionDecision": "deny"' <<< "$out"; then echo deny
    elif grep -q 'Blocker' <<< "$out"; then echo blocker
    else echo silent; fi
}
mkpat "$T/k-ctrl"  '[{"name":"strict","enforcement":"deny","all_of":[{"tool_matches":["Bash"]},{"tool_input_regex":"tool_input_regex"}]}]'
mkpat "$T/k-empty" '[{"name":"strict","enforcement":"deny","all_of":[{"tool_input_regex":""},{"tool_matches":["Bash"]}]}]'
mkpat "$T/k-noname" '[{"all_of":[{"tool_matches":["Bash"]}]}]'
mkdir -p "$T/s1" "$T/s2" "$T/s3" "$T/s4" "$T/s5"
check "страж, контроль: непустой образец" "deny" "$(hook_says "$T/k-ctrl" "$T/s1")"
check "страж: пустой образец не отказывает" "silent" "$(hook_says "$T/k-empty" "$T/s2")"
check "страж: сигнал без имени молчит, как прежде" "silent" "$(hook_says "$T/k-noname" "$T/s3")"
if [ -n "$OLD" ]; then
    # Тот же страж с прежней библиотекой рядом — ожидание взято у неё, а не придумано.
    mkdir -p "$T/h"
    cp "$REPO"/hooks/*.sh "$T/h/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_d509r3_empty_lexeme_takes_previous.sh:$LINENO" >&2; exit 1; }
    cp "$OLD" "$T/h/detection-signals-lib.sh"
    mkdir -p "$T/s6"
    check "страж с прежней библиотекой, контроль" "deny" "$(hook_says "$T/k-ctrl" "$T/s6" "$T/h/blocker-tier-check.sh")"
    check "страж с прежней библиотекой: пустой образец" "silent" "$(hook_says "$T/k-empty" "$T/s4" "$T/h/blocker-tier-check.sh")"
    check "страж с прежней библиотекой: без имени" "silent" "$(hook_says "$T/k-noname" "$T/s5" "$T/h/blocker-tier-check.sh")"
else
    echo "skip сверка с прежней редакцией: нет истории git"
fi

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
