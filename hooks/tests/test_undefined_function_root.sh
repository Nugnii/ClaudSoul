#!/usr/bin/env bash
# СУДИТ: hooks/undefined-function-check.sh
# test_undefined_function_root.sh — установленный страж необъявленных функций судит проект ClaudSoul, а не каталог, где лежит сам, и не обходит его на каждой команде (D497).
#
# Результат: копия стража в ~/.claude/hooks без CLAUDSOUL_REPO берёт корень по указателю
#            ~/.claude/claudsoul-repo и находит необъявленную функцию в скрипте, записанном
#            командой в проекте; файлы самого ~/.claude не обходит; на PreToolUse до обхода не
#            доходит и метку не двигает; метка своя у сессии.
# Проверка результата: bash hooks/tests/test_undefined_function_root.sh даёт 0
#
# Повод (1 октября 2026, D497). Корень «каталог выше хука» у установленной копии — ~/.claude:
# 110 тыс. файлов, не git-репозиторий. Обход шёл дважды на каждую команду Bash (PreToolUse и
# PostToolUse), по 0,35 с при обычной нагрузке, а скрипты проекта, записанные командой, не
# попадали в цели вовсе.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Установка в песочнице: HOME/.claude/hooks с копией стража и его библиотек, в HOME/.claude —
# свой «мусорный» скрипт с необъявленной функцией (его судить нельзя), указатель на проект.
H="$T/home"; IH="$H/.claude/hooks"; ST="$H/.claude/hooks/state"; mkdir -p "$IH/lib" "$ST"
for f in undefined-function-check.sh command-scope-lib.sh paths-lib.sh portable-lib.sh; do
    cp "$REPO/hooks/$f" "$IH/" 2>/dev/null || true
done
cp "$REPO/hooks/lib/"*.sh "$IH/lib/" 2>/dev/null || true
cp "$REPO/hooks/lib/"*.py "$IH/lib/" 2>/dev/null || true
printf '#!/usr/bin/env bash\n_junk_absent_in_dot_claude\n' > "$H/.claude/junk.sh"
# Проект: git-репозиторий с библиотекой вселенной определений и одним определением.
P="$T/proj"; mkdir -p "$P/hooks/lib"
cp "$REPO/hooks/lib/universe-lib.sh" "$P/hooks/lib/"
printf '#!/usr/bin/env bash\nproj_defined_helper() { :; }\n' > "$P/hooks/base.sh"
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 \
    || { echo "FAIL [setup]: проект не собрался"; exit 1; }
printf '%s' "$P" > "$H/.claude/claudsoul-repo"

hook() {  # hook <событие> <сессия> → вывод установленной копии; корень берётся по указателю
    printf '{"hook_event_name":"%s","session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"true"}}' "$1" "$2" "$P" \
      | env -u CLAUDSOUL_REPO -u CLAUDSOUL_ROOT -u CLAUDSOUL_STATE_DIR HOME="$H" STATE_DIR="$ST" \
            bash "$IH/undefined-function-check.sh" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_root.sh:$LINENO" >&2; exit 1; }
}

hook PostToolUse s1 >/dev/null              # первое событие сессии ставит метку
sleep 1
printf '#!/usr/bin/env bash\n_proj_absent_helper "$1"\n' > "$P/hooks/new.sh"   # команда записала скрипт
touch "$H/.claude/junk.sh"

# R2 — PreToolUse до обхода не доходит и метку не двигает: иначе событие ДО команды съедало бы
# правку, сделанную командой (метка новее файла).
M0=$(ls -l "$ST/undefined-function-scan-s1.stamp" 2>/dev/null)
hook PreToolUse s1 >/dev/null
M1=$(ls -l "$ST/undefined-function-scan-s1.stamp" 2>/dev/null)
[ -n "$M0" ] && [ "$M0" = "$M1" ] && ok || bad R2 "PreToolUse тронул метку прохода (до: «${M0}», после: «${M1}») — обход шёл и до команды"

# R3 — метка своя у сессии: событие ЧУЖОЙ сессии не уносит правку этой.
hook PostToolUse s2 >/dev/null              # s2: первое событие — своя метка, без суда
hook PostToolUse s2 >/dev/null              # s2 второй раз: при общей метке он забрал бы находку s1

# R1 — корень по указателю: найдена необъявленная функция проекта, мусор ~/.claude не судим.
OUT=$(hook PostToolUse s1)
grep -q '_proj_absent_helper' <<< "$OUT" && ok \
    || bad R1 "установленная копия не нашла необъявленную функцию в скрипте проекта, записанном командой — корень взят не по указателю (вывод: «${OUT:0:160}»)"
grep -q '_junk_absent_in_dot_claude' <<< "$OUT" && bad R1b "судит файлы ~/.claude, а не проекта" || ok

echo "undefined function root: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
