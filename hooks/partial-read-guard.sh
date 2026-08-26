#!/usr/bin/env bash
# partial-read-guard.sh — PostToolUse[Read]: называет числом, сколько строк файла прочитано.
# en: PostToolUse[Read]: states how much of a file was actually read, in lines.
# Первая строка держится самодостаточной намеренно: regen-readme-skills.sh берёт для
# русской таблицы README ровно её, и описание, разорванное переносом, попадает в таблицу
# оборванным на запятой.
#
# Инцидент (внешний отчёт Claude Code Insights, 2026-08-21): «Claude claimed a file had
# no psychology content after reading only its first few kilobytes». Утверждение об
# ОТСУТСТВИИ сделано по прочтению начала — и было неверным.
#
# Почему текстового правила тут мало. Правило «читай целиком» требует помнить, что
# чтение было неполным. А неполнота как раз незаметна: инструмент Read без параметров
# молча обрезает файл на 2000 строк и возвращает результат, ничем не отличимый от
# полного. Модель видит содержимое и не видит границы. Это второй уровень
# embedded-ness по principle-knowledge-in-the-world: не правило в голове, а факт
# в контексте — «прочитано 40 из 900».
#
# ПОТОЛОК, названный честно. Хук видит только вызовы инструмента Read. Чтение через
# Bash (`cat`, `sed -n '1,50p'`, `head`) он не видит вовсе — а в сессиях с авторежимом
# именно так и читают. То есть покрытие частичное по конструкции, и хук снижает
# вероятность класса, а не устраняет его. Расширять на Bash не стал намеренно: разбор
# произвольной команды на предмет «какой файл и сколько строк» — источник ложных
# срабатываний дороже пользы.
#
# Шум ограничен: один маркер на файл на сессию. Повторные чтения того же файла молчат,
# иначе разбор большого файла кусками превратил бы маркер в фон.
#
# Input  (stdin): {session_id, tool_name, tool_input} (PostToolUse JSON)
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
[ "$TOOL_NAME" = "Read" ] || exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Картинки, PDF и блокноты меряются не строками — молчим, иначе число соврёт.
# ${VAR,,} — синтаксис bash 4+, а macOS несёт 3.2 (pattern-shell-portability).
LOWER=$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')
case "$LOWER" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.pdf|*.ipynb) exit 0 ;;
esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosid"' 2>/dev/null)
OFFSET=$(printf '%s' "$INPUT" | jq -r '.tool_input.offset // 0' 2>/dev/null)
LIMIT=$(printf '%s' "$INPUT" | jq -r '.tool_input.limit // 0' 2>/dev/null)
case "$OFFSET" in ''|*[!0-9]*) OFFSET=0 ;; esac
case "$LIMIT"  in ''|*[!0-9]*) LIMIT=0  ;; esac

# Умолчание инструмента: без limit читается не «всё», а первые 2000 строк. Именно это
# умолчание и делает обрезку невидимой, поэтому оно здесь записано явно.
DEFAULT_LIMIT="${READ_DEFAULT_LIMIT:-2000}"
[ "$LIMIT" -eq 0 ] && LIMIT="$DEFAULT_LIMIT"

TOTAL=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')
case "$TOTAL" in ''|*[!0-9]*) exit 0 ;; esac
# Хвост без перевода строки — тоже строка.
[ -s "$FILE_PATH" ] && [ "$(tail -c 1 "$FILE_PATH" | wc -l | tr -d ' ')" = "0" ] && TOTAL=$((TOTAL + 1))
[ "$TOTAL" -eq 0 ] && exit 0

START=$OFFSET
[ "$START" -le 0 ] && START=1
END=$((START + LIMIT - 1))
[ "$END" -gt "$TOTAL" ] && END="$TOTAL"
READ_LINES=$((END - START + 1))
[ "$READ_LINES" -lt 0 ] && READ_LINES=0

# Прочитано всё — говорить не о чем.
[ "$READ_LINES" -ge "$TOTAL" ] && exit 0

# Один маркер на файл на сессию.
mkdir -p "$STATE" 2>/dev/null
KEY=$(printf '%s' "$FILE_PATH" | shasum 2>/dev/null | cut -c1-12)
[ -n "$KEY" ] || KEY=$(printf '%s' "$FILE_PATH" | cksum | cut -d' ' -f1)
SEEN="$STATE/partial-read-${SID}.seen"
if [ -f "$SEEN" ] && grep -qxF "$KEY" "$SEEN" 2>/dev/null; then
    exit 0
fi
printf '%s\n' "$KEY" >> "$SEEN" 2>/dev/null

PCT=$(( READ_LINES * 100 / TOTAL ))
UNREAD=$(( TOTAL - READ_LINES ))
BASE=$(basename "$FILE_PATH")

MSG="📄 Прочитано ${READ_LINES} из ${TOTAL} строк файла ${BASE} (${PCT}%), строки ${START}–${END}.
Об ОТСУТСТВИИ чего-либо в этом файле по такому чтению судить нельзя — непрочитанного ${UNREAD} строк.
Нужен вывод про весь файл: дочитать целиком либо grep по всему файлу, и назвать, чем проверено."

jq -cn --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}' 2>/dev/null || true
exit 0
