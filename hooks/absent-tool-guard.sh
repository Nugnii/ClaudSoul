#!/usr/bin/env bash
# absent-tool-guard.sh — PreToolUse[Bash]: команда зовёт инструмент, которого на ЭТОЙ машине нет, и отказывается исполняться впустую.
# en: PreToolUse[Bash] — refuses a command that calls a tool absent on this machine.
#
# Зачем (14 сентября 2026). Разбор исходов знаний: из 283 записей «знание было уместно и не
# применено» 97 приходятся на `pattern-shell-portability`, и среди них есть класс, который
# УРОВЕНЬ 4 не покрывает — GNU-инструмент, отсутствующий на macOS. Замер по 12101 прошлому
# вызову Bash: форма `timeout <число>` встречается 18 раз, и НИ ОДИН из восемнадцати не
# защищён проверкой наличия. На этой машине `timeout` отсутствует (проверено запуском), то
# есть все 18 вызовов не исполнились: команда молча не сделала ничего, а её вывод читался
# как результат работы.
#
# ПРИЗНАК С ОДНИМ ПОСЛЕДСТВИЕМ — условие уровня 4 по правилу проекта: продолжение вызова
# означает ровно одно — «команда не исполнится». Признак не судит вкус и не угадывает
# намерение: он спрашивает САМУ МАШИНУ (`command -v`), есть ли инструмент.
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. `pattern-shell-portability` стоит на уровне 4 через `blocker-tier-check`,
# но его признак ловит ФОРМЫ РАЗНИЦЫ ДИАЛЕКТОВ (`${PIPESTATUS}`, `[ a < b ]`), а не отсутствие
# инструмента. Замена для таймаута в дереве ЕСТЬ и остаётся владельцем: `hooks/timeout-lib.sh`,
# функция `run_with_timeout` (снимает дерево процессов, код 124 на срыв срока) — страж её
# НАЗЫВАЕТ, а не повторяет.
#
# НАЗВАННЫЙ ПРЕДЕЛ: судится только имя в позиции команды. Вызов через переменную (`$TOOL 5 …`)
# не виден; условие снятия — разбор оболочки вместо шаблона. Инструмент, установленный позже,
# перестаёт отбиваться сам собой — признак спрашивает машину на каждом вызове, а не помнит.
#
# Input  (stdin): {tool_name:"Bash", tool_input:{command}} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, permissionDecision, permissionDecisionReason}}
# Exit:  always 0; отказ выражается полем permissionDecision, а не кодом.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat); [ -z "$INPUT" ] && exit 0
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "$CMD" ] || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosid"' 2>/dev/null)
STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"

# Реестр: форма в команде · имя инструмента · чем заменить. Заводится ТОЛЬКО то, у чего
# измерена точность и названа замена; предположений здесь нет.
# Журнал: `state/absent-tool-fired-<SID>.jsonl` — семейство `*-fired-*`, читатель у него
# есть (`scripts/signal-precision.sh:82`). Без журнала точность уровня 4 измерена ОДИН раз
# при заведении и больше никогда: объявление без механической сверки — корень R5.
deny() {  # deny <текст отказа> <форма, по которой сработало>
    mkdir -p "$STATE_DIR" 2>/dev/null
    # Поле одно: `key` — его читает семейство `*-fired-*`. Второе поле с тем же значением
    # (`form`) здесь было и оказалось носителем рода G — объявление без исполнителя; снято
    # в тот же час, реестром `defect-class-carriers.py --genus G`.
    # Запись собирает jq, а не printf: команда приходит извне, и перевод строки в ней рвал JSONL —
    # 16 неразбираемых строк из 78 в живом журнале 20 октября 2026 (класс разобран в `throttle-lib.sh:40-51`).
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg key "$2" --arg cmd "${CMD:0:200}" \
        '{ts: $ts, key: $key, cmd: $cmd}' 2>/dev/null >> "$STATE_DIR/absent-tool-fired-${SID}.jsonl"
    jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
        permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
}

