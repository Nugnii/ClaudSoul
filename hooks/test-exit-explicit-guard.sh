#!/usr/bin/env bash
# test-exit-explicit-guard.sh — PreToolUse[Write|Edit|MultiEdit]: тест, чей код возврата берётся у последней команды, а не у явного exit, в дерево не записывается.
# en: PreToolUse on test writes — refuse a test whose last non-empty line is not an explicit exit.
#
# Результат: в `hooks/tests/test_*.sh` не появляется файл, чья последняя непустая строка —
#            не `exit …`; отказ стоит в момент записи, а не в момент полного прогона
# Проверка результата: bash hooks/tests/test_test_exit_explicit_guard.sh даёт 0
#
# Повод (D338). D289 привёл 232 теста из 349 к явному `exit`, и в тот же день новый тест
# (`test_mcp_orphan_reap.sh`) был написан в старой форме — `[ "$FAIL" -eq 0 ]` последней
# строкой. Поймал это полный прогон через час: правило жило в `test_tests_exit_explicit.sh`,
# то есть судило СБОРКУ, а не запись (case-2026-09-07-check-shaped-as-test-does-not-guard).
# Каждый новый тест пишется по образцу соседа и воспроизводит его концовку — без стража в
# момент записи счётчик отрастает обратно за несколько дней (замер D289: 220 → 232).
#
# Правило живёт у ОДНОГО владельца — `hooks/tests/test_tests_exit_explicit.sh`: страж
# собирает содержимое файла ПОСЛЕ правки и зовёт тот же тест на нём с явным аргументом.
# Копии предиката здесь нет (род K): изменится правило — изменится и отказ.
#
# Уровень — ОТКАЗ. Признак с одним последствием: «код возврата теста возьмётся у последней
# команды, и любая дописанная строка сделает прогон зелёным при красных утверждениях».
# Точность измерена при заведении 12 сентября 2026: предикат прогнан по всем тестам дерева
# (полный прогон `test_tests_exit_explicit.sh`) — 0 срабатываний; положительный контроль —
# старая форма в ногах `test_test_exit_explicit_guard.sh`.
#
# Что под правило НЕ подпадает: файлы вне `hooks/tests/test_*.sh`; дерево без
# `test_tests_exit_explicit.sh` (чужой проект — прибора нет, гейт `-f` стоит ДО вызова);
# правка, чью старую половину в файле не найти (итог неизвестен — страж молчит, отказ
# назовёт сам инструмент); отказ самого предиката по иной причине, чем форма концовки
# (выход без строки «FAIL: код возврата» читается как «не измерено», а не как дефект).
#
# Input  (stdin): {tool_name, tool_input:{file_path, content | old_string,new_string,replace_all | edits}}
# Output (stdout): {hookSpecificOutput:{hookEventName, permissionDecision:"deny", permissionDecisionReason}} либо пусто
# Exit:  always 0.

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
case "$FILE" in */hooks/tests/test_*.sh) ;; *) exit 0 ;; esac

ROOT="${FILE%/hooks/tests/*}"
CHECK="$ROOT/hooks/tests/test_tests_exit_explicit.sh"
[ -f "$CHECK" ] || exit 0

TMP=$(mktemp -d 2>/dev/null) || exit 0
trap 'rm -rf "$TMP"' EXIT
AFTER="$TMP/$(basename "$FILE")"

# Итог правки собирается тем же способом, каким его соберёт инструмент: Write — целиком,
# Edit — замена старой половины новой (replace_all уважается), MultiEdit — по очереди.
# Полезная нагрузка идёт файлом, а не трубой: heredoc со скриптом уже занимает stdin.
printf '%s' "$INPUT" > "$TMP/input.json"
python3 - "$FILE" "$AFTER" "$TMP/input.json" <<'PY' 2>/dev/null || exit 0
import json, sys
inp = json.load(open(sys.argv[3], encoding="utf-8"))
src, dst = sys.argv[1], sys.argv[2]
t = inp.get("tool_input") or {}
tool = inp.get("tool_name")
if tool == "Write":
    text = t.get("content") or ""
else:
    try:
        text = open(src, encoding="utf-8").read()
    except OSError:
        sys.exit(1)
    edits = [t] if tool == "Edit" else (t.get("edits") or [])
    for e in edits:
        old, new = e.get("old_string") or "", e.get("new_string") or ""
        if old == "" or old not in text:
            sys.exit(1)
        text = text.replace(old, new) if e.get("replace_all") else text.replace(old, new, 1)
open(dst, "w", encoding="utf-8").write(text)
PY

VERDICT=$(bash "$CHECK" "$AFTER" 2>/dev/null)
grep -q '^FAIL: код возврата' <<< "$VERDICT" || exit 0

LAST=$(grep -vE '^[[:space:]]*$' "$AFTER" | tail -1 | cut -c1-80)
jq -Rn --arg f "${FILE##*/}" --arg last "$LAST" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:
    ("🚫 " + $f + " кончается строкой «" + $last + "», а не явным exit: код возврата возьмётся у последней команды, и любая дописанная строка сделает прогон зелёным при красных утверждениях (D289, D338). Закончи файл `exit $(( FAIL != 0 ))` либо `exit \"$FAIL\"`; правило и его прогон по дереву — hooks/tests/test_tests_exit_explicit.sh.")}}' 2>/dev/null
exit 0
