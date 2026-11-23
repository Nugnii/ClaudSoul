#!/usr/bin/env bash
# module-context-inject.sh — PreToolUse[Edit|Write|MultiEdit]: при правке файла подаёт модуль документации, который его описывает, заголовки его бизнес-правил и напоминание обновить модуль тем же коммитом; файл, не описанный ни одним модулем, называет отдельно.
# en: PreToolUse[Edit|Write|MultiEdit] — on a file edit, injects the documentation module that describes it, the headings of its business rules and a reminder to update the module in the same commit; a file no module describes is named as such.
#
# Зачем. Правила проекта грузятся агенту целиком каждую сессию, а модули (детальная
# документация, 850 КБ в ProjectA) — только если агент сам догадается открыть нужный.
# Отсюда двойная беда: файл правил пухнет, потому что в него тащат то, что «иначе не
# прочитают», а модуль при этом лежит непрочитанным. Замер ProjectA 2026-09-01: §4 CLAUDE.md
# был 80 КБ при 65 модулях на 850 КБ; 96 выносок из 109 пересказывали свой же модуль.
#
# Источник — `.claude-docs/module-index.md` (генерирует scripts/module-index.py):
# карта «файл → модули», построенная ИЗ КОДА. Нет индекса — хук молчит.
#
# Input  (stdin): {tool_name, tool_input:{file_path}, session_id, cwd} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).
# bash-путь: не нужен — в этом дереве страж нем по построению: `.claude-docs/module-index.md`
# нет, генератора `scripts/module-index.py` нет, и гейт `[ -f "$INDEX" ] || exit 0` закрывает
# его на любом входе (замер 13 сентября 2026: 0 срабатываний на любой сессии). УСЛОВИЕ СНЯТИЯ:
# появится индекс модулей — вписать в список `hooks/bash-write-dispatch.sh`, подача задним
# числом там осмысленна («обнови модуль тем же коммитом»).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat); [ -z "$INPUT" ] && exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -n "$FILE" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
INDEX="$ROOT/.claude-docs/module-index.md"
[ -f "$INDEX" ] || exit 0

