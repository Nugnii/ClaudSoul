#!/usr/bin/env bash
# limit_quoted_path.sh — ПРОВЕРКА СНЯТИЯ названного предела `git-add-sweep-guard.sh:53`.
#
# Предел: пути для `git add --dry-run` берутся делением по пробелам, поэтому захват,
# названный путём В КАВЫЧКАХ С ПРОБЕЛОМ, стражу не виден и он молчит.
#
# Код 0 = условие снятия НАСТУПИЛО: страж спросил, то есть пути пошли через разбор.
# Код 1 = предел держится (нынешнее состояние).
# Код 2 = судить нечем (нет jq либо git) — не путать с «не наступило».
#
# Направление кода обратно «Проверке» пункта долга и это намеренно: там красное значит
# «дефект жив», здесь зелёное значит «ограничение больше не нужно».
set -uo pipefail

command -v jq  >/dev/null 2>&1 || { echo "limit_quoted_path: нет jq"  >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "limit_quoted_path: нет git" >&2; exit 2; }

HOOKS="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$HOOKS/git-add-sweep-guard.sh"
[ -f "$GUARD" ] || { echo "limit_quoted_path: стража нет на месте" >&2; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/docs"
git -C "$R" init -q
git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo base > "$R/docs/tracked.md"
git -C "$R" add docs/tracked.md
git -C "$R" -c user.email=t@t -c user.name=t commit -qm base

# Неотслеживаемый файл, чьё имя НЕСЁТ ПРОБЕЛ: ради него предел и назван.
printf 'x\n' > "$R/docs/мой файл.md"

ask() {  # ask <команда> → 0, если страж спросил
    local out
    out=$(jq -cn --arg c "$1" --arg d "$R" \
            '{tool_name:"Bash",hook_event_name:"PreToolUse",tool_input:{command:$c},cwd:$d}' \
          | bash "$GUARD" 2>/dev/null)
    [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)" = "ask" ]
}

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ РАМКИ ПЕРЕД СУДОМ. На обычном захвате страж обязан спросить;
# иначе «молчит на кавычках» значило бы «рамка не собралась», а не «предел держится».
if ! ask 'git add -A -- docs'; then
    echo "limit_quoted_path: РАМКА НЕ СОБРАЛАСЬ — страж молчит и на обычном захвате" >&2
    exit 2
fi

# СУД: путь назван в кавычках с пробелом. Сейчас слова получаются делением по пробелам,
# git такого пути не находит, и страж молчит — предел держится.
if ask 'git add "docs/мой файл.md" docs'; then
    echo "условие снятия НАСТУПИЛО: страж спросил на пути в кавычках с пробелом"
    exit 0
fi
echo "предел держится: путь в кавычках с пробелом стражу не виден" >&2
exit 1
