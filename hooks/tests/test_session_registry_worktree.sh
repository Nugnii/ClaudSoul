#!/usr/bin/env bash
# test_session_registry_worktree.sh — сессия во вложенном worktree принадлежит worktree,
# а не родительскому репозиторию.
#
# Повод (D287, третий остаток пункта). `_sr_detect_project` проверял `-d "$dir/.git"`,
# тогда как единый walk-up `hooks/paths-lib.sh` давно перешёл на `-e`. В worktree и
# подмодуле `.git` — ФАЙЛ («gitdir: …»), поэтому проверка на каталог перешагивала корень
# worktree и отдавала родителя: хуки писали SESSION.md и проектную память соседнего
# проекта, молча. Комментарий в paths-lib называет это прямо и добавляет, почему это не
# теория: «Worktree здесь штатный режим — инструмент Agent умеет isolation:"worktree"».
#
# Две копии одного правила разошлись молча — тот же класс, что у замка (D308) и у признака
# пункта долга (D305).
set -uo pipefail
LIB="$(cd "$(dirname "$0")/.." && pwd)/session-registry-lib.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Рамка. Worktree обязан лежать ВНУТРИ настоящего репозитория, иначе нога зелена по
# неверной причине: при ненайденном проекте walk-up возвращает исходный каталог (`$start`),
# и «worktree распознан» неотличимо от «не нашли ничего». Первая редакция этой фикстуры
# держала родителя в стороне от цепочки подъёма и проходила на НЕПОЧИНЕННОЙ библиотеке.
mkdir -p "$TMP/parent/.git" "$TMP/parent/wt"
printf 'gitdir: %s/parent/.git/worktrees/wt\n' "$TMP" > "$TMP/parent/wt/.git"

got=$(. "$LIB"; _sr_detect_project "$TMP/parent/wt")
if [ "$got" = "$TMP/parent/wt" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T1]: worktree приписан «${got}», ожидался «${TMP}/parent/wt»"
fi

# Положительный контроль: обычный клон (`.git` — каталог) узнаётся по-прежнему.
mkdir -p "$TMP/plain/.git"
got2=$(. "$LIB"; _sr_detect_project "$TMP/plain")
if [ "$got2" = "$TMP/plain" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T2]: обычный клон приписан «${got2}»"
fi

# Мёртвого кода в горячей библиотеке нет: у функции обязан быть хоть один вызывающий.
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
# Имя собирается из частей НАМЕРЕННО: наблюдатель не должен попадать в собственный
# универсум. Литерал в тексте теста делал бы сам тест носителем — ровно тот класс, из-за
# которого «Проверка» этого пункта считала мёртвой функцию, уже удалённую (и тот же класс,
# что открытый D310: шаблон внутри строки-сообщения принят за перечень).
DEAD='_sr_project'"_name"
n=$(grep -rl "$DEAD" "$HOOKS" --include='*.sh' 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 0 ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T3]: ${DEAD} жива в $n файле(ах) — вызывающих ноль"
fi

echo "test_session_registry_worktree: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
