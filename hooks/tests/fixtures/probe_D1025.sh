#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# probe_D1025.sh — команда git, которая не коммит, не получает отказа «обход ловушки» за слова в своих аргументах (D1025).
#
# Коды: 0 — в судимом репозитории с ловушкой `git grep -E 'commit…--no-verify'` проходит PreToolUse без отказа, а
#       контроль `bash -c 'git commit --no-verify -m x'` отбит; 1 — поиску дан отказ (дефект D1025: запасной разбор
#       ищет `git … commit` в любом месте строки, и слово «commit» в аргументе `git grep` читается подкомандой);
#       2 — судить нечем: нет стража, git, jq или python3, либо контроль не отбит (страж молчит на всём).
# Повод — 22 октября 2026, сессия D1023: поиск по дереву `git grep` с образцом про `--no-verify` получил отказ.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/merge-root-gate.sh"
[ -f "$HOOK" ] || exit 2
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || exit 2; done
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state" CLAUDSOUL_ROOT="$REPO" GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n' > "$GIT_CONFIG_GLOBAL"
R="$T/repo"; mkdir -p "$R/src" "$R/scripts/probes"
git -C "$R" init -q -b main || exit 2
printf '%s\n' '# ROOTS' '' '## R1 — тестовый корень' '**Устройство.** src делает BAD.' \
    '**Признак.** `scripts/probes/R1.sh`' '**Зависимости (чек-лист регрессии).** —' '**Держит.** —' > "$R/ROOTS.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/probes/R1.sh"
printf '%s\n' '# BACKLOG' '' '### X1 ☐ [P2] пункт с корнем' '**Корень.** R1' > "$R/BACKLOG.md"
printf 'module.exports = 1;\n' > "$R/src/a.js"
git -C "$R" add -A && git -C "$R" commit -qm init || exit 2
bash "$HOOK" --install "$R" </dev/null >/dev/null 2>&1
pre() { jq -cn --arg c "$1" --arg d "$R" '{session_id:"probe-d1025",tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
        | (cd "$R" && bash "$HOOK" 2>/dev/null); }
grep -q '"deny"' <<< "$(pre "bash -c 'git commit --no-verify -m x'")" || exit 2
grep -q '"deny"' <<< "$(pre "git grep -n -E 'commit[^|;&#]*(--no-verify|[[:space:]]-n[[:space:]])' -- src")" && exit 1
exit 0
