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
# Третьим аргументом идёт КОРЕНЬ ПРОЕКТА, а не каталог сессии. Библиотека создаёт там
# `.claude-docs/` и дописывает файл, то есть ПИШЕТ в чужое дерево. Сырой cwd давал две беды
# сразу: из подкаталога запись ложилась в подкаталог (в одном месте — сама в себя,
# `.claude-docs/exports/.claude-docs/`), а вне проектов — в `/Users/user` и `~/Downloads`,
# где проекта нет вовсе. Замер 7 сентября 2026: 99 файлов, из них незакоммиченными в
# 9 чужих репозиториях. Пустой ответ помощника означает «писать некуда» и это законно.
_SC_PROJ_ROOT=""
command -v project_root_or_empty >/dev/null 2>&1 && [ -n "$PAYLOAD_CWD" ] \
    && _SC_PROJ_ROOT=$(project_root_or_empty "$PAYLOAD_CWD")
if [ -f "$ACTIVITY_LIB" ] && [ -n "$PAYLOAD_SID" ] && [ -n "$PAYLOAD_TRANSCRIPT" ] && [ -n "$_SC_PROJ_ROOT" ]; then
    # shellcheck source=/dev/null
    source "$ACTIVITY_LIB"
    activity_flush "$PAYLOAD_SID" "$PAYLOAD_TRANSCRIPT" "$_SC_PROJ_ROOT" >/dev/null 2>&1 || true
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
# Единый счётчик «прошедшего»: дни ОПЫТА, не календаря (D234). Библиотеки нет — каждый
# потребитель ниже сам падает на календарь, прежнее поведение.
FSRS_LIB="${FSRS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/fsrs-lib.sh}"
[ -f "$FSRS_LIB" ] || FSRS_LIB="$HOME/.claude/hooks/fsrs-lib.sh"
# shellcheck source=/dev/null
[ -f "$FSRS_LIB" ] && source "$FSRS_LIB" 2>/dev/null || true
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
    # Третий продюсер (D229): кандидаты там, где знание было показано и ход вскоре упал
    # (серия провалов команд либо внешнее событие мира — откат, красный CI).
    command -v dis_harvest_failures >/dev/null 2>&1 && \
        dis_harvest_failures "$DIS_SID" "$STATE_DIR" >/dev/null 2>&1 || true
    # Затем гасим просроченные — иначе алерт растёт бесконечно и становится фоном,
    # ровно как предупреждал комментарий продюсера в knowledge-activator.
    EXPIRED_COUNT=$(dis_expire_old "${DISAGREEMENT_EXPIRE_DAYS:-7}" "$STATE_DIR" 2>/dev/null || echo 0)
    OPEN_RECORDS=$(dis_scan_open "$STATE_DIR" 2>/dev/null || true)
    if [ -n "$OPEN_RECORDS" ]; then
        PENDING_COUNT=$(printf '%s\n' "$OPEN_RECORDS" | grep -c '') || PENDING_COUNT=0
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
        # ЗАЛЕЖАЛОСЬ — МЕРА ОПЫТА, НЕ КАЛЕНДАРЯ (D234, 10 сентября 2026). Запись
        # несогласия ждёт исхода, а исход приносит РАБОТА: за год тишины ни одна запись
        # не «залежалась», хотя календарь насчитает 365 дней. Обе проверки возраста
        # зовут одно, чтобы единица не объявлялась заново в каждой (D234, род K).
        # ВОЗРАСТ ЗАПИСИ — КАЛЕНДАРНЫЙ, и это ревизия перевода от 10 сентября 2026 (D391).
        # «Залежалось» не самостоятельный срок, а ТОЧКА ВНУТРИ окна жизни записи; окно задаёт
        # `dis_expire_old` (`hooks/disagreement-lib.sh:157`), и оно календарное осознанно, с
        # доводом и замером в той же шапке: неразрешимой запись делает ушедший контекст, а
        # сессия линейкой не годится — одна дала 156 событий Stop и шла сутки, другая
        # закрылась за минуту, разброс в 150 раз.
        # Точку и границу ОДНОГО окна нельзя мерить разными единицами, и цена измерена:
        # при темпе 11 сентября 2026 семь календарных дней равнялись трём дням опыта, то
        # есть ровно порогу «залежалось» — окно схлопнулось в точку, запись истекала в тот
        # самый миг, когда её впервые можно было так назвать. Ноги T15d/T15e держали это
        # красным, и правы были они, а не механизм.
        # Правило «периодичность в единицах работы» здесь не нарушено: оно про СРОК, который
        # механизм назначает сам, а тут срок задан соседом, и единица берётся у него.
        _dis_age_days() {
            local _e="$1"
            printf '%s' "$(( (_dis_now - _e) / 86400 ))"
        }
        PENDING_MINE=0
        PENDING_STALE=0
        # Состав очереди по ПРОДЮСЕРУ. Продюсеров три, а этикетка называла один: жнецы
        # (disagreement-lib.sh:190 corrections, :270 failures) фильтруют по типу записи
        # знания, а не по флагу blocker — см. «этикетка» ниже. Признак берётся из поля
        # `tool`, которое dis_scan_open отдаёт и так: у ветки блокера там имя инструмента
        # вызова, у жнецов — «correction» / «failure». Замер на 282 открытых: разбор по
        # полю `class` и по полю `tool` дал одно и то же — 10 / 91 / 181, — поэтому лишнего
        # чтения журналов не заводим.
        PENDING_BLOCKER=0
        PENDING_CORR=0
        PENDING_FAIL=0
        while IFS='|' read -r s k d c t; do
            [ -n "$k" ] || continue
            case "$t" in
                correction) PENDING_CORR=$((PENDING_CORR + 1)) ;;
                failure)    PENDING_FAIL=$((PENDING_FAIL + 1)) ;;
                *)          PENDING_BLOCKER=$((PENDING_BLOCKER + 1)) ;;
            esac
            if [ "$s" = "$DIS_SID" ]; then
                PENDING_MINE=$((PENDING_MINE + 1))
                continue
            fi
            _e=$(iso_epoch "$d" 2>/dev/null || echo 0)
            [ "${_e:-0}" -gt 0 ] 2>/dev/null || continue
            [ "$(_dis_age_days "$_e")" -ge "$PENDING_STALE_DAYS" ] \
                && PENDING_STALE=$((PENDING_STALE + 1))
        done <<DIS_EOF
