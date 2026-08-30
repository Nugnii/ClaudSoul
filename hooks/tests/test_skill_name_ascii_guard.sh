#!/usr/bin/env bash
# test_skill_name_ascii_guard.sh — отказ приходит на создание не-ASCII имени скилла и
# не приходит ни на что другое.
#
# Главная проверка здесь не «отказ срабатывает» — такую пишут всегда, — а обратная:
# признак прогнан по ОТРИЦАТЕЛЬНОМУ классу (D107). Уровень 4 оправдан только если у
# признака нет ложных срабатываний: отказ, часть которого ложна, обязан снова стать
# подсказкой (case-2026-08-28-enforcement-is-a-property-of-consequence). Поэтому блок C
# гоняет признак по всей истории коммитов репозитория и сверяет число с ожидаемым.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/skill-name-ascii-guard.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
[ -x "$HOOK" ] || { echo "FAIL: хук не исполняем: $HOOK"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# run <cmd> [cwd] → печатает permissionDecision или пусто
run() {
    local cmd="$1" cwd="${2:-$REPO}"
    jq -cn --arg c "$cmd" --arg w "$cwd" \
        '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' \
      | bash "$HOOK" 2>/dev/null \
      | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null
}

assert_fires() {
    local label="$1" cmd="$2"
    local got; got=$(run "$cmd")
    [ "$got" = "deny" ] && ok "$label" || bad "$label" "ожидался deny, получено '${got:-пусто}'"
}
assert_silent() {
    local label="$1" cmd="$2"
    local got; got=$(run "$cmd")
    [ -z "$got" ] && ok "$label" || bad "$label" "ожидалось молчание, получено '$got'"
}

echo "--- A. Создание не-ASCII имени отбивается ---"
assert_fires "A1 mkdir кириллица"      'mkdir -p skills/противник'
assert_fires "A2 mkdir вложенный путь" 'mkdir -p /Users/x/proj/skills/грилинг'
assert_fires "A3 git mv в кириллицу"   'git mv skills/adversary skills/противник'
assert_fires "A4 имя в кавычках"       'git mv a "skills/новый скилл"'
assert_fires "A5 редирект в файл"      'echo x > skills/хейтер/SKILL.md'
assert_fires "A6 заглавные латиницей"  'mkdir -p skills/MySkill'

echo "--- B. Ложных срабатываний нет ---"
assert_silent "B1 латинское имя"        'mkdir -p skills/new-skill'
assert_silent "B2 имя с точкой и цифрой" 'mkdir -p skills/skill.v2'
assert_silent "B3 чтение кириллицы"     'cat skills/противник/SKILL.md'
assert_silent "B4 поиск по дереву"      'grep -rn "x" skills/'
assert_silent "B5 ls каталога"          'ls -la skills/грилинг'
assert_silent "B6 команда без skills/"  'mkdir -p /tmp/противник'
assert_silent "B7 echo пути"            'echo skills/противник'

# B8: тот же путь, но инструмент не Bash — хук обязан молчать.
GOT=$(jq -cn '{tool_name:"Write", tool_input:{file_path:"skills/противник/SKILL.md"}, cwd:"'"$REPO"'"}' \
      | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
[ -z "$GOT" ] && ok "B8 не-Bash инструмент игнорируется" || bad "B8" "ожидалось молчание, получено '$GOT'"

echo "--- C. Отрицательный класс: признак по всей истории коммитов (D107) ---"
# Признак: путь skills/<имя>/ где имя вне [a-z0-9._-]. Прогон по КАЖДОМУ коммиту.
HIST=$(cd "$REPO" && git -c core.quotepath=false log --all --pretty=format:'' --name-only 2>/dev/null \
       | sed -e 's/^"//' -e 's/"$//' \
       | grep '^skills/' \
       | sed -n 's#^skills/\([^/]*\)/.*#\1#p' \
       | sort -u)
OFFENDING=$(printf '%s\n' "$HIST" | grep -v '^$' | LC_ALL=C grep -vE '^[a-z0-9][a-z0-9._-]*$' || true)
OFF_COUNT=$(printf '%s\n' "$OFFENDING" | grep -c . || true)
TOTAL=$(printf '%s\n' "$HIST" | grep -c . || true)
echo "    имён скиллов за всю историю: $TOTAL, из них признак горит на: $OFF_COUNT"
[ -n "$OFFENDING" ] && printf '      • %s\n' $OFFENDING

# Ожидание названо числом, а не «мало»: за всю историю репозитория кириллицей звались
# ровно два скилла — противник и грилинг, оба переименованы 28.08.2026. Больше признак
# гореть не должен ни на чём. Вырастет число — либо вернулось нарушение, либо признак
# начал ловить лишнее; и то и другое требует разбора, а не правки ожидания.
if [ "$OFF_COUNT" -le 2 ]; then
    ok "C1 признак горит только на известных двух ($OFF_COUNT ≤ 2)"
else
    bad "C1" "признак загорелся на $OFF_COUNT именах — ложные срабатывания либо новое нарушение"
fi

echo "--- E. Второй вход: staged при коммите (обход через Write) ---"
# Каталог заводят не Bash-ом — хук первого входа не видит. Ловит второй: путь всё равно
# обязан попасть в индекс, чтобы стать коммитом.
TMP=$(mktemp -d 2>/dev/null) || TMP=""
if [ -n "$TMP" ]; then
    (
      cd "$TMP" || exit 1
      git init -q . 2>/dev/null
      git config user.email t@t; git config user.name t
      mkdir -p "skills/противник" skills/adversary
      printf 'x\n' > "skills/противник/SKILL.md"
      printf 'x\n' > skills/adversary/SKILL.md
      git add -A 2>/dev/null
    )
    GOT=$(run 'git commit -m "тест"' "$TMP")
    [ "$GOT" = "deny" ] && ok "E1 не-ASCII в staged отбивается на коммите" \
        || bad "E1" "ожидался deny, получено '${GOT:-пусто}'"

    ( cd "$TMP" && git rm -r -q --cached "skills/противник" 2>/dev/null; rm -rf "skills/противник" )
    GOT=$(run 'git commit -m "тест"' "$TMP")
    [ -z "$GOT" ] && ok "E2 чистый staged проходит молча" \
        || bad "E2" "ожидалось молчание, получено '$GOT'"
    rm -rf "$TMP"
else
    echo "SKIP: mktemp недоступен"
fi

echo "--- D. Живое дерево чисто ---"
LIVE=$(cd "$REPO" && ls -1 skills/ 2>/dev/null | LC_ALL=C grep -vE '^[a-z0-9][a-z0-9._-]*$' || true)
if [ -z "$LIVE" ]; then
    ok "D1 в skills/ нет имён вне латиницы"
else
    bad "D1" "остались: $(printf '%s' "$LIVE" | tr '\n' ' ')"
fi

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
