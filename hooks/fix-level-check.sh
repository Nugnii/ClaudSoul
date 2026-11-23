#!/usr/bin/env bash
# fix-level-check.sh — детектор пост-инцидентного фикса, оставшегося текстом.
# en: detects post-incident text-rule fixes in the agent's own reply and reminds to lift them to a mechanism (activator/blocker)
#
# Заявка на эскалацию pattern-inside-out-blindness (открыта 2026-04-23, закрыта
# этим хуком): 15-е проявление (case-2026-04-23-text-rule-vs-mechanism) показало,
# что blocker-tier сигналы знания не ловят сам момент, когда агент после инцидента
# предлагает ФИКС УРОВНЯ 1 — текстовое правило, обещание «буду внимательнее» —
# вместо механизма (уровни embedded-ness: см. principle-knowledge-in-the-world).
#
# Словарь НЕ придуман (урок v1.13.3: придуманный словарь — девять срабатываний за
# 214 сессий и ноль на реальных поправках). Фразы взяты из задокументированных
# проявлений:
#   - case-2026-04-23-model-vs-system-source-blindness: «надо вынести урок»,
#     «не хватает жёсткого чеклиста», и жанровый ряд оттуда же: ретро → «нужен
#     чеклист», post-mortem → «будем осторожнее», ошибка → «учту на будущее»
#   - правило Source-check (rules/CLAUDE.md v0.3): «надо X / будем осторожнее /
#     учту» — маркеры модельной пост-инцидентной фразы
#
# Механика — как у output-language-check.sh (уровень 2, activator injection):
#   - Stop / PreCompact: скан последнего ответа агента, находки → state (pending)
#   - UserPromptSubmit / PreToolUse: инжект напоминания, pending → surfaced
#
# Подавление: если в том же ответе назван механизм (хук, скрипт, тест, детектор,
# blocker, инжект) или стоит пометка model-generated — фикс уже не текстовый
# (или источник уже размечен), молчим. Сознательное ограничение: фразы внутри
# кода/цитат не отличаются от прозы — принято, инжект советующий, не блокирующий.
#
# Silent degradation: нет jq / расшифровки / session_id — exit 0 без вывода.

set -eo pipefail

HOOK_NAME="fix-level-check"
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# Окно текущего хода (D498): последний ответ ищется в расшифровке от последней реплики
# владельца, а не во всей сессии. Библиотеки нет — окно вырождается в файл целиком.
INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hook-input-lib.sh}"
[ -f "$INPUT_LIB" ] || INPUT_LIB="$HOME/.claude/hooks/hook-input-lib.sh"
# shellcheck source=/dev/null
if [ -f "$INPUT_LIB" ]; then . "$INPUT_LIB"; fi
# Общий замок и правка под ним (род H): очередь висящих записей общая на сессию.
STATE_LOCK_LIB="${STATE_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/state-lock-lib.sh}"
[ -f "$STATE_LOCK_LIB" ] || STATE_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
if [ -f "$STATE_LOCK_LIB" ]; then . "$STATE_LOCK_LIB"; fi
mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || exit 0

# portable-lib: to_lower (кириллица), pad_words. Порядок поиска: рядом с собой,
# потом установленный каталог — обратный порядок выключил бы хук на чистой машине.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib in "$HOOK_DIR/portable-lib.sh" "$HOME/.claude/hooks/portable-lib.sh"; do
    [ -f "$lib" ] && { . "$lib"; break; }
done
command -v to_lower >/dev/null 2>&1 || exit 0

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$SID" ] && exit 0
PENDING_FILE="${STATE_DIR}/fix-level-${SID}.jsonl"

# Фразы-маркеры текстового фикса. Каждая — из задокументированного проявления
# (см. шапку), сравнение по нормализованному нижнему регистру с границами слов.
FIX_PHRASES=(
    "надо вынести урок"
    "не хватает чеклиста"
    "не хватает жёсткого чеклиста"
    "нужен чеклист"
    "надо чеклист"
    "будем осторожнее"
    "будем аккуратнее"
    "буду внимательнее"
    "буду осторожнее"
    "буду аккуратнее"
    "учту на будущее"
    "запомню на будущее"
    "надо запомнить"
    "запишу правило"
    "добавлю правило"
)

# Маркеры механизма/разметки: подстрочное совпадение, ловит словоформы.
MECHANISM_MARKERS=("хук" "hook" "скрипт" "детектор" "инжект" "blocker" "detection_signal" "механизм" "тест" "model-generated")

