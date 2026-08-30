#!/usr/bin/env bash
# test_command_scope_differential.sh — разбор команды сверяется с ЭТАЛОНОМ, а не с ожиданием.
#
# Зачем этот тест существует отдельно от остальных. Три раунда адверсариальной критики
# дали 31 находку, и каждый раунд находил в первую очередь дефект, внесённый починкой
# предыдущего. Цепочка «почему» упирается не в невнимательность:
#
#   раунд находит новое        ← каждая починка вносила новый дефект
#   починка вносила дефект     ← была точечной, под конкретный вход
#   правка была точечной       ← находка приходит как конкретная строка
#   форма находки решала всё   ← не было модели предмета
#   модели не было             ← предмет построен как текстовая обработка,
#                                а является ПАРСЕРОМ shell-грамматики
#
# Пока проверка идёт по примерам, критик будет находить новое бесконечно: примеров
# бесконечно. Здесь проверка идёт иначе — эталоном служит сам bash.
#
# Как: каждая команда собирается из безобидных кусков и ВЫПОЛНЯЕТСЯ в песочнице, где
# `git` подменён скриптом-регистратором. Факт «git commit реально запустился» берётся из
# журнала регистратора, а не из ожидания автора теста. Расхождение факта с вердиктом
# `is_git_commit` — дефект, найденный без критика.
#
# Безопасность: команды порождаются из фиксированного набора безобидных кусков
# (echo/printf/cat/true), `git` и `rm` подменены, работа идёт в свежем mktemp -d,
# stdin закрыт. Ничего реального не запускается и не удаляется.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$HOOKS_DIR/command-scope-lib.sh"

PASS=0; FAIL=0; MISMATCH=""
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/sandbox"; BIN="$TMP/bin"
mkdir -p "$SANDBOX" "$BIN"

# Регистратор вместо git: пишет подкоманду в журнал и молчит.
cat > "$BIN/git" <<'GITSTUB'
#!/usr/bin/env bash
# Пропускаем глобальные опции, чтобы записать именно подкоманду.
while [ $# -gt 0 ]; do
    case "$1" in
        -C|-c) shift 2 ;;
        --git-dir=*|--work-tree=*|--no-pager|-P) shift ;;
        *) break ;;
    esac
done
printf '%s\n' "${1:-}" >> "$GIT_CALLS"
exit 0
GITSTUB
chmod +x "$BIN/git"

run_real() {  # $1 = команда → печатает "yes", если git commit реально запустился
    : > "$TMP/git-calls"
    # Песочница чистится между вызовами: файл-маркер, оставшийся от прошлой команды,
    # менял поведение следующей — цикл не входил, и эталон отвечал про другую команду.
    find "$SANDBOX" -mindepth 1 -delete 2>/dev/null
    ( cd "$SANDBOX" && PATH="$BIN:$PATH" GIT_CALLS="$TMP/git-calls" \
        bash -c "$1" >/dev/null 2>&1 </dev/null )
    grep -qx 'commit' "$TMP/git-calls" 2>/dev/null && echo yes || echo no
}

check() {  # $1 = команда, $2 = метка
    local real verdict
    real=$(run_real "$1")
    verdict=$(is_git_commit "$1" && echo yes || echo no)
    if [ "$real" = "$verdict" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        MISMATCH="${MISMATCH}
  [$2] bash: $real, is_git_commit: $verdict
      вход: $(printf '%s' "$1" | tr '\n' '~')
      exec: $(printf '%s' "$(executable_part "$1")" | tr '\n' '~')"
    fi
}

# ── Обёртки. В каждой PLACEHOLDER заменяется на вызов git commit ──────────────
# Часть обёрток исполняет вставку, часть превращает её в текст. Классификацию НЕ
# задаём: её выносит bash. Тест сравнивает вердикт с фактом, а не с мнением автора.
WRAPPERS=(
'@'
'@ -m x'
'cd . && @'
'cd . ; @'
'( @ )'
'{ @ ; }'
'true && @ || true'
'if true; then @; fi'
'for i in 1; do @; done'
# `while false` не годится: тело не выполняется по построению, и эталон сказал бы «нет»
# там, где вызов в команде есть. Цикл должен отработать ровно один раз.
'while [ ! -f done.marker ]; do @; touch done.marker; done'
'case x in x) @ ;; esac'
'f() { @ ; }; f'
'echo "текст @ конец"'
"echo 'текст @ конец'"
'echo "экранировано \"@\" внутри"'
'printf "%s" "@" > out.txt'
'echo x # @'
'echo x ;# @'
'echo x && true  # хвост @'
'cat > out.txt <<EOF
@
EOF'
'cat > out.txt <<'"'"'EOF'"'"'
@
EOF'
'cat > out.txt <<-EOF
	@
	EOF'
'cat > out.txt <<\EOF
@
EOF'
'grep -q x <<< "@" || true'
'M="$(@)"'
'M="`@`"'
'echo "итог: $(@)"'
'echo "итог: `@`"'
'echo "скобка: $(grep -c ")" /dev/null || true)" ; @'
'V=$((1 << 3)); @'
"echo \$'don\\'t' ; @"
'cat > out.txt <<EOF && @
данные
EOF'
'cat > a.txt <<EOF && cat > b.txt <<EOF2 && @
первое
EOF
второе
EOF2'
'echo "путь C:\\" && @'
"echo 'путь C:\\' && @"
'@ \
  -m "перенос"'
'/bin/echo x && @'
'echo "$(echo "вложенное $(echo глубже)")" ; @'
'echo "цитата: <<EOF" && @'
'echo "hi" | cat ; @'
)

# Вставки: настоящий вызов и его текстовый двойник.
INSERTS=(
'git commit'
'git commit -m "правка"'
'git -C . commit -m "правка"'
'git --no-pager commit'
)

for w in "${WRAPPERS[@]}"; do
    for ins in "${INSERTS[@]}"; do
        cmd="${w//@/$ins}"
        check "$cmd" "$(printf '%s' "$w" | tr '\n' '~' | cut -c1-46)"
    done
done

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "РАСХОЖДЕНИЯ разбора с эталоном (bash):$MISMATCH"
    echo ""
fi
echo "differential scope: $PASS/$((PASS + FAIL)) совпали с эталоном"
[ "$FAIL" -eq 0 ]
