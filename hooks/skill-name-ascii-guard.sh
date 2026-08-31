#!/usr/bin/env bash
# skill-name-ascii-guard.sh — PreToolUse[Bash]: имя скилла вне латиницы отбивается отказом, а не напоминанием.
# en: PreToolUse[Bash] — a skill directory named outside ASCII is denied, not merely flagged.
#
# Результат: в skills/ нет ни одного имени вне [a-z0-9._-], и фильтры путей в стражах
#            не могут онеметь на скилле.
# Проверка результата: bash hooks/tests/test_skill_name_ascii_guard.sh
#
# Повод. 28 августа 2026 собеседник спросил, почему скилл зовётся `противник`. Правило
# в rules/CLAUDE.md требовало русских имён; следовали ему 2 скилла из 23, и расхождение
# 21:2 прожило незамеченным. Цена оказалась не стилистической: git при core.quotePath
# отдаёт не-ASCII путь в кавычках с восьмеричными экранами, фильтр путей его не узнаёт,
# и страж МОЛЧИТ на скилле независимо от содержимого. Так по очереди онемели пять
# механизмов — docs-family-check, quality-gate-check, skill-review-check,
# code-review-reminder, dep-index вместе с doc-impact-check, — и каждый чинили отдельным
# обходом там, где заметили. Обход лечит один страж; латиница закрывает класс, включая
# стражей ненаписанных. Правило переписано, скиллы переименованы, здесь стоит возврат.
#
# Почему уровень 4 (отказ), а не инжект. Признак несёт РОВНО ОДНО последствие: путь
# станет кавыченным и фильтры его потеряют. Разных исходов у него нет, значит и вилки
# «напомнить или отбить» нет — правило выбора уровня из case-2026-08-28-enforcement-is-
# a-property-of-consequence. Проверка на отрицательном классе (D107) — в тесте: признак
# прогнан по всей истории коммитов репозитория.
#
# Два входа, одно последствие. Команда с путём `skills/<не-ASCII>/` ловится в момент
# создания; staged-файл при `git commit` — на случай, когда каталог завели не через Bash
# (Write, файловый менеджер, чужой процесс). Первый вход экономит написанную работу,
# второй закрывает обход.
#
# КОНТРПРИМЕР: скилл, положенный СРАЗУ в ~/.claude/commands/ мимо репозитория, сюда не
# попадает — хук смотрит на дерево проекта. Для таких остаётся сверка при установке.
#
# Input  (stdin): {tool_name, tool_input, cwd, ...}
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny", ...}} либо пусто
# Exit:  always 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "$CMD" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"

# Имя скилла законно, если целиком укладывается в [a-z0-9._-] и начинается с буквы
# или цифры. LC_ALL=C обязателен: в UTF-8 локали диапазоны классов зависят от таблицы
# сортировки, и кириллица может проскочить через [a-z] на части систем.
bad_name() {
    printf '%s' "$1" | LC_ALL=C grep -qvE '^[a-z0-9][a-z0-9._-]*$'
}

OFFENDERS=""
add_offender() {
    case "$OFFENDERS" in
        *"|$1|"*) : ;;
        *) OFFENDERS="$OFFENDERS|$1|" ;;
    esac
}

# --- Вход 1: команда СОЗДАЁТ каталог скилла ----------------------------------------
# Только запись. Чтение (`cat skills/имя/SKILL.md`, `grep -r skills/`) последствия
# «страж онемеет» не несёт, а отказ на нём был бы ложным — и по правилу выбора уровня
# отказ, часть срабатываний которого ложна, обязан снова стать подсказкой.
IS_CREATE=0
grep -qE '(^|[|;&[:space:]])(mkdir|mv|cp|touch|install|rsync)([[:space:]]|$)' <<< "$CMD" && IS_CREATE=1
grep -qE 'git[[:space:]]+mv([[:space:]]|$)' <<< "$CMD" && IS_CREATE=1
grep -qE '>>?[[:space:]]*[^&[:space:]]*skills/' <<< "$CMD" && IS_CREATE=1
if [ "$IS_CREATE" -eq 1 ]; then
    # Кавычки снимаются до разбора: `git mv a "skills/имя"` иначе даёт имя с хвостовой
    # кавычкой, мимо проверки не проходит, а мимо ОТКАЗА проходит — то есть молча.
    CMD_BARE=$(printf '%s' "$CMD" | tr -d '"'"'" | tr -s ' \t;|&()' '\n')
    while IFS= read -r TOKEN; do
        case "$TOKEN" in
            *skills/*) ;;
            *) continue ;;
        esac
        NAME=$(printf '%s' "$TOKEN" | sed -n 's#.*skills/\([^/]*\)\(/.*\)\{0,1\}$#\1#p')
        [ -n "$NAME" ] || continue
        bad_name "$NAME" && add_offender "$NAME"
    done <<EOF
$CMD_BARE
EOF
fi

# --- Вход 2: staged skills/<имя>/SKILL.md при коммите ------------------------------
# quotepath=false здесь не защита, а условие работы: без него страж против не-ASCII
# сам бы не увидел не-ASCII.
case "$CMD" in
    *"git commit"*|*"git"*"commit"*)
        if [ -e "$CWD/.git" ]; then
            STAGED=$(git -C "$CWD" -c core.quotepath=false diff --cached --name-only 2>/dev/null \
                | sed -e 's/^"//' -e 's/"$//')
            while IFS= read -r F; do
                case "$F" in
                    skills/*/*) ;;
                    *) continue ;;
                esac
                NAME=$(printf '%s' "$F" | sed -n 's#^skills/\([^/]*\)/.*#\1#p')
                [ -n "$NAME" ] || continue
                bad_name "$NAME" && add_offender "$NAME"
            done <<EOF
$STAGED
EOF
        fi
        ;;
esac

[ -n "$OFFENDERS" ] || exit 0

LIST=$(printf '%s' "$OFFENDERS" | tr '|' '\n' | grep -v '^$' | sed 's/^/  • /')

MSG="⛔ ОТКАЗ (вызов не выполнен). Имя скилла вне латиницы:

$LIST

Имя каталога становится путём skills/<имя>/SKILL.md. Git при core.quotePath отдаёт такой
путь в кавычках с восьмеричными экранами, фильтр путей его не узнаёт — и страж молчит на
скилле независимо от содержимого. Так по очереди онемели пять механизмов: docs-family-check,
quality-gate-check, skill-review-check, code-review-reminder, dep-index с doc-impact-check.

Правило: имя — только [a-z0-9._-], русскими остаются description, тело и роль в промпте
(rules/CLAUDE.md § Skills organization → Naming). Переименуй каталог и поле name: в
frontmatter — и повтори."

jq -cn --arg m "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$m}}' 2>/dev/null || true
exit 0
