#!/usr/bin/env bash
# СУДИТ: hooks/docs-family-check.sh
# probe_D528.sh — сверка автотаблиц судит СНИМОК КОММИТА, а не рабочую копию (D528).
#
# `check_generated_tables` берёт документ из индекса (`git show :<doc>`), а генератор таблиц гоняет
# по рабочей копии (`bash "$GEN" "$CWD"`). Незакоммиченный хук в рабочей копии, которого в коммите
# нет, попадает в «ожидаемую» таблицу, и согласованный коммит части дерева получает отказ.
# Найдено 11 октября 2026 (D525): коммит стража git-stash отбит из-за незакоммиченного стража D526.
#
# Судится страж ИЗ CLAUDSOUL_REPO (копия на HEAD несёт старую редакцию — рамка не позеленела бы).
# Рамка: копия (git worktree) репозитория из CLAUDSOUL_REPO на HEAD; в индексе — правка шапки
# существующего хука с пересобранной таблицей (коммит согласован); в рабочей копии — лишний хук.
# Контроль: тот же коммит без лишнего хука — страж молчит; иначе код 2.
# Код: 0 — страж судит снимок коммита; 1 — рабочую копию; 2 — проба не исполнима либо контроль мёртв.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$REPO/hooks/docs-family-check.sh" ] || { echo "проба не исполнима: нет docs-family-check.sh в $REPO"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "проба не исполнима: нет jq"; exit 2; }
W=$(mktemp -d "${HOME}/.probeD528.XXXXXX") || exit 2
trap 'git -C "$REPO" worktree remove --force "$W/wt" >/dev/null 2>&1; rm -rf "$W"' EXIT
git -C "$REPO" worktree add -q --detach "$W/wt" HEAD >/dev/null 2>&1 || { echo "проба не исполнима: worktree"; exit 2; }
WT="$W/wt"

# Вердикт — ВХОДОМ ЛОВУШКИ git (`--commit-msg`, D1022), а не PreToolUse (D1222, 8 ноября 2026): рабочая копия пробы делит
# каталог ловушек с репозиторием владельца, где ловушка коммита стоит, и на PreToolUse страж уступает суд ей — молчит
# всегда, при любой редакции. Проба была пуста не только для выпотрошенного стража; ловушка судит индекс коммита
# (корень дерева — `git rev-parse --show-toplevel` из папки вызова), отказ — код 1.
verdict() {   # → deny|silent
    (cd "$WT" && STATE_DIR="$W/st" CLAUDSOUL_ROOT="$REPO" bash "$REPO/hooks/docs-family-check.sh" --commit-msg /dev/null \
        >/dev/null 2>&1) && echo silent || echo deny
}

# Согласованная правка в индексе: строка 2 шапки хука и пересобранные таблицы.
H=hooks/revert-signal.sh
sed '2s/$/ (проба D528)/' "$WT/$H" > "$W/h" && cp "$W/h" "$WT/$H" || exit 2
# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (D1222): та же правка шапки БЕЗ пересборки таблиц — несогласованный коммит, страж обязан его
# отбить. Без контроля проба судила только молчание, и пустой вход (см. verdict) её не выдавал.
git -C "$WT" add "$H" >/dev/null 2>&1 || exit 2
[ "$(verdict)" = deny ] || { echo "контроль: правка шапки без пересборки таблиц не отбита — страж не судит"; exit 1; }
for d in $(git -C "$WT" grep -l -e 'HOOKS-TABLE:START' -- '*.md' 2>/dev/null); do
    (cd "$WT" && README_FILE="$d" bash scripts/regen-readme-skills.sh "$WT" >/dev/null 2>&1)   # корень явно: без него генератор берёт CLAUDSOUL_REPO
done
git -C "$WT" add -A >/dev/null 2>&1 || exit 2

[ "$(verdict)" = silent ] || { echo "контроль мёртв: согласованный коммит без лишнего хука отбит"; exit 2; }

# Лишний незакоммиченный хук в рабочей копии — в коммит не входит.
printf '#!/usr/bin/env bash\n# zz-probe-d528.sh — лишний хук рабочей копии (проба D528).\n# en: extra hook.\n' > "$WT/hooks/zz-probe-d528.sh"
if [ "$(verdict)" = deny ]; then echo "страж судит рабочую копию: незакоммиченный хук отбил согласованный коммит"; exit 1; fi
echo "страж судит снимок коммита: лишний хук рабочей копии не мешает"
exit 0
