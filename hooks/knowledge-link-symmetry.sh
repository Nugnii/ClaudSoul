#!/usr/bin/env bash
# knowledge-link-symmetry.sh — PostToolUse[Write|Edit]: ссылка кейс → паттерн получает встречную.
# en: PostToolUse on knowledge writes — a case→pattern edge gets its back-reference written.
#
# Результат: у ссылки, объявленной в кейсе (`specializes`/`confirms`/`extends`/`generalizes`),
#            есть встречная запись в `source_cases` паттерна — без участия памяти автора
# Проверка результата: bash hooks/tests/test_knowledge_link_symmetry.sh даёт 0
#
# Зачем (D208). Симметрия — свойство ПАРЫ файлов, а создаётся односторонней записью: автор
# пишет `edges:` в кейсе, паттерн при этом не трогает никто. Закрытие D12 (v1.14.5)
# восстановило 22 ссылки руками и поставило ПРОВЕРКУ (`test_knowledge_link_symmetry.py` в
# наборе mcp), приняв её за поддержание. Замер 29 августа 2026: закрытие не удержалось —
# три односторонние ссылки, две созданы в тот же день, третья в апреле при живом стороже.
# Проверка ловит позже и в другом контуре, поэтому расхождение живёт от прогона до прогона.
#
# ПОЧЕМУ ДОПИСЫВАНИЕ, А НЕ НАПОМИНАНИЕ. Напоминание — уровень 2 укоренённости: замер
# 28 августа показал, что оно читается и не меняет действия. Здесь действие механическое и
# однозначное (добавить имя файла в список), спорных случаев нет — значит его надо делать,
# а не просить.
#
# КОНТРПРИМЕР, объявлен: ссылка на НЕСУЩЕСТВУЮЩИЙ паттерн не дописывается никуда — это
# опечатка или ещё не созданное знание, и молча заводить ему `source_cases` нельзя.
# НАЗВАННЫЙ ПРЕДЕЛ: правится только файл в `~/.claude/global-lessons`. Копия базы в
# `knowledge/` для чистой установки пересобирается `regen-seed.py` и здесь не трогается.
# Условие снятия: предел уйдёт, если seed перестанет быть производным от рабочей базы.
#
# Input  (stdin): {tool_name, tool_input:{file_path}} (PostToolUse JSON)
# Output (stdout): {hookSpecificOutput:{additionalContext}} — что дописано, либо пусто
# Exit:  always 0 (degrade gracefully).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -n "$FILE" ] || exit 0

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"

# Предмет — файл кейса В РАБОЧЕЙ БАЗЕ. Копия seed и чужие каталоги не трогаются.
case "$FILE" in
    "$LESSONS"/case-*.md) ;;
    *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

ADDED=$(LESSONS_DIR="$LESSONS" python3 - "$FILE" <<'PY'
import re, sys, pathlib, os

case = pathlib.Path(sys.argv[1])
lessons = pathlib.Path(os.environ.get("LESSONS_DIR", case.parent))
text = case.read_text(errors="replace")

# Ссылки кейса на родителя: и в `edges:`, и в `source_cases`-подобных полях.
rx = re.compile(r"^\s*-\s*(confirms|specializes|extends|generalizes)\s*:\s*(\S+\.md)\s*$", re.M)
added = []
for _kind, target in rx.findall(text):
    parent = lessons / target
    # Контрпример: несуществующий паттерн не заводим — это опечатка либо ещё не созданное.
    if not parent.exists():
        continue
    ptext = parent.read_text(errors="replace")
    if case.name in ptext:
        continue
    m = re.search(r'^source_cases:\s*$', ptext, re.M)
    if m:
        ptext = ptext[:m.end()] + f"\n  - {case.name}" + ptext[m.end():]
    else:
        # Поля нет — заводим его перед `related:`/`edges:`, то есть внутри frontmatter,
        # а не в конце файла: иначе YAML сломается и знание перестанет читаться.
        m2 = re.search(r'^(related:|edges:)', ptext, re.M)
        if not m2:
            continue
        ptext = ptext[:m2.start()] + f"source_cases:\n  - {case.name}\n" + ptext[m2.start():]
    parent.write_text(ptext)
    added.append(target)

print(" ".join(added))
PY
) || exit 0

[ -n "${ADDED// /}" ] || exit 0

MSG="🔗 Встречная ссылка дописана автоматически: $(basename "$FILE") → ${ADDED}.
Симметрия — свойство пары файлов; проверка её ловила, но не создавала (D208)."
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}' 2>/dev/null || true
exit 0
