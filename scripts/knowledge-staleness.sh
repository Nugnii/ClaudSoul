#!/usr/bin/env bash
# knowledge-staleness.sh — знания, ссылающиеся на несуществующие файлы: кандидаты ревизии (D232).
#
# Результат: знание, чей названный носитель исчез из мира (файл переименован, механизм
#            снесён), названо кандидатом ревизии, а не ждёт, пока устареет молча
# Проверка результата: bash scripts/knowledge-staleness.sh печатает кандидатов и даёт 0;
#            при непустом списке — 1 (находка)
#
# Зачем (D232). FSRS меряет возраст без подтверждений, но не меряет ПРАВДУ: знание может
# подтверждаться и ссылаться на файл, которого больше нет. Это docs-staleness, применённый
# к самой базе: у документов возраст описаний сверяется с механизмами, у знаний до сих пор
# не сверялось ничто.
#
# ЧТО РЕШАЕТ ЭТО ЧИСЛО. Кандидат — вход для /retro: обновить ссылку, сузить знание либо
# вывести из обращения (deprecate). Решает человек; скрипт даёт имя и мёртвую ссылку.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. (1) Ловит только ЯВНЫЕ имена файлов с расширением; знание о
# поведении без имени носителя невидимо — это записано кейсом
# claim-without-mechanism-name-evades-staleness, и потолок общий с dep-index.
# (2) RC_TRACE_ADDR_RE из root-cause-lib не переиспользован намеренно: он требует
# «:строку», а знания чаще ссылаются на файл без номера. (3) Существование проверяется
# в репозитории ClaudSoul и в ~/.claude/hooks — файл чужого проекта, названный в знании
# из его домена, даст ложного кандидата; такие гасятся точечно списком-исключением.
set -uo pipefail

LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
REPO="${CLAUDSOUL_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOKS_INSTALLED="${CLAUDE_HOOKS_DIR:-$HOME/.claude/hooks}"
# Имена, которые не файлы этого мира: примеры из чужих доменов, плейсхолдеры.
# Второй ряд исключений — generic-имена, живущие в знаниях как ПРИМЕРЫ чужих доменов
# (deploy.sh, lib.sh, ru.json): первый прогон дал 11 кандидатов, и около половины были
# иллюстрациями, а не носителями. Веб-расширения исключены целиком: носители системы —
# sh/py/md/tsv.
EXCLUDE_RE="${KNOWLEDGE_STALENESS_EXCLUDE:-^(package|tsconfig|docker-compose|next|README|CHANGELOG|SESSION|Cargo|pyproject|settings|index)\.|^[a-z]\.(sh|py|md)$|\.(tmpl|tmp|bak|log|lock|js|ts|json|yml|yaml|toml)$|^(deploy|lib|sborka|security-gate|app|main|build)\.(sh|py)$|(^|/)(SKILL|MEMORY|skill_contract)\.md$|^feedback_}"

[ -d "$LESSONS" ] || { echo "базы знаний нет ($LESSONS)"; exit 0; }

FOUND=0
REPORT=""
for kf in "$LESSONS"/pattern-*.md "$LESSONS"/principle-*.md; do
    [ -f "$kf" ] || continue
    # Явные имена файлов с расширением; без обязательного «:строка» (см. предел 2).
    refs=$(grep -oE '[A-Za-z0-9_][A-Za-z0-9_./-]*\.(sh|py|md|tsv)\b' "$kf" 2>/dev/null \
           | sed 's|^\./||' | sort -u | grep -vE "$EXCLUDE_RE" || true)
    [ -n "$refs" ] || continue
    dead=""
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        base=$(basename "$ref")
        # Существует по прямому пути от корня репозитория, по basename в известных
        # каталогах, либо это файл самой базы знаний.
        # Память проектов и references скиллов — законные дома ссылок знаний.
        if ls "$REPO"/skills/*/references/"$base" >/dev/null 2>&1; then continue; fi
        if ls "$HOME"/.claude/projects/*/memory/"$base" >/dev/null 2>&1; then continue; fi
        if [ -e "$REPO/$ref" ] || [ -e "$LESSONS/$base" ] || [ -e "$HOOKS_INSTALLED/$base" ] \
           || [ -e "$HOOKS_INSTALLED/$ref" ] \
           || [ -e "$REPO/hooks/$base" ] || [ -e "$REPO/scripts/$base" ] \
           || [ -e "$REPO/docs/$base" ] || [ -e "$REPO/$base" ] \
           || [ -e "$REPO/knowledge/$base" ] || [ -e "$REPO/hooks/lib/$base" ] \
           || [ -e "$REPO/hooks/tests/$base" ] || [ -e "$REPO/mcp-server/$base" ]; then
            continue
        fi
        dead="${dead}${dead:+, }${ref}"
    done <<EOF
$refs
EOF
    if [ -n "$dead" ]; then
        FOUND=$((FOUND + 1))
        REPORT="${REPORT}  $(basename "$kf"): ссылки в никуда: ${dead}
"
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "мёртвых ссылок в обобщениях базы нет"
    exit 0
fi
echo "Кандидаты ревизии (знание называет файл, которого нет ни в репозитории, ни в установленном):"
printf '%s' "$REPORT"
echo "[замер: находки, не сбой] знаний с мёртвыми ссылками: $FOUND — обновить ссылку, сузить либо вывести через /retro"
exit 1
