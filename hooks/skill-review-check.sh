#!/usr/bin/env bash
# skill-review-check.sh — PreToolUse skill contract gate при `git commit`.
# en: PreToolUse: skill-review gate on `git commit`.
#
# v1.5.8 — auto-invocation trigger для /skill-review (C-класс nice-to-have).
# Отличается от quality-gate (v1.5.6): тот проверяет DoD чекбоксы (done or not),
# этот — contract integrity самой SKILL.md (frontmatter валидный, DoD present,
# Version + Last Updated в конце, <=400 строк, нет **Changes:** секции).
# Источник контракта — docs/skill-contract.md.
#
# Contract:
#   Input  (stdin): {session_id, tool_name, tool_input, cwd}  (PreToolUse JSON)
#   Output (stdout): {hookSpecificOutput: {hookEventName, additionalContext}} или пусто
#   Exit:  always 0 (degrade gracefully) — не блокирует commit, только silent marker
#
# Scope:
#   Проверяется только skills/**/SKILL.md, присутствующие в staged diff.
#   Для каждого — список violations: missing_frontmatter, missing_name,
#   missing_description, desc_too_long, missing_user_invocable, missing_type,
#   missing_dod, missing_version, missing_last_updated, too_long, has_changes.
#
# Silent by design: additionalContext, не banner. Agent решает применить.
#
# Throttle: state/skill-review-fired-<SID>.jsonl — per-session, ключ = md5(violations).

set -uo pipefail

# Детект коммита — по ИСПОЛНЯЕМОЙ части команды (single source — command-scope-lib.sh):
# `git commit` в кавычках или в теле heredoc — текст, а не команда.
SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    is_git_commit() { grep -qE 'git[[:space:]]+commit' <<< "${1:-}"; }
fi

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

