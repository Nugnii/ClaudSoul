#!/usr/bin/env bash
# session-collector.sh — Stop: напоминает записать незафиксированные уроки через /learn, финализирует сессию в реестре, чистит ephemeral state.
# en: Stop: reminds to record uncaptured lessons via /learn, finalises the session in the registry, cleans ephemeral state.
# Fires when Claude is about to stop. Reminds to record unrecorded
# learnings (corrections, successes, struggles) via /learn.
# Also finalizes session in the registry and cleans up ephemeral state files.
#
# Session registry (v0.5.1):
#   - Finalizes active session: appends to registry.jsonl, updates last-session.json
#   - Cleans up active/{session_id}.json
#
# Input: JSON on stdin from Claude Code (Stop event)
# Output: JSON with systemMessage

set -euo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; fi

# Read stdin payload once (used for session_id resolution)
INPUT="$(cat)"

# Stable session_id from Claude Code payload — overrides PPID-based fallback
# in session-registry-lib.sh so finalize matches the active record written by
# knowledge-activator/session-start (also using payload session_id).
PAYLOAD_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$PAYLOAD_SID" ]; then
    export SR_OVERRIDE_SESSION_ID="$PAYLOAD_SID"
fi

# Activity flush (v1.5.2-alpha): parse transcript, append machine log to
# .claude-docs/session-activity.md. Complements /save narrative flow —
# activity survives even if /save wasn't called.
PAYLOAD_TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
ACTIVITY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/activity-flush-lib.sh"
[ -f "$ACTIVITY_LIB" ] || ACTIVITY_LIB="$HOME/.claude/hooks/activity-flush-lib.sh"
if [ -f "$ACTIVITY_LIB" ] && [ -n "$PAYLOAD_SID" ] && [ -n "$PAYLOAD_TRANSCRIPT" ] && [ -n "$PAYLOAD_CWD" ]; then
    # shellcheck source=/dev/null
    source "$ACTIVITY_LIB"
    activity_flush "$PAYLOAD_SID" "$PAYLOAD_TRANSCRIPT" "$PAYLOAD_CWD" >/dev/null 2>&1 || true
fi

# Session-specific state (PPID-based, preserves compatibility with error-tracker
# and other hooks that key state files by ${CLAUDE_CODE_SESSION_ID:-$PPID})
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-$PPID}"
STRUGGLE_FILE="$STATE_DIR/had_struggle_${SESSION_ID}"

# Source session registry library (will pick up SR_OVERRIDE_SESSION_ID if set)
REGISTRY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/session-registry-lib.sh"
[ -f "$REGISTRY_LIB" ] || REGISTRY_LIB="$HOME/.claude/hooks/session-registry-lib.sh"
HAS_REGISTRY=false
if [ -f "$REGISTRY_LIB" ]; then
    source "$REGISTRY_LIB"
    HAS_REGISTRY=true
fi

# Check if this session had struggles (set by error-tracker)
HAD_STRUGGLE=false
if [ -f "$STRUGGLE_FILE" ]; then
    HAD_STRUGGLE=true
fi

# User-visible systemMessage: keep short. Verbose self-reflection prompts
# (interlocutor model questions, intrusiveness summary, H10 section) were
# moved to silent file logging — feedback v1.7.2: видимый Stop-вывод не
# должен занимать пол-экрана пользователя. Agent self-reflection on next
# session start через session-start startup-signals.

