#!/usr/bin/env bash
# СУДИТ: hooks/rules-write-bypass.sh
# test_rules_write_bypass.sh — запись в установленные правила мимо библиотеки не проходит (D101).
#
# Повод: 28 августа 2026 пара «правила» в drift-check была BROKEN — в ~/.claude/CLAUDE.md не
# оказалось маркеров управляемого блока, и сравнивать было нечем. Шесть пар из семи сверялись,
# седьмая нет: мастер-копия могла уехать сколь угодно далеко молча.
#
# Пункт D101 отверг этого стража возражением «правка идёт инструментом Edit, а хук
# PreToolUse[Bash] её не видит». Замер того же дня по пяти сессиям: касаний
# ~/.claude/CLAUDE.md через Bash — 23, через Edit/Write — 0. Возражение снято данными.
#
# Отличие этой пары от прочих шести: у остальных установка — побайтовая копия, и обход
# ловится сравнением. Здесь установка ПРЕОБРАЗУЕТ содержимое (оборачивает в маркеры),
# поэтому обход даёт не расхождение, а невозможность сравнить.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/rules-write-bypass.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

# Ложные отказы, пойманные 1 сентября 2026 (три за одну сессию, все на одной форме):
# путь к правилам стоял ВНУТРИ данных — исходника питона, аргумента grep, тела heredoc, —
# а знак записи в другом месте той же команды (`awk 'length($0) >= 40'`). Отказ требует,
# чтобы путь был ЦЕЛЬЮ операции, а не встретился в тексте.
FALSE_DENY_CASES=(
  'python3 -c "import pathlib; print(pathlib.Path.home()/\".claude/CLAUDE.md\")" && awk "length(\$0) >= 40" f'
  'grep -n "Step 2" ~/.claude/CLAUDE.md | head -5'
  'diff <(cat ~/.claude/CLAUDE.md) rules/CLAUDE.md > /tmp/d'
)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
dec() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null; }
assert_silent() { [ -z "$(dec "${1:-}")" ] && ok || bad "${2:-тишина}" "${3:-получен отказ}"; }
assert_contains() { grep -q "${2:-}" <<< "${1:-}" && ok || bad "${3:-текст}" "${4:-нет ожидаемого текста}"; }
run() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null; }

# 1. Запись мимо библиотеки — отказ.
for cmd in 'cp rules/CLAUDE.md ~/.claude/CLAUDE.md' \
           'cat x > ~/.claude/CLAUDE.md' \
           'printf hi >> "$HOME/.claude/CLAUDE.md"'; do
    [ "$(dec "$(run "$cmd")")" = "deny" ] && ok || bad "обход не пойман" "$cmd"
done

# 2. Через библиотеку — проходит: это и есть правильный путь.
assert_silent "$(run '. lib/claude-md-merge.sh && sync_claude_md "$HOME/.claude/CLAUDE.md" rules/CLAUDE.md')" \
    "правильный путь" "путь через библиотеку заблокирован"

# 3. Чтение — проходит всегда.
for cmd in 'cat ~/.claude/CLAUDE.md' 'grep -n Global ~/.claude/CLAUDE.md' 'wc -l < ~/.claude/CLAUDE.md'; do
    assert_silent "$(run "$cmd")" "чтение проходит" "чтение заблокировано: $cmd"
done

# 4. Чужой CLAUDE.md (проектный) — не наше дело.
assert_silent "$(run 'echo x > /Users/user/My Project/ClaudSoul/CLAUDE.md')" \
    "чужой файл" "страж лезет в проектный CLAUDE.md"

# 5. Установщик — законный путь, проходит.
assert_silent "$(run 'bash install.sh')" "установщик" "install.sh заблокирован"

echo ""
# Ложный отказ — такой же дефект стража, как пропуск: он останавливает работу на чтении.
for cmd in "${FALSE_DENY_CASES[@]}"; do
    assert_silent "$(run "$cmd")" "ложный отказ" "путь в данных принят за цель: $cmd"
done
# Контроль: запись через переменную рядом не стоит — отказа нет, но и не молчим.
# Без кавычек: в кавычках цель стирается ещё в BARE, и вызов отсеивается раньше — это
# прежнее поведение, не предмет этой проверки.
OUT=$(run 'F=$HOME/.claude/CLAUDE.md; cat x > $F')
[ -z "$(dec "$OUT")" ] && ok || bad "разнесённая запись" "отказ там, где назван предел"
assert_contains "$OUT" "не стоит целью операции" "разнесённая запись" "напоминания нет: $OUT"