# Shared per-session throttle (single source — see throttle-lib.sh).
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
if [ -f "$THROTTLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$THROTTLE_LIB"
else
    echo "Missing throttle-lib.sh: $THROTTLE_LIB" >&2; exit 1
fi

# Shared hash helper (single source — see hash-lib.sh).
HASH_LIB="${HASH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash-lib.sh}"
if [ -f "$HASH_LIB" ]; then
    # shellcheck source=/dev/null
    source "$HASH_LIB"
else
    echo "Missing hash-lib.sh: $HASH_LIB" >&2; exit 1
fi
MAX_LINES="${SKILL_REVIEW_MAX_LINES:-400}"
# Порог — платформенный лимит, а не выдуманное число. Прежние 200 были самоограничением,
# перенесённым из чужого репозитория, и однажды уже стоили функциональности: при подгонке
# под них из описаний `entity` и `ingest` вырезали фразы, по которым скилл вызывается сам
# («добавь в базу знаний», «что ты знаешь о X»). Цена ошибки асимметрична — лишняя сотня
# символов в описании стоит дёшево, неработающий автовызов дорого.
MAX_DESC_LEN="${SKILL_REVIEW_MAX_DESC:-1024}"

mkdir -p "$STATE_DIR" 2>/dev/null

# check_contract <rel_path>: echoes "rel|violation1,violation2,..." if any, else nothing.
# check_contract <rel_path> [<path_to_content>]
# Второй аргумент — ЧТО именно проверять. Без него берётся рабочий файл (режим сплошного
# обхода). При коммите передаётся выгрузка из индекса: шапка этого файла заявляет областью
# staged diff, а код читал рабочее дерево, и проба на подложенном случае показала промах —
# переименованное поле в индексе оставалось незамеченным, потому что рабочий файл был цел.
# `quality-gate-check.sh:107` делает это правильно (`git show ":$rel"`), здесь было иначе.
check_contract() {
    local rel="$1"
    local abs="${2:-$CWD/$rel}"
    [ -f "$abs" ] || return 0

    local violations=""

    # Line count.
    local line_count
    line_count=$(wc -l < "$abs" | tr -d ' ')
    if [ "${line_count:-0}" -gt "$MAX_LINES" ]; then
        violations="too_long(${line_count}>${MAX_LINES})"
    fi

    # Frontmatter: must start with --- on line 1 and close with --- later.
    local first_line
    first_line=$(head -n 1 "$abs")
    if [ "$first_line" != "---" ]; then
        [ -z "$violations" ] && violations="missing_frontmatter" || violations="$violations,missing_frontmatter"
        printf '%s|%s\n' "$rel" "$violations"
        return 0
    fi

    # Extract frontmatter block (between first --- and next ---).
    local frontmatter
    frontmatter=$(awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {exit} in_fm {print}' "$abs")
    if [ -z "$frontmatter" ]; then
        [ -z "$violations" ] && violations="missing_frontmatter" || violations="$violations,missing_frontmatter"
        printf '%s|%s\n' "$rel" "$violations"
        return 0
    fi

    # Required frontmatter keys.
    if ! grep -qE '^name:[[:space:]]*\S' <<< "$frontmatter"; then
        [ -z "$violations" ] && violations="missing_name" || violations="$violations,missing_name"
    fi
    if ! grep -qE '^user-invocable:[[:space:]]*\S' <<< "$frontmatter"; then
        [ -z "$violations" ] && violations="missing_user_invocable" || violations="$violations,missing_user_invocable"
    fi

    # description: must exist, and if single-line, length <= MAX_DESC_LEN.
    if grep -qE '^description:[[:space:]]*\S' <<< "$frontmatter"; then
        local desc_line desc_len
        desc_line=$(echo "$frontmatter" | grep -E '^description:' | head -n 1 | sed -E 's/^description:[[:space:]]*//' | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
        desc_len=${#desc_line}
        if [ "$desc_len" -gt "$MAX_DESC_LEN" ]; then
            [ -z "$violations" ] && violations="desc_too_long(${desc_len}>${MAX_DESC_LEN})" || violations="$violations,desc_too_long(${desc_len}>${MAX_DESC_LEN})"
        fi
    else
        [ -z "$violations" ] && violations="missing_description" || violations="$violations,missing_description"
    fi

    # **Type:** — один из 4 валидных типов (см. docs/skill-contract.md).
    if ! grep -qE '^\*\*Type:\*\*[[:space:]]+(worker|coordinator|orchestrator|reference)' "$abs"; then
        [ -z "$violations" ] && violations="missing_type" || violations="$violations,missing_type"
    fi

    # ## Definition of Done section.
    if ! grep -qE '^## Definition of Done[[:space:]]*$' "$abs"; then
        [ -z "$violations" ] && violations="missing_dod" || violations="$violations,missing_dod"
    fi

    # **Version:** at end (in last 20 lines).
    if ! grep -qE '^\*\*Version:\*\*[[:space:]]+' <<< "$(tail -n 20 "$abs")"; then
        [ -z "$violations" ] && violations="missing_version" || violations="$violations,missing_version"
    fi

    # **Last Updated:** YYYY-MM-DD at end.
    if ! grep -qE '^\*\*Last Updated:\*\*[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}' <<< "$(tail -n 20 "$abs")"; then
        [ -z "$violations" ] && violations="missing_last_updated" || violations="$violations,missing_last_updated"
    fi

    # **Changes:** section — forbidden.
    if grep -qE '^(\*\*Changes:\*\*|## Changes)' "$abs"; then
        [ -z "$violations" ] && violations="has_changes_section" || violations="$violations,has_changes_section"
    fi

    [ -n "$violations" ] && printf '%s|%s\n' "$rel" "$violations"
}

# --- Сплошной обход (D42) ---------------------------------------------------------
#
# Хук по построению видит только те SKILL.md, что попали в staged diff. Значит скилл,
# которого давно не касаются, не проверяется НИКОГДА — обязанность просто не наступает.
# Класс уже кусал: коммит c662f0a сообщает, что четыре нарушения длины описания пролежали
# месяцами именно потому, что файлы не попадали в коммит.
#
# Режим `sweep` обходит все skills/*/SKILL.md в репозитории и падает при нарушениях.
# Логика проверки та же — единый источник, а не вторая копия контракта.
# Вызывается по расписанию: строка `skill-contract` в `scripts/measurements.tsv`.
if [ "${1:-}" = "sweep" ]; then
    CWD="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
    _sweep_issues=""
    _sweep_n=0
    for _f in "$CWD"/skills/*/SKILL.md; do
        [ -f "$_f" ] || continue
        _sweep_n=$((_sweep_n + 1))
        _rel="skills/$(basename "$(dirname "$_f")")/SKILL.md"
        _r=$(check_contract "$_rel" "$_f")
        [ -n "$_r" ] && _sweep_issues="${_sweep_issues}${_r}"$'\n'
    done
    if [ "$_sweep_n" -eq 0 ]; then
        # Ноль сравнений — отказ проверки, а не успех. Проект уже закрывал этот класс
        # для детектора дрейфа (v1.14.2), и первая версия обхода ввела его заново.
        echo "Контракт скиллов: НЕ ПРОВЕРЕНО — ни одного skills/*/SKILL.md в ${CWD}" >&2
        exit 2
    fi
    if [ -z "$_sweep_issues" ]; then
        echo "Контракт скиллов: проверено ${_sweep_n}, нарушений нет."
        exit 0
    fi
    echo "Контракт скиллов: проверено ${_sweep_n}, нарушения:"
    printf '%s' "$_sweep_issues" | awk -F '|' 'NF==2 {printf "  • %s — %s\n", $1, $2}'
    exit 1
fi

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

is_git_commit "$COMMAND" || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

[ -e "$CWD/.git" ] || exit 0

# `core.quotepath=false` обязателен: без него git отдаёт имена вне ASCII в кавычках с
# восьмеричными escape ("skills/\320\277\321\200\320\276.../SKILL.md"), фильтр их не
# узнаёт, и страж молчит на скилле независимо от его содержимого. У проекта два таких
# скилла из двадцати трёх (`противник`, `грилинг`). Хвостовая `"?` добирает остаток:
# имена с пробелами и спецсимволами git кавычит и при quotepath=false.
STAGED_SKILLS=$(git -C "$CWD" -c core.quotepath=false diff --cached --name-only 2>/dev/null \
    | grep -E '^"?skills/[^/]+/SKILL\.md"?$' \
    | sed -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g')
[ -z "$STAGED_SKILLS" ] && exit 0

ISSUES=""
_STAGE_TMP=$(mktemp -d 2>/dev/null) || _STAGE_TMP=""
trap '[ -n "$_STAGE_TMP" ] && rm -rf "$_STAGE_TMP"' EXIT
while IFS= read -r skill_rel; do
    [ -z "$skill_rel" ] && continue
    # Проверяется то, что уйдёт в коммит, а не то, что лежит в рабочем дереве.
    _content="$CWD/$skill_rel"
    if [ -n "$_STAGE_TMP" ]; then
        _staged_file="$_STAGE_TMP/$(printf '%s' "$skill_rel" | tr '/' '_')"
        if git -C "$CWD" show ":$skill_rel" > "$_staged_file" 2>/dev/null && [ -s "$_staged_file" ]; then
            _content="$_staged_file"
        fi
    fi
    result=$(check_contract "$skill_rel" "$_content")
    [ -z "$result" ] && continue
    if [ -z "$ISSUES" ]; then ISSUES="$result"
    else ISSUES="$ISSUES"$'\n'"$result"
    fi
done <<< "$STAGED_SKILLS"

[ -z "$ISSUES" ] && exit 0

# hash_value() — из общего hash-lib.sh (источается в bootstrap выше)

ISSUES_HASH=$(hash_value "$ISSUES")
THROTTLE_FILE=$(throttle_file "$STATE_DIR" skill-review "$SESSION_ID")
if throttle_seen "$THROTTLE_FILE" "$ISSUES_HASH"; then
    exit 0
fi
throttle_mark "$THROTTLE_FILE" "$ISSUES_HASH"

ITEMS=$(printf '%s\n' "$ISSUES" | awk -F '|' 'NF==2 {printf "  • %s — %s\n", $1, $2}')

CONTEXT=$(printf '🧾 Skill-review: в staged diff есть SKILL.md с contract violations:\n%s\nКонтракт: docs/skill-contract.md — frontmatter (name+description≤200+user-invocable), **Type:** worker, ## Definition of Done, **Version:** + **Last Updated:** YYYY-MM-DD в конце, ≤%s строк, запрещены **Changes:** секции.\nИсправь контракт перед коммитом; если осознанно waived — добавь причину в commit message.' \
    "$ITEMS" "$MAX_LINES")

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0