$OPEN_RECORDS
DIS_EOF
        PENDING_FRESH=$((PENDING_COUNT - PENDING_MINE - PENDING_STALE))
        # Готовая команда вместо «запусти /learn»: скилл целиком ради одной строки —
        # цена, которую платят не всегда, а контур без закрытия не измеряет ничего.
        #
        # ПРЕДЕЛ (8 сентября 2026). На запись приходится 5-6 строк и отдельный вызов jq, а
        # подходящих записей бывают сотни: замер по 298 файлам инжекта дал средний размер
        # 113 529 байт и максимум 1 206 838. Соседний алерт этого же файла предел уже имеет
        # (имена просроченных замеров, :480-484). Ограничение стоит внутри цикла, а не
        # `| head`: под конвейером head закрыл бы трубу и дал SIGPIPE 141 (D239).
        # Число подходящих известно заранее — фильтр здесь тот же, что у счётчиков выше
        # (свои целиком + чужие залежавшиеся), поэтому хвост считается, а не угадывается.
        _dis_detail_max="${DIS_DETAIL_MAX:-8}"
        PENDING_DETAIL=$(_det_n=0; printf '%s\n' "$OPEN_RECORDS" | while IFS='|' read -r s k d c t; do
            [ -n "$k" ] || continue
            # Чужую запись показываем детально, только если она залежалась.
            if [ "$s" != "$DIS_SID" ]; then
                _e=$(iso_epoch "$d" 2>/dev/null || echo 0)
                [ "${_e:-0}" -gt 0 ] 2>/dev/null || continue
                [ "$(_dis_age_days "$_e")" -ge "$PENDING_STALE_DAYS" ] || continue
            fi
            _det_n=$((_det_n + 1))
            [ "$_det_n" -le "$_dis_detail_max" ] || continue
            printf '   ⚡ %s (conf %s, %s, инструмент %s)\n' "$k" "${c:-?}" "${d:-?}" "${t:-?}"
            # Улика для судьи: цитата поправки, замороженная жнецом в pending-записи.
            # Без неё вердикт выносился вслепую — 304 кандидата → 0 опровержений
            # (диагностика 2026-08-31); dis_scan_open не трогаем: его контракт `|`
            # произвольный текст собеседника сломал бы, читаем поле из JSONL напрямую.
            _snip=$(jq -rR --arg k "$k" \
                'fromjson? // empty | select(.key == $k and .outcome == "pending") | .snippet // empty' \
                "$STATE_DIR/disagreement-pending-${s}.jsonl" 2>/dev/null | tail -1)
            [ -n "$_snip" ] && printf '      цитата поправки: «%s»\n' "$_snip"
            printf '      верно     → DIS_SESSION=%s bash ~/.claude/hooks/knowledge-counter-bump.sh %s confirmed "<почему>"\n' "$s" "$k"
            printf '      ошиблось  → DIS_SESSION=%s bash ~/.claude/hooks/knowledge-counter-bump.sh %s contradicted "<что разошлось>"  # затем /retro: narrow/branch/deprecate + кейс\n' "$s" "$k"
            printf '      не к месту→ DIS_SESSION=%s bash ~/.claude/hooks/knowledge-counter-bump.sh %s not_applicable "<почему мимо>"\n' "$s" "$k"
            printf '      не применил→ DIS_SESSION=%s bash ~/.claude/hooks/knowledge-counter-bump.sh %s applicable_not_followed "<что помешало>"\n' "$s" "$k"
        done)
        _dis_detail_all=$((PENDING_MINE + PENDING_STALE))
        if [ "$_dis_detail_all" -gt "$_dis_detail_max" ] 2>/dev/null; then
            PENDING_DETAIL="${PENDING_DETAIL}
   ⚡ …и ещё $((_dis_detail_all - _dis_detail_max)) запис(ей) — перечень целиком:
      bash -c 'source ~/.claude/hooks/disagreement-lib.sh; dis_scan_open'"
        fi
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
        BWD_COUNT=$(grep -c '"trigger":"BACKWARD"' "$CASCADE_LOG" 2>/dev/null) || BWD_COUNT=0
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
# Постоянное состояние держится отдельно от событийного: ⚡/📋/📏 описывают мир, который
# сам между ходами не меняется, и потому обязаны идти через дроссель (ниже, перед записью
# в очередь). Событийные строки (⚠️ ошибки, ⌛ истекло, 🗄️ архиватор) самоустраняются и
# дросселя не требуют. Повод — замер 7 сентября 2026: свод нёс 69-94% пользовательских
# ходов в четырёх сессиях подряд.
ALERTS_PERSIST=""
if [ "$HAD_STRUGGLE" = true ]; then
    ALERTS="${ALERTS}⚠️ В сессии были ошибки — рассмотри /learn. "
