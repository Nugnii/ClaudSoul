#!/usr/bin/env bash
# five-whys-gate.sh — PreToolUse: повтор замечен, а разбора причин не было — требует «5 почему».
# en: PreToolUse: a repeat signal fired but no why-chain was stated — demands the 5 Whys.
#
# Повод — три напоминания собеседника за три недели, дословно:
#   28.07: «3 раза делал одно и то же потому что не использовал 5 почему, хотя должен был
#           и раньше это делал»
#   29.07: «А ты задавал 5 почему по этому поводу? Ты должен если видишь повторяющиеся
#           признаки понять, что есть же причина всему этому»
#   21.08: «ты детектил дефект, а использовал ли 5 почему? давненько не видел»
#
# Третье напоминание об одном и том же — это не забывчивость, а отсутствующий механизм
# (principle-knowledge-in-the-world). Проверено при заведении: хука не было ни в
# репозитории, ни в регистрации настроек с 16.06, ни одним инжектом в транскриптах —
# все 23 вхождения фразы в транскриптах оказались эхом SESSION.md через session-registry.
# В глобальных правилах на месте разбора ошибок стоит «назови 2-3 версии причины»: это
# перебор ВШИРЬ (какие бывают причины), а «5 почему» — спуск ВГЛУБЬ по одной цепочке.
# Ширина закрывает ощущение глубины, и разбор считается сделанным.
#
# ПОЧЕМУ НЕ НОВЫЙ СЧЁТЧИК. Повторы уже считают двое: error-tracker (полоса провалов) и
# rework-detector (третий заход на тот же файл). Второй существует потому, что на той же
# реплике 28.07 собеседник заметил главное: «ошибкой может быть успех, и он не
# детектируется как ошибка = не подлежит проверке на 5 почему». Поэтому гейт слушает ОБА
# сигнала: и провал, и повторяющийся успех.
#
# ПОТОЛОК, названный честно. Произнесённость цепочки проверяется по тексту последних
# ответов — счётом «почему» и маркеров разбора. Это распознаёт форму, а не мысль: связный
# разбор без слова «почему» гейт не увидит и напомнит зря, а пять слов «почему» подряд
# без содержания сочтёт разбором. Дешёвая проверка выбрана намеренно: цена ложного
# напоминания — одна строка в контексте, цена пропуска — третий заход на тот же симптом.
#
# Input  (stdin): {session_id, tool_name, transcript_path} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} либо пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PATHS_LIB"
else
    : "${STATE_DIR:=$HOME/.claude/hooks/state}"
fi
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
    Edit|Write|MultiEdit|Bash) ;;
    *) exit 0 ;;
esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SID" ] || exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# ── Сигналы повтора: чужие детекторы, свой счётчик не заводится ───────────────
REWORK="$STATE/rework-fired-${SID}.jsonl"
STREAK="$STATE/error_streak_fired_${SID}"
SIGNALS=0
WHAT=""
if [ -f "$REWORK" ]; then
    _n=$(grep -c '' "$REWORK" 2>/dev/null || printf '0')
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    if [ "$_n" -gt 0 ]; then
        SIGNALS=$((SIGNALS + _n))
        WHAT="повторные заходы на один файл при зелёных прогонах"
    fi
fi
if [ -f "$STREAK" ]; then
    SIGNALS=$((SIGNALS + 1))
    if [ -n "$WHAT" ]; then WHAT="$WHAT и полоса упавших команд"
    else WHAT="полоса упавших команд"; fi
fi
[ "$SIGNALS" -eq 0 ] && exit 0

# ── Разбор уже произнесён? ────────────────────────────────────────────────────
# Считаем только ответы ПОСЛЕ последней реплики собеседника: разбор из прошлого хода
# к нынешнему повтору не относится.
WHY_COUNT=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    LAST_TEXT=$(jq -s '
        def role(x): x.message.role // x.role // "";
        def get_text(x):
            (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then
                ($c | map(select(.type == "text") | .text) | join("\n"))
            elif ($c | type) == "string" then $c
            else "" end;
        . as $items | (length) as $n |
        ([range(0; $n) | ($n - 1 - .)
          | select(role($items[.]) == "user" and
                   ((get_text($items[.]) // "") | length > 0))]
          | first) as $pu |
        if $pu == null then
            ([range(0; $n) | $items[.] | select(role(.) == "assistant")]
             | map(get_text(.)) | map(select(. != "")) | join("\n"))
        else
            ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]
             | map(get_text(.)) | map(select(. != "")) | join("\n"))
        end
    ' "$TRANSCRIPT" 2>/dev/null | jq -r '.' 2>/dev/null)
    if [ -n "$LAST_TEXT" ]; then
        WHY_COUNT=$(grep -oiE 'почему' <<< "$LAST_TEXT" 2>/dev/null | grep -c '' || printf '0')
        case "$WHY_COUNT" in ''|*[!0-9]*) WHY_COUNT=0 ;; esac
    fi
fi
# Цепочка — это спуск, а не одно «почему». Три и больше считаем разбором.
MIN_WHYS="${FIVE_WHYS_MIN:-3}"
[ "$WHY_COUNT" -ge "$MIN_WHYS" ] && exit 0

# ── Дедуп: одно напоминание на каждый НОВЫЙ сигнал ────────────────────────────
mkdir -p "$STATE" 2>/dev/null
SEEN_FILE="$STATE/five-whys-${SID}.seen"
SEEN=0
if [ -f "$SEEN_FILE" ]; then
    SEEN=$(cat "$SEEN_FILE" 2>/dev/null)
    case "$SEEN" in ''|*[!0-9]*) SEEN=0 ;; esac
fi
[ "$SIGNALS" -le "$SEEN" ] && exit 0
printf '%s\n' "$SIGNALS" > "$SEEN_FILE" 2>/dev/null

MSG="🔁 Признак повторяется (${WHAT}), а разбора причин в этом ходе не было.
Прежде чем править — цепочка «почему» до корня, не первое объяснение:
  1. Почему это произошло? → 2. Почему это стало возможно? → 3. Почему это не поймали?
  4. Почему условие вообще возникло? → 5. Почему его никто не заметил раньше?
Симптом чинится там, где заметили; причина — там, где возникла. Останавливаться на
первом «почему» значит чинить симптом и вернуться сюда в третий раз.
Повтор бывает и в успехах: три зелёных прогона одного файла — тоже признак."

jq -cn --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$ctx}}' 2>/dev/null || true
exit 0
