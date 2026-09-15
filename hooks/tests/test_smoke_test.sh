#!/usr/bin/env bash
# test_smoke_test.sh — «Проверка результата» smoke-test.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/smoke-test.sh на подложенной установке считает хуки,
#            регистрации в settings.json, скиллы и знания, видит маркеры правил и venv сервера,
#            отвечает 1 при отсутствии критичных каталогов и 2 при одних предупреждениях.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного.
# Установка подкладывается через CLAUDE_HOME и CLAUDSOUL_DIR. Наличие `uv` зависит от машины и
# даёт предупреждение — ноги полной установки судят «Провалов: 0» и названные строки, а не код 0.
# Команда БЕРЁТСЯ из шапки инструмента, как в test_split_provenance_log.sh.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/smoke-test.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *smoke-test.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CH="$TMP/claude-home"; CD="$TMP/claudsoul"

mk_install() {   # полная установка: 16 хуков, 15 регистраций, 10 скиллов, 1 знание, маркеры, venv
    rm -rf "$CH" "$CD"; mkdir -p "$CH/hooks" "$CH/commands" "$CH/global-lessons" "$CH/sessions/active" "$CD/mcp-server/.venv/bin"
    local i=1
    while [ "$i" -le 16 ]; do : > "$CH/hooks/h$i.sh"; i=$((i + 1)); done
    i=1
    while [ "$i" -le 10 ]; do mkdir -p "$CH/commands/skill$i"; : > "$CH/commands/skill$i/SKILL.md"; i=$((i + 1)); done
    : > "$CH/global-lessons/one.md"
    printf '# правила\n<!-- ClaudSoul: managed-start -->\n<!-- ClaudSoul: managed-end -->\n' > "$CH/CLAUDE.md"
    jq -n '{hooks:{PreToolUse:[{hooks:[range(15) | {type:"command", command:("h" + tostring + ".sh")}]}]}}' > "$CH/settings.json"
    printf '#!/bin/sh\nexit 0\n' > "$CD/mcp-server/.venv/bin/python"; chmod +x "$CD/mcp-server/.venv/bin/python"
}
run_tool() {
    OUT=$(cd "$REPO" && CLAUDE_HOME="$CH" CLAUDSOUL_DIR="$CD" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: пустой каталог — критичные компоненты отсутствуют, код 1 --------------------------------
rm -rf "$CH" "$CD"; mkdir -p "$CH" "$CD"; run_tool
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 '~/.claude/hooks/ отсутствует'
has T1 'Установка неполная'

# --- T2: полная установка — провалов ноль, все счётчики названы -------------------------------
mk_install; run_tool
{ [ "$RC" -eq 0 ] || [ "$RC" -eq 2 ]; } && ok || bad T2 "rc=$RC — $OUT"
has T2 'Провалов:       0'
has T2 'хуков установлено: 16'
has T2 'хуков зарегистрировано в settings.json: 15'
has T2 'скиллов установлено: 10'
has T2 'файлов знаний: 1'
has T2 'маркеры managed-start/end на месте'
has T2 '.venv создан'
has T2 'python в .venv доступен'

# --- T3: правила без маркеров — предупреждение, код 2 -------------------------------------------
mk_install; printf '# правила без маркеров\n' > "$CH/CLAUDE.md"; run_tool
[ "$RC" -eq 2 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'маркеры отсутствуют'
has T3 'Провалов:       0'

# --- T4: хуков меньше порога — предупреждение с числом --------------------------------------------
mk_install; rm -f "$CH"/hooks/h1[0-6].sh; run_tool
[ "$RC" -eq 2 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'хуков всего 9 (ожидалось ≥15)'

# --- T5: регистраций в settings.json одна из шестнадцати — предупреждение с числом (порог 15) ------
mk_install; jq -n '{hooks:{PreToolUse:[{hooks:[{type:"command", command:"h1.sh"}]}]}}' > "$CH/settings.json"; run_tool
[ "$RC" -eq 2 ] && ok || bad T5 "rc=$RC — $OUT"
has T5 'хуков в settings.json: 1 (ожидалось ≥15)'

# --- T6: скиллов меньше порога (10) --------------------------------------------------------------
mk_install; rm -rf "$CH/commands/skill10"; run_tool
[ "$RC" -eq 2 ] && ok || bad T6 "rc=$RC — $OUT"
has T6 'скиллов всего 9 (ожидалось ≥10)'

# --- T7: база знаний пуста — предупреждение, не провал ----------------------------------------------
mk_install; rm -f "$CH/global-lessons/one.md"; run_tool
[ "$RC" -eq 2 ] && ok || bad T7 "rc=$RC — $OUT"
has T7 'база знаний пуста'
has T7 'Провалов:       0'

echo ""
echo "smoke-test tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