scan_and_persist() {
    [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || return 0

    # Ход берётся из окна хода библиотеки ввода (D1153). Помощника `transcript_turn_window` нет (файла библиотеки нет) —
    # не судить: окном был бы весь файл, и находки прошлых ходов судились бы заново. У старой редакции помощник есть и
    # окно начинается с последней реплики владельца: без ядра `HIL_TURN_USER_JQ` его запасное `false` оставляет окно
    # одним ходом — текущим (скептик, третий круг, M1: охрана по ядру глушила этот верный суд).
    command -v transcript_turn_window >/dev/null 2>&1 || return 0
    local last_assistant lam
    # Итог из поля входа Stop достраивает окно, если файл расшифровки его не догнал (D1210, `with_final` библиотеки ввода).
    lam=$(command -v transcript_final_text >/dev/null 2>&1 && transcript_final_text "$INPUT") || lam=""
    last_assistant=$(transcript_turn_window "$TRANSCRIPT_PATH" wide | jq -s --arg lam "$lam" "${HIL_TURN_USER_JQ:-def turn_user: false;}${HIL_WITH_FINAL_JQ:-def with_final(l): .;}"'
        def role(x): x.message.role // x.role // "";
        def get_text(x):
            (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then
                ($c | map(select(.type == "text") | .text) | join("\n"))
            elif ($c | type) == "string" then $c
            else "" end;
        with_final($lam) | . as $items | (length) as $n |
        ([range(0; $n) | ($n - 1 - .)
          | select($items[.] | turn_user)]
          | first) as $pu |
        if $pu == null then
            ([range(0; $n) | $items[.] | select(role(.) == "assistant")]
             | map(get_text(.)) | map(select(. != "")) | join("\n"))
        else
            ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]
             | map(get_text(.)) | map(select(. != "")) | join("\n"))
        end
    ' 2>/dev/null | jq -r '.' 2>/dev/null)

    [ -z "$last_assistant" ] && return 0
    [ "$last_assistant" = "null" ] && return 0

    local lower padded
    lower=$(to_lower "$last_assistant")
    padded=$(pad_words "$lower")

    # Глушитель применяется к ПРЕДЛОЖЕНИЮ, где стоит фраза, а не ко всему ответу.
    # Замер 29 августа 2026 реплеем по корпусу (`scripts/fix-level-replay.py`): на 15005
    # блоках речи словарь совпал 6 раз, и 4 из них (66%) гасил маркер механизма, стоявший
    # ГДЕ-ТО в ответе. В проекте про хуки слова «хук», «тест», «скрипт» есть почти в каждом
    # ответе — глушитель по всему тексту выключал признак почти всегда, независимо от того,
    # назван ли механизм для ЭТОЙ фразы. Предмет глушения — та фраза, что сработала, а не
    # соседний абзац про другое.
    # Предложение берётся из ИСХОДНОГО текста, не из padded: `pad_words` разделяет слова
    # по небуквенным символам, и маркер с дефисом («model-generated») в padded распадается
    # надвое — глушитель перестаёт его видеть. Поймано собственным тестом T8 при первой же
    # правке: предмет глушения был взят из строки, удобной для поиска ФРАЗЫ, а не из той,
    # где живут МАРКЕРЫ.
    # Внутри предложения ищется ПОДСТРОКА, без нормализации границ: класс `[:alnum:]`
    # кириллицу не покрывает (C-локаль), и нормализация стирала русскую фразу целиком —
    # глушитель тогда не находил ни одного предложения и переставал глушить вовсе.
    # Границы слов уже проверены снаружи, на `padded`; здесь нужен только контекст.
    _sentence_of() {   # <исходный lower> <фраза> → предложение, содержащее фразу
        printf '%s' "$1" | awk -v p="$2" '
            { n = split($0, s, /[.!?\n]/)
              for (i = 1; i <= n; i++) if (index(s[i], p) > 0) print s[i] }'
    }

    # --- Второй словарь (D231): речевые признаки нарушения КОНКРЕТНЫХ знаний ---
    # Знание с полем outcome_signals (knowledge/META.md) выражает, как его нарушение
    # звучит в речи агента, — единственный выразимый род признака для знаний о суждении
    # (в момент вызова инструмента они inexpressible). Словарь грузится здесь, а не при
    # старте: scan_and_persist работает только на Stop/PreCompact — редких событиях.
    # Формат кэш-строк: "имя-знания<TAB>фраза".
    #
    # ПОТОЛОК СТОИТ НА ВЫВОДЕ, А НЕ НА СЛОВАРЕ (13 сентября 2026). До этой правки здесь
    # висел `awk 'NR<=30'` с пояснением «инжект ограничен» — но обрезал он СЛОВАРЬ, то есть
    # распознавание: пары идут в порядке глоба (паттерны, принципы, кейсы), и всё за
    # тридцатой строкой не существовало для стража вовсе. Замер дня правки: пар в базе 78,
    # доезжало 30, отрезано 48 — среди них ВСЕ кейсы, записанные в тот день, и то знание,
    # которое утром на агенте сработало: добавление новых фраз молча выключило работавший
    # признак. Предмет ограничения («сообщение не должно раздуться») и объект, к которому
    # оно приложено (что вообще видно), разошлись — род L реестра дефектов.
    # Цена снятия измерена: словарь и так читается по всей базе, 0,03 с на 561 файле.
    local os_dict=""
    local lessons_dir="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
    if [ -d "$lessons_dir" ]; then
        # 2>/dev/null + || true: несовпавший глоб уходит в grep литералом, grep отвечает
        # кодом 2, и под set -eo pipefail подстановка убила бы весь скан (класс D225).
        # КЕЙСЫ ЧИТАЮТСЯ ТОЖЕ (13 сентября 2026). Поле объявлено в общем разделе
        # метаданных knowledge/META.md, то есть у ЛЮБОГО типа знания, а читатель брал два
        # типа из трёх. Замер в день правки: поле стоит у 5 паттернов (18 фраз) и у
        # 13 КЕЙСОВ, из которых механизм не видел ни одного, и молчание было неотличимо
        # от отсутствия нарушений. Цена чтения всей базы измерена: 0,03 с на 561 файле.
        # ПОРЯДОК ГЛОБА ЗНАЧИМ: паттерны и принципы идут ПЕРВЫМИ, потому что потолок в
        # 30 фраз ниже режет хвост — при переполнении усечётся кейсовый, а не тот, что
        # подтверждён многократно.
        os_dict=$(grep -l '^outcome_signals:' "$lessons_dir"/pattern-*.md \
                  "$lessons_dir"/principle-*.md "$lessons_dir"/case-*.md 2>/dev/null | while IFS= read -r _kf; do
            awk -v name="$(basename "$_kf" .md)" '
                /^outcome_signals:/ { on = 1; next }
                on && /^[^ ]/ { exit }
                on && /^[[:space:]]*-[[:space:]]*"/ {
                    line = $0
                    sub(/^[[:space:]]*-[[:space:]]*"/, "", line)
                    sub(/"[[:space:]]*$/, "", line)
                    if (line != "") printf "%s\t%s\n", name, line
                }' "$_kf"
        done || true)
    fi
    if [ -n "$os_dict" ]; then
        local os_name os_phrase
        while IFS=$'\t' read -r os_name os_phrase; do
            [ -n "$os_phrase" ] || continue
            case "$padded" in
                *" $os_phrase "*)
                    if [ -f "$PENDING_FILE" ] && \
                       jq -e --arg p "$os_phrase" 'select(.phrase==$p)' "$PENDING_FILE" >/dev/null 2>&1; then
                        continue
                    fi
                    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$SID" \
                        --arg p "$os_phrase" --arg event "$EVENT" --arg k "$os_name" \
                        '{ts:$ts, sid:$sid, event:$event, phrase:$p, knowledge:$k,
                          class:"outcome_signal", status:"pending"}' \
                        >> "$PENDING_FILE" 2>/dev/null || true
                    ;;
            esac
        done <<EOF
$os_dict
EOF
    fi

    local ts phrase
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    for phrase in "${FIX_PHRASES[@]}"; do
        case "$padded" in
            *" $phrase "*)
                # Механизм назван в той же фразе — это не пост-инцидентная отписка, а план.
                _ctx=$(_sentence_of "$lower" "$phrase")
                _muffled=0
                for m in "${MECHANISM_MARKERS[@]}"; do
                    case "$_ctx" in *"$m"*) _muffled=1; break ;; esac
                done
                [ "$_muffled" -eq 1 ] && continue
                if [ -f "$PENDING_FILE" ] && \
                   jq -e --arg p "$phrase" 'select(.phrase==$p)' "$PENDING_FILE" >/dev/null 2>&1; then
                    continue
                fi
                jq -cn --arg ts "$ts" --arg sid "$SID" --arg p "$phrase" --arg event "$EVENT" \
                    '{ts:$ts, sid:$sid, event:$event, phrase:$p, status:"pending"}' \
                    >> "$PENDING_FILE" 2>/dev/null || true
                ;;
        esac
    done
}