# СУДИТСЯ ВИД «ТОЛЬКО ОБОЛОЧКА», А НЕ СЫРОЙ ТЕКСТ (D1012). Шаблон шёл по строкам и кавычек не видел:
# строка `timeout N` в многострочном скрипте для `ssh host "…"` и в теле heredoc, которое только пишется
# в файл, читалась как местный вызов, и отказ утверждал «не исполнится» о команде другой машины (24
# октября 2026 так отбита и проба этой самой починки). Вид — у владельца, `hooks/detection-signals-lib.sh`:
# `ds_shell_only` снимает тело heredoc, `ds_unquoted_command` — закавыченное, а содержимое `"$(…)"`
# оставляет — оно исполняется здесь (D1015). Позиция команды — его же `DS_CMD_POS_RE`. Без библиотеки
# судится сырой текст прежним шаблоном. Вид строится только после дешёвого предфильтра: страж стоит на
# каждом вызове Bash, а форма встречается в долях процента команд.
# НАЗВАННЫЙ ПРЕДЕЛ: тело, которое исполнит МЕСТНАЯ оболочка (`bash <<EOF`, `bash -c "…"` в одну строку и
# многострочный, `eval "…"`, `trap '…'`, `sh -c '…'` в `find -exec` и `xargs`), вид снимает вместе с прочими —
# такой вызов страж пропустит (финальный скептик D1012: в корпусе 67 536 вызовов таких пропусков один).
# Подстановки `$(…)` в теле `<<EOF` без кавычек у метки вид держит (D1053). Смещение в сторону пропуска взято
# у владельца вида. Условие снятия: разбор, различающий получателя тела.
grep -qE '(timeout[[:space:]]+[0-9]|cat[[:space:]]+-A|stat[[:space:]]+-c|date[[:space:]]+-d[[:space:]])' <<< "$CMD" || exit 0
VIEW="$CMD"; POS='(^|[;|&(]|&&|\|\|)[[:space:]]*'
DSL="${DETECTION_SIGNALS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/detection-signals-lib.sh}"
[ -f "$DSL" ] || DSL="$HOME/.claude/hooks/detection-signals-lib.sh"
# shellcheck source=/dev/null
# Вид считается в ПОДОБОЛОЧКЕ (D1054): `set -u` или `exit` на верхнем уровне общей библиотеки (её зовут
# десятки потребителей) роняли весь страж, и отказ становился пропуском. Упала подоболочка — судится сырой текст.
# Падение судится по коду САМИХ функций вида и по метке конца вывода (D1058): код подоболочки прежде был кодом
# последнего `printf`, и ошибка awk в `ds_shell_only` или `exit 0` в библиотеке давали пустой вид — пропуск.
if [ -f "$DSL" ] && _atg_v=$( . "$DSL" >/dev/null 2>&1 || exit 3
        { command -v ds_shell_only && command -v ds_unquoted_command; } >/dev/null 2>&1 && [ -n "${DS_CMD_POS_RE:-}" ] || exit 3
        _atg_s=$(ds_shell_only "$CMD" 2>/dev/null) || exit 3
        _atg_u=$(ds_unquoted_command "$_atg_s" 2>/dev/null) || exit 3
        printf '%s\n%s\n.' "$DS_CMD_POS_RE" "$_atg_u" ) && [ "${_atg_v: -2}" = $'\n.' ]; then
    POS=${_atg_v%%$'\n'*}; VIEW=${_atg_v#*$'\n'}; VIEW=${VIEW%.}
fi

# Проверка наличия своя у каждой формы: страж спрашивает машину, а не помнит ответ.
if grep -qE "${POS}timeout[[:space:]]+[0-9]" <<< "$VIEW"; then
    if ! command -v timeout >/dev/null 2>&1; then
        deny "🚫 \`timeout\` на этой машине НЕТ (проверено \`command -v\`), и вызов не исполнится — команда молча не сделает ничего, а её вывод прочитается как результат. Замер: из 12101 прошлого вызова Bash форма \`timeout <число>\` встретилась 18 раз, защищённых проверкой — ноль. Замена есть в дереве и она владелец предмета: \`source hooks/timeout-lib.sh\` и \`run_with_timeout <секунды> <команда…>\` — снимает ДЕРЕВО процессов, код 124 означает срыв срока. Нужен именно внешний \`timeout\` — поставь \`brew install coreutils\` и зови \`gtimeout\`." timeout
    fi
fi

if grep -qE "${POS}cat[[:space:]]+-A" <<< "$VIEW"; then
    if ! cat -A /dev/null >/dev/null 2>&1; then
        deny "🚫 \`cat -A\` — GNU-опция, которой в BSD-версии нет (проверено запуском), вызов оборвётся с ошибкой разбора флага. Показать непечатаемые: \`cat -v -e -t\` (BSD-эквивалент) либо \`od -c\`." cat-A
    fi
fi

if grep -qE "${POS}stat[[:space:]]+-c" <<< "$VIEW"; then
    if ! stat -c %s /dev/null >/dev/null 2>&1; then
        deny "🚫 \`stat -c\` — GNU-форма, в BSD её нет (проверено запуском). В дереве владелец предмета — \`file_mtime\` из \`hooks/portable-lib.sh\`; если нужен размер, переносимо \`wc -c < файл\`." stat-c
    fi
fi

if grep -qE "${POS}date[[:space:]]+-d[[:space:]]" <<< "$VIEW"; then
    if ! date -d @0 >/dev/null 2>&1; then
        deny "🚫 \`date -d\` — GNU-форма, в BSD её нет (проверено запуском): разбор даты оборвётся. В дереве владелец — \`iso_epoch\` из \`hooks/portable-lib.sh\` (он же держит запасную ветку \`date -j -f\`)." date-d
    fi
fi

exit 0
