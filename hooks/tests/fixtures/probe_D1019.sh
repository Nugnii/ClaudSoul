#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# probe_D1019.sh — починка без пункта не входит в main и прямым коммитом, а не только слиянием (D1019).
#
# Коды: 0 — `git commit -m "fix: …"` в main с изменённым кодом, чья тема не называет пункт, в main не вошёл (страж
#       отбил команду либо, исполненная, она не сдвинула HEAD), а коммит починки с пунктом, у которого корень из
#       карты, и коммит не-починки (chore) вошли; 1 — починка без пункта вошла (дефект D1019: страж стоит только на
#       `git merge`, а работа входит в main прямыми коммитами); 2 — судить нечем: нет стража, git, jq или python3,
#       либо не вошёл один из контролей.
# Судится РЕЗУЛЬТАТ в мире: репозиторий обставлен, как судимый проект, — стражем поставлена его ловушка git
# (`--install`; у стража без этого режима вызов ничего не делает), а коммит исполняется по-настоящему.
# Повод — 21 октября 2026: в main ClaudSoul с 9 октября 119 коммитов, из них 13 починок (fix/perf) меняли код,
# не называя пункт, — среди них c3148ba7 и 21baa528 той же сессии; слияний за это время не было ни одного.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/merge-root-gate.sh"
[ -f "$HOOK" ] || exit 2
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || exit 2; done
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state" CLAUDSOUL_ROOT="$REPO"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$T/repo"; mkdir -p "$R/src" "$R/scripts/probes"
git -C "$R" init -q -b main || exit 2
printf '%s\n' '# ROOTS' '' '## R1 — тестовый корень' '**Устройство.** src делает BAD.' \
    '**Признак.** `scripts/probes/R1.sh`' '**Зависимости (чек-лист регрессии).** —' '**Держит.** —' > "$R/ROOTS.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/probes/R1.sh"
printf '%s\n' '# BACKLOG' '' '### X1 ☐ [P2] пункт с корнем' '**Корень.** R1' > "$R/BACKLOG.md"
printf 'module.exports = 1;\n' > "$R/src/a.js"
git -C "$R" add -A && git -C "$R" commit -qm init || exit 2
bash "$HOOK" --install "$R" </dev/null >/dev/null 2>&1

hook() { jq -cn --arg c "$1" --arg d "$R" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' | bash "$HOOK" 2>/dev/null; }
denied() { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
fresh() { printf 'module.exports = %s;\n' "$1" > "$R/src/a.js"; git -C "$R" add src/a.js; }
# lands <команда> → 0, если коммит вошёл в main: страж не отбил, и исполненная команда сдвинула HEAD.
lands() { local h0; h0=$(git -C "$R" rev-parse HEAD)
    denied "$(hook "$1")" && return 1
    ( cd "$R" && bash -c "$1" >/dev/null 2>&1 )
    [ "$(git -C "$R" rev-parse HEAD)" != "$h0" ]; }
fresh 2
lands 'git commit -q -m "fix: правка (X1)"' \
    || { echo "probe_D1019: контроль — починка с пунктом и корнем не вошла, судить нечем" >&2; exit 2; }
fresh 3
lands 'git commit -q -m "chore: учёт"' \
    || { echo "probe_D1019: контроль — коммит не-починки не вошёл, судить нечем" >&2; exit 2; }
fresh 4
if lands 'git commit -q -m "fix: правка без пункта"'; then
    echo "probe_D1019: дефект — починка без пункта вошла в main прямым коммитом" >&2
    exit 1
fi
# Основная форма работы агента — `git add … && git commit …` одной командой: на момент хука PreToolUse индекс ещё
# пуст, и страж, судящий индекс до исполнения команды, такой коммит не видит (волна проверки D1019, 21 октября 2026).
# Это и есть путь, которым идёт работа, а D1019 заведён ровно о страже, стоящем не на нём.
git -C "$R" reset -q; printf 'module.exports = 5;\n' > "$R/src/a.js"
if lands 'git add src/a.js && git commit -q -m "fix: правка без пункта"'; then
    echo "probe_D1019: дефект — починка без пункта вошла в main формой «git add && git commit»" >&2
    exit 1
fi
exit 0
