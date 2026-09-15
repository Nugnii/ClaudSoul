#!/usr/bin/env bash
# test_adv4_worktree_root.sh — find_project_root перешагивает корень git-worktree
# (и подмодуля) и отдаёт РОДИТЕЛЬСКИЙ репозиторий.
#
# hooks/paths-lib.sh:72 — признак корня:
#     if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
# В worktree и в подмодуле `.git` — не каталог, а ФАЙЛ со строкой «gdir: …»
# (проверено на реальном `git worktree add`: -rw-r--r--, 100 байт). Проверка `-d`
# ложна, `CLAUDE.md` в свежем worktree обычно нет, и подъём продолжается — до первого
# предка, у которого .git настоящий каталог. Это соседний, ЧУЖОЙ проект.
#
# Последствие не косметическое: возвращённый корень определяет, в чей SESSION.md,
# в чей BACKLOG.md и в чью проектную память пишут хуки. Работа в worktree
# приписывается основному репозиторию, причём молча — ошибки нет ни одной.
#
# Достижимость: worktree — штатный режим этой среды. Инструмент Agent принимает
# isolation:"worktree" и создаёт агенту отдельный worktree; в hooks/tests уже лежат
# test_adv2_changelog_worktree.sh и test_adv2_docs_family_index_vs_worktree.sh, то есть
# среда признана рабочей. Вызывающие: hooks/knowledge-activator.sh (find_project_root
# на cwd из payload), hooks/session-start.sh, hooks/pre-compact-handoff.sh.
#
# Раскладка создаётся руками, а не `git worktree add`: тест не должен зависеть от
# наличия git, а форма `.git`-файла и так воспроизведена дословно. Ничего не удаляется.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/paths-lib.sh"
TMP="$(mktemp -d)"

# Родительский (чужой для работы) репозиторий и его worktree внутри.
mkdir -p "$TMP/parent/.git"
printf '# parent\n' > "$TMP/parent/CLAUDE.md"
mkdir -p "$TMP/parent/wt/sub/deeper"
printf 'gitdir: %s/parent/.git/worktrees/wt\n' "$TMP" > "$TMP/parent/wt/.git"

got="$(env -u CLAUDSOUL_ROOT bash -c \
    'source "$1"; find_project_root "$2"' _ "$LIB" "$TMP/parent/wt/sub/deeper")"

if [ "$got" = "$TMP/parent/wt" ]; then
    echo "PASS: корень worktree опознан ($got)"
    echo "adv4 worktree root: 1/1 passed"
    exit 0
fi

echo "FAIL [paths-lib.sh:72]: корень worktree перешагнут."
echo "     Вход:      $TMP/parent/wt/sub/deeper"
echo "     Ожидалось: $TMP/parent/wt"
echo "     Получено:  $got"
echo "     Причина: в worktree и в подмодуле .git — файл, а проверка требует каталог"
echo "     ([ -d \"\$dir/.git\" ]). Подъём уходит в родительский репозиторий, и хуки"
echo "     пишут SESSION.md, BACKLOG и память чужого проекта — молча, без ошибки."
echo "adv4 worktree root: 0/1 passed"
exit 1
