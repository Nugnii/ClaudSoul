#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh hooks/undefined-function-check.sh hooks/trust-guard.sh hooks/ci-check-reminder.sh hooks/publish-guard.sh
# probe_D1212 — начало команды внутри подстановки видно читателям `executable_part`. Вывод функции: открытие `$(` и
# обратной кавычкой — `( ` (`x=$(a)` и `x=`a`` → `x=( a`). Страж «запускается файл, которого нет» подаётся командой из
# каталога, где файла нет (`$W/home`), а файл лежит в дереве `$W/repo` (вызовы внутри обратных кавычек этот страж не
# судит вовсе — D1253, поэтому их форма судится выводом функции, а не стражем):
#   повод  — `cd home && out=$(cd repo && bash scripts/x.sh)`: переход внутри подстановки засчитан — молчит;
#   нет    — `cd repo && out=$(bash scripts/none.sh)`: перехода в подстановке нет, файла нет — тревога (контроль: починка
#            не глушит подстановку целиком);
#   D422   — `cd repo && bash scripts/none.sh` — тревога;
#   D1028  — `cd home && true; cd repo && bash scripts/x.sh` — молчит; `cd repo && bash scripts/none.sh && cd -` — тревога.
# Распознавание коммита (`is_git_commit`, на нём стоят стражи коммита): `out=$(git commit -q -m x)` — коммит,
# `echo "`date`" && git commit -m x` — коммит (закрывающая обратная кавычка не открывает подстановку), `echo "git commit"` — нет.
# `echo $(echo "`git commit -m x`")` — коммит (обратная кавычка внутри `$(` открывает подстановку).
# Стражи с якорем «пробел перед командой»: `trust-guard` видит `x=$(rm -rf …)`, `ci-check-reminder` — `r=$(git push 2>&1)`.
# Читатели, которым прежде хватало склейки `out=…` (скептик D1212): `publish-guard` отказывает на
# `out=$(./scripts/publish-public.sh --push 2>&1)` и на `out="$(./scripts/publish-public.sh --push 2>&1)"` (открытие внутри
# двойных кавычек тоже выводится `( `), молчит на `grep publish-public.sh README.md`; поиск вызовов функций
# видит `$(undefined_helper_xyz arg)` в начале строки записанного файла.
# 0 — все формы как названо; 1 — иначе (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v jq >/dev/null 2>&1 || { echo "рамка: нет jq" >&2; exit 2; }
[ -f "$R/hooks/undefined-function-check.sh" ] && [ -f "$R/hooks/command-scope-lib.sh" ] || { echo "рамка: нет стража" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1212.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home" "$W/repo/scripts" && printf '#!/usr/bin/env bash\n' > "$W/repo/scripts/x.sh" || exit 2

BAD=""
# ufc <имя> <ждём: тихо|тревога> <команда>
ufc() {
    local out
    out=$(jq -nc --arg c "$3" --arg w "$W/home" '{tool_name:"Bash",hook_event_name:"PreToolUse",cwd:$w,tool_input:{command:$c}}' \
        | bash "$R/hooks/undefined-function-check.sh" 2>/dev/null)
    case "$2:$out" in
        тихо:) ;;
        тревога:*'которого нет'*) ;;
        *) BAD="$BAD $1(ждали $2)" ;;
    esac
}
ufc повод   тихо    "cd \"$W/home\" && out=\$(cd \"$W/repo\" && bash scripts/x.sh --dry-run)"
ufc нет     тревога "cd \"$W/repo\" && out=\$(bash scripts/none.sh)"
ufc D422    тревога "cd \"$W/repo\" && bash scripts/none.sh"
ufc D1028   тихо    "cd \"$W/home\" && true; cd \"$W/repo\" && bash scripts/x.sh"
ufc D1028b  тревога "cd \"$W/repo\" && bash scripts/none.sh && cd -"

# shellcheck source=/dev/null
. "$R/hooks/command-scope-lib.sh" 2>/dev/null || { echo "рамка: библиотека не подключилась" >&2; exit 2; }
command -v is_git_commit >/dev/null 2>&1 || { echo "рамка: нет is_git_commit" >&2; exit 2; }
is_git_commit 'out=$(git commit -q -m x)' || BAD="$BAD коммит-в-присваивании"
is_git_commit 'echo "`date`" && git commit -m x' || BAD="$BAD коммит-за-кавычкой"
is_git_commit 'echo "git commit"' && BAD="$BAD текст-как-коммит"
is_git_commit 'echo $(echo "`git commit -m x`")' || BAD="$BAD коммит-в-кавычке-в-подстановке"
[ "$(executable_part 'x=$(a)')" = 'x=( a' ] || BAD="$BAD вывод-открытия"
[ "$(executable_part 'x=`a`')" = 'x=( a' ] || BAD="$BAD вывод-обратной-кавычки"

# Братья того же корня — стражи, чей якорь начала команды ждёт пробела: подстановка в присваивании видна и им.
out=$(jq -nc --arg c "x=\$(rm -rf \"$W/none\")" '{session_id:"p1212",tool_name:"Bash",tool_input:{command:$c}}' \
    | STATE_DIR="$W/state" bash "$R/hooks/trust-guard.sh" 2>/dev/null)
case "$out" in *Trust-guard*) ;; *) BAD="$BAD rm-в-присваивании" ;; esac
git -C "$W/repo" init -q 2>/dev/null && printf '#!/usr/bin/env bash\n' > "$W/repo/scripts/ci-status.sh" || exit 2
out=$(jq -nc --arg w "$W/repo" '{tool_name:"Bash",cwd:$w,tool_input:{command:"r=$(git push 2>&1)"}}' \
    | bash "$R/hooks/ci-check-reminder.sh" 2>/dev/null)
case "$out" in *'Пуш ушёл'*) ;; *) BAD="$BAD push-в-присваивании" ;; esac

# Читатели, которым прежде хватало склейки `out=…`.
pg() { jq -nc --arg c "$1" --arg w "$W/repo" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}' \
    | STATE_DIR="$W/state" bash "$R/hooks/publish-guard.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }
[ "$(pg 'out=$(./scripts/publish-public.sh --push 2>&1)')" = deny ] || BAD="$BAD публикация-в-подстановке"
[ "$(pg 'out="$(./scripts/publish-public.sh --push 2>&1)"')" = deny ] || BAD="$BAD публикация-в-двойных"
[ -z "$(pg 'grep publish-public.sh README.md')" ] || BAD="$BAD публикация-аргументом"
printf '%s\n' '#!/usr/bin/env bash' 'msg="текст' '$(undefined_helper_xyz arg)"' > "$W/fn.sh" || exit 2
out=$(jq -nc --arg f "$W/fn.sh" '{tool_name:"Write",hook_event_name:"PostToolUse",session_id:"p1212",tool_input:{file_path:$f}}' \
    | STATE_DIR="$W/state" bash "$R/hooks/undefined-function-check.sh" 2>/dev/null)
case "$out" in *undefined_helper_xyz*) ;; *) BAD="$BAD функция-в-подстановке" ;; esac

[ -z "$BAD" ] || { echo "D1212: не так:$BAD"; exit 1; }
echo "D1212: переход и коммит внутри подстановки видны"
exit 0
