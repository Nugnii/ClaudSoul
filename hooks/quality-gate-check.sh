#!/usr/bin/env bash
# quality-gate-check.sh — PreToolUse страж контракта скиллов при `git commit`.
# en: PreToolUse: skill-contract guard on `git commit`.
#
# v1.5.6 — первый auto-invocation trigger для /quality-gate скилла (C-класс tier 2
# из docs/skill-triggers-audit.md). Закрывает подразрыв C «agent-heuristic skills
# live только через memory»: контракт SKILL.md проверяется механически перед
# коммитом, а не памятью агента.
#
# v1.12.1 — ИНВЕРСИЯ ИСПРАВЛЕНА. До этого хук считал незакрытые чекбоксы `- [ ]`
# в секции Definition of Done и горел, если хоть один не отмечен. Но `docs/skill-contract.md`
# ПРЕДПИСЫВАЕТ именно такой вид: в его собственном шаблоне чекбоксы пустые, а формулировка
# «скилл не завершён, пока все не выполнены» относится к ИСПОЛНЕНИЮ скилла, не к коммиту
# файла. Чекбоксы — runtime-чеклист воркера, а не список задач автора.
#
# Следствие: незакрыты во ВСЕХ 21 скилле (ноль отмеченных примерно из 150). Страж
# загорался ровно тогда, когда контракт соблюдён, то есть на каждом коммите со
# SKILL.md, и его срабатывание не несло информации. Тест закреплял ту же ошибку:
# фикстура «complete» использовала `- [x]`, чего нет ни в одном реальном скилле.
#
# Теперь проверяется то, что контракт действительно требует и что механически
# проверяемо: наличие обязательных полей и бамп версии при изменении тела.
#
# Contract:
#   Input  (stdin): {session_id, tool_name, tool_input, cwd}  (PreToolUse JSON)
#   Output (stdout): {hookSpecificOutput: {hookEventName, additionalContext}} или пусто
#   Exit:  always 0 (degrade gracefully) — не блокирует commit, только silent marker
#
# Scope:
#   Только skills/**/SKILL.md в staged diff (guard R3). Читается STAGED blob, а не
#   рабочий файл: гейт судит о том, что уходит в коммит.
#
# Проверки (все из таблицы «Обязательное» в docs/skill-contract.md):
#   1. секция `## Definition of Done` есть и в ней хотя бы один чекбокс
#      (наличие, НЕ отмеченность; для `**Type:** reference` требование номинально)
#   2. `**Version:** X.Y.Z` присутствует
#   3. `**Last Updated:** YYYY-MM-DD` присутствует
#   4. `**Type:**` присутствует и из четырёх допустимых
#   5. тело изменилось, а Version и Last Updated — нет (главный практический сигнал)
#   6. запрещённая секция `**Changes:**` / файл длиннее 400 строк
#
# Silent by design (feedback_silent_correct_decisions.md): additionalContext, не banner.
# Agent решает применить — не blocker.
#
# Throttle: state/quality-gate-fired-<SID>.jsonl — per-session, ключ = md5(missing_skills).
# Тот же набор неполных SKILL.md не fired дважды; новый diff → новый fire.

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

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Match "git commit" as distinct command invocation.
is_git_commit "$COMMAND" || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# git repo check
[ -e "$CWD/.git" ] || exit 0