fi
if [ "${PENDING_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    # Формулировка честная: запись означает «знание было активно и не получило исхода»,
    # а не «агент не согласился». Ложная этикетка → алерт читают как шум → контур
    # перестаёт закрываться.
    #
    # ЭТИКЕТКА ИСПРАВЛЕНА 8 сентября 2026 (род L — область механизма шире предмета его
    # утверждения). Здесь стояло «blocker-tier знание(й) без исхода». Это было верно, пока
    # продюсер был один — ветка блокера в knowledge-activator.sh. Потом добавились два
    # жнеца (D229) с другим признаком, а текст не пересмотрели. Замер на 282 открытых
    # записях: blocker-tier 10 (3,5%), от поправок 91, от провалов 181 — то есть этикетка
    # врала в 96% случаев и раздувала восприятие долга. Состав печатается потому, что он
    # говорит, ЧЕМ запись закрывать: у блокера и у жнеца это разные вопросы.
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
    _dis_line="${PENDING_COUNT} знание(й) без исхода (blocker-tier ${PENDING_BLOCKER}, от поправок ${PENDING_CORR}, от провалов ${PENDING_FAIL})"
    if [ -n "$_dis_parts" ]; then
        _dis_line="$_dis_line: $_dis_parts"
    fi
    ALERTS_PERSIST="${ALERTS_PERSIST}⚡ ${_dis_line}. "
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
    # РАБОТА И ОЖИДАНИЕ — ПОРОЗНЬ, И НАЗВАН СЛЕДУЮЩИЙ (12 сентября 2026, план разгребания
    # долга). Одно число смешивало пункты, которые закрывает работа, с пунктами, которые
    # закрывает событие мира (у них `**Проверка возврата:** \`команда\``): 43 открытых читались
    # как 43 дела, а дел было 37. Порядок взятия жил в голове — теперь его несёт строка
    # `**Очередь.**` пункта, и коллектор называет наименьший номер среди ☐ без команды
    # возврата; взятый (◐) печатается как «в работе», а не как «следующий». Разбор пункта на
    # поля — у единственного владельца `backlog_open_items` (backlog-lib.sh); без библиотеки
    # строка остаётся прежней. `_bl_open_count` сохраняется для N: он останавливается на
    # «## Архив» (T12a), а разбор библиотеки идёт по файлу целиком.
    # ponytail: K считает ☐ с командой по всему файлу — пункт-ожидание ниже «## Архив»
    # попал бы в K, но не в N; в корпусе таких нет (архив держит только закрытое).
    _bl_detail=""
    _BLL="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/backlog-lib.sh"
    [ -f "$_BLL" ] || _BLL="$HOME/.claude/hooks/backlog-lib.sh"
    if [ -f "$_BLL" ]; then
        # shellcheck source=/dev/null
        . "$_BLL" 2>/dev/null || true
    fi
    if command -v backlog_open_items >/dev/null 2>&1; then
        _bl_rows=$(backlog_open_items "$BACKLOG_FILE" 2>/dev/null || true)
        _bl_detail=$(printf '%s\n' "$_bl_rows" | awk -F'\t' -v n="$BACKLOG_OPEN" \
            -v todo="${BACKLOG_MARK_TODO:-☐}" -v wip="${BACKLOG_MARK_WIP:-◐}" '
            $2 == todo && $3 == "cmd" { k++ }
            $2 == wip { w = w " " $1 }
            $2 == todo && $3 != "cmd" && $4 ~ /^[1-9][0-9]*$/ && (nq == "" || $4 + 0 < nq + 0) { nq = $4; nid = $1; nroot = $5 }
            END {
                m = n - k; if (m < 0) m = 0
                s = ": " m " в работе, " k " ждут условия (команда возврата задана)"
                if (w != "") s = s "; в работе:" w
                else if (nid != "") s = s "; следующий к взятию: " nid " (очередь " nq (nroot != "" ? ", корень " nroot : "") ")"
                print s
            }' 2>/dev/null || true)
    fi
    ALERTS_PERSIST="${ALERTS_PERSIST}📋 ${BACKLOG_OPEN} открытых пункт(ов) в BACKLOG.md — долг проекта${_bl_detail:-.}${_bl_hint} "
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
    # ответ архиватора — данные, не статус жизни хука: exit 1 — его ЗАКОННЫЙ отказ
    # («красная Проверка — не закрытие»; на вязкой машине ещё и rc=125 по таймауту
    # команды пункта), а awk с ранним exit добавляет SIGPIPE производителю — без
    # || true любой из двух убивал Stop-коллектор целиком, включая всё после этой
    # строки (T1-T3 теста ловили именно это; разбор — D239-сессия 2026-09-01)
    # Вывод берётся ЦЕЛИКОМ, а не сразу процеживается awk: у архиватора несколько
    # законных исходов, и «строки с числом нет» само по себе отказом НЕ является.
    # Перечень снят с самого архиватора 5 сентября 2026 (`grep -oE 'print\(f?"'` по
    # scripts/backlog-archive.sh) — первая редакция этой ветки строилась на непроверенной
    # посылке «строка с числом печатается всегда, включая ноль» и объявляла бы отказом
    # самый частый случай, давая ложную тревогу на каждом Stop. Род B в починке рода B.
    # stderr берётся ВМЕСТЕ со stdout: часть законных исходов архиватор печатает именно
    # туда («архив недоступен», «библиотека старше скрипта»), и с `2>/dev/null` они
    # выглядели бы немотой. Число всё равно снимается якорем `^Перенесено в архив:`.
    _bl_out=$(BACKLOG_FILE="$BACKLOG_FILE" \
              BACKLOG_ARCHIVE="${CLAUDSOUL_BACKLOG_ARCHIVE:-${BACKLOG_FILE%/*}/BACKLOG-archive.md}" \
              bash "$BACKLOG_ARCHIVER" run 2>&1 || true)
    _bl_moved=$(printf '%s\n' "$_bl_out" \
                | awk -F': ' '/^Перенесено в архив:/ { split($2, a, " "); print a[1]; exit }' || true)
    if [ -z "$_bl_moved" ]; then
        # Перечень снят СО СТОРОНЫ ПРОИЗВОДИТЕЛЯ (`grep -nE '^\s*(echo|print\()'` по
        # scripts/backlog-archive.sh), а не по фразе, знакомой отсюда: первая редакция
        # знала одну строку из семи и потому объявляла отказом самый частый случай.
        case "$_bl_out" in
            *"Переносить нечего"*|*"Закрытие без показания"*|*"Вложенный прогон"*\
            |*"архив недоступен"*|*"старше скрипта"*|*"нет определения пункта"*) _bl_moved=0 ;;
            *)  ALERTS="${ALERTS}🗄️ Архиватор долга НЕ ОТВЕТИЛ ни одним известным исходом — это не «переносить нечего»; прогони bash scripts/backlog-archive.sh run руками. "
                _bl_moved=0 ;;
        esac
    fi
    if [ "${_bl_moved:-0}" -gt 0 ] 2>/dev/null; then
        ALERTS="${ALERTS}🗄️ Закрытых пунктов унесено в BACKLOG-archive.md: ${_bl_moved} — оба файла изменены, добавь в коммит. "
    fi