# Путь относительно корня репозитория — в индексе он записан так. Обе стороны сначала
# нормализуются `pwd -P`: на macOS каталог из mktemp приходит как /var/..., а git отдаёт
# /private/var/... — тот же каталог через симлинк. Без нормализации префикс не совпадал,
# REL оставался абсолютным, grep не находил ничего, и хук МОЛЧАЛ на живом файле.
FDIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P) || FDIR=""
[ -n "$FDIR" ] && FILE="$FDIR/$(basename "$FILE")"
ROOT_P=$(cd "$ROOT" 2>/dev/null && pwd -P) || ROOT_P="$ROOT"
case "$FILE" in "$ROOT_P"/*) REL="${FILE#"$ROOT_P"/}" ;; "$ROOT"/*) REL="${FILE#"$ROOT"/}" ;; *) REL="$FILE" ;; esac
# Документацию документации не комментируем.
case "$REL" in .claude-docs/*|*.md) exit 0 ;; esac

LINE=$(grep -F -- "\`$REL\` → " "$INDEX" 2>/dev/null | head -1)
[ -n "$LINE" ] || exit 0

# Throttle: один инжект на файл за сессию — подсказка нужна перед первой правкой.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
FKEY=$(printf '%s' "$REL" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
# ФЛАГ/ДРОССЕЛЬ ГЕЙТИТ ДОСТАВКУ, а доставка идёт по АКТОРУ (D457, класс D463, 18 сентября
# 2026): «ЭТОМУ вызывающему уже показали». Без суффикса первый сработавший гасит инжект всем
# остальным, и владелец не видит того, что показали субагенту.
# Владелец суффикса один — `resolve_actor_suffix` (`paths-lib.sh`); у родителя он даёт ПУСТО,
# и имена его файлов остаются прежними.
_MCI_PATHS="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "${_MCI_PATHS}" ] || _MCI_PATHS="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "${_MCI_PATHS}" ] && . "${_MCI_PATHS}"
_MCI_ACTOR=""
command -v resolve_actor_suffix >/dev/null 2>&1 && _MCI_ACTOR=$(resolve_actor_suffix "$INPUT")
THROTTLE="$STATE_DIR/module-ctx-${SID}${_MCI_ACTOR}-${FKEY}.flag"
[ -f "$THROTTLE" ] && exit 0
: > "$THROTTLE" 2>/dev/null

MODS=$(printf '%s' "$LINE" | grep -oE '\[[a-z0-9-]+\]\(modules/' | sed 's/^\[//; s/\](modules\///' | tr '\n' ' ')

if [ -z "$MODS" ] || [[ $MODS != *[!\ ]* ]]; then
    MSG="📘 Правишь \`$REL\` — его не описывает НИ ОДИН модуль (.claude-docs/module-index.md). Если правка вводит правило или ловушку, ей негде жить, кроме кода: заведи описание в подходящем модуле либо новый модуль по формату §8.2."
else
    # ГЛАВНЫЙ модуль — тот, у кого файл стоит в разделе «## Файлы»: это описание, а не
    # попутное упоминание. У balance-service.ts упоминаний восемь, и подать все — то же
    # самое, что не подать ни одного: главное тонет.
    PRIMARY=""; SECOND=""
    for m in $MODS; do
        f="$ROOT/.claude-docs/modules/$m.md"
        [ -f "$f" ] || continue
        # `grep -q` закрывает пайп на первом совпадении, awk получает SIGPIPE, и под
        # `pipefail` статус пайплайна становится 141 — известный класс проекта
        # (test_assert_no_sigpipe). Блок читается целиком, поиск идёт по строке.
        _files_block=$(awk '/^##[[:space:]]*Файлы/{f=1;next} /^## /{f=0} f' "$f" 2>/dev/null)
        if grep -qF -- "$REL" <<< "$_files_block"; then
            PRIMARY="${PRIMARY}${PRIMARY:+ }${m}"
        else
            SECOND="${SECOND}${SECOND:+ }${m}"
        fi
    done
    [ -z "$PRIMARY" ] && { PRIMARY=$(printf '%s' "$MODS" | awk '{print $1}'); SECOND=$(printf '%s' "$MODS" | cut -d" " -f2-); }

    # Правила — только из главных модулей и только ЗАГОЛОВКИ пунктов: жирный текст внутри
    # абзаца даёт обрывки вида «знаковую «Корректировка»», по которым ничего не понять.
    RULES=""
    for m in $PRIMARY; do
        f="$ROOT/.claude-docs/modules/$m.md"
        [ -f "$f" ] || continue
        # Заголовок ищется АЛЬТЕРНАЦИЕЙ, а не скобкой `[Бб]`: mawk (умолчание Debian и Ubuntu)
        # сравнивает байты, и скобка с двухбайтовой буквой совпадает с одним байтом из неё —
        # раздел не находился, и хук молча не подавал правил. Поймано 12 сентября 2026 замером
        # чистой рамки (D404); на gawk и BWK awk обе записи равносильны.
        r=$(awk '/^##[[:space:]]*(Ключевые[[:space:]]+)?(Б|б)изнес-правила/{f=1;next} /^## /{f=0} f' "$f" 2>/dev/null \
            | grep -oE '^[-*[:space:]]*[0-9]*\.?[[:space:]]*\*\*[^*]{6,70}\*\*' \
            | sed -E 's/^[-*0-9.[:space:]]*\*\*//; s/\*\*$//; s/[:;,.[:space:]]+$//' \
            | head -4 | paste -sd ' · ' -)
        [ -n "$r" ] && RULES="${RULES}${RULES:+ | }${m}: ${r}"
    done

    MSG="📘 Правишь \`$REL\` — он описан в модуле: ${PRIMARY}."
    [ -n "$SECOND" ] && MSG="${MSG} Задет также в: $(printf '%s' "$SECOND" | tr ' ' ',' | sed 's/,/, /g')."
    MSG="${MSG} Прочти ПЕРЕД правкой: там инварианты, которые в CLAUDE.md сжаты до одной строки."
    [ -n "$RULES" ] && MSG="${MSG} Правила модуля: ${RULES:0:400}"
    MSG="${MSG} Меняешь поведение — обнови модуль тем же коммитом (§8.4)."
fi

jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
