#!/usr/bin/env bash
# doc-impact-check.sh — PreToolUse[Bash] на `git commit`: называет документы, описывающие изменённое, и требует решения по документу состояния при правке поведения.
# en: PreToolUse[Bash] on `git commit`: names describing documents; demands a decision on state docs when behaviour changed.
#
# Зачем. Правило «изменил — проверь зависимости и обнови описания» держалось на
# внимательности и не исполнялось: 28 августа 2026 три утверждения в справочниках и
# мастер-копии правил разошлись с деревом, и нашёл это владелец вопросом, а не механизм.
# Полный аудит стоит часы работы агента — поэтому проверка АДРЕСНАЯ: из изменённых файлов
# берётся короткий список, а не предложение обойти дерево.
#
# Почему глубина 0, а не «все зависимые». Замер 28 августа 2026 по 151 механизму:
# документы, описывающие сам изменённый файл, — медиана 2 на изменение; документы всего,
# что от него зависит, — медиана 21. Второе и есть «проверь всё», только автоматическое:
# такой список не читают. Поэтому зависимые называются ИМЕНАМИ (медиана 1), а судить,
# задело ли их описания, — работа для головы.
#
# Уровень — инжект, не отказ, и это ИЗМЕРЕННОЕ решение, а не осторожность: документ,
# упоминающий механизм, не обязан меняться при каждой правке (починка опечатки поведение
# не меняет). Точность отказа здесь не замерена, а отказ без замера — ложный отказ,
# который обходят не думая (case-2026-08-28-enforcement-is-a-property-of-consequence).
#
# Opt-in по наличию индекса: нет `.claude-docs/dep-index.tsv` — хук молчит. Так он не
# кричит в чужом проекте, где документации ещё нет.
#
# Input  (stdin): {tool_name, tool_input, cwd, session_id}
# Output (stdout): {hookSpecificOutput:{additionalContext}} либо пусто
# Exit:  always 0.

set -uo pipefail

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
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(cat); [ -n "$INPUT" ] || exit 0
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
is_git_commit "$COMMAND" || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/.claude-docs/dep-index.tsv" ] || exit 0
INDEXER="${DEP_INDEX_TOOL:-$ROOT/scripts/dep-index.py}"
[ -f "$INDEXER" ] || exit 0

# Нулевой разделитель на всём пути: `xargs` без `-0` делит имя по ПРОБЕЛУ, и файл
# «hooks/data lib.sh» приходит в индексатор двумя кусками — свой документ не назван, зато
# объявлен новым механизмом несуществующий «lib.sh». Поймано противником 28 августа 2026;
# в дереве путей с пробелом сейчас ноль, но запрета на них нет.
# `git commit -am` кладёт файлы в индекс только В МОМЕНТ коммита: до него `--cached` пуст,
# и страж молчал целиком. Поэтому берётся объединение индекса и рабочего дерева — так же
# делают соседние хуки того же события (`changelog-reminder`, `docs-family-check`).
# Поймано противником 28 августа 2026.
STAGED=$( { git -C "$ROOT" diff --cached --name-only -z 2>/dev/null;
            git -C "$ROOT" diff --name-only -z 2>/dev/null; } | tr '\0' '\n' | sort -u)
[ -n "$STAGED" ] || exit 0

