#!/usr/bin/env bash
# test_bash_cost_detector.sh — характеризующий тест детектора стоимости bash-команд.
# Хук был без своего теста (F8). Проверяет: деструктивные команды → предупреждение,
# безопасные/не-Bash → тишина. Изоляция через HOME + ITR_STATE_DIR. Команды ниже — ДАННЫЕ для
# хука (передаются как JSON-вход), реально не исполняются.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/bash-cost-detector.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_nonsilent() {
    if [ -n "$1" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалось предупреждение, получена тишина"; fi
}
assert_silent() {
    if [ -z "$1" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $1"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

# Хук берёт библиотеку из $HOME/.claude/hooks, не из репозитория, и молча выходит, если
# её там нет. На машине разработчика ClaudSoul установлен — тест незаметно пользовался
# установленной копией и был зелёным; на чистой машине (контейнер, CI) каталога нет,
# хук выходит до чтения входа, и T1/T2 видят тишину (а jq рядом жалуется на обрыв трубы).
# Отличие тут не BSD против GNU, а наличие установки — поэтому свой HOME с ссылками на
# библиотеки репозитория. Ссылать надо все пять: state-lib подключает соседей через
# ${BASH_SOURCE%/*}, то есть ищет их рядом с собой уже в песочнице.
SANDBOX_HOME="$TMP/home"
mkdir -p "$SANDBOX_HOME/.claude/hooks"
for lib in "$HOOKS_DIR"/intrusiveness-*-lib.sh; do
    ln -sf "$lib" "$SANDBOX_HOME/.claude/hooks/"
done

run() {  # $1=tool_name $2=command $3=sid
    jq -nc --arg t "$1" --arg c "$2" --arg s "$3" \
        '{session_id:$s, tool_name:$t, tool_input:{command:$c}}' \
        | HOME="$SANDBOX_HOME" ITR_STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# деструктивная команда (рекурсивное удаление с force) → предупреждение
out=$(run "Bash" "rm -rf /tmp/some/path" "s1")
assert_nonsilent "$out" "T1 recursive-force delete → warning"

# принудительный push → предупреждение
out=$(run "Bash" "git push --force origin main" "s2")
assert_nonsilent "$out" "T2 force push → warning"

# безопасная команда → тишина
out=$(run "Bash" "echo привет && ls -la" "s3")
assert_silent "$out" "T3 safe command → silent"

# не-Bash инструмент → тишина (хук только для Bash)
out=$(run "Read" "rm -rf /tmp/x" "s4")
assert_silent "$out" "T4 non-Bash tool → silent"

# пустая команда → тишина
out=$(run "Bash" "" "s5")
assert_silent "$out" "T5 empty command → silent"

echo ""
echo "bash-cost-detector tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
