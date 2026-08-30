#!/usr/bin/env bash
# knowledge-frontmatter-check.sh — PostToolUse[Write|Edit|MultiEdit]: битый YAML frontmatter записанного знания называется СРАЗУ, а не когда-нибудь при прогоне тестов.
# en: PostToolUse[Write|Edit|MultiEdit]: reports broken YAML frontmatter right after a knowledge file is written.
#
# Инцидент (2026-08-11). Строка `description: … это не ловит: он проверяет …` — валидный
# русский и невалидный YAML: двоеточие с пробелом внутри незакавыченного скаляра читается
# как вложенное отображение. Замер живой базы: 21 файл из 317, включая
# principle-affect-as-engineering и pattern-shell-portability.
#
# Почему это НЕ ловилось само:
#   · tests/test_frontmatter.py проверяет парсер на выдуманных строках и живую базу
#     не открывает — предмет теста «умеет ли парсер», предмет вопроса «парсится ли база»
#     (pattern-subject-of-measurement-mismatch);
#   · после v1.x парсер получил salvage битого YAML — файл больше не теряется целиком,
#     но списки (edges, source_cases, related, domain, tags) он не восстанавливает.
#     То есть СВЯЗИ ГРАФА исчезают тихо, а запись выглядит здоровой. Пластырь без
#     детектора сделал класс менее заметным, чем он был.
# Поймано было случайно — проверкой, которую можно было и не писать. Этот хук убирает
# случайность: уровень 3 embedded-ness (principle-knowledge-in-the-world).
#
# Покрытие — честно о потолке:
#   · есть python с PyYAML (venv ClaudSoul либо системный) → ПОЛНАЯ проверка парсером;
#   · нет → regex на доминирующий класс «незакавыченное двоеточие»: замер на живой базе
#     17 из 21 (81%). Остальные 4 — «while parsing a block mapping» / «while scanning for
#     the next token» — regex-режим пропустит, их ловит тест mcp-server на живой базе.
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
    : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"
    : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"
fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
    Write|Edit|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

# Только знания: *.md внутри базы. Черновики (_drafts) и META.md — не трогаем.
case "$FILE_PATH" in
    "$LESSONS_DIR"/*.md) ;;
    *) exit 0 ;;
esac
BASE_NAME=$(basename "$FILE_PATH")
case "$BASE_NAME" in
    _*|META.md) exit 0 ;;
esac

# Нет frontmatter вовсе — не наш случай (бывают справочные файлы без него).
grep -q '^---$' <<< "$(head -n 1 "$FILE_PATH")" || exit 0

emit() {
    # $1 — текст для агента
    jq -n --arg ctx "$1" \
        '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}' 2>/dev/null
    exit 0
}

# ── Режим 1: полная проверка парсером, если есть python с PyYAML ──────────────
PY=""
# Явно названный интерпретатор ОТМЕНЯЕТ поиск, а не встаёт в его середину. Иначе
# переменная не управляет режимом: до 2026-08-11 проверка запасного пути (T2) думала,
# что отключает python подстановкой несуществующего пути, а хук всё равно доходил до
# системного `python3` — и четыре дня утверждала про regex-режим, исполняя парсерный.
# Красным это стало не от правки кода, а от среды: системный python3 обзавёлся PyYAML.
if [ -n "${CLAUDSOUL_PYTHON:-}" ]; then
    _py_candidates=("$CLAUDSOUL_PYTHON")
else
    _py_candidates=("$CLAUDSOUL_ROOT/mcp-server/.venv/bin/python" python3)
fi
for candidate in "${_py_candidates[@]}"; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ] || continue
    if "$candidate" -c 'import yaml' >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done

if [ -n "$PY" ]; then
    REPORT=$("$PY" - "$FILE_PATH" <<'PYEOF' 2>/dev/null
import sys, yaml
path = sys.argv[1]
raw = open(path, encoding="utf-8", errors="replace").read()
parts = raw.split("---", 2)
if len(parts) < 3:
    sys.exit(0)
try:
    meta = yaml.safe_load(parts[1])
except yaml.YAMLError as e:
    mark = getattr(e, "problem_mark", None)
    where = f"строка {mark.line + 1}, колонка {mark.column + 1}" if mark else "место не определено"
    print(f"BROKEN|{str(e).splitlines()[0].strip()}|{where}")
    sys.exit(0)
# YAML валиден — отдельно предупреждаем о пустом frontmatter (тоже потеря метаданных).
if not isinstance(meta, dict) or not meta:
    print("EMPTY||")
PYEOF
)
    case "$REPORT" in
        BROKEN*)
            WHY=$(printf '%s' "$REPORT" | cut -d'|' -f2)
            WHERE=$(printf '%s' "$REPORT" | cut -d'|' -f3)
            emit "⚠️ Битый YAML frontmatter: ${BASE_NAME}
   ${WHY} (${WHERE}).
   Знание НЕ потеряно (парсер достаёт скаляры построчно), но СПИСКИ — edges,
   source_cases, related, domain, tags — не читаются вовсе: связи графа исчезают тихо.
   Частая причина: двоеточие с пробелом внутри незакавыченного значения
   (\`description: … не ловит: он проверяет …\`). Лечится кавычками вокруг значения.
   Почини сейчас и перечитай файл — иначе запись выглядит здоровой, а связей у неё нет."
            ;;
        EMPTY*)
            emit "⚠️ Пустой frontmatter: ${BASE_NAME} — метаданных нет, знание не попадёт ни в один фильтр."
            ;;
    esac
    exit 0
fi

# ── Режим 2 (без PyYAML): regex на доминирующий класс ─────────────────────────
# Ловит верхнеуровневый скаляр без кавычек/блока, в значении которого есть ": ".
# Потолок известен и назван в шапке: 17 из 21 на замере живой базы.
SUSPECT=$(awk '
    /^---$/ { n++; if (n == 2) exit; next }
    n != 1 { next }
    # Разделитель ключа отрезаем и ищем ": " ТОЛЬКО в значении — иначе условие
    # срабатывает на самом разделителе, то есть на каждой строке подряд.
    match($0, /^[A-Za-z_][A-Za-z0-9_-]*:[ \t]+/) {
        val = substr($0, RSTART + RLENGTH)
        if (val ~ /^["'"'"'|>[{]/) next          # закавычено или блок/список — YAML разберёт
        # Комментарий YAML отбрасывает, а двоеточия в нём безвредны: без этой срезки
        # строки вида `instrument_verdict: inexpressible   # …по конструкции: …` давали
        # ложную тревогу (замер: 6 здоровых файлов из 317).
        sub(/[ \t]+#.*/, "", val)
        if (val ~ /: /) {
            # Печатаем ключ, а не кусок значения: обрезка по байтам рубит UTF-8 посередине.
            key = $0; sub(/:.*/, "", key)
            print "   строка " NR ", ключ «" key "»"
            found++
            if (found >= 3) exit
        }
    }
' "$FILE_PATH" 2>/dev/null)

if [ -n "$SUSPECT" ]; then
    emit "⚠️ Возможен битый YAML frontmatter: ${BASE_NAME}
   Незакавыченное значение с двоеточием — YAML прочитает его как вложенное отображение
   и потеряет СПИСКИ (edges, source_cases, related, domain, tags), оставив вид здоровой записи:
${SUSPECT}
   Лечится кавычками вокруг значения. (Проверка неполная: PyYAML недоступен — доступен был
   бы, проверка шла бы парсером. Полный контроль — тест live-базы в mcp-server.)"
fi

exit 0
