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
# Каталог скиллов взят `cd` той же команды, имя — относительное (D1088): разбор приклеивал имя к каталогу запроса,
# и отказ молчал, хотя прямую форму отбивал.
assert_fires "A7 cd в скиллы, имя относительное"    'cd ~/.claude/skills && mkdir "Имя-скилла"'
assert_fires "A8 cd через \$HOME, имя без кавычек"  'cd "$HOME/.claude/skills" && mkdir Имя-скилла'
assert_silent "A9 cd в скиллы, имя латиницей"       'cd ~/.claude/skills && mkdir good-name'
# Переменная в ПРЕФИКСЕ, литеральное имя — отказ законен: литеральность судится по сегменту-имени (D1037, финальный
# скептик: первая редакция разбора выкидывала такую цель целиком, и отказ немел на путях через $HOME/$PWD/$(…)).
assert_fires "A7 префикс через переменную"  'mkdir -p "$HOME/.claude/skills/Мой-скилл"'
assert_fires "A8 префикс через подстановку" 'mkdir -p "$(git rev-parse --show-toplevel)/skills/Кир"'
assert_fires "A9 префикс в фигурных"        'cp -r tmpl "${ROOT}/skills/Кир"'

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
      git init -q . 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_skill_name_ascii_guard.sh:$LINENO" >&2; exit 1; }
      git config user.email t@t; git config user.name t
      mkdir -p "skills/противник" skills/adversary
      printf 'x\n' > "skills/противник/SKILL.md"
      printf 'x\n' > skills/adversary/SKILL.md
      git add -A 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_skill_name_ascii_guard.sh:$LINENO" >&2; exit 1; }
    )
    GOT=$(run 'git commit -m "тест"' "$TMP")
    [ "$GOT" = "deny" ] && ok "E1 не-ASCII в staged отбивается на коммите" \
        || bad "E1" "ожидался deny, получено '${GOT:-пусто}'"

    # E3 (D420): «git commit» СТОИТ В ПРОЗЕ, вызов ничего не коммитит — разбор staged
    # открываться не должен, хотя плохое имя в индексе есть. До 16 сентября 2026 второй вход
    # решал по вхождению подстроки в текст и отказывал здесь.
    GOT=$(run 'echo "дальше нужен git commit -m x, но не сейчас"' "$TMP")
    [ -z "$GOT" ] && ok "E3 упоминание коммита в прозе не открывает разбор staged" \
        || bad "E3" "ожидалось молчание, получено '$GOT'"

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

# --- Ложные отказы на НЕЛИТЕРАЛЬНОМ имени (6 сентября 2026) ---
# Замер того дня: два отказа подряд на рабочем коде — обход `"$REPO"/skills/*/` и перенос
# `"$SKILLS_SRC/$_f"`. Мест с такой формой в дереве 27, включая сам `drift-check.sh` и его
# тест, то есть страж отвергал код, написанный до него и рабочий. Отказ уровня 4 с
# ложными срабатываниями блокирует работу, и шапка самого стража это запрещает.
_probe() {  # $1 — команда, $2 — что ожидаем: deny | allow
    _out=$(printf '%s' "$1" | jq -Rs '{tool_name:"Bash",tool_input:{command:.}}' \
           | bash "$HOOK" 2>/dev/null)
    case "$_out" in
        *deny*) _got=deny ;;
        *)      _got=allow ;;
    esac
    if [ "$_got" = "$2" ]; then ok "нелитерал/литерал: $2 на ${1:0:34}"
    else bad "признак имени" "ожидалось $2, получено $_got на: $1"; fi
}
_probe 'for d in "$REPO"/skills/*/; do cp "$d"SKILL.md /tmp/x; done' allow
_probe 'cp "$SKILLS_SRC/$_f" "$HOME/.claude/commands/$_f"' allow
_probe 'mkdir -p "skills/${name}/references"' allow
# Отрицательный контроль: ЛИТЕРАЛЬНОЕ имя вне латиницы отвергается по-прежнему.
# Имя собирается из ВОСЬМЕРИЧНЫХ байтов UTF-8: литерал кириллицы в ЭТОМ файле ловится тем
# же стражем, что файл и проверяет, а `\uXXXX` в bash 3.2 (macOS) не разворачивается —
# первая редакция ноги была зелена на строке с обратными слэшами, то есть на форме,
# которой мир не производит. Замер развёртки: 6 байт на 3 символа.
_cyr=$(printf '\321\205\320\265\320\271')
_probe "mkdir -p skills/$_cyr" deny


echo "--- F. Область: ЦЕЛЬ операции, а не слово в тексте (D420) ---"
# Замер по корпусу 16 сентября 2026: 488 команд с путём каталога скиллов, прежняя редакция
# давала 25 отказов, нынешняя 7 — снято 18 ложных, включая отбитый перенос каталога в
# латиницу, то есть страж отбивал ровно ту починку, которой сам требует.
# Пути и кириллица собираются из частей и восьмеричных байтов: литерал в ЭТОМ файле ловится
# тем же стражем, что файл и проверяет (идиома взята у ноги отрицательного контроля выше).
_sk=$(printf '%s%s' 'sk' 'ills')
_cyr3=$(printf '\320\277\321\200\320\276\321\202\320\270\320\262\320\275\320\270\320\272')
_bt=$(printf '\140')

# F1: слово создания и путь стоят в ПРОЗЕ тела ЧУЖОГО heredoc — оболочка не создаёт ничего.
assert_silent "F1 проза в теле python-heredoc" \
  "$(printf 'python3 - <<EOF\nmkdir -p x — пример\nкаталоги %s%s/%s, правила\nEOF\n' "$_bt" "$_sk" "$_bt")"

# F2: heredoc, открытый САМОЙ ОБОЛОЧКОЙ, она и исполняет — отказ обязан остаться.
# Это названный предел сужения: вырезать все тела heredoc нельзя, `bash <<EOF` пишет по-настоящему.
assert_fires "F2 тело heredoc самой оболочки" \
  "$(printf 'bash <<EOF\nmkdir -p %s/%s\nEOF\n' "$_sk" "$_cyr3")"

# F3: имя, собранное из подстановки в обратных кавычках, литеральным не является.
assert_silent "F3 обратная кавычка не литеральное имя" \
  "$(printf 'mkdir -p %s/%swhoami%s' "$_sk" "$_bt" "$_bt")"

# F4: РАЗБОРА НЕТ — страж молчит, а не отказывает наугад. Без сужения признак даёт 18 ложных
# отказов из 25 по корпусу, а отказ уровня 4 с ложными обязан снова стать подсказкой.
_c=$(printf 'mkdir -p %s/%s' "$_sk" "$_cyr3")
GOT=$(jq -nc --arg c "$_c" --arg w "$REPO" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' \
      | WRITE_TARGETS_PY=/net/takogo/faila.py HOME=/net/takogo bash "$HOOK" 2>/dev/null \
      | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
[ -z "$GOT" ] && ok "F4 без разбора страж молчит, а не отказывает" \
    || bad "F4" "ожидалось молчание, получено '$GOT'"

echo
echo "PASS: $PASS  FAIL: $FAIL"
exit $(( FAIL != 0 ))