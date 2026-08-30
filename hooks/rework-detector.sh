#!/usr/bin/env bash
# rework-detector.sh — PostToolUse: третий заход на тот же файл при зелёных прогонах.
# en: PostToolUse: third rework cycle on the same file while every run looks green.
#
# Слепое пятно, которое он закрывает. Все существующие детекторы повторения реагируют
# на ОШИБКИ: `error-tracker` считает подряд идущие провалы Bash и на втором просит
# остановиться. Повторение с ЗЕЛЁНЫМ результатом не видит никто.
#
# Живой случай (v1.12.4). Один тест переписывался трижды: чистое дерево → staged пусто,
# стражи не запускались; воспроизведение последнего коммита → покрытие случайное;
# и только «всё дерево в индекс» дало настоящий прогон. Каждая из трёх итераций
# завершалась «0 провалов», то есть выглядела успехом. Ни один счётчик их не связал,
# и разбор причины («5 почему») не запускался — запускать его было нечему.
#
# Собеседник назвал это точно: три раза сделано одно и то же, потому что не был
# применён приём, который агент знает и раньше применял. Знание без момента
# срабатывания не работает — уровень 1 embedded-ness.
#
# Сигнатура переработки: правка файла → прогон → правка ТОГО ЖЕ файла → прогон →
# правка. Просто три правки подряд не считаются: это нормальное дописывание.
# Между правками обязан быть прогон — значит, результат проверяли и он не устроил.
#
# Contract:
#   Input  (stdin): PostToolUse JSON {session_id, tool_name, tool_input}
#   Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
#   Exit:  always 0
#
# Порог: REWORK_THRESHOLD (по умолчанию 3) — на третьей правке в цепочке.
# Throttle: один раз на файл за сессию, иначе алерт станет фоном.

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

# Порядок разбора — из root-cause-lib. До 29 августа 2026 здесь стояли ПЯТЬ готовых
# вопросов «почему» — своя редакция с фикс-глубиной, отменённой /retro 3.1 («критерий
# остановки — НЕ глубина 5»). Переработка файла — один из поводов гейта разбора, и хуки
# печатали разное. Библиотеки нет — текст деградирует до строки, детекция не страдает.
RC_LIB="${RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/root-cause-lib.sh}"
[ -f "$RC_LIB" ] || RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
[ -f "$RC_LIB" ] && source "$RC_LIB"
if command -v rc_doctrine_short >/dev/null 2>&1; then
    RC_DOCTRINE=$(rc_doctrine_short)
else
    RC_DOCTRINE="Разбор до корня: вширь по проявлениям с адресами, затем цепочка «почему» от самых разных, остановка по признаку корня."
fi
# Порядок разбора говорит, КАК искать причину, но не говорит, чем ход обязан кончиться —
# и без второго предписание тормозит, не называя исхода (D111). Список исходов закрытый и
# лежит в библиотеке, а не переписывается здесь своими словами.
if command -v rc_resolution_kinds >/dev/null 2>&1; then
    RC_OUTCOME_LINE="Исход из закрытого списка: $(rc_resolution_kinds). Все четыре исполнимы без разрешения."
else
    RC_OUTCOME_LINE="Исход: починка механизма · пункт долга · запись знания · вердикт «показалось»."
fi

THRESHOLD="${REWORK_THRESHOLD:-3}"

mkdir -p "$STATE_DIR" 2>/dev/null
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

