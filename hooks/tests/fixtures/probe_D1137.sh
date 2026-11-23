#!/usr/bin/env bash
# СУДИТ: hooks/backlog-open-write-guard.sh
# probe_D1137 — закрытие пункта, который чинит защитный слой (`hooks/`), требует строки «Скептик.»: ☑ ставится после
# отчёта финального скептика, а не по собственной пробе автора. Красная (1), пока закрытие пункта с адресом в `hooks/` без
# строки «Скептик.» проходит. Контроль — то же закрытие со строкой «Скептик.» и закрытие пункта с адресом в `scripts/`
# проходят (иначе страж отбивал бы всякое закрытие). Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/backlog-open-write-guard.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1137.XXXXXX") || exit 2
# Каталог `hooks/` в корне — условие мира: защитный слой есть у ЭТОГО репозитория (у React-проекта `hooks/` — другое).
BL="$T/BACKLOG.md"; ST="$T/state"; mkdir -p "$ST" "$T/hooks"
RET='  **Проверка возврата:** решение — пункт описывает наличный дефект, возврат наступает, когда за него берутся.'
item() {  # item <метка> <id> <адрес> [closed|skeptic] — блок пункта
    printf '%s\n' "- $1 **$2** дефект" "  **Повод.** \`$3\` пропускает запись." '  **Корень.** R5 — объявление без проверки.' \
        '  **Проверка.** `true` → 0'
    if [ -n "${4:-}" ]; then printf '%s\n' '  **Показание.** «Проверка» 0 (до — 1).'; [ "$4" = skeptic ] && printf '%s\n' '  **Скептик.** opus, отчёт без находок H/M.'
    else printf '%s\n' "$RET"; fi
}
run() {  # молчание стража — пропуск: на пустом выводе jq не печатает ничего
    local d; d=$(CLAUDSOUL_ROOT="$R" STATE_DIR="$ST" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
    printf '%s\n' "${d:-allow}"
}
close() {  # close <id> <адрес> <closed|skeptic> → решение стража на закрытие ◐ → ☑
    { printf '%s\n\n' '# BACKLOG'; item ◐ "$1" "$2"; } > "$BL"
    jq -cn --arg f "$BL" --arg o "$(item ◐ "$1" "$2")" --arg n "$(item ☑ "$1" "$2" "$3")" \
        '{session_id:"p",tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}' | run
}
[ "$(close D20 hooks/x-guard.sh:10 skeptic)" = allow ] || exit 2
[ "$(close D21 scripts/report.sh:5 closed)" = allow ] || exit 2
[ "$(close D22 hooks/x-guard.sh:10 closed)" = deny ] || exit 1
exit 0
