#!/usr/bin/env bash
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

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
dec() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null; }
assert_silent() { [ -z "$(dec "${1:-}")" ] && ok || bad "${2:-тишина}" "${3:-получен отказ}"; }
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
echo "rules write bypass tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