# rw_write_targets "<команда оболочки>"
#   Печатает по одному в строке абсолютные пути файлов проекта, В КОТОРЫЕ команда пишет.
#   Формы: редирект `> f` / `>> f`; `sed -i … f`; `tee f`; запись из python
#   (`open(…, "w")` — тогда берутся литералы путей, встреченные в команде).
#
#   Берётся АДРЕСАТ записи, а не любое упоминание пути: `bash run_all.sh > log` упоминает
#   скрипт, но пишет в другое место. Замер по живой сессии 27 августа 2026: по упоминаниям
#   сигналов было бы 12, треть из них по файлам, которые только запускались; по адресатам —
#   3, и все три действительно переписывались многократно.
#
#   Временные каталоги и файлы-хроники отбрасываются: хроники исключены и в ветке Edit,
#   повторная правка там норма жанра (калибровка D18).
rw_write_targets() {
    _rw_c="$1"
    {
        printf '%s' "$_rw_c" | grep -oE '>>?[[:space:]]*["'"'"']?[A-Za-z0-9_./~-]+\.(sh|py|md|json|yml|yaml|tsv)' 2>/dev/null \
            | sed -E 's/^>>?[[:space:]]*["'"'"']?//'
        printf '%s' "$_rw_c" | grep -oE '(sed[[:space:]]+-i|tee)[^|;&]*[[:space:]]["'"'"']?[A-Za-z0-9_./~-]+\.(sh|py|md|json|yml|yaml|tsv)' 2>/dev/null \
            | grep -oE '[A-Za-z0-9_./~-]+\.(sh|py|md|json|yml|yaml|tsv)$'
        # herestring, а не труба: `cmd | grep -q` под pipefail врёт кодом 141 под нагрузкой
        # (D50, страж test_assert_no_sigpipe — он и поймал эту строку при первом прогоне).
        if grep -qE 'open\([^)]*["'"'"']w' <<< "$_rw_c" 2>/dev/null; then
            printf '%s' "$_rw_c" | grep -oE '["'"'"'][A-Za-z0-9_./~-]+\.(sh|py|md|json|yml|yaml|tsv)["'"'"']' 2>/dev/null \
                | tr -d '"'"'"'"'
        fi
    } 2>/dev/null | while IFS= read -r _rw_t; do
        [ -n "$_rw_t" ] || continue
        case "$_rw_t" in
            */tmp/*|*scratchpad*|*CHANGELOG*|*BACKLOG*|*SESSION*|*.claude-docs/sessions/*) continue ;;
        esac
        case "$_rw_t" in
            /*) [ -f "$_rw_t" ] && printf '%s\n' "$_rw_t" ;;
            *)
                for _rw_r in "${CLAUDE_PROJECT_DIR:-}" "$PWD" "$HOME/.claude/hooks"; do
                    [ -n "$_rw_r" ] || continue
                    for _rw_s in "" "hooks/" "hooks/tests/" "scripts/"; do
                        if [ -f "$_rw_r/$_rw_s$_rw_t" ]; then printf '%s\n' "$_rw_r/$_rw_s$_rw_t"; break 2; fi
                    done
                done
                ;;
        esac
    done | awk '!seen[$0]++'
}

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
LOG="$STATE_DIR/rework-${SID}.jsonl"

case "$TOOL" in
    Bash)
        # Правка через оболочку — такая же правка (D91). Раньше здесь стоял только
        # «прогон», и цепочка не набирала ни шага в сессиях, где файлы правят через
        # heredoc и sed: замер 27 августа 2026 по живой сессии — 156 записей в логе,
        # из них 16 правок, и все 16 от субагентов через Write, а `hook-input-lib.sh`,
        # переписанный больше десяти раз через оболочку, отсутствовал полностью.
        # Непустой лог маскировал нулевой сигнал. Тот же корень закрывали 26 августа
        # для blocker-tier знаний (D79, 45% правок мимо), у этого потребителя он остался.
        [ -f "$LOG" ] || exit 0
        _rw_cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        _rw_targets=$(rw_write_targets "$_rw_cmd")
        if [ -z "$_rw_targets" ]; then
            printf '{"kind":"run"}\n' >> "$LOG" 2>/dev/null || true
            exit 0
        fi
        printf '%s\n' "$_rw_targets" | while IFS= read -r _rw_f; do
            [ -n "$_rw_f" ] || continue
            printf '{"kind":"edit","path":"%s"}\n' "$_rw_f" >> "$LOG" 2>/dev/null || true
        done
        # Порог проверяется по первому адресату: команда, пишущая сразу в несколько
        # файлов проекта, в этой работе редкость, а остальные уже попали в цепочку.
        FILE=$(printf '%s\n' "$_rw_targets" | awk 'NF { print; exit }')
        ;;
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

# Для Bash адресат уже определён в ветке выше; у файловых инструментов он в tool_input.
if [ -z "${FILE:-}" ]; then
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
fi
[ -n "$FILE" ] || exit 0

# Калибровка D18 (2026-08-08, выборка 40 срабатываний): 10 пришлись на
# файлы-хроники (CHANGELOG x4, BACKLOG x3, SESSION x2, архив) — там повторные
# правки норма жанра (append-лог), ни одно срабатывание не было переработкой.
# Хроники исключены до записи в цепочку; маска переопределяется env.
#
# Разметка выборки D23 (2026-08-11, 36 срабатываний после калибровки): хроник ноль —
# исключение работает, — но два срабатывания пришлись на CLAUDE.md и одно на META.md.
# Это документы СОСТОЯНИЯ: они переписываются по ходу сессии столько раз, сколько
# уточняется картина, и повторная правка в них — тот же жанр, что append в хронике.
# КОНТРПРИМЕР: журнальные файлы ВНЕ этого перечня — `docs/*.md`, `.claude-docs/*` —
# исключением не покрыты, и повторная дозапись в них засчитается переработкой.
# Перечень назван перечнем: он растёт по мере встречи новых журналов, не по правилу.
REWORK_EXCLUDE_RE="${REWORK_EXCLUDE_RE:-(CHANGELOG|SESSION|BACKLOG[^/]*|CLAUDE|META)\.md$}"
# Ответ берётся у grep, а не у трубы: под `set -o pipefail` producer, убитый SIGPIPE,
# отдаёт 141, и исключение молча перестаёт исключать (D50; доказано замером в D59).
grep -qE "$REWORK_EXCLUDE_RE" <<< "$FILE" && exit 0

printf '{"kind":"edit","path":"%s"}\n' "$FILE" >> "$LOG" 2>/dev/null || true

# Считаем правки этого файла, между которыми был прогон.
# Цепочка: edit(F) ... run ... edit(F) ... run ... edit(F) → CYCLES=3.
CYCLES=$(awk -v f="$FILE" '
    /"kind":"run"/ { ran = 1; next }
    /"kind":"edit"/ {
        # путь текущей строки
        if (split($0, a, "\"path\":\"") < 2) next
        split(a[2], b, "\"")
        if (b[1] != f) next
        if (first == 0) { first = 1; n = 1; ran = 0; next }
        if (ran == 1) { n++; ran = 0 }
    }
    END { print n + 0 }
' "$LOG" 2>/dev/null || echo 0)
CYCLES=${CYCLES:-0}

[ "$CYCLES" -ge "$THRESHOLD" ] 2>/dev/null || exit 0

# Throttle: один раз на (файл, число циклов) за сессию — а не на файл. Первый прогон замера
# detection-share (30 августа 2026) показал «сказал 16%»: после первого напоминания файл
# переделывался дальше — четвёртый, пятый цикл — и страж молчал, хотя каждый новый цикл есть
# НОВОЕ событие того же рода («повтор уплывает», поправка владельца 27 августа). Правки без
# прогона между ними число циклов не меняют и молчат как прежде.
FIRED="$STATE_DIR/rework-fired-${SID}.jsonl"
if [ -f "$FIRED" ] && grep -Fq "\"path\":\"$FILE\",\"cycles\":$CYCLES}" "$FIRED" 2>/dev/null; then
    # Признак СОВПАЛ, страж промолчал по троттлу — это знаменатель, а не пустота (D205):
    # без него доля «сказал против промолчал» непосчитаема по построению. Подпись —
    # файл и цикл: повтор той же подписи в замере не считается подавлением.
    command -v rc_note_detection >/dev/null 2>&1 && \
        rc_note_detection "$STATE_DIR" "$SID" "rework-detector" "muted" "$FILE:$CYCLES"
    exit 0
fi
command -v rc_note_detection >/dev/null 2>&1 && \
    rc_note_detection "$STATE_DIR" "$SID" "rework-detector" "said" "$FILE:$CYCLES"
printf '{"path":"%s","cycles":%s}\n' "$FILE" "$CYCLES" >> "$FIRED" 2>/dev/null || true

BASE=$(basename "$FILE")
CTX=$(printf '🔁 Переработка: %s правится %s-й раз, и между правками были прогоны — значит результат каждый раз проверяли и он не устраивал.\n\nВсе прогоны при этом могли быть зелёными: детектор ошибок такое не видит, он считает провалы.\n\nОстановись до следующей правки и назови причину, а не симптом:\n\n%s\n\n%s\n\nЕсли причина найдена — чини её, а не текущий симптом. Если правка действительно четвёртая по делу (разные задачи в одном файле) — игнорируй.' \
    "$BASE" "$CYCLES" "$RC_DOCTRINE" "$RC_OUTCOME_LINE")

jq -n --arg ctx "$CTX" '{
    hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $ctx
    }
}'
exit 0