# Staged SKILL.md files (paths relative to repo root).
# Guard R3: если в staged нет skills/*/SKILL.md — skip, не false-positive на docs-only.
# `core.quotepath=false` обязателен: без него git отдаёт имена вне ASCII в кавычках с
# восьмеричными escape ("skills/\320\277\321\200\320\276.../SKILL.md"), фильтр их не
# узнаёт, и страж молчит на скилле независимо от его содержимого. Повод был живой: два
# скилла из двадцати трёх звались кириллицей. 28.08.2026 их переименовали (`adversary`,
# `grilling`), и не-ASCII имён в `skills/` больше нет — причину убрали, а не обошли.
# Защита остаётся страховкой: имена с пробелами и спецсимволами git кавычит и при
# quotepath=false, и это добирает хвостовая `"?`. Возврат кириллицы теперь отбивает
# `skill-name-ascii-guard`, а не эта строка.
STAGED_SKILLS=$(git -C "$CWD" -c core.quotepath=false diff --cached --name-only 2>/dev/null \
    | grep -E '^"?skills/[^/]+/SKILL\.md"?$' \
    | sed -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g')
[ -z "$STAGED_SKILLS" ] && exit 0

# Для каждого SKILL.md — проверить контракт.
# check_contract <rel>: echoes "rel|проблема; проблема" если есть нарушения; иначе nothing.
check_contract() {
    local rel="$1"
    local staged
    # Staged blob, а не рабочий файл: судим о том, что уходит в коммит.
    staged=$(git -C "$CWD" show ":$rel" 2>/dev/null) || return 0
    [ -n "$staged" ] || return 0

    local problems=""
    add() { if [ -z "$problems" ]; then problems="$1"; else problems="$problems; $1"; fi; }

    local type_line
    type_line=$(printf '%s\n' "$staged" | grep -m1 '^\*\*Type:\*\*' || true)
    if [ -z "$type_line" ]; then
        add "нет **Type:**"
    elif ! grep -qE '\*\*Type:\*\*[[:space:]]*(worker|coordinator|orchestrator|reference)' <<< "$type_line"; then
        add "**Type:** не из четырёх допустимых"
    fi

    # DoD: проверяем НАЛИЧИЕ секции и хотя бы одного чекбокса. Отмеченность не
    # проверяем принципиально — контракт предписывает пустые `- [ ]` в исходнике.
    # Для reference требование номинально (контракт, раздел про типы).
    if ! grep -q 'reference' <<< "$type_line"; then
        local dod
        dod=$(printf '%s\n' "$staged" | awk '
            /^## Definition of Done[[:space:]]*$/ { in_s=1; next }
            in_s && /^## / { in_s=0 }
            in_s { print }
        ')
        if [ -z "$dod" ]; then
            add "нет секции ## Definition of Done"
        elif ! grep -qE '^[[:space:]]*-[[:space:]]*\[[ xX]\]' <<< "$dod"; then
            add "секция Definition of Done без чекбоксов"
        fi
    fi

    local ver_line upd_line
    ver_line=$(printf '%s\n' "$staged" | grep -m1 '^\*\*Version:\*\*' || true)
    upd_line=$(printf '%s\n' "$staged" | grep -m1 '^\*\*Last Updated:\*\*' || true)
    [ -n "$ver_line" ] || add "нет **Version:**"
    [ -n "$upd_line" ] || add "нет **Last Updated:**"

    grep -q '^\*\*Changes:\*\*' <<< "$staged" && add "секция **Changes:** запрещена контрактом"

    local lines
    lines=$(printf '%s\n' "$staged" | grep -c '' || echo 0)
    [ "$lines" -gt 400 ] && add "$lines строк > 400 — выноси в references/"

    # Главный практический сигнал: тело поменялось, а версия и дата — нет.
    # Ровно этот дрейф ловили руками, когда правили процедуру скилла и забывали бамп.
    local prev
    if prev=$(git -C "$CWD" show "HEAD:$rel" 2>/dev/null) && [ -n "$prev" ]; then
        if [ "$prev" != "$staged" ]; then
            local prev_ver prev_upd
            prev_ver=$(printf '%s\n' "$prev" | grep -m1 '^\*\*Version:\*\*' || true)
            prev_upd=$(printf '%s\n' "$prev" | grep -m1 '^\*\*Last Updated:\*\*' || true)
            if [ "$prev_ver" = "$ver_line" ] && [ "$prev_upd" = "$upd_line" ]; then
                add "тело изменено, Version и Last Updated прежние"
            fi
        fi
    fi

    [ -n "$problems" ] && printf '%s|%s\n' "$rel" "$problems"
    return 0
}

INCOMPLETE=""
while IFS= read -r skill_rel; do
    [ -z "$skill_rel" ] && continue
    result=$(check_contract "$skill_rel")
    [ -z "$result" ] && continue
    if [ -z "$INCOMPLETE" ]; then INCOMPLETE="$result"
    else INCOMPLETE="$INCOMPLETE"$'\n'"$result"
    fi
done <<< "$STAGED_SKILLS"

[ -z "$INCOMPLETE" ] && exit 0

# Per-session throttle by hash of incomplete-set.
# hash_value() — из общего hash-lib.sh (источается в bootstrap выше)

INCOMPLETE_HASH=$(hash_value "$INCOMPLETE")
THROTTLE_FILE=$(throttle_file "$STATE_DIR" quality-gate "$SESSION_ID")
if throttle_seen "$THROTTLE_FILE" "$INCOMPLETE_HASH"; then
    exit 0
fi
throttle_mark "$THROTTLE_FILE" "$INCOMPLETE_HASH"

# Сформировать список для inject.
ITEMS=$(printf '%s\n' "$INCOMPLETE" | awk -F '|' 'NF==2 {printf "  • %s — %s\n", $1, $2}')

CONTEXT=$(printf '🚦 Quality-gate: staged SKILL.md нарушает контракт (docs/skill-contract.md):\n%s\nПочини перед коммитом либо укажи в сообщении коммита, почему осознанно пропускаешь.\nЧекбоксы Definition of Done отмечать НЕ нужно — контракт предписывает их пустыми, это runtime-чеклист исполнения скилла.' \
    "$ITEMS")

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0
