#!/usr/bin/env bash
# СУДИТ: hooks/docs-family-check.sh
# probe_D1022.sh — страж коммита судит репозиторий, в который ляжет коммит, а не папку сессии (D1022).
#
# Коды: 0 — `git -C <другой репозиторий> commit` из папки сессии, где автотаблицы на деле разошлись, вошёл: коммит
#       ложится в другой репозиторий, а у того ни таблиц, ни расхождения нет; 1 — отбит (дефект D1022: страж
#       восстанавливает коммит из текста команды и судит папку сессии); 2 — проба не исполнима либо контроль мёртв
#       (тот же коммит в самой папке сессии вошёл — расхождение не судится, и «вошёл» ничего не значит).
# Судится РЕЗУЛЬТАТ пути агента целиком: PreToolUse стража, затем исполнение команды с ловушкой git, если дерево её
# ставит (`hooks/commit-trap.sh --install`). Отбит — отказ PreToolUse либо HEAD целевого репозитория не сдвинулся.
# Рамка — как у probe_D528.sh: копия (git worktree) репозитория из CLAUDSOUL_REPO на HEAD; в её индексе — правка
# строки 2 шапки хука без пересборки таблиц, то есть настоящее расхождение. Каталог ловушек — временный, через
# GIT_CONFIG_GLOBAL (core.hooksPath): ловушки и настройки настоящего репозитория не трогаются.
# Повод — 21 октября 2026: фикстурный коммит во временном каталоге получил отказ «Автотаблицы разошлись» по
# незакоммиченной правке шапки hooks/merge-root-gate.sh в ClaudSoul — папке сессии, куда коммит не шёл.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$REPO/hooks/docs-family-check.sh" ] || { echo "проба не исполнима: нет docs-family-check.sh в $REPO"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "проба не исполнима: нет jq"; exit 2; }
W=$(mktemp -d "${HOME}/.probeD1022.XXXXXX") || exit 2
trap 'git -C "$REPO" worktree remove --force "$W/wt" >/dev/null 2>&1; rm -rf "$W"' EXIT
git -C "$REPO" worktree add -q --detach "$W/wt" HEAD >/dev/null 2>&1 || { echo "проба не исполнима: worktree"; exit 2; }
WT="$W/wt" O="$W/other"
mkdir -p "$W/hooks"
printf '[core]\n\thooksPath = %s\n[user]\n\tname = t\n\temail = t@t\n' "$W/hooks" > "$W/gitconfig"
export GIT_CONFIG_GLOBAL="$W/gitconfig" STATE_DIR="$W/st" CLAUDSOUL_ROOT="$REPO"
git init -q "$O" && printf 'x\n' > "$O/f" && git -C "$O" add f && git -C "$O" commit -qm init || exit 2
printf 'y\n' > "$O/f" && git -C "$O" add f || exit 2
[ -f "$REPO/hooks/commit-trap.sh" ] && { bash "$REPO/hooks/commit-trap.sh" --install "$WT" >/dev/null 2>&1 \
    || { echo "проба не исполнима: ловушка не встала"; exit 2; }; }

lands() {   # <команда> <целевой репозиторий> → 0, если коммит вошёл; вывод стража берётся целиком, не через трубу
    local out h0
    out=$(jq -cn --arg c "$1" --arg d "$WT" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:"probeD1022"}' \
        | (cd "$WT" && bash "$REPO/hooks/docs-family-check.sh" 2>/dev/null))
    grep -q '"permissionDecision":"deny"' <<< "$out" && return 1
    h0=$(git -C "$2" rev-parse HEAD 2>/dev/null)
    ( cd "$WT" && bash -c "$1" ) >/dev/null 2>&1
    [ "$(git -C "$2" rev-parse HEAD 2>/dev/null)" != "$h0" ]
}

H=hooks/revert-signal.sh
sed '2s/$/ (проба D1022)/' "$WT/$H" > "$W/h" && cp "$W/h" "$WT/$H" && git -C "$WT" add "$H" >/dev/null 2>&1 || exit 2
if lands "git commit -q -m 'docs: проба'" "$WT"; then
    echo "контроль мёртв: коммит в папке сессии с расхождением таблиц вошёл — судить нечем"; exit 2
fi
if ! lands "git -C '$O' commit -q -m x" "$O"; then
    echo "дефект: коммит в другой репозиторий отбит по расхождению таблиц папки сессии"; exit 1
fi
echo "страж судит репозиторий коммита: коммит в другой репозиторий вошёл"
exit 0