fi

# Показания открытых пунктов — ЗДЕСЬ же, на каждом Stop, после архиватора (D210).
#
# Показание утверждает о МИРЕ (журнал исходов, состояние), а мир меняется каждым ходом
# независимо от того, трогали ли BACKLOG.md. Пересчёт только по правке файла устарел через
# 50 минут после введения (30 августа 2026, 01:14, вопрос владельца «как было 19, так и
# осталось?»). Граница хода — единственное событие, которое наступает всегда.
#
# ПОЧЕМУ ПОСЛЕ АРХИВАТОРА И ТЕМ ЖЕ ХУКОМ. Оба переписывают BACKLOG.md целиком («прочитал →
# посчитал → записал»); два писателя на одном событии без гарантированного порядка — гонка,
# в которой унесённые в архив пункты воскресают. Здесь они последовательны.
# Пересчёт сохраняет mtime файла (см. шапку scripts/backlog-refresh-readings.sh): сверщик
# `declared-problem-recorded` судит об исходе хода по mtime носителя, а пересчёт — не запись
# агента. Локальный бэклог инициированного проекта считается тем же способом по cwd
# (предел тот же, что у сверщика: вложенный CLAUDE.md/.git отдаёт подпапку).
_bl_refresh_readings() {   # <BACKLOG.md> — пересчитать показания, если рядом есть пересчётчик
    _rr_file="${1:-}"
    [ -f "$_rr_file" ] || return 0
    _rr_root=$(cd "${_rr_file%/*}" 2>/dev/null && pwd -P) || return 0
    _rr_script="$_rr_root/scripts/backlog-refresh-readings.sh"
    [ -f "$_rr_script" ] || return 0
    # ДРОССЕЛЬ ПО ВРЕМЕНИ (10 сентября 2026). Пересчёт исполняет команды показаний ВСЕХ
    # открытых пунктов, а команда там — произвольная. Замер: граница хода стоила 39 секунд,
    # из них 35 — этот пересчёт, и 29,5 из тридцати пяти брала ОДНА команда, зовущая
    # `docs-refresh-claims.sh --check`, который сам исполняет 173 команды-источника.
    # Показаний девять, тяжёлое одно — разделитель назван: тяжесть даёт вызов ДРУГОГО прибора
    # целиком, а не подсчёт по файлу.
    # Дефект виден был как «тесты зависают под нагрузкой»: `test_disagreement_loop` зовёт
    # сборщик несколько раз и упирался в таймаут 120 с — 10 прогонов из 10. Нагрузка тут ни
    # при чём, и одиночный прогон это показал: 229 секунд, вывод пуст.
    # Правило дерева уже есть и записано у соседа: на Stop произвольные команды не
    # исполняются (D321) — `measurement-due` зовётся там режимом `check`, где команд нет.
    # К пересчёту показаний его не применили; здесь применяется мягкая форма — не запрет, а
    # срок: показание не обязано быть свежее десяти минут, а граница хода обязана быть быстрой.
    #
    # ЕДИНИЦА ДРОССЕЛЯ — ХОДЫ, А НЕ ЧАСЫ (10 сентября 2026, поправка владельца). Первая
    # редакция этого дросселя стояла на десяти МИНУТАХ, и владелец назвал дефект прежде,
    # чем он проявился: «Я за день могу 100500 инструментов сделать, а могу через год
    # компьютер открыть. ВРЕМЯ НЕ ПОКАЗАТЕЛЬ при периодичности». Правило записано в дереве
    # (rules/CLAUDE.md:98, D234) и до этого дня имело потребителей только в контуре знаний:
    # замер того же дня — мест, решающих «пора ли», шесть, календарём решали шесть.
    # Предмет здесь — «устарело ли показание», а показание устаревает от РАБОТЫ: сто ходов
    # за десять минут оставляли его свежим, а один ход через год объявлял просроченным.
    # Ход — та же мера опыта, только мельче дня: пересчёт нужен внутри сессии, а дни опыта
    # различают только сессии.
    #
    # ПОЧЕМУ НЕ ПРЕДМЕТ, КАК У СОСЕДА. `completion-gate` на том же Stop исполняет 41
    # «Проверку» и защищён иначе — по mtime самого BACKLOG.md: файл не менялся, проверки
    # пропущены (замер: 21 с при изменённом бэклоге, 0 с при неизменном). Это точнее часов,
    # и соблазн повторить приём здесь был. Он не годится: «Проверка» судит БЭКЛОГ, а
    # показание — МИР, и мир меняется без правки бэклога. Ключ по mtime файла оставил бы
    # показание устаревшим молча — ровно тот дефект, ради которого пересчёт и заведён.
    # Отметка несёт СЧЁТЧИК ХОДОВ с прошлого пересчёта, а не время: этот хук зовётся ровно
    # раз на границу хода, поэтому его собственные вызовы и есть мера наработанного.
    # НАЗВАННЫЙ ПРЕДЕЛ: файл общий для параллельных сессий и пишется без замка. Гонка здесь
    # теряет инкремент либо обнуляет счётчик — последствие «пересчитали ходом позже или
    # раньше», а не порча: замок берётся там, где гонка портит (род H), и это не тот случай.
    _rr_stamp="${STATE_DIR:-$HOME/.claude/hooks/state}/backlog-readings-turns"
    # `|| true` обязателен: файл 15 объявляет `set -euo pipefail`, и `cat` на ещё не
    # созданной отметке отдаёт 1, а `pipefail` протаскивает этот код через трубу в
    # присваивание — хук умирает молча, до `exit 0`, с кодом 1 на КАЖДОМ Stop.
    _rr_n=$( { cat "$_rr_stamp" 2>/dev/null || true; } | tr -dc '0-9' )
    case "${_rr_n:-}" in ''|*[!0-9]*) _rr_n=0 ;; esac
    _rr_n=$((_rr_n + 1))
    if [ "$_rr_n" -lt "${BACKLOG_READINGS_EVERY_TURNS:-20}" ]; then
        printf '%s' "$_rr_n" > "$_rr_stamp" 2>/dev/null || true
        return 0
    fi
    printf '0' > "$_rr_stamp" 2>/dev/null || true
    BACKLOG_FILE="$_rr_file" CLAUDSOUL_REPO="$_rr_root" bash "$_rr_script" run >/dev/null 2>&1 || true
}
_bl_refresh_readings "$BACKLOG_FILE"
if [ -n "${PAYLOAD_CWD:-}" ] && command -v find_project_root >/dev/null 2>&1; then
    _rr_local_root=$(find_project_root "$PAYLOAD_CWD")
    _rr_cs_root=$(cd "$CLAUDSOUL_ROOT" 2>/dev/null && pwd -P || printf '%s' "$CLAUDSOUL_ROOT")
    if [ -n "${_rr_local_root:-}" ] && [ "$_rr_local_root" != "$_rr_cs_root" ]; then
        _bl_refresh_readings "$_rr_local_root/BACKLOG.md"
    fi
