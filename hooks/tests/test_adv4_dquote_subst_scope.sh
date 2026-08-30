#!/usr/bin/env bash
# test_adv4_dquote_subst_scope.sh — адверсариальный раунд 4: подстановка внутри
# ДВОЙНЫХ кавычек копируется в исполняемую часть СЫРОЙ, вместе с кавычками,
# heredoc'ами и скобками, которые в ней лежат.
#
# Ветка `in_d` в `executable_part` при виде `$(` и обратной кавычки переписывает
# содержимое подстановки символ в символ, не отслеживая ни кавычек внутри неё, ни
# открытия heredoc. Три следствия, все проверяются ниже:
#
#   A1  `"$(cat <<'EOF' … EOF)"` — heredoc, открытый ВНУТРИ подстановки, не
#       регистрируется (`in_h` не выставляется). Цикл копирования упирается в конец
#       строки и оставляет `in_d = 1`, поэтому тело heredoc разбирается как текст
#       в двойных кавычках. Первая же `"` или обратная кавычка в теле переключает
#       состояние — и ОСТАТОК СООБЩЕНИЯ КОММИТА становится «исполняемой частью».
#       Это ровно тот дефект, ради которого библиотека написана: страж горит на
#       тексте. Форма — штатный способ коммитить в этом проекте.
#   A2  кавычки внутри подстановки копируются вместе с содержимым: шаблон
#       `grep -n 'делает git commit'` внутри `"$( … )"` выходит наружу как команда.
#   A3  `)` внутри кавычек внутри подстановки закрывает её досрочно (счётчик глубины
#       кавычек не видит), а непарная `(` — наоборот, уводит копирование до конца
#       строки. В обоих случаях состояние кавычек разъезжается и СЛЕДУЮЩИЕ СТРОКИ
#       команды съедаются целиком: настоящий `rm -rf`/`git commit` идёт мимо стража.
#
# Тесты написаны, чтобы УПАСТЬ на текущем коде. Ничего не чинят.
#
# Достижимость замерена по 20 224 реальным вызовам Bash из ~/.claude/projects
# (записи собственных адверсариальных прогонов отфильтрованы по упоминанию
# `test_adv` / `command-scope-lib` / `executable_part` / `is_git_commit`):
#   A1 — 113 живых команд формы `"$( … <<MARKER` с `"` или обратной кавычкой в теле;
#        у 34 из них фрагмент тела длиной ≥ 15 символов ИЗМЕРЕННО присутствует в
#        выводе `executable_part` (утёкшие строки вида `bash hooks/tests/run_all.sh`,
#        `uv sync --frozen`, `grep -vE '^#' file | grep -q '...'`);
#   A2 — 822 живых команды содержат кавычку внутри подстановки внутри двойных
#        кавычек (4.1 % корпуса); у 166 из них в исполняемой части уже лежит
#        сигнатура стража. Расхождений именно по `is_git_commit` в живом корпусе
#        нет — сверено с эталонным разбором, счётчик коммитов пока цел;
#   A3 — подмножество тех же 822.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
source "$HOOKS_DIR/command-scope-lib.sh"

_show() { printf '%s' "$1" | tr '\n' '~'; }

yes_() { # $1=команда $2=имя — is_git_commit ДОЛЖЕН распознать
    if is_git_commit "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$2]: настоящий коммит НЕ распознан"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    fi
}
no_() { # $1=команда $2=имя — is_git_commit НЕ должен распознать
    if is_git_commit "$1"; then FAIL=$((FAIL + 1))
        echo "FAIL [$2]: коммитом сочтён текст"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$(executable_part "$1")")]"
    else PASS=$((PASS + 1)); fi
}
exec_has() { # $1=команда $2=подстрока $3=имя
    local e; e=$(executable_part "$1")
    if grep -qF -- "$2" <<< "$e"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$3]: исполняемая часть потеряла «$2»"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$e")]"
    fi
}
exec_lacks() { # $1=команда $2=подстрока $3=имя
    local e; e=$(executable_part "$1")
    if grep -qF -- "$2" <<< "$e"; then FAIL=$((FAIL + 1))
        echo "FAIL [$3]: текст «$2» попал в исполняемую часть"
        echo "       вход: $(_show "$1")"
        echo "       executable_part: [$(_show "$e")]"
    else PASS=$((PASS + 1)); fi
}

# ---------------------------------------------------------------------------
# Фикстура: репозиторий, где у стражей есть повод сработать.
# ---------------------------------------------------------------------------
CR="$TMP/repo"
mkdir -p "$CR/hooks" "$CR/scripts" "$CR/lessons/_drafts" "$TMP/state"
git -C "$CR" init -q 2>/dev/null
git -C "$CR" config user.email "t@e"; git -C "$CR" config user.name "t"
printf '# Changelog\n' > "$CR/CHANGELOG.md"
printf '#!/usr/bin/env bash\necho ci\n' > "$CR/scripts/ci-status.sh"
git -C "$CR" add -A >/dev/null 2>&1
git -C "$CR" commit -q -m seed 2>/dev/null

