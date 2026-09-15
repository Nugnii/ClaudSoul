#!/usr/bin/env bash
# impact-inject.sh — PreToolUse[Edit|Write|MultiEdit] и PostToolUse[Bash]: при правке файла ЛЮБЫМ путём подаёт ПОЛНЫЙ ПУТЬ по карте связей — кто на этом файле стоит (тесты, документы, знания, пункты долга, рода, корни) и на скольких стоит он сам; новый файл вносит в карту и говорит об этом, а если он попал в СЧИТАЕМОЕ множество (хуки, библиотеки, тесты, скиллы, домены, мосты) — называет сдвиг чисел документов и команду пересчёта; рядом называет, чем проверить после сохранения.
# en: PreToolUse[Edit|Write|MultiEdit] and PostToolUse[Bash] — on a file edit made by ANY route, injects the FULL dependency path from the project map: who stands on this file (tests, docs, knowledge, backlog items, defect genera, roots) and how many it stands on itself; a new file is entered into the map and said so, and if it lands in a COUNTED set (hooks, libraries, tests, skills, domains, bridges) the shifted document numbers are named together with the recount command; alongside, names what to run after saving.
#
# Зачем. Потребитель карты назван владельцем 13 сентября 2026: «потребитель карты — ты,
# когда редактируешь файл, ты смотришь на карту, что ещё зависит; когда сохранил —
# смотришь, не поломал ли чего». Оставить карту командой, которую агент должен ВСПОМНИТЬ,
# нельзя: замер той же сессии — правила с механизмом исполнялись 7 раз из 7, правила
# текстом нарушены трижды (case-2026-09-13-mechanized-rules-held-text-rules-did-not).
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. `module-context-inject.sh` на том же событии подаёт МОДУЛЬ
# ДОКУМЕНТАЦИИ, описывающий файл, — предшественник остаётся, предметы разные: там «что
# про этот файл написано», здесь «что на нём стоит». `doc-impact-check.sh` и
# `dep-index.py --impact` отвечают на вопрос о документах ПОСЛЕ правки, в момент коммита;
# здесь ответ нужен ДО неё и шире документов. Вторая половина слова владельца («не
# поломал ли») владельца уже имеет — выбор тестов по изменённым файлам в
# `hooks/tests/run_all.sh --changed`; хук его НАЗЫВАЕТ, а не повторяет.
#
# ЦЕНА. Сборка карты стоит 54 с — в ходе правки это неприемлемо, поэтому прибор зовётся
# с `PROJECT_GRAPH_NO_BUILD=1`: ответ только из кэша (0,05 с), а устаревший кэш даёт
# код 3, и тогда хук один раз за сессию говорит, чем пересобрать. Решение о свежести
# принимает ПРИБОР, здесь его копии нет (род K — копия правила у потребителя).
#
# Input  (stdin): {tool_name, tool_input:{file_path}, session_id, cwd} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat); [ -z "$INPUT" ] && exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)
case "$TOOL" in Edit|Write|MultiEdit|Bash) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
# ПРАВКА ИДЁТ НЕ ТОЛЬКО ИНСТРУМЕНТОМ EDIT (13 сентября 2026). Замер того дня: за сессию
# правлено 11 файлов кода, через карту прошло НОЛЬ — все правки шли командой Bash
# (`python3 - <<PY`, `sed -i`, перенаправление), а хук стоял на Edit|Write|MultiEdit.
# Признак не задевал реальный поток работы, и механизм был мнимым при зелёных тестах.
# Поэтому на Bash предмет берётся не из аргументов команды (там путь бывает собран из
# переменных и не виден), а у ГИТА: что в дереве стало изменённым или новым.
[ -n "$FILE" ] || [ "$TOOL" = "Bash" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

# ТРИ СОСТОЯНИЯ ПРИБОРА. «Инструмента здесь нет» — другой проект, молчим.
TOOL_PY="$ROOT/scripts/project-graph.py"
[ -f "$TOOL_PY" ] || exit 0

if [ "$TOOL" = "Bash" ]; then
    # Тишина, если изменённых нет. Каждый файл говорит ОДИН раз за сессию (дедуп ниже),
    # поэтому перечень уже правленных не гремит на каждой команде.
    SID_B=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
    CHANGED=$( { git -C "$ROOT" diff --name-only HEAD 2>/dev/null
                 git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null; } | sort -u )
    [ -n "$CHANGED" ] || exit 0
    LINES=""; SHOWN=0; REST=0
    while IFS= read -r _rel; do
        [ -n "$_rel" ] || continue
        case "$_rel" in *.sh|*.py|*.md) ;; *) continue ;; esac
        _fk=$(printf '%s' "$_rel" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
        _flag="$STATE_DIR/impact-inject-${SID_B}-${_fk}.flag"
        [ -f "$_flag" ] && continue
        if [ "$SHOWN" -ge 3 ]; then REST=$((REST+1)); continue; fi
        : > "$_flag" 2>/dev/null
        _out=$(cd "$ROOT" && PROJECT_GRAPH_NO_BUILD=1 python3 "$TOOL_PY" --node "$_rel" --brief 2>/dev/null)
        if [ -z "$_out" ]; then
            # Узла нет — файл НОВЫЙ. Вносим его в карту сразу: «при создании новое должно
            # попадать в карту» (слово владельца). Входящие рёбра появятся на --refresh.
            _add=$(cd "$ROOT" && python3 "$TOOL_PY" --touch "$_rel" 2>/dev/null)
            # НОВЫЙ ФАЙЛ В СЧИТАЕМОМ МНОЖЕСТВЕ УЖЕ СДВИНУЛ ЧИСЛА ДОКУМЕНТОВ. Карта про это
            # молчит по построению: входящие рёбра появятся лишь на `--refresh`, а числа
            # живут не в ней, а в реестре `scripts/doc-claims.tsv`. Множества берутся у
            # ВЛАДЕЛЬЦА счёта (`scripts/count-stats.sh:19-25`), а не перечисляются заново.
            # Полного сверщика здесь не зовём: он идёт 48 секунд, а на границе записи это
            # неприемлемо — совпадения пути довольно, потому что новый файл такого вида
            # меняет счёт ПО ПОСТРОЕНИЮ. Повод измерен 14 сентября 2026: за день я создал
            # шесть таких файлов и ни разу не пересчитал числа — `test_derived_counts_inventory`
            # покраснел в ТРЁХ полных прогонах подряд, это около 36 минут прогонов, законченных
            # красным из-за команды, которая идёт две секунды.
            # НОВИЗНА СПРАШИВАЕТСЯ У МИРА, А НЕ У КАРТЫ (поправка 14 сентября 2026, в день
            # заведения ветки). Первая редакция считала новым всякий файл, которого НЕТ В
            # КАРТЕ, — а карта пересобирается лишь по `--refresh`, поэтому «новым» выглядел
            # любой давно не правленный файл. Ложная тревога поймана на себе в тот же день:
            # `doc-impact-check.sh` заведён 28 августа, хуков как было 82, так и осталось, а
            # ветка велела пересчитывать СЕЙЧАС. Точность была 2 из 3, и цена ложного — не
            # только лишний прогон, но и привычка не читать этот канал.
            # Признак теперь ровно тот, о котором утверждение: файл НЕ ОТСЛЕЖИВАЕТСЯ git,
            # значит он в мире новый и счёт множества сдвинут по построению. Один вызов
            # `ls-files`, около 10 мс; `count-stats.sh` (0,67 с) звать незачем, а полный
            # сверщик утверждений — тем более: 48 секунд принадлежат ему, не счётчику.
            # НАЗВАННЫЙ ПРЕДЕЛ: файл, заведённый и закоммиченный ДРУГОЙ сессией без
            # пересчёта, этой веткой не назван — он уже отслеживается. Там владелец пересчёта
            # чужой, а страж класса свой: `test_derived_counts_inventory` в наборе.
            # Условие снятия: ветка станет сверять СЧЁТ, а не новизну — `count-stats.sh`
            # по одному множеству идёт 0,67 с, и сравнение его числа с утверждением
            # документа назовёт и чужой файл. Сейчас не сделано по НАЗВАННОЙ причине:
            # владелец утверждения — реестр `scripts/doc-claims.tsv`, и чтение его отсюда
            # завело бы ВТОРОГО владельца одного факта (корень R1). Предел уйдёт, когда у
            # реестра появится режим «дай число по имени множества» — тогда звать станет кого.
            _cnt=""
            if git -C "$ROOT" ls-files --error-unmatch -- "$_rel" >/dev/null 2>&1; then
                :
            else
            case "$_rel" in
                hooks/tests/test_*.sh) _cnt="файлов тестов хуков" ;;
                hooks/*-lib.sh)        _cnt="библиотек" ;;
                hooks/*.sh)            _cnt="активных хуков" ;;
                skills/*/SKILL.md)     _cnt="скиллов" ;;
                domains/*.md)          _cnt="доменов" ;;
                bridges/L*.md)         _cnt="мостов" ;;
                mcp-server/tests/test_*.py) _cnt="тестов MCP" ;;
            esac
            fi
            LINES="${LINES}
  · ${_rel} — в карте его не было, внесён (${_add:-новый узел}); кто на нём стоит, станет видно после \`project-graph.py --refresh\`"
            [ -n "$_cnt" ] && LINES="${LINES}
    ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ (${_cnt}): пересчитай СЕЙЧАС, иначе набор покраснеет —
    \`bash scripts/count-stats.sh --patch-claude-md\` и \`bash scripts/docs-refresh-claims.sh\`"
        else
            LINES="${LINES}
  · ${_rel} — ${_out}"
        fi
        SHOWN=$((SHOWN+1))
    done <<< "$CHANGED"
    [ -n "$LINES" ] || exit 0
    MSG_B="🗺 Тронуты файлы — связи по карте:${LINES}"
    [ "$REST" -gt 0 ] && MSG_B="${MSG_B}
  · и ещё ${REST} файл(ов) в этом ходу — полный путь: \`python3 scripts/project-graph.py --node <путь>\`"
    MSG_B="${MSG_B}
Сломанное здесь вылезет там: пройди названные документы и прогони \`bash hooks/tests/run_all.sh --changed\`."
    jq -cn --arg m "$MSG_B" --arg e "${EVENT:-PostToolUse}" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
    exit 0
fi

# Путь относительно корня; обе стороны нормализуются pwd -P (macOS отдаёт /var против /private/var).
FDIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P) || FDIR=""
[ -n "$FDIR" ] && FILE="$FDIR/$(basename "$FILE")"
ROOT_P=$(cd "$ROOT" 2>/dev/null && pwd -P) || ROOT_P="$ROOT"
case "$FILE" in "$ROOT_P"/*) REL="${FILE#"$ROOT_P"/}" ;; "$ROOT"/*) REL="${FILE#"$ROOT"/}" ;; *) exit 0 ;; esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
FKEY=$(printf '%s' "$REL" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/impact-inject-${SID}-${FKEY}.flag"
[ -f "$THROTTLE" ] && exit 0

OUT=$(cd "$ROOT" && PROJECT_GRAPH_NO_BUILD=1 python3 "$TOOL_PY" --node "$REL" --brief 2>/dev/null)
RC=$?

if [ "$RC" = "3" ]; then
    # Кэш стар: это НЕ поломка и НЕ «чисто». Говорим один раз за сессию, не на каждый файл.
    STALE="$STATE_DIR/impact-inject-stale-${SID}.flag"
    [ -f "$STALE" ] && exit 0
    : > "$STALE" 2>/dev/null
    jq -cn --arg m "🗺 Карта связей устарела (учёт новее кэша) — полный путь по файлу сейчас не показать. Пересобрать: \`python3 scripts/project-graph.py --refresh\` (около минуты, можно фоном)." \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    exit 0
fi

: > "$THROTTLE" 2>/dev/null

if [ "$RC" != "0" ]; then
    jq -cn --arg m "🗺 Карта связей: BROKEN — \`scripts/project-graph.py\` вернул код $RC. Молчание тут читалось бы как «зависимостей нет», а это не проверено." \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    exit 0
fi

# Узла в карте нет (новый файл) — законная тишина, не находка.
[ -n "$OUT" ] || exit 0

MSG="🗺 Правишь \`$REL\` — по карте связей ${OUT}. Смотри ПЕРЕД правкой, что на нём стоит: сломанное здесь вылезет там. После сохранения — \`bash hooks/tests/run_all.sh --changed\`: выбор тестов идёт по этим же рёбрам. Полный путь: \`python3 scripts/project-graph.py --node $REL\`."

jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