fi

# Долг ИНИЦИИРОВАННОГО проекта (2026-08-07, просьба собеседника): локальный BACKLOG.md
# по cwd — В ДОПОЛНЕНИЕ к абсолютному ClaudSoul-долгу, не вместо. Урок v1.15.1 держится
# с двух сторон: cwd-only глушил кросс-проектный контур, absolute-only глушит локальный.
# Сигнал инициированности — сам файл BACKLOG.md в корне проекта.
LOCAL_BL_OPEN=0
# Корень берётся подъёмом (`find_project_root`, значение посчитано выше на этом же ходу),
# а не как cwd. Из подпапки инициированного проекта — например `ProjectA_NEW/web`, отдельная
# запись в реестре сессий, — файл в корне не виден, и локальный долг молчал. Три соседних
# хука того же контура (declared-problem-recorded:64, completion-gate:120,
# backlog-touch-check:96) ходят подъёмом; расходился один этот.
_LOCAL_BL_ROOT="${_rr_local_root:-${PAYLOAD_CWD:-}}"
if [ -n "${_LOCAL_BL_ROOT:-}" ] && [ -f "$_LOCAL_BL_ROOT/BACKLOG.md" ]; then
    _cs_root=$(cd "$CLAUDSOUL_ROOT" 2>/dev/null && pwd || printf '%s' "$CLAUDSOUL_ROOT")
    _cwd_real=$(cd "$_LOCAL_BL_ROOT" 2>/dev/null && pwd || printf '%s' "$_LOCAL_BL_ROOT")
    # В самом ClaudSoul локальный файл и есть ClaudSoul-долг — не считать дважды.
    if [ "$_cwd_real" != "$_cs_root" ]; then
        LOCAL_BL_OPEN=$(_bl_open_count "$_LOCAL_BL_ROOT/BACKLOG.md")
        : "${LOCAL_BL_OPEN:=0}"
        if [ "${LOCAL_BL_OPEN:-0}" -ge "${BACKLOG_ALERT_MIN:-1}" ] 2>/dev/null; then
            ALERTS_PERSIST="${ALERTS_PERSIST}📋 ${LOCAL_BL_OPEN} открытых пункт(ов) в BACKLOG.md этого проекта ($(basename "$_cwd_real")). "
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
        # лимит внутри awk, не `| head -4`: при >4 просроченных head выходил раньше,
        # awk ловил SIGPIPE 141, и под set -euo pipefail Stop-коллектор гиб (D239)
        MEASURE_NAMES=$(printf '%s\n' "$MEASURE_CHECK" \
            | awk '/^  просрочен:/ && ++n<=4 { print $2 }' | tr '\n' ' ' | sed 's/ $//')
        if [ "${MEASURE_OVERDUE:-0}" -gt 4 ]; then
            MEASURE_NAMES="${MEASURE_NAMES} и ещё $((MEASURE_OVERDUE - 4))"
        fi
        # Текст говорит то, что механизм ДЕЛАЕТ. Прежняя редакция обещала «Называет и
        # ЗАПУСКАЕТ их», тогда как выше (:447) бегун зовётся режимом `check`, а в нём команды
        # НЕ ИСПОЛНЯЮТСЯ вовсе (`[ "$MODE" = "check" ] && continue`). Запускать их здесь и
        # нельзя: исполнение произвольных команд на границе хода — повод шторма из 2225
        # процессов 1 сентября 2026, и запрет держит пункт D321. Замер 7 сентября 2026:
        # замеры числились просроченными с 30 августа, то есть обещание не исполнялось ни
        # разу за восемь дней. Сообщение, обещающее чужую работу, хуже молчания: оно
        # закрывает вопрос, не решив его.
        ALERTS_PERSIST="${ALERTS_PERSIST}📏 Просрочены замеры: ${MEASURE_NAMES}. Здесь они только НАЗВАНЫ — на границе хода произвольные команды не запускаются (D321). Прогнать: bash scripts/measurement-due.sh run. "
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

