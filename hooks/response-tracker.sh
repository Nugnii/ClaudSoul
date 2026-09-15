#!/usr/bin/env bash
# response-tracker.sh — PostToolUse: пишет РЕАКЦИЮ агента после того, как система его о чём-то предупредила.
# en: PostToolUse: records the agent's REACTION after the system warned it about something.
#
# Зачем. Все остальные логи фиксируют стимул: сработал блокер, инжектнулось знание,
# юзер поправил. Ни один не фиксирует, что агент сделал следующим ходом — архитектура
# признаёт это формулой «детект ≠ комплаенс». Без зависимой переменной вопрос «правило
# меняет поведение или нет» неотвечаем: есть только частота попадания в ситуацию.
#
# Восстановить реакцию из транскриптов можно (см. backfill-compliance.sh), но
# транскрипты живут ограниченное время — 78% событий из логов уже невосстановимы.
# Поэтому пишем онлайн: потолок снимается навсегда.
#
# Дёшево по конструкции: пока в сессии не было ни одного маркера — выходим по двум
# `[ -f ]`, без jq и без записи. Пишем только после первого стимула.
#
# Формат строки: {"ts","sid","tool","file","after"}
#   after — что уже сработало в этой сессии: blocker | knowledge | both
#
# Input: JSON на stdin (PostToolUse). Output: ничего (silent).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SID=$(resolve_session_id "$INPUT" "" 2>/dev/null || true)
SID="${SID:-${CLAUDE_CODE_SESSION_ID:-$PPID}}"

# --- Гейт: был ли в этой сессии стимул? Два теста файла, дальше не идём. ---
BLOCKER_LOG="$STATE_DIR/blocker-fired-${SID}.jsonl"
KNOWLEDGE_GATE="$STATE_DIR/knowledge_injected_${SID}"
HAS_BLOCKER=false
HAS_KNOWLEDGE=false
[ -s "$BLOCKER_LOG" ] && HAS_BLOCKER=true
[ -f "$KNOWLEDGE_GATE" ] && HAS_KNOWLEDGE=true
if [ "$HAS_BLOCKER" = false ] && [ "$HAS_KNOWLEDGE" = false ]; then
    exit 0
fi

AFTER="knowledge"
if [ "$HAS_BLOCKER" = true ] && [ "$HAS_KNOWLEDGE" = true ]; then AFTER="both"
elif [ "$HAS_BLOCKER" = true ]; then AFTER="blocker"; fi

# ОБЛАСТЬ ЗАПИСИ СУЖЕНА ДО ПРЕДМЕТА (10 сентября 2026, род L). Гейт выше спрашивает «был ли
# стимул В СЕССИИ», а шапка объявляет предметом реакцию НА ПРЕДУПРЕЖДЕНИЕ — то есть на
# конкретное событие. Маркер знания ставится один раз за сессию (активатор инжектит на первый
# PreToolUse), поэтому после него КАЖДЫЙ вызов писался как «реакция»: 46 992 записи в 74
# файлах, из них `blocker` — 56, остальные 46 936 (99,9%) к объявленному предмету отношения
# не имеют. Читателя у журнала нет ни одного, и это следствие: данные не отвечают на вопрос,
# ради которого заведены («правило меняет поведение или нет»).
#
# Ключ дросселя — СОСТАВ СТИМУЛА, а не факт его наличия: размер журнала блокеров плюс время
# маркера знания. Новый стимул меняет ключ и даёт ОДНУ запись — первую реакцию после него;
# те же данные ключа значат «стимул тот же, реакция уже записана». Дроссель берётся у
# владельца (`hooks/throttle-lib.sh`), а не пишется здесь заново — правило «новый механизм
# зовёт предшественника», а не заводит вторую реализацию.
# Библиотеки нет — пишем как прежде: потеря точности хуже, чем потеря записи.
for _rt_thr in "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/throttle-lib.sh" \
               "$HOME/.claude/hooks/throttle-lib.sh"; do
    # shellcheck source=/dev/null
    [ -f "$_rt_thr" ] && { . "$_rt_thr"; break; }
done
if command -v throttle_file >/dev/null 2>&1; then
    _rt_bsz=$(wc -c < "$BLOCKER_LOG" 2>/dev/null | tr -d ' ')
    _rt_kmt=""
    command -v file_mtime >/dev/null 2>&1 && [ -f "$KNOWLEDGE_GATE" ] \
        && _rt_kmt=$(file_mtime "$KNOWLEDGE_GATE" 2>/dev/null)
    _rt_key="${AFTER}:${_rt_bsz:-0}:${_rt_kmt:-0}"
    # Имя дросселя НЕ начинается с `response-`: под этот glob ходит уборка состояния
    # (`scripts/state-prune.sh:52`) и всякий счёт по журналу реакций. Первым на коллизию
    # наступил я сам в тот же час — `cat state/response-*.jsonl | wc -l` дал вдвое больше
    # строк, потому что захватил файл дросселя, и правка выглядела несработавшей.
    _rt_thr_f=$(throttle_file "$STATE_DIR" rtrack-stimulus "$SID")
    throttle_seen "$_rt_thr_f" "$_rt_key" && exit 0
    throttle_mark "$_rt_thr_f" "$_rt_key"
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
[ -n "$TOOL" ] || exit 0
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)

# Сборка через jq: пути содержат пробелы и кавычки, printf рождал бы битые строки
# (ровно то, на чём три месяца врал injection-log).
jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$SID" \
       --arg tool "$TOOL" --arg file "$FILE" --arg after "$AFTER" \
   '{ts: $ts, sid: $sid, tool: $tool, file: $file, after: $after}' \
   >> "$STATE_DIR/response-${SID}.jsonl" 2>/dev/null || true

exit 0