# Троттл по СОДЕРЖИМОМУ правки, а не по набору имён. Ключ из одних имён глушил стража
# на весь остаток сессии после первого же коммита того же файла: правка комментария
# съедала право высказаться про следующую правку, добавившую публичное имя. При дисциплине
# «одно изменение — один коммит» набор имён повторяется постоянно. Поймано противником
# 28 августа 2026.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
KEY=$( { git -C "$ROOT" diff --cached 2>/dev/null; git -C "$ROOT" diff 2>/dev/null; } \
    | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/doc-impact-${SID}.txt"
if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi

REPORT=$(cd "$ROOT" && printf '%s' "$STAGED" | tr '\n' '\0' \
    | xargs -0 python3 "$INDEXER" --impact 2>/dev/null)
[ -n "$REPORT" ] || exit 0

printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null

# ── Документ СОСТОЯНИЯ и изменение ПОВЕДЕНИЯ (D209) ───────────────────────────
# Требование обновить документ состояния было привязано к бампу версии
# (`docs-family-check`) либо к появлению нового модуля (`module-doc-check`). Изменение
# поведения существующего механизма не требовало ничего — поэтому модульный док
# обновлялся исправно (у него есть страж), а `docs/architecture.md` и `docs/decisions.md`
# отставали. Замер 29 августа 2026: раздел архитектуры про контур разбора говорил «поводов
# семь» при фактических восьми, а правило лестницы эскалации жило в трёх местах и не имело
# ADR. Нашёл это владелец вопросом, а не механизм.
#
# ПОВЕДЕНИЕ ОТЛИЧАЕТСЯ ОТ КОСМЕТИКИ МАШИННО: в diff остаются строки, не являющиеся
# комментарием и не пустые. Починка опечатки в комментарии документ состояния не трогает —
# и требовать за неё решение значило бы сделать стража фоном.
STATE_DOCS="${DOC_STATE_LIST:-docs/architecture.md docs/decisions.md PLAN.md README.md README.ru.md CLAUDE.md}"

_behaviour_changed() {
    _bc=$( { git -C "$ROOT" diff --cached -U0 -- '*.sh' '*.py' 2>/dev/null;
             git -C "$ROOT" diff -U0 -- '*.sh' '*.py' 2>/dev/null; } \
           | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
           | sed -E 's/^[+-][[:space:]]*//' \
           | grep -vE '^#' | grep -vE '^$' | head -1)
    [ -n "$_bc" ]
}

DECIDED=0
# Решение наблюдаемо двумя способами: документ состояния в этом же коммите ЛИБО явная
# отметка в сообщении коммита. Второе нужно, потому что «не задето» — законный исход, и
# без наблюдаемого следа он неотличим от «забыл».
grep -qE 'doc-state:' <<< "$COMMAND" && DECIDED=1

PENDING=""
if [ "$DECIDED" -eq 0 ] && _behaviour_changed; then
    for _d in $STATE_DOCS; do
        grep -qxF "$_d" <<< "$STAGED" && { DECIDED=1; break; }
        grep -qF "$_d" <<< "$REPORT" && PENDING="$PENDING $_d"
    done
fi

# Журнал решений — знаменатель для замера: сколько правок поведения прошло с решением и
# сколько без. Без него «страж сказал» и «страж помог» опять были бы одним утверждением.
if _behaviour_changed && [ -n "${REPORT// /}" ]; then
    _st=$([ "$DECIDED" -eq 1 ] && printf 'decided' || printf 'undecided')
    jq -cn --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg s "$_st" \
           --arg d "$(printf '%s' "${PENDING# }" | tr ' ' ',')" \
        '{ts:$ts, status:$s, docs:$d}' >> "$STATE_DIR/doc-state-${SID}.jsonl" 2>/dev/null || true
fi

MSG="📗 Влияние на документацию — из индекса зависимостей, а не обходом дерева:
${REPORT}

Правило: изменил механизм — реши, задело ли это его описания и описания зависимых,
и обнови их В ЭТОМ ЖЕ коммите. Ничего не задело — так и скажи в ответе, это тоже исход.
Пересобрать индекс после правки: python3 scripts/dep-index.py --changed <файлы>"

if [ -n "${PENDING// /}" ]; then
    MSG="$MSG

📘 Поведение механизма изменилось, а документ СОСТОЯНИЯ его описывает и не тронут:${PENDING}
Документ состояния отвечает на вопрос «как есть сейчас», и правка поведения делает его
ответ неверным — в отличие от правки комментария, за которую здесь не спрашивают.
Реши наблюдаемо, БЕЗ ожидания разрешения:
  · задело → добавь документ в этот же коммит;
  · не задело → допиши в сообщение коммита \`doc-state: не задето — <почему>\`."
fi

jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