# --- D425: ОСВОБОЖДЕНИЕ судит исполняемую часть, завершителем цели служит и комментарий ---
# Повод, 17 сентября 2026. Страж уровня 4 обходился ДОБАВЛЕНИЕМ СЛОВА: `install.sh` в кавычках
# эха, в комментарии оболочки или в теле чужого heredoc снимало отказ, и настоящая перезапись
# установленных правил проходила. Цена ошибки здесь ОБРАТНАЯ обычной — промах даёт ПРОПУСК.
# Корень R3, тот же, что у закрытых D420 и D424; концов в этом файле оказалось ДВА, и второй
# нашёл прогон: `ADJ_RE` не знал `#` завершителем цели.
#
# Многострочная нагрузка подаётся python-ом, а НЕ `jq -Rc`: тот читает вход построчно и на
# многострочной команде выдаёт по JSON на строку — страж получает только первую и молчит
# ВЕРНО. Первая редакция этих ног так и обманулась (дефект пробы, не стража).
runm() { python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" | bash "$HOOK" 2>/dev/null; }

# T-D425a: слово-пароль в КАВЫЧКАХ эха отказа не снимает.
[ -n "$(dec "$(runm 'cp rules/CLAUDE.md ~/.claude/CLAUDE.md && echo "мимо install.sh"')")" ] && ok \
    || bad "D425a" "слово в кавычках сняло отказ — перезапись правил прошла"

# T-D425b: слово-пароль в КОММЕНТАРИИ отказа не снимает (второй конец, ADJ_RE).
[ -n "$(dec "$(runm 'cp rules/CLAUDE.md ~/.claude/CLAUDE.md   # законный путь sync_claude_md')")" ] && ok \
    || bad "D425b" "слово в комментарии сняло отказ"

# T-D425c: слово-пароль в теле ЧУЖОГО heredoc отказа не снимает.
[ -n "$(dec "$(runm 'python3 - <<EOF
# см. install.sh
EOF
cp rules/CLAUDE.md ~/.claude/CLAUDE.md')")" ] && ok || bad "D425c" "слово в чужом heredoc сняло отказ"

# T-D425d: ОТЗЫВ. Настоящий законный путь по-прежнему проходит молча.
[ -z "$(dec "$(runm '. lib/claude-md-merge.sh && sync_claude_md "$HOME/.claude/CLAUDE.md" rules/CLAUDE.md')")" ] && ok \
    || bad "D425d" "сужение съело освобождение: законный путь получил отказ"

# T-D425e: ОТЗЫВ. Установщик тоже законный путь.
[ -z "$(dec "$(runm 'bash install.sh')")" ] && ok || bad "D425e" "установщик получил отказ"

# T-D425f: КОНТРПРИМЕР. Путь как ИСТОЧНИК — не цель, отказа быть не должно.
[ -z "$(dec "$(runm 'cp ~/.claude/CLAUDE.md /tmp/backup.md')")" ] && ok \
    || bad "D425f" "путь-источник принят за цель — отказ ложный"

# T-D425g/h: РАЗЛИЧАЮЩАЯ СПОСОБНОСТЬ — мутантами, каждый за СВОЙ конец.
# Половины отвечают за разное: область освобождения держит случай «слово в кавычках»,
# завершитель цели — случай «слово в комментарии». Требовать от обеих одного значит не
# проверить ни одну (урок ног T15f/T16g тех же дней).
_rwb_mutant() {   # _rwb_mutant <sed-выражение> <команда> → печатает 1, если мутант отказал
    local _t; _t=$(mktemp -d) || { echo "-1"; return; }
    mkdir -p "$_t/hooks"
    sed "$1" "$HOOK" > "$_t/hooks/rules-write-bypass.sh"
    cp "$REPO/hooks/command-scope-lib.sh" "$_t/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_rules_write_bypass.sh:$LINENO" >&2; exit 1; }
    python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$2" \
      | bash "$_t/hooks/rules-write-bypass.sh" 2>/dev/null | grep -c deny
    rm -rf "$_t"
}

# g — ОБЛАСТЬ освобождения: вернём суждение по сырому тексту, случай «в кавычках» обязан пройти мимо.
_M=$(_rwb_mutant 's|^_EXEC_CMD=$(executable_part "$CMD")$|_EXEC_CMD="$CMD"|' \
     'cp rules/CLAUDE.md ~/.claude/CLAUDE.md && echo "мимо install.sh"')
[ "$_M" = "0" ] && ok || bad "D425g" "с несуженной областью страж всё равно отказал (получено '$_M') — ОБЛАСТЬ ничем не доказана"

# h — ЦЕЛЬ записи называет владелец лексики (D1323; прежде — завершитель `#` в своём регулярном выражении стража):
# уберём вопрос владельцу, случай «цель, за ней комментарий» обязан пройти мимо.
_M=$(_rwb_mutant 's|^_TGT=$(executable_change_targets "$CMD"); _TRC=$?$|_TGT=""; _TRC=0|' \
     'cp rules/CLAUDE.md ~/.claude/CLAUDE.md   # законный путь sync_claude_md')
[ "$_M" = "0" ] && ok || bad "D425h" "без вопроса владельцу лексики страж всё равно отказал (получено '$_M') — ВЛАДЕЛЕЦ ЦЕЛИ ничем не доказан"

echo "rules write bypass tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