# ДРОССЕЛЬ ПОСТОЯННОГО СОСТОЯНИЯ (8 сентября 2026).
#
# Очередь pending-alerts.txt даёт доставку-ровно-один-раз для каждой ДОПИСАННОЙ строки, но
# не мешает дописать ту же строку заново на следующем Stop — а Stop наступает каждый ход.
# Замер по расшифровкам: доля пользовательских ходов, несущих свод, — 52/64, 46/67, 41/48,
# 31/33 (69-94%). Оба соседних производителя этой же очереди дроссель имеют
# (carrier-growth-check.sh:106-119, install-drift-notice.sh:62-68) — без него канал не гасит
# фон, а переносит его в другое место.
#
# КЛЮЧ — ВИДЫ присутствующих алертов, а не их тело. Дедуп по телу снял бы 7 показов из 52:
# число открытых записей меняется почти каждый ход, а сказать при этом нечего. Сменился
# СОСТАВ (появился новый вид, пропал прежний) — свод звучит заново.
#
# Нет библиотеки — дросселя нет, но канал остаётся: повтор в очереди дешевле потерянного
# алерта (та же развилка, что в carrier-growth-check.sh:113-115).
# ОБНАРУЖЕНИЕ БЕЗ ИСХОДА (8 сентября 2026). Повод — владелец: «ты должен реагировать при
# обнаружении симптома. ЛЮБОГО», и уточнение «событие-триггер глубже» → незакрытость.
# Разбор: распознавание и запись работали, возврата не было. Гейт пишет исход каждого
# сигнала, среди исходов есть `deferred` и `none`, но читали их ТОЛЬКО замеры — как
# статистику. Из трёх родов сигнала возврат имели два (знания без исхода, пункты долга),
# обнаружения — ни одного. Накоплено к тому дню: 115 незакрытых в 43 журналах, самое старое
# от 29 августа 2026.
# Строка ПОСТОЯННАЯ: состояние само не меняется между ходами, поэтому идёт в ALERTS_PERSIST
# и проходит дроссель ниже наравне с прочими.
_OF_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/lib/open-findings-lib.sh"
[ -f "$_OF_LIB" ] || _OF_LIB="$HOME/.claude/hooks/lib/open-findings-lib.sh"
if [ -f "$_OF_LIB" ]; then
    # shellcheck source=/dev/null
    . "$_OF_LIB"
    if command -v of_open_counts >/dev/null 2>&1; then
        # `|| true` не косметика: файл идёт под `set -euo pipefail`, а прибор при поломке
        # ВОЗВРАЩАЕТ 2 — и простое присваивание из подстановки убивало весь свод. Замер
        # 8 сентября 2026: ни свода, ни очереди алертов, ни чистки состояния, вывод пуст.
        # Отказ прибора, задуманный как видимый, оказался смертельнее нуля, который заменял.
        # Код возврата и вывод берутся ПОРОЗНЬ: при частичном счёте (часть журналов
        # не прочитана) прибор отдаёт и числа, и ненулевой код — а `||` выбросил бы числа.
        # Ветка `if` заодно снимает `set -e`, из-за которого свод умирал целиком.
        if _of_line=$(of_open_counts "$STATE_DIR" 2>/dev/null); then _of_rc=0; else _of_rc=$?; fi
        case "$_of_line" in "") _of_line="BROKEN BROKEN прибор не ответил (код ${_of_rc})" ;; esac
        _of_def=$(printf '%s' "$_of_line" | awk '{print $1}')
        _of_none=$(printf '%s' "$_of_line" | awk '{print $2}')
        _of_old=$(printf '%s' "$_of_line" | awk '{print $3}')
        _of_unread=$(printf '%s' "$_of_line" | awk '{print $4 + 0}')
        # Поломка называется словом, а не арифметикой: `«BROKEN» + 0` даёт 0, и прежний
        # гейт `-gt 0` молчал ровно там, где обязан был кричать.
        if [ "${_of_def:-}" = "BROKEN" ]; then
            ALERTS_PERSIST="${ALERTS_PERSIST}🔎 Счёт поводов без исхода сломан: $(printf '%s' "$_of_line" | cut -d' ' -f3-). Молчание этой строки больше не значит «незакрытого нет». "
        elif [ "$(printf '%s' "${_of_def:-0}" | awk '{print $1 + 0}')" -gt 0 ] 2>/dev/null || [ "$(printf '%s' "${_of_none:-0}" | awk '{print $1 + 0}')" -gt 0 ] 2>/dev/null; then
            _of_age=""
            if [ -n "${_of_old:-}" ] && command -v iso_epoch >/dev/null 2>&1; then
                _of_e=$(iso_epoch "$_of_old" 2>/dev/null || echo 0)
                if [ "${_of_e:-0}" -gt 0 ] 2>/dev/null; then
                    _of_days=$(( ( $(date +%s) - _of_e ) / 86400 ))
                    [ "$_of_days" -gt 0 ] 2>/dev/null && _of_age=", самому старому ${_of_days} дн."
                fi
            fi
            # `none` и `deferred` названы РАЗДЕЛЬНО: первое значит «исход не наблюдался»
            # (сверщик видит четыре вида действий и мог не увидеть пятый), второе — «отказ
            # сработал, правка отложена». Решение по ним разное, и сливать их в одно число
            # значило бы повторить ту же ошибку, из-за которой они и копились.
            _of_bad=""
            # Непрочитанное называется ВСЕГДА, а не только когда счёт ненулевой: частичное
            # число, выданное за полное, — тот же род B, что и молчаливый ноль.
            [ "${_of_unread:-0}" -gt 0 ] 2>/dev/null && _of_bad=", журналов НЕ ПРОЧИТАНО: ${_of_unread} — счёт неполон"
            # Число УБЫВАЕТ: запись закрывающего исхода того же вида гасит самое раннее
            # незакрытое. Прежняя редакция считала строки и потому росла всегда — требование
            # «довести до исхода» было неисполнимо по построению, что и доказал противник
            # 8 сентября 2026. Названный предел зачёта честный: он говорит СКОЛЬКО повисло,
            # а не КАКОЙ именно повис, — связать закрытие с конкретным поводом нечем, пока
            # закрывающая запись не несёт ссылку на ключ закрываемого.
            # Условие снятия: закрывающая запись начнёт нести ключ закрываемого повода —
            # тогда зачёт сменится сопоставлением, и приближение уйдёт вместе с пределом.
            ALERTS_PERSIST="${ALERTS_PERSIST}🔎 Поводов разбора без исхода: ${_of_def} отложено, ${_of_none} без наблюдаемого исхода${_of_age}${_of_bad}. Довести до исхода (bash scripts/outcome.sh — исход, вид, почему) либо назвать «показалось» — число убывает зачётом по виду сигнала. "
        fi
    fi