# Disagreement outcomes check (v1.12.0: по ВСЕМ сессиям, не только текущей).
#
# До v1.12.0 здесь считался файл текущей сессии, а текст алерта уходил в очередь и
# показывался на СЛЕДУЮЩЕЙ. Агент видел «N знаний без исхода» и шёл в /learn, который
# читает файл СВОЕЙ сессии — а там этих записей нет. Закрыть было нечего и нечем.
# Результат на живых данных: из 5 записей закрыта одна, та единственная, что успела
# закрыться внутри своей же сессии за 10 минут. Остальные висели неделями, и
# contradicted_count оставался нулевым во всех 265 знаниях.
DIS_SID="${PAYLOAD_SID:-$SESSION_ID}"
# Сначала рядом со скриптом, потом установленная копия — тот же порядок, что у
# paths-lib в других хуках. Иначе тест, запускающий хук из репозитория, молча
# получал бы ноль записей вместо контура.
DIS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/disagreement-lib.sh"
[ -f "$DIS_LIB" ] || DIS_LIB="$HOME/.claude/hooks/disagreement-lib.sh"
PENDING_COUNT=0
PENDING_DETAIL=""
EXPIRED_COUNT=0
if [ -f "$DIS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$DIS_LIB"
    # Второй продюсер: собрать кандидатов там, где знание вероятно ошиблось —
    # собеседник поправил агента вскоре после инжекта. Первый продюсер берёт выборку
    # там, где знание вероятно право (blocker-tier = подтверждено ≥5 раз), поэтому
    # сам по себе он не может дать ни одного опровержения.
    dis_harvest_corrections "$DIS_SID" "$STATE_DIR" >/dev/null 2>&1 || true
    # Затем гасим просроченные — иначе алерт растёт бесконечно и становится фоном,
    # ровно как предупреждал комментарий продюсера в knowledge-activator.
    EXPIRED_COUNT=$(dis_expire_old "${DISAGREEMENT_EXPIRE_DAYS:-7}" "$STATE_DIR" 2>/dev/null || echo 0)
    OPEN_RECORDS=$(dis_scan_open "$STATE_DIR" 2>/dev/null || true)
    if [ -n "$OPEN_RECORDS" ]; then
        PENDING_COUNT=$(printf '%s\n' "$OPEN_RECORDS" | grep -c '' || echo 0)
        # Возраст и происхождение записи меняют её смысл, поэтому считаются отдельно.
        # Запись, созданную соседней ЖИВОЙ сессией двадцать минут назад, закрывать
        # нечем: агент не знает, применилось ли там знание, — а единственная кнопка,
        # гасящая строку, пишет confirmed. Печатать такие записи детально значит
        # давить в сторону завышения confirmed_count (дефект D60 с другой стороны).
        # Наблюдение 2026-08-09: 16 открытых записей, все моложе суток, из шести
        # чужих сессий; владелец видел растущее число без признака, требует ли оно
        # действия. Детально печатаем СВОИ и залежавшиеся, остальное — числом.
        PENDING_STALE_DAYS="${PENDING_STALE_DAYS:-3}"
        _dis_now=$(date +%s)
        PENDING_MINE=0
        PENDING_STALE=0
        while IFS='|' read -r s k d c t; do
            [ -n "$k" ] || continue
            if [ "$s" = "$DIS_SID" ]; then
                PENDING_MINE=$((PENDING_MINE + 1))
                continue
            fi
            _e=$(iso_epoch "$d" 2>/dev/null || echo 0)
            [ "${_e:-0}" -gt 0 ] 2>/dev/null || continue
            [ $(( (_dis_now - _e) / 86400 )) -ge "$PENDING_STALE_DAYS" ] \
                && PENDING_STALE=$((PENDING_STALE + 1))
        done <<DIS_EOF
$OPEN_RECORDS
DIS_EOF
        PENDING_FRESH=$((PENDING_COUNT - PENDING_MINE - PENDING_STALE))
        # Готовая команда вместо «запусти /learn»: скилл целиком ради одной строки —
        # цена, которую платят не всегда, а контур без закрытия не измеряет ничего.
        PENDING_DETAIL=$(printf '%s\n' "$OPEN_RECORDS" | while IFS='|' read -r s k d c t; do
            [ -n "$k" ] || continue
            # Чужую запись показываем детально, только если она залежалась.
            if [ "$s" != "$DIS_SID" ]; then
                _e=$(iso_epoch "$d" 2>/dev/null || echo 0)
                [ "${_e:-0}" -gt 0 ] 2>/dev/null || continue
                [ $(( (_dis_now - _e) / 86400 )) -ge "$PENDING_STALE_DAYS" ] || continue
            fi
            printf '   ⚡ %s (conf %s, %s, инструмент %s)\n' "$k" "${c:-?}" "${d:-?}" "${t:-?}"
            printf '      верно     → bash ~/.claude/hooks/knowledge-counter-bump.sh %s confirmed "<почему>"\n' "$k"
            printf '      ошиблось  → bash ~/.claude/hooks/knowledge-counter-bump.sh %s contradicted "<что разошлось>"\n' "$k"
            printf '      не к месту→ bash ~/.claude/hooks/knowledge-counter-bump.sh %s not_applicable "<почему мимо>"\n' "$k"
            printf '      не применил→ bash ~/.claude/hooks/knowledge-counter-bump.sh %s applicable_not_followed "<что помешало>"\n' "$k"
        done)
    fi
fi

# Intrusiveness summary (v1.3)
# If this session had intrusiveness events — append summary and remind agent to reflect.
ITR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/intrusiveness-state-lib.sh"
[ -f "$ITR_LIB" ] || ITR_LIB="$HOME/.claude/hooks/intrusiveness-state-lib.sh"
ITR_SID="${PAYLOAD_SID:-$SESSION_ID}"
ITR_STATE="$STATE_DIR/intrusiveness-${ITR_SID}.json"
if [ -f "$ITR_LIB" ] && [ -f "$ITR_STATE" ]; then
    # shellcheck source=/dev/null
    source "$ITR_LIB"

    # Closing_cost detector (v1.3.1): compute cost-of-silence for session end.
    # If there are pending silence_debt items — elevate their priority by marking
    # high-cost ones as "surfaced" (triggers metric increment), and persist the
    # computed cost in cost_hints for cross-session audit.
    CLOSING_COST=$(itr_compute_closing_cost "$ITR_SID" 2>/dev/null || echo 0)
    itr_set_cost_hint "$ITR_SID" last_closing_cost "$CLOSING_COST" >/dev/null 2>&1 || true

    # Surface high-cost pending debt (silence_cost >= 3) — marks them so next
    # session's startup sees these as "closed-but-recorded" signals.
    if [ "${CLOSING_COST:-0}" -ge 3 ] && command -v jq >/dev/null 2>&1; then
        HIGH_DEBT_TOPICS=$(jq -r '[.silence_debt[] | select(.status=="pending" and .silence_cost>=3) | .topic] | .[]' "$ITR_STATE" 2>/dev/null || true)
        if [ -n "$HIGH_DEBT_TOPICS" ]; then
            while IFS= read -r topic; do
                [ -z "$topic" ] && continue
                itr_mark_debt_surfaced "$ITR_SID" "$topic" >/dev/null 2>&1 || true
                itr_log_event "$ITR_SID" silence_debt surfaced 3 "closing: $topic" >/dev/null 2>&1 || true
            done <<< "$HIGH_DEBT_TOPICS"
        fi
    fi

    # H11/H12 measurement: aggregate cascading + injection metrics into
    # cost_hints so itr_append_history picks them up in the digest.
    CASCADE_LOG="$STATE_DIR/cascading-events-${SESSION_ID}.jsonl"
    if [ -f "$CASCADE_LOG" ]; then
        BWD_COUNT=$(grep -c '"trigger":"BACKWARD"' "$CASCADE_LOG" 2>/dev/null || echo 0)
        BWD_COUNT=$(printf '%s' "$BWD_COUNT" | tr -d '[:space:]')
        [ -z "$BWD_COUNT" ] && BWD_COUNT=0
        itr_set_cost_hint "$ITR_SID" cascading_backward_count "$BWD_COUNT" >/dev/null 2>&1 || true
    fi
    INJECT_PEAK_FILE="$STATE_DIR/injection-bytes-peak-${SESSION_ID}"
    if [ -f "$INJECT_PEAK_FILE" ]; then
        INJ_PEAK=$(cat "$INJECT_PEAK_FILE" 2>/dev/null | tr -d '[:space:]')
        [ -z "$INJ_PEAK" ] && INJ_PEAK=0
        itr_set_cost_hint "$ITR_SID" injection_bytes_max "$INJ_PEAK" >/dev/null 2>&1 || true
    fi

    # Finalize → history → cleanup (v1.3.2).
    # Order matters: finalize AFTER all events are logged (including the
    # silence_debt/surfaced events added just above), so history digest
    # reflects the true final state.
    itr_finalize_metrics "$ITR_SID" >/dev/null 2>&1 || true
    HISTORY_APPENDED=false
    if itr_append_history "$ITR_SID" stop >/dev/null 2>&1; then
        HISTORY_APPENDED=true
    fi
    # Prune stale sessions (>30d). Runs once per session close — cheap.
    CLEANED_STATES=$(itr_cleanup_old_states 30 2>/dev/null || echo 0)

    # Detailed intrusiveness summary moved to silent log only (v1.7.2).
    # Session digest already written to intrusiveness-history.jsonl by
    # itr_append_history above. Carry-over surfacing happens on next session
    # via session-start.sh Signal 4 (AP3 pending debt).
fi

# H10 cross-contour surfacing — moved to silent file logging (v1.7.2).
# Metrics still written via cross-contour-surfaced-${SID}.txt and discoveries
# log; verbose Stop-message section dropped per user feedback. Audit available
# via /knowledge-audit and weekly digest.
CC_SURFACED_SID="${PAYLOAD_SID:-$SESSION_ID}"
CC_SURFACED_FILE="$STATE_DIR/cross-contour-surfaced-${CC_SURFACED_SID}.txt"

# Finalize session in registry — silent.
if [ "$HAS_REGISTRY" = true ]; then
    SUMMARY=""
    if [ "$HAD_STRUGGLE" = true ]; then
        SUMMARY="Session with errors/struggles"
    fi
    sr_finalize_session "$SUMMARY" 2>/dev/null || true
fi

# Compose minimal user-visible message.
#   - Default: silent (empty MESSAGE — no systemMessage emitted).
#   - HAD_STRUGGLE: short alert that errors happened (agent may /learn).
#   - PENDING_COUNT > 0: pending disagreements need closure on next session.
ALERTS=""
if [ "$HAD_STRUGGLE" = true ]; then
    ALERTS="${ALERTS}⚠️ В сессии были ошибки — рассмотри /learn. "
fi
if [ "${PENDING_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    # Формулировка честная: запись означает «blocker-tier знание было активно и не
    # получило исхода», а не «агент не согласился». Ложная этикетка → алерт читают
    # как шум → контур перестаёт закрываться.
    # Разбивка вместо голого числа: «16 без исхода» одинаково читается и как долг
    # недели, и как след соседней сессии, начатой двадцать минут назад. Считаем
    # отдельно то, по чему может действовать ЭТА сессия, и то, что реально залежалось.
    _dis_parts=""
    [ "${PENDING_MINE:-0}" -gt 0 ] 2>/dev/null && _dis_parts="${PENDING_MINE} в этой сессии"
    if [ "${PENDING_STALE:-0}" -gt 0 ] 2>/dev/null; then
        [ -n "$_dis_parts" ] && _dis_parts="${_dis_parts}, "
        _dis_parts="${_dis_parts}${PENDING_STALE} залежалось (${PENDING_STALE_DAYS}+ дн.)"
    fi
    if [ "${PENDING_FRESH:-0}" -gt 0 ] 2>/dev/null; then
        [ -n "$_dis_parts" ] && _dis_parts="${_dis_parts}, "
        _dis_parts="${_dis_parts}${PENDING_FRESH} в других свежих сессиях"
    fi
    # Склейка без параметрической подстановки: не-ASCII тире вплотную к `$var`
    # внутри `${x:+...}` — ровно класс pattern-shell-portability, blocker поймал
    # на первой же попытке (18-е подтверждение).
    _dis_line="${PENDING_COUNT} blocker-tier знание(й) без исхода"
    if [ -n "$_dis_parts" ]; then
        _dis_line="$_dis_line: $_dis_parts"
    fi
    ALERTS="${ALERTS}⚡ ${_dis_line}. "
fi
if [ "${EXPIRED_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    # Истёкшие показываем отдельно: это не работа, а признание, что данных не будет.
    ALERTS="${ALERTS}⌛ ${EXPIRED_COUNT} запись(ей) истекло без исхода. "
fi

# Долг проекта из BACKLOG.md (v1.14.0).
#
# Зачем. Собран список из 30 незакрытых пунктов одной сессии, и при сборке выяснилось:
# большинство были НАЗВАНЫ ВСЛУХ в тот же момент, когда пропущены. Раздел «Ограничения»
# в CHANGELOG работал как способ закрыть тему, а не как долг — прочитать его потом
# некому и нечем.
#
# BACKLOG.md существовал и до этого, но его не читал ни один хук: только
# `skills/project-health/SKILL.md` упоминал текстом. Отложенное испарялось не потому,
# что его не записывали, а потому что записанное никто не поднимал.
#
# Считаем открытые (`- ☐`) И взятые в работу (`- ◐`): по легенде BACKLOG.md обе метки
# означают «не сделано». Прежняя версия считала только ☐, и перевод пункта в «в работе»
# гасил алерт — долг умолкал ровно тогда, когда за него взялись и остановились.
# Порог env — в чужом проекте бэклог может быть длинным по устройству, и ежесессионный
# алерт станет фоном.
#
# Путь — абсолютный, а не от каталога сессии. `PAYLOAD_CWD` означал, что весь контур
# долга виден только пока работа идёт внутри самого ClaudSoul; из любого другого проекта
# долг молчал. Это тот же класс, что чинится этой правкой: обязанность, которая
# существует, но не наступает.
# Открытые пункты (☐/◐) до секции архива (## Архив/Archive/Done): сведённый бэклог
# держит закрытое в архиве, дублировать его в счётчик = шум. Нет архива → весь файл.
# awk-альтернация, а не класс `[☐◐]`: многобайтный символ в `[...]` = диапазон БАЙТОВ
# (pattern-shell-portability). Хелпер один на оба долга — ClaudSoul и локальный проект.
_bl_open_count() {
    [ -f "${1:-}" ] || { echo 0; return; }
    awk '/^##[[:space:]]+(Архив|Archive|Done)/{exit} /^- (☐|◐)/{c++} END{print c+0}' "$1" 2>/dev/null | tr -d '[:space:]'
}
BACKLOG_FILE="${CLAUDSOUL_BACKLOG:-$CLAUDSOUL_ROOT/BACKLOG.md}"
BACKLOG_OPEN=$(_bl_open_count "$BACKLOG_FILE")
: "${BACKLOG_OPEN:=0}"
if [ "${BACKLOG_OPEN:-0}" -ge "${BACKLOG_ALERT_MIN:-1}" ] 2>/dev/null; then
    # Если аудит /project-health ранее запускался (маркер в файле) — свод мог устареть:
    # предлагаем ре-аудит/сведение, а не только цифру. Сам аудит НЕ проводим — Stop-хук не
    # место для авто-мутаций (это и была бы «мусорка»); детектор лишь указывает команду.
    _bl_hint=""
    grep -q "project-health" "$BACKLOG_FILE" 2>/dev/null && _bl_hint=" Свод мог устареть → /project-health для ре-аудита."
    ALERTS="${ALERTS}📋 ${BACKLOG_OPEN} открытых пункт(ов) в BACKLOG.md — долг проекта.${_bl_hint} "
fi

# Уборка закрытых пунктов — ЗДЕСЬ, а не по недельному сроку.
#
# Правило собеседника (2026-08-25): «бэклог должен чиститься методом перенесения
# исполненного пункта в архив: есть процесс "отметить пункт", и по завершении отмеченные
# должны уезжать». Отметка — событие; уборка обязана быть его следствием, а не отдельной
# обязанностью с периодом. Прежняя схема (строка в реестре замеров, срок 7 дней) дважды
# кончилась одинаково: 1 августа собеседник сказал «бэклог не почистился», 25 августа —
# «а почему бэклог не очищен от исполненных». Между этими датами уборка просрочилась на
# девять дней, и всё это время шла правка самого BACKLOG.md.
#
# Про строку выше «Stop-хук не место для авто-мутаций». Она про АУДИТ (/project-health):
# он требует суждения, и его результат — новый текст, который кто-то должен принять.
# Уборка другого рода и это записано в шапке backlog-archive.sh: «её результат не требует
# суждения, а идемпотентность и сохранность свидетельств закрытий проверены тестом».
# Пункт не исчезает — он переезжает в BACKLOG-archive.md, оба файла под git. Прогон
# стоит 0,04 с. Различие названо здесь намеренно, чтобы правка не читалась как обход
# прежнего решения: запрет остаётся в силе для операций с суждением.
#
# Убирается ТОЛЬКО долг ClaudSoul. Локальный BACKLOG.md чужого проекта ниже по файлу
# лишь считается: у него свой формат и свой владелец, и переносить в нём что-либо по
# нашим меткам — правка чужого документа без спроса.
BACKLOG_ARCHIVER="${CLAUDSOUL_BACKLOG_ARCHIVER:-$CLAUDSOUL_ROOT/scripts/backlog-archive.sh}"
if [ -f "$BACKLOG_ARCHIVER" ] && [ -f "$BACKLOG_FILE" ]; then
    _bl_moved=$(BACKLOG_FILE="$BACKLOG_FILE" \
                BACKLOG_ARCHIVE="${CLAUDSOUL_BACKLOG_ARCHIVE:-${BACKLOG_FILE%/*}/BACKLOG-archive.md}" \
                bash "$BACKLOG_ARCHIVER" run 2>/dev/null \
                | awk -F': ' '/^Перенесено в архив:/ { split($2, a, " "); print a[1]; exit }')
    : "${_bl_moved:=0}"
    if [ "${_bl_moved:-0}" -gt 0 ] 2>/dev/null; then
        ALERTS="${ALERTS}🗄️ Закрытых пунктов унесено в BACKLOG-archive.md: ${_bl_moved} — оба файла изменены, добавь в коммит. "
    fi
fi

# Долг ИНИЦИИРОВАННОГО проекта (2026-08-07, просьба собеседника): локальный BACKLOG.md
# по cwd — В ДОПОЛНЕНИЕ к абсолютному ClaudSoul-долгу, не вместо. Урок v1.15.1 держится
# с двух сторон: cwd-only глушил кросс-проектный контур, absolute-only глушит локальный.
# Сигнал инициированности — сам файл BACKLOG.md в корне проекта.
LOCAL_BL_OPEN=0
if [ -n "${PAYLOAD_CWD:-}" ] && [ -f "$PAYLOAD_CWD/BACKLOG.md" ]; then
    _cs_root=$(cd "$CLAUDSOUL_ROOT" 2>/dev/null && pwd || printf '%s' "$CLAUDSOUL_ROOT")
    _cwd_real=$(cd "$PAYLOAD_CWD" 2>/dev/null && pwd || printf '%s' "$PAYLOAD_CWD")
    # В самом ClaudSoul локальный файл и есть ClaudSoul-долг — не считать дважды.
    if [ "$_cwd_real" != "$_cs_root" ]; then
        LOCAL_BL_OPEN=$(_bl_open_count "$PAYLOAD_CWD/BACKLOG.md")
        : "${LOCAL_BL_OPEN:=0}"
        if [ "${LOCAL_BL_OPEN:-0}" -ge "${BACKLOG_ALERT_MIN:-1}" ] 2>/dev/null; then
            ALERTS="${ALERTS}📋 ${LOCAL_BL_OPEN} открытых пункт(ов) в BACKLOG.md этого проекта ($(basename "$_cwd_real")). "
        fi
    fi
fi

# Просроченные замеры. Только СЧИТАЕТ (режим check) и ничего не запускает: Stop не место
# для долгой работы, а среди замеров есть прогон в контейнере. Повод завести это здесь,
# а не только в недельном дайджесте: замер «становится ли знание инструментом» случился
# лишь потому, что о нём спросили — у измерения не было ни владельца, ни срока, и его
# отсутствие ничем не обнаруживалось.
# Путь абсолютный по той же причине, что и у BACKLOG выше: срок, повешенный в реестре,
# спал, пока работа шла в другом проекте.
MEASURE_DUE_SH="${CLAUDSOUL_MEASURE_DUE:-$CLAUDSOUL_ROOT/scripts/measurement-due.sh}"
if [ -f "$MEASURE_DUE_SH" ]; then
    MEASURE_CHECK=$(bash "$MEASURE_DUE_SH" check 2>/dev/null || true)
    MEASURE_OVERDUE=$(printf '%s\n' "$MEASURE_CHECK" | grep -c '^  просрочен:' || true)
    : "${MEASURE_OVERDUE:=0}"
    if [ "${MEASURE_OVERDUE:-0}" -gt 0 ] 2>/dev/null; then
        # Имена, а не только число. Голое «8 просроченных замеров» на фоне длинной работы
        # неотличимо от прочего фона: оно не говорит, ЧТО просрочено, и потому не может
        # совпасть с тем, чем занят читатель. Живой случай (2026-08-25): просрочка
        # backlog-archive на 9 дней висела в этом алерте шесть ходов подряд, пока шла
        # правка самого BACKLOG.md, и была замечена только вопросом собеседника
        # «почему бэклог не очищен». Имя рядом с работой промахнуться не даёт.
        MEASURE_NAMES=$(printf '%s\n' "$MEASURE_CHECK" \
            | awk '/^  просрочен:/ { print $2 }' | head -4 | tr '\n' ' ' | sed 's/ $//')
        if [ "${MEASURE_OVERDUE:-0}" -gt 4 ]; then
            MEASURE_NAMES="${MEASURE_NAMES} и ещё $((MEASURE_OVERDUE - 4))"
        fi
        ALERTS="${ALERTS}📏 Просрочены замеры: ${MEASURE_NAMES}. Называет и ЗАПУСКАЕТ их scripts/measurement-due.sh. "
    fi
fi

# Compile reminder (Фаза 3 L1→L2): nudge to run /compile when raw material has
# accumulated past the threshold. Free, gate-aligned (once per session).
COMPILE_REMINDER_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/compile-reminder-lib.sh"
[ -f "$COMPILE_REMINDER_LIB" ] || COMPILE_REMINDER_LIB="$HOME/.claude/hooks/compile-reminder-lib.sh"
if [ -f "$COMPILE_REMINDER_LIB" ]; then
    # shellcheck source=/dev/null
    source "$COMPILE_REMINDER_LIB"
    COMPILE_NUDGE=$(compile_reminder_check "${PAYLOAD_SID:-$SESSION_ID}" 2>/dev/null || true)
    [ -n "$COMPILE_NUDGE" ] && ALERTS="${ALERTS}${COMPILE_NUDGE}"
fi

# Shared vocabulary (мост L3↔L7, v1.21.0): кандидаты в словарь из речи собеседника.
# Только предлагает — словарь курируется руками. Работает лишь там, где словарь уже
# заведён (файл существует): пара, не начавшая словарь, шума не получает.
for _shlang_lib in "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared-language-lib.sh" \
                   "$HOME/.claude/hooks/shared-language-lib.sh"; do
    [ -f "$_shlang_lib" ] && { . "$_shlang_lib"; break; }
done
if command -v shlang_candidates >/dev/null 2>&1 \
   && [ -n "${PAYLOAD_TRANSCRIPT:-}" ] && [ -f "${PAYLOAD_TRANSCRIPT:-}" ]; then
    _shlang_vocab=$(shlang_vocab_path "${PAYLOAD_CWD:-}")
    if [ -n "$_shlang_vocab" ] && [ -f "$_shlang_vocab" ]; then
        SHLANG_FOUND=$(shlang_candidates "$PAYLOAD_TRANSCRIPT" "$_shlang_vocab" 2>/dev/null \
            | awk 'BEGIN{ORS=""} NR>1{printf ", "} {printf "%s", $0}')
        [ -n "$SHLANG_FOUND" ] && \
            ALERTS="${ALERTS}🗣️ Кандидаты в shared vocabulary: ${SHLANG_FOUND} — если референс устойчив, добавь в словарь (мост L3↔L7). "
    fi
fi

if [ -n "$ALERTS" ]; then
    # Видимый канал: кладём алерты в очередь, pending-alerts-surface.sh покажет их
    # на следующем UserPromptSubmit через additionalContext. Причина: Stop→systemMessage
    # не отображается в части UI (VS Code) — алерты уходили в пустоту (case-2026-06-14).
    printf '%s\n' "$ALERTS" >> "$STATE_DIR/pending-alerts.txt" 2>/dev/null || true
    # Подробности с готовыми командами — только в очередь: она читается через
    # `jq -Rs` и переживает многострочность, а systemMessage собирается printf'ом
    # и сломался бы на переводе строки.
    [ -n "$PENDING_DETAIL" ] && \
        printf '%s\n' "$PENDING_DETAIL" >> "$STATE_DIR/pending-alerts.txt" 2>/dev/null || true
    printf '{"systemMessage": "%s"}\n' "$ALERTS"
fi
# Else: silent exit, no systemMessage. Detailed digest in intrusiveness-history.jsonl.

# Clean up THIS session's state files
# Note: disagreement-pending log is NOT cleaned — it persists across sessions
# until outcomes are closed via /learn. Agent reviews in startup context.
rm -f "$STATE_DIR/error_count_${SESSION_ID}" "$STATE_DIR/had_struggle_${SESSION_ID}" "$STATE_DIR/knowledge_injected_${SESSION_ID}" "$STATE_DIR/last_keywords_${SESSION_ID}" "$STATE_DIR/reformulation_last_fire_${SESSION_ID}" "$STATE_DIR/struggle-signatures_${SESSION_ID}.jsonl" "$STATE_DIR/cascading-events-${SESSION_ID}.jsonl" "$STATE_DIR/injection-bytes-peak-${SESSION_ID}" "$CC_SURFACED_FILE" 2>/dev/null

# Intrusiveness state: NOT deleted here — itr_cleanup_old_states above handles
# stale (>30d) files. Current session file survives so a re-opened terminal or
# follow-up session can still read it. Authoritative digest was already written
# to intrusiveness-history.jsonl.

exit 0
