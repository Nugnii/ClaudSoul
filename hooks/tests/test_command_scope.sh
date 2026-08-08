#!/usr/bin/env bash
# test_command_scope.sh — стражи сопоставляют ДЕЙСТВИЕ, а не текст команды.
#
# Повод конкретный, не гипотетический. За одну сессию `trust-guard` дал восемь ложных
# срабатываний, а `playwright-cli-guard` дважды ЗАБЛОКИРОВАЛ работу: сперва запись
# собственного теста, потом запись раздела BACKLOG, где описывался этот же дефект.
# Причина общая — сигнатура искалась во всей строке команды, включая то, что никогда
# не исполняется: шаблоны grep, аргументы в кавычках, тела heredoc, уходящие в файл.
#
# Все строки ниже — настоящие, снятые с этой сессии, а не придуманные для теста.
# Обе стороны обязательны: страж должен молчать на тексте И гореть на действии.
# Проверка только «молчит» превратила бы фикс в отключение стража.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

SEQ=0
_run() { # $1=хук, $2=команда → stdout хука
    SEQ=$((SEQ + 1))
    jq -cn --arg c "$2" --arg s "scope-$SEQ" \
        '{session_id:$s, transcript_path:"", cwd:"/tmp", tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" bash "$HOOKS_DIR/$1" 2>/dev/null
}

fires() { # $1=хук $2=команда $3=имя
    if [ -n "$(_run "$1" "$2")" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: страж промолчал на реальном действии"; fi
}
silent() { # $1=хук $2=команда $3=имя
    local out; out=$(_run "$1" "$2")
    if [ -z "$out" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: ложное срабатывание — $(printf '%s' "$out" | tr -d '\n' | head -c 140)"; fi
}

echo "=== trust-guard: горит на действии ==="
fires trust-guard.sh 'rm -rf /tmp/claudsoul-verify' "T1 rm -rf с путём"
fires trust-guard.sh 'T=/tmp/x; rm -rf "$T"' "T2 rm -rf с целью в кавычках — кавычки не прячут действие"
fires trust-guard.sh 'git push --force origin main' "T3 force push"
fires trust-guard.sh 'cd /repo && git reset --hard HEAD~1' "T4 reset --hard после &&"

echo "=== trust-guard: молчит на тексте (реальные строки сессии) ==="
silent trust-guard.sh 'grep -n "DESTRUCTIVE\|rm -rf\|force" hooks/trust-guard.sh' \
    "T5 read-only grep, шаблон содержит rm -rf"
silent trust-guard.sh "grep -qE '(^|[[:space:];&|])rm[[:space:]]+(-[rRfv]*[rR])' hooks/trust-guard.sh" \
    "T6 grep по собственной сигнатуре стража"
silent trust-guard.sh 'printf "%s" "git push --force origin main" >> BACKLOG.md' \
    "T7 запись строки про force push в файл"
silent trust-guard.sh 'cat > /tmp/doc.md <<'"'"'EOF'"'"'
Пример: git push --force origin main
и rm -rf каталога
EOF' "T8 тело heredoc уходит в файл"

echo "=== playwright-cli-guard: горит на исполняемом скрипте ==="
fires playwright-cli-guard.sh 'python3 - <<'"'"'PY'"'"'
from playwright.sync_api import sync_playwright
browser = chromium.launch(headless=True)
PY' "T9 heredoc в интерпретатор — настоящий scratch-скрипт"
fires playwright-cli-guard.sh 'node -e "const {chromium} = require(\"playwright\"); chromium.launch()"' \
    "T10 node -e с запуском браузера"

echo "=== playwright-cli-guard: молчит, когда тело уходит в файл ==="
silent playwright-cli-guard.sh 'cat > /tmp/test_guard.sh <<'"'"'EOF'"'"'
# фикстура теста: строка chromium.launch( ниже — данные, не запуск
echo "chromium.launch("
EOF' "T11 запись собственного теста — первый реальный блок"
silent playwright-cli-guard.sh 'cat >> BACKLOG.md <<'"'"'EOF'"'"'
- ☐ **D2** playwright-cli-guard матчит chromium.launch( в тексте команды
EOF' "T12 запись раздела BACKLOG про этот дефект — второй реальный блок"
silent playwright-cli-guard.sh 'grep -rn "chromium.launch(" hooks/' "T13 поиск строки по репозиторию"

echo ""
echo "command scope tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
