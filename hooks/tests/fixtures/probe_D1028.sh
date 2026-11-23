#!/usr/bin/env bash
# СУДИТ: hooks/undefined-function-check.sh
# probe_D1028.sh — страж «запускается файл, которого нет» судит путь от ПОСЛЕДНЕГО перехода перед вызовом, а не от ведущего (D1028).
#
# Коды: 0 — команда `cd /tmp && true; cd <репозиторий> && bash hooks/tests/fixtures/probe_D1018.sh` не получает «файла
#       нет», а контроль — вызов несуществующего файла из репозитория — получает; 1 — получает (дефект D1028: каталог
#       вызова берётся из ведущего `cd`, второй переход после `;` не учитывается); 2 — судить нечем: нет стража, jq или
#       существующего файла-вызова, либо контроль не назван (страж молчит на всём).
# Повод — 22 октября 2026: `cd ~/.claude/projects && …; cd "<ClaudSoul>" && bash hooks/tests/fixtures/probe_D1018.sh`
# получила «Запускается файл, которого нет», хотя проба исполнилась (rc=1 самой пробы).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/undefined-function-check.sh"
[ -f "$HOOK" ] && [ -f "$REPO/hooks/tests/fixtures/probe_D1018.sh" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
S=$(mktemp -d) || exit 2; trap 'rm -rf "$S"' EXIT
q() { jq -cn --arg c "$1" --arg d "$REPO" --arg i "$2" '{session_id:$i,tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
        | (cd "$REPO" && STATE_DIR="$S" bash "$HOOK" 2>/dev/null); }
case "$(q "bash hooks/tests/fixtures/probe_NONE.sh" probe-d1028a)" in *"которого нет"*) ;; *) exit 2 ;; esac
case "$(q "cd /tmp && true; cd \"$REPO\" && bash hooks/tests/fixtures/probe_D1018.sh" probe-d1028b)" in *"которого нет"*) exit 1 ;; esac
exit 0
