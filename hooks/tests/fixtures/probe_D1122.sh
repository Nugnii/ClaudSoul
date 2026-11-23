#!/usr/bin/env bash
# СУДИТ: hooks/backlog-open-write-guard.sh BACKLOG.md BACKLOG-archive.md
# probe_D1122 — новый пункт не вписывается ВНУТРЬ блока другого пункта, и показание D1111 стоит у своего пункта.
# Красная (1), пока (а) показание закрытия D1111 лежит хвостом блока D1120 в BACKLOG.md, а архивная копия D1111 его не
# несёт (D1112 в ecbc8d93 вписан правкой по строке «Зелёная сторона» D1111, а за ней стояло показание), или (б) правка,
# вписывающая пункт между строками закрытого пункта, проходит страж записи бэклога. Положительный контроль (б) — та же
# вставка после последней строки пункта проходит. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/backlog-open-write-guard.sh"; LIB="$R/hooks/backlog-lib.sh"
[ -f "$HOOK" ] && [ -f "$LIB" ] && [ -f "$R/BACKLOG.md" ] && [ -f "$R/BACKLOG-archive.md" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
. "$LIB" 2>/dev/null || exit 2
EV="touched поверх deferred отброшен"
arc=$(backlog_item_block "$R/BACKLOG-archive.md" D1111) || exit 2
grep -qF "$EV" <<< "$arc" || { echo "(а) архивная копия D1111 без своего показания" >&2; exit 1; }
if cur=$(backlog_item_block "$R/BACKLOG.md" D1120); then
    grep -qF "$EV" <<< "$cur" && { echo "(а) показание D1111 лежит в блоке D1120" >&2; exit 1; }
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1122.XXXXXX") || exit 2
BL="$T/BACKLOG.md"; ST="$T/state"; mkdir -p "$ST"
printf '%s\n' '# BACKLOG' '' '- ☑ **D10** закрытый' '  **Корень.** R6 — два состояния.' '  **Проверка.** `true` → 0' \
    '  **Зелёная сторона.** нога D10.' '  **Показание.** «Проверка» 0 (до — 1).' > "$BL"
NEW='- ☐ **D11** новый
  **Повод.** `x.sh:1` ломается.
  **Корень.** R6 — два состояния.
  **Проверка.** `false` → 0'
ed() { jq -cn --arg f "$BL" --arg o "$1" --arg n "$2" \
    '{session_id:"p1122", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
    | CLAUDSOUL_ROOT="$R" STATE_DIR="$ST" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }
ok=$(ed '  **Показание.** «Проверка» 0 (до — 1).' "  **Показание.** «Проверка» 0 (до — 1).

$NEW")
[ "${ok:-allow}" = allow ] || exit 2
split=$(ed '  **Зелёная сторона.** нога D10.' "  **Зелёная сторона.** нога D10.

$NEW")
[ "$split" = deny ] || { echo "(б) пункт, вписанный внутрь блока закрытого, прошёл страж записи" >&2; exit 1; }
echo "пункты не раскалывают чужой блок"
exit 0