fi

if [ -n "$ALERTS_PERSIST" ]; then
    for _sc_thr in "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/throttle-lib.sh" \
                   "$HOME/.claude/hooks/throttle-lib.sh"; do
        # shellcheck source=/dev/null
        [ -f "$_sc_thr" ] && { . "$_sc_thr"; break; }
    done
    if command -v throttle_file >/dev/null 2>&1; then
        # Ключ несёт виды алертов и СОСТАВ категорий внутри ⚡ — но не числа. Голого вида
        # мало: тест T15d/T15e (test_disagreement_loop.sh:186-187) поймал потерю сигнала —
        # переход записи из «чужая свежая» в «залежавшуюся» есть событие, а не рост
        # счётчика, и молчать о нём нельзя. Числа в ключ по-прежнему не входят: 145→146
        # звучать не должно.
        _sc_kinds=""
        case "$ALERTS_PERSIST" in *⚡*)
            _sc_kinds="${_sc_kinds}dis"
            [ "${PENDING_MINE:-0}" -gt 0 ] 2>/dev/null && _sc_kinds="${_sc_kinds}m"
            [ "${PENDING_STALE:-0}" -gt 0 ] 2>/dev/null && _sc_kinds="${_sc_kinds}s"
            [ "${PENDING_FRESH:-0}" -gt 0 ] 2>/dev/null && _sc_kinds="${_sc_kinds}f"
            ;;
        esac
        case "$ALERTS_PERSIST" in *📋*) _sc_kinds="${_sc_kinds}bl" ;; esac
        case "$ALERTS_PERSIST" in *📏*) _sc_kinds="${_sc_kinds}ms" ;; esac
        case "$ALERTS_PERSIST" in *🔎*) _sc_kinds="${_sc_kinds}of" ;; esac
        _sc_thr_f=$(throttle_file "$STATE_DIR" session-persist "${PAYLOAD_SID:-$SESSION_ID}")
        if throttle_seen "$_sc_thr_f" "$_sc_kinds"; then
            # Уже звучало в этой сессии тем же составом — молчим вместе с детализацией.
            ALERTS_PERSIST=""
            PENDING_DETAIL=""
        else
            throttle_mark "$_sc_thr_f" "$_sc_kinds"
        fi
    fi
