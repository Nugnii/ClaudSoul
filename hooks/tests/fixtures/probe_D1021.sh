#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# probe_D1021.sh — починка без пункта не входит в main ни в какой форме команды коммита (D1021).
#
# Коды: 0 — каждая форма (`bash -c "git commit …"`, `eval "git commit …"`, слитное `-am"…"`) либо отбита стражем,
#       либо, исполненная в фикстурном репозитории, не сдвинула HEAD; 1 — хотя бы одна форма вошла в main без
#       пункта (дефект D1021: страж восстанавливает коммит из текста команды по перечню форм, и форма вне перечня
#       проходит молча); 2 — судить нечем: нет стража, git, jq или python3, либо не вошёл законный коммит той же
#       формы (контроль: без него «не вошло» не отличить от сломанного git).
# Судится РЕЗУЛЬТАТ в мире, а не способ: проба зеленеет и от стража, дописавшего формы, и от суда в ловушке git
# (`commit-msg` видит готовое сообщение и ровно тот индекс, что войдёт в коммит). Репозиторий обставлен, как судимый
# проект: стражем поставлена его ловушка git (`--install`; у стража без этого режима вызов ничего не делает).
# Повод — 21 октября 2026, финальный скептик D1019: три формы из фикстуры обходов проходили молча.
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
lands "bash -c \"git commit -q -m 'fix: правка (X1)'\"" \
    || { echo "probe_D1021: контроль — законный коммит формы bash -c не вошёл, судить нечем" >&2; exit 2; }
bad="" n=3
for form in "bash -c \"git commit -q -m 'fix: правка без пункта'\"" \
            "eval \"git commit -q -m 'fix: правка без пункта'\"" \
            'git commit -q -am"fix: правка без пункта"'; do
    fresh "$n"; n=$((n + 1))
    lands "$form" && bad="$bad | $form"
done
[ -z "$bad" ] || { echo "probe_D1021: дефект — вошли в main без пункта:$bad" >&2; exit 1; }
exit 0