_sid() { printf '%s' "$1" | tr -cd '[:alnum:]-' | head -c 48; }
_run() { # $1=хук $2=команда $3=sid
    jq -cn --arg c "$2" --arg cwd "$CR" --arg s "$3" \
        '{session_id:$s, transcript_path:"", cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" LESSONS_DIR="$CR/lessons" bash "$HOOKS_DIR/$1" 2>/dev/null
}
hook_silent() { # $1=хук $2=команда $3=имя
    local out; out=$(_run "$1" "$2" "$(_sid "$3")")
    if [ -z "$out" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1))
        echo "FAIL [$3]: $1 сработал на тексте — $(printf '%s' "$out" | tr -d '\n' | head -c 150)"
        echo "       executable_part: [$(_show "$(executable_part "$2")")]"; fi
}
hook_fires() { # $1=хук $2=команда $3=имя
    if [ -n "$(_run "$1" "$2" "$(_sid "$3")")" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: $1 промолчал на настоящем действии"
        echo "       executable_part: [$(_show "$(executable_part "$2")")]"; fi
}

# ===========================================================================
echo "=== АТАКА 1: тело heredoc, открытого внутри \"\$( … )\", становится командой ==="
# Штатная форма коммита в этом проекте: сообщение приходит heredoc'ом через
# подстановку в двойных кавычках. Кавычка в тексте сообщения переключает in_d,
# и остаток сообщения уходит стражам как исполняемая часть.
A1_DQ=$(cat <<'CMD'
git commit -q -m "$(cat <<'EOF'
fix(hooks): страж больше не путает "rm -rf" в тексте с действием
EOF
)"
CMD
)
exec_lacks "$A1_DQ" 'rm -rf' "A1-a  текст сообщения коммита не исполняемая часть"
hook_silent trust-guard.sh "$A1_DQ" "A1-b  trust-guard молчит на сообщении коммита про rm -rf"

# Обратные кавычки в сообщении — та же дверь: ветка in_d копирует всё между ними.
# В этом проекте имена команд в сообщениях размечают именно так.
A1_BT=$(cat <<'CMD'
git commit -q -m "$(cat <<'EOF'
docs: разобран случай `git push --force origin main` из чужого репозитория
EOF
)"
CMD
)
exec_lacks "$A1_BT" 'git push --force' "A1-c  разметка обратными кавычками не исполняемая часть"
hook_silent trust-guard.sh "$A1_BT" "A1-d  trust-guard молчит на сообщении коммита про force push"

# Тот же вход, другой потребитель: ci-check-reminder ищет `git push`.
A1_CI=$(cat <<'CMD'
git commit -q -m "$(cat <<'EOF'
fix(ci): напоминание после `git push` ждёт прогон своего коммита
EOF
)"
CMD
)
exec_lacks "$A1_CI" 'git push' "A1-e  упоминание git push в сообщении не исполняемая часть"
hook_silent ci-check-reminder.sh "$A1_CI" "A1-f  ci-check-reminder молчит: пуша не было"

# ===========================================================================
echo "=== АТАКА 2: кавычки внутри подстановки внутри двойных кавычек ==="
# Шаблон поиска — аргумент grep. Внутри "$( … )" он копируется сырым и становится
# командой: `knowledge-capture-reminder` засчитывает несуществующий коммит и
# пишет счётчик в файл состояния — портятся накопленные данные, а не только вывод.
A2_GC='echo "нашёл: $(grep -n '"'"'делает git commit сам'"'"' README.md)"'
no_ "$A2_GC" "A2-a  шаблон grep внутри \"\$( … )\" — не коммит"
exec_lacks "$A2_GC" 'git commit' "A2-b  содержимое кавычек не выходит из подстановки"

A2_GC2='echo "нашёл: $(grep -n "как делать git commit правильно" README.md)"'
no_ "$A2_GC2" "A2-c  двойные кавычки внутри подстановки — тоже аргумент"

# Тот же механизм разрушительной сигнатурой.
A2_RM='echo "совпадений: $(grep -c '"'"' rm -rf '"'"' BACKLOG.md)"'
exec_lacks "$A2_RM" 'rm -rf' "A2-d  шаблон rm -rf внутри \"\$( … )\" не исполняемая часть"
hook_silent trust-guard.sh "$A2_RM" "A2-e  trust-guard молчит на подсчёте вхождений"

# ===========================================================================
echo "=== АТАКА 3: скобка в кавычках внутри подстановки рвёт состояние ==="
# `)` внутри кавычек досрочно закрывает подстановку — счётчик глубины кавычек не
# видит. Дальше `in_d` разъезжается, и СЛЕДУЮЩИЕ строки съедаются целиком.
A3_CLOSE=$(cat <<'CMD'
N="$(grep -c ")" README.md)"
git commit -m "правка"
CMD
)
yes_ "$A3_CLOSE" "A3-a  коммит на следующей строке распознан"
exec_has "$A3_CLOSE" 'git commit' "A3-b  вторая строка не должна быть съедена"

# Непарная `(` внутри кавычек — зеркальная беда: копирование уходит до конца
# строки, `in_d` остаётся выставленным, остаток команды исчезает.
A3_OPEN=$(cat <<'CMD'
N="$(grep -c "(" README.md)"
rm -rf /tmp/adv4-build
CMD
)
exec_has "$A3_OPEN" 'rm -rf' "A3-c  разрушительная команда на второй строке не съедена"
hook_fires trust-guard.sh "$A3_OPEN" "A3-d  trust-guard видит rm -rf после подстановки со скобкой"

echo ""
echo "adv4 dquote subst scope: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