fi
ALERTS="${ALERTS}${ALERTS_PERSIST}"

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
    # JSON собирается jq, а не printf: прямая кавычка в ЛЮБОМ алерте рвала весь вывод
    # хода — а алерты цитируют имена файлов и слова собеседника. Поймано 8 сентября 2026
    # на собственном тексте. Запасная ветка сохраняет прежнее поведение там, где jq нет,
    # и это осознанный предел: без jq экранировать нечем.
    # systemMessage СНЯТ 12 сентября 2026. Канал выбирался по посылке «в VSCode он не
    # рендерится, значит либо виден в терминале, либо нигде» — посылка устарела вместе с
    # миром: в мобильном клиенте он рендерится ПОСТРОЧНО. Свод многострочен по построению,
    # поэтому одно напоминание разворачивалось у владельца в дюжину строк «Stop says:»,
    # включая пустые. Текст адресован агенту и целиком лежит в очереди выше.
fi
# Else: silent exit, no systemMessage. Detailed digest in intrusiveness-history.jsonl.

# Clean up THIS session's state files
# Note: disagreement-pending log is NOT cleaned — it persists across sessions
# until outcomes are closed via /learn. Agent reviews in startup context.
rm -f "$STATE_DIR/had_struggle_${SESSION_ID}" "$STATE_DIR/knowledge_injected_${SESSION_ID}" "$STATE_DIR/last_keywords_${SESSION_ID}" "$STATE_DIR/reformulation_last_fire_${SESSION_ID}" "$STATE_DIR/cascading-events-${SESSION_ID}.jsonl" "$STATE_DIR/injection-bytes-peak-${SESSION_ID}" "$CC_SURFACED_FILE" 2>/dev/null

# Intrusiveness state: NOT deleted here — itr_cleanup_old_states above handles
# stale (>30d) files. Current session file survives so a re-opened terminal or
# follow-up session can still read it. Authoritative digest was already written
# to intrusiveness-history.jsonl.

exit 0
