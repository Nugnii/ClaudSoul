#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# probe_D1023.sh — обход ловушки git формой вне перечня слов не вводит починку без пункта в main (D1023).
#
# Коды: 0 — в судимом репозитории с ловушкой и псевдонимом `ci = commit -n`, заданным НЕ агентом (настройкой
#       репозитория до сессии), команда `git ci -m "fix: …"` без пункта в main не вошла (страж отбил её либо,
#       исполненная, она не сдвинула HEAD); 1 — вошла (дефект D1023: обход ловится по слову, а псевдоним слова не
#       несёт); 2 — судить нечем: нет стража, git, jq или python3, либо не вошёл законный коммит `git ci` с пунктом
#       (контроль: без него «не вошло» не отличить от сломанного git).
# Повод — 21 октября 2026, финальный скептик D1021: псевдоним с `commit -n` проходил мимо ловушки и мимо слова.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/merge-root-gate.sh"
[ -f "$HOOK" ] || exit 2
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || exit 2; done
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state" CLAUDSOUL_ROOT="$REPO"
# Коммит делает агент: --no-verify владельца в терминале — его право, и сверка его не судит (D1023). Признак агента
# задан явно, чтобы ответ пробы не зависел от того, кто её запустил.
export CLAUDECODE=1
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
git -C "$R" config alias.ci 'commit -n'   # настройка репозитория до сессии: агент её не писал

hook() { jq -cn --arg c "$1" --arg d "$R" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' | bash "$HOOK" 2>/dev/null; }
denied() { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
fresh() { printf 'module.exports = %s;\n' "$1" > "$R/src/a.js"; git -C "$R" add src/a.js; }
lands() { local h0; h0=$(git -C "$R" rev-parse HEAD)
    denied "$(hook "$1")" && return 1
    ( cd "$R" && bash -c "$1" >/dev/null 2>&1 )
    [ "$(git -C "$R" rev-parse HEAD)" != "$h0" ]; }
# Контроль — законный коммит через тот же псевдоним без обхода: `git -c alias.ok=commit ok` входит.
fresh 2
lands "git -c alias.ok=commit ok -q -m 'fix: правка (X1)'" \
    || { echo "probe_D1023: контроль — законный коммит через псевдоним не вошёл, судить нечем" >&2; exit 2; }
fresh 3
if lands "git ci -q -m 'fix: правка без пункта'"; then
    echo "probe_D1023: дефект — починка без пункта вошла в main через псевдоним с commit -n" >&2; exit 1
fi
exit 0