surface_pending() {
    # ОЧЕРЕДЬ ПРИНАДЛЕЖИТ РОДИТЕЛЮ (D456). Находка — про речь основной сессии, а
    # `surface_pending` не только показывает, но и ГАСИТ: переводит `pending` в `surfaced`.
    # Вызов субагента приходит с тем же `session_id`, поэтому чужая находка расходовалась им
    # — показывалась не тому и пропадала для родителя безвозвратно. Признак актора берётся у
    # владельца (`resolve_actor_id`, `hooks/paths-lib.sh`); библиотеки нет — прежнее
    # поведение. Родитель покажет находку на своём следующем событии.
    if command -v resolve_actor_id >/dev/null 2>&1 && [ -n "$(resolve_actor_id "${INPUT:-}")" ]; then
        return 0
    fi
    local event_name="${1:-UserPromptSubmit}"
    [ -f "$PENDING_FILE" ] || return 0

    local pending
    # лимит внутри awk, не `| head`: head выходит раньше, awk/jq ловят SIGPIPE 141,
    # и под set -eo pipefail хук гибнет до инжекта (D239; идиом metrics-collector:395)
    pending=$(jq -r 'select(.status=="pending" and (.class // "") != "outcome_signal") | .phrase' \
              "$PENDING_FILE" 2>/dev/null | awk '!seen[$0]++ && n<5 {print; n++}')
    # Нарушения знаний (D231) — отдельный блок: у них есть адрес (имя знания) и свой
    # требуемый исход (сверить и записать через контур 4e), это не «подними уровень фикса».
    local os_pending os_all os_extra
    os_all=$(jq -r 'select(.status=="pending" and (.class // "") == "outcome_signal")
                    | "\(.knowledge // "?"): «\(.phrase)»"' "$PENDING_FILE" 2>/dev/null \
             | awk '!seen[$0]++')
    # `grep -c` на пустом входе отдаёт код 1, а файл идёт под `set -eo pipefail` (:31) —
    # без `|| true` пустой список находок рубил бы функцию целиком, и молчал бы ВЕСЬ хук,
    # включая соседний блок пост-инцидентных фраз. Поймано прогоном: 8 ног из 34 покраснели.
    os_pending=$(printf '%s\n' "$os_all" | grep -v '^[[:space:]]*$' | head -5 || true)
    _os_n=$(printf '%s\n' "$os_all" | grep -c '[^[:space:]]' || true)
    _os_k=$(printf '%s\n' "$os_pending" | grep -c '[^[:space:]]' || true)
    os_extra=$(( ${_os_n:-0} - ${_os_k:-0} ))
    [ -z "$pending" ] && [ -z "$os_pending" ] && return 0

    local msg=""
    if [ -n "$pending" ]; then
        local phrase_list
        phrase_list=$(printf '%s' "$pending" | awk 'BEGIN{ORS=""} NR>1{printf ", "} {printf "«%s»", $0}')
        msg="🧱 Fix-level check: в предыдущем ответе — ${phrase_list}. Это пост-инцидентный фикс уровня 1 (текст, который надо вспомнить). Source-check: назови механизм системы, породивший вывод, — либо явно пометь фразу как model-generated observation. Если фикс настоящий — подними до уровня 2 (activator injection) или 3 (blocker-tier hook), см. principle-knowledge-in-the-world; текстовое правило после инцидента — описание проблемы, не fix."
    fi
    if [ -n "$os_pending" ]; then
        local os_list
        os_list=$(printf '%s\n' "$os_pending" | awk 'BEGIN{ORS=""} NR>1{printf "; "} {printf "%s", $0}')
        # Остаток НАЗЫВАЕТСЯ числом: молчаливое усечение читается как «это всё», и находка
        # за пятой перестаёт существовать для читателя (13 сентября 2026).
        [ "${os_extra:-0}" -gt 0 ] 2>/dev/null && os_list="${os_list}; и ещё ${os_extra}"
        [ -n "$msg" ] && msg="${msg}
"
        msg="${msg}⛳ Outcome-signal: в предыдущем ответе — фраза-признак нарушения знания: ${os_list}. Сверь действие с этим знанием и запиши исход (контур 4e: confirmed / outdated / not_applicable / applicable_not_followed)."
    fi

    jq -cn --arg msg "$msg" --arg ev "$event_name" \
        '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $msg}}'

    atomic_filter "$PENDING_FILE" jq -c 'if .status=="pending" then .status="surfaced" else . end' || true
}

case "$EVENT" in
    Stop|PreCompact)
        scan_and_persist
        ;;
    UserPromptSubmit)
        surface_pending "UserPromptSubmit"
        ;;
    PreToolUse)
        surface_pending "PreToolUse"
        ;;
esac

exit 0
