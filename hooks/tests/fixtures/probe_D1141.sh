#!/usr/bin/env bash
# СУДИТ: hooks/backlog-open-write-guard.sh
# probe_D1141 — правка бэклога, названного путём в другом регистре (`backlog.md`), судится как правка BACKLOG.md: на
# файловой системе без различия регистра (macOS) это тот же файл. Красная (1), пока новый открытый пункт с зелёной
# «Проверкой», вписанный по пути `…/backlog.md`, проходит. Контроль — та же правка по `…/BACKLOG.md` отбита. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/backlog-open-write-guard.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1141.XXXXXX") || exit 2
# `backlog.md` — ТОТ ЖЕ файл, что BACKLOG.md: на ФС без различия регистра (macOS) это одно имя, на различающей (Linux) —
# жёсткая ссылка. Так проба судит одно и то же на обеих: правку бэклога под другим именем.
printf '%s\n' '# BACKLOG' '' '- ☐ **D1** старый' '  **Проверка.** `false` → 0' > "$T/BACKLOG.md"
[ "$T/backlog.md" -ef "$T/BACKLOG.md" ] || ln "$T/BACKLOG.md" "$T/backlog.md" 2>/dev/null || exit 2
dec() {  # dec <имя файла> → решение стража на вписывание открытого пункта с зелёной «Проверкой»
    local d
    d=$(jq -cn --arg f "$T/$1" --arg o '- ☐ **D1** старый' --arg n "$(printf '%s\n' '- ☐ **D2** новый' '  **Проверка.** `true` → 0' '- ☐ **D1** старый')" \
          '{session_id:"p", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
        | CLAUDSOUL_ROOT="$R" STATE_DIR="$T/state" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
    printf '%s\n' "${d:-allow}"
}
[ "$(dec BACKLOG.md)" = deny ] || exit 2
[ "$(dec backlog.md)" = deny ] || exit 1
exit 0
