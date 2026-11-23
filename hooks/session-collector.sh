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
INPUT="$(cat)"; _SC_T0=$(date +%s)   # старт прогона — для уборки в конце файла (D1000)

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
# Итог хода (поле Stop `last_assistant_message`) — для сверки доставки отказа архиватора владельцу (D1271, ниже).
PAYLOAD_LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // "" | if type == "string" then . else "" end' 2>/dev/null)
# Граница хода (D1250): свод фоновый, и к чтению в расшифровке бывает уже начало следующего хода — читатели хода дальше
# строки итога ЭТОГО Stop не идут. Первым делом, до тяжёлой работы: итог не найден — граница на момент вызова.
_SC_HIL="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hook-input-lib.sh"
[ -f "$_SC_HIL" ] || _SC_HIL="$HOME/.claude/hooks/hook-input-lib.sh"
# shellcheck source=/dev/null
if [ -n "${PAYLOAD_TRANSCRIPT:-}" ] && [ -f "$_SC_HIL" ] && . "$_SC_HIL" 2>/dev/null; then
    transcript_stop_bound "$PAYLOAD_TRANSCRIPT" "$PAYLOAD_LAST_MSG" || true
fi
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
    # Код берётся ВЕТВЬЮ: файл под `set -e`. Код 2 — архив несогласия не прочитан, перечень неполон (D1008, род B):
    # называется постоянным напоминанием ниже, а не выдаётся за «открытых меньше».
    if OPEN_RECORDS=$(dis_scan_open "$STATE_DIR" 2>/dev/null); then DIS_ARCH_BAD=0; else DIS_ARCH_BAD=1; fi
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
        # `dis_expire_old` (`hooks/disagreement-lib.sh:318`), и оно календарное осознанно, с
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
        # (disagreement-lib.sh:343 corrections, :420 failures) фильтруют по типу записи
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
            # произвольный текст собеседника сломал бы, читаем поле из JSONL напрямую. Строки сессии — архив уборки и
            # живой файл (`_dis_lines`, D1008): у ключа перенесённой сессии улика иначе пропадала (скептик, M1).
            _snip=$(_dis_lines "$STATE_DIR" \
                | awk -F'\t' -v n="disagreement-pending-${s}.jsonl" '$1 == n { sub(/^[^\t]*\t[^\t]*\t/, ""); print }' \
                | jq -rR --arg k "$k" \
                'fromjson? // empty | select(.key == $k and .outcome == "pending") | .snippet // empty' 2>/dev/null | tail -1)
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
    # Файлы состояния сессий сборщик НЕ убирает (D1335, корень R1, решение владельца 20 ноября 2026): срок их жизни
    # держит один хозяин — общая уборка каталога состояния `scripts/state-prune.sh` (14 дней тишины за окном свежих
    # сессий, раз в неделю по реестру замеров). Здесь стоял вызов `itr_cleanup_old_states 30` — вторая копия срока в
    # другой единице (тридцать дней опыта на этой машине — от полугода календаря), ни одного файла не снимавшая.

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
# Адресные сообщения (D1304): о ЭТОЙ сессии — `ALERTS_OWN`, в канал своей сессии (`session_alert`); о проекте файла —
# сразу `project_alert`. В общую очередь `ALERTS` идёт только сказанное обо всей системе: её снимает первая сессия с
# репликой. Предел: постоянные состояния `ALERTS_PERSIST` (📋 долг, отказ архиватора) остаются в общей очереди — их
# дроссель ведётся по сессии; доля показов чужой сессии не измерена.
ALERTS_OWN=""
# Постоянное состояние о бэклоге проекта (скептик opus по 9310f120, L3: «📋 … этого проекта» — 3 показа из 4 в чужом
# проекте, отказ архиватора — 1 из 13): адресат — проект, а дроссель — тот же, что у ALERTS_PERSIST (по составу, сессия).
_SC_PP=""; _SC_PP_TEXT=""
_sc_persist_proj() {  # <каталог проекта> <текст>
    _SC_PP="${_SC_PP}${1}	${2}
"; _SC_PP_TEXT="${_SC_PP_TEXT}${2}"
}
_sc_project_alert() {  # <каталог проекта> <текст>; без библиотеки — общая очередь, как до D1304
    if command -v project_alert >/dev/null 2>&1; then project_alert "$STATE_DIR" "$1" "$2"
    else ALERTS="${ALERTS}$2"; fi
}
# Постоянное состояние держится отдельно от событийного: ⚡/📋/📏 описывают мир, который
# сам между ходами не меняется, и потому обязаны идти через дроссель (ниже, перед записью
# в очередь). Событийные строки (⚠️ ошибки, ⌛ истекло, 🗄️ архиватор) самоустраняются и
# дросселя не требуют. Повод — замер 7 сентября 2026: свод нёс 69-94% пользовательских
# ходов в четырёх сессиях подряд.
ALERTS_PERSIST=""
if [ "${DIS_ARCH_BAD:-0}" = 1 ]; then
    ALERTS_PERSIST="${ALERTS_PERSIST}⚠️ Архив несогласия не прочитан ($STATE_DIR/archive/disagreement-pending.tsv) — счёт открытых суждений неполон. "
fi
if [ "$HAD_STRUGGLE" = true ]; then
    ALERTS_OWN="${ALERTS_OWN}⚠️ В сессии были ошибки — рассмотри /learn. "
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
# Библиотека бэклога — ДО счёта (D1101): счёт читает цельную копию `backlog_read`, а прежде она подключалась ниже
# первого вызова, и запасная ветка `cat` срабатывала всегда.
_BLL="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/backlog-lib.sh"
[ -f "$_BLL" ] || _BLL="$HOME/.claude/hooks/backlog-lib.sh"
if [ -f "$_BLL" ]; then
    # shellcheck source=/dev/null
    . "$_BLL" 2>/dev/null || true
fi
# Договор инициации и на границе хода (D1301, 15 ноября 2026): проект, в который сессия вошла переходом или который стал
# инициированным посреди неё (SESSION.md заведён агентом), прежде получал части только на следующем старте сессии в нём.
# Владелец правила — `backlog_contract_parts_ensure`; повтор молчит (заводит только отсутствующее). Слово — в канал СВОЕЙ
# сессии `stop-signals-<sid>.txt` с корнем проекта рядом (D1047), а не в общую очередь `pending-alerts.txt`: её снимает
# первая сессия с репликой и приняла бы «в проекте заведены» за свой проект (скептик opus по e6775d9d, H1).
if [ -n "${PAYLOAD_CWD:-}" ] && [ -n "${PAYLOAD_SID:-}" ] && command -v backlog_contract_parts_ensure >/dev/null 2>&1; then
    _ct_said=$(backlog_contract_parts_ensure "$PAYLOAD_CWD" 2>/dev/null)
    if [ -n "$_ct_said" ]; then
        if command -v session_alert >/dev/null 2>&1; then
            session_alert "$STATE_DIR" "$PAYLOAD_SID" "${_SC_PROJ_ROOT:-$PAYLOAD_CWD}" "$_ct_said"
        else
            printf '%s\n' "$_ct_said" >> "$STATE_DIR/pending-alerts.txt" 2>/dev/null || true
        fi
    fi
fi
# Тот же договор по ЦЕЛЯМ ПРАВОК хода (D1307, корень R6): каталог события отвечает «откуда запустили», а проект работы —
# там, куда ход пишет. Сессия из родительского каталога, правившая проект по абсолютному пути, иначе частей ему не давала
# (два проекта Biznes-sovetnik, 3 сессии с 23 октября 2026). Цели — `file_path` файловых инструментов правки (Edit, Write,
# MultiEdit; та же тройка, что у журнала активности) в окне ХОДА: прошлые ходы судила своя граница. Корень каталога
# события пропускается — его судила ветка выше. Пределы: запись командой Bash и правки субагента (его расшифровка
# отдельна) целями не считаются.
if [ -n "${PAYLOAD_SID:-}" ] && [ -n "${PAYLOAD_TRANSCRIPT:-}" ] && [ -f "$PAYLOAD_TRANSCRIPT" ] \
   && command -v backlog_contract_parts_ensure >/dev/null 2>&1 && command -v transcript_turn_window >/dev/null 2>&1 \
   && command -v project_root_or_empty >/dev/null 2>&1 && command -v session_alert >/dev/null 2>&1; then
    _ct_seen="|${_SC_PROJ_ROOT:-}|"
    while IFS= read -r _ct_dir; do
        _ct_root=$(project_root_or_empty "$_ct_dir")
        [ -n "$_ct_root" ] || continue
        case "$_ct_seen" in *"|$_ct_root|"*) continue ;; esac
        _ct_seen="$_ct_seen$_ct_root|"
        _ct_said=$(backlog_contract_parts_ensure "$_ct_root" 2>/dev/null)
        # Канал сессии привязан к проекту СЕССИИ, а не к правленому (скептик opus по 176e7f0a, M2): `.project` пишет
        # первый писатель, и корень цели отдал бы собственные сообщения сессии сессиям чужого проекта. Путь цели — в тексте.
        if [ -n "$_ct_said" ]; then session_alert "$STATE_DIR" "$PAYLOAD_SID" "${_SC_PROJ_ROOT:-$PAYLOAD_CWD}" "$_ct_said"; fi
    done < <(transcript_turn_window "$PAYLOAD_TRANSCRIPT" | jq -rR 'fromjson? | select((.message.role // .role // "") == "assistant")
                | (.message.content // .content // []) | if type == "array" then .[] else empty end
                | select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit"))
                | .input.file_path // empty | strings | select(startswith("/") and (contains("\n") | not))' 2>/dev/null \
             | while IFS= read -r _ct_f; do _ct_d="${_ct_f%/*}"; until [ -d "$_ct_d" ] || [ -z "$_ct_d" ]; do _ct_d="${_ct_d%/*}"; done
                   [ -n "$_ct_d" ] && printf '%s\n' "$_ct_d"; done | sort -u)
fi
_bl_open_count() {
    [ -f "${1:-}" ] || { echo 0; return; }
    # Здесь-строка, а не труба: `awk … exit` выходит рано, и под `set -euo pipefail` запасной `cat` (старая библиотека
    # без `backlog_read`) получил бы SIGPIPE — 141 убил бы сборщик на присваивании (правило D59).
    _bl_txt=$(backlog_read "$1" 2>/dev/null || cat -- "$1" 2>/dev/null) || true
    # СТРОКУ ПУНКТА НАЗЫВАЕТ ВЛАДЕЛЕЦ ФОРМЫ (D1334, корень R1): своя копия признака `^- (☐|◐)` знала одну вёрстку из
    # двух, и пункт-заголовок (`### B40 … ◐`) в счёт не шёл — у blalb владелец называл 9 открытых, сборщик 0, и строка
    # «открытых пунктов в BACKLOG.md этого проекта» там не звучала ни разу. Граница «## Архив» остаётся здесь (T12a):
    # текст режется до неё, а считают его `backlog_item_re` и `backlog_status_is` (`hooks/backlog-lib.sh`).
    # Счёт — `grep -c`, а не ранний выход: труба дочитывается, SIGPIPE под pipefail не возникает (правило D59).
    _bl_txt=$(awk '/^##[[:space:]]+(Архив|Archive|Done)/{exit} {print}' <<< "$_bl_txt" 2>/dev/null) || true
    if command -v backlog_item_re >/dev/null 2>&1 && command -v backlog_status_is >/dev/null 2>&1 \
       && command -v backlog_strip_fenced >/dev/null 2>&1; then
        _bl_n=$(backlog_strip_fenced <<< "$_bl_txt" 2>/dev/null \
                | grep -E "$(backlog_item_re "$BACKLOG_OPEN_MARKS")" 2>/dev/null \
                | backlog_status_is "$BACKLOG_OPEN_MARKS" 2>/dev/null | grep -c . ) || true
        printf '%s' "${_bl_n:-0}" | tr -d '[:space:]'
        return
    fi
    # Библиотеки нет (старая установка) — прежний счёт по списочной вёрстке.
    awk '/^- (☐|◐)/{c++} END{print c+0}' <<< "$_bl_txt" 2>/dev/null | tr -d '[:space:]'
}
BACKLOG_FILE="${CLAUDSOUL_BACKLOG:-$CLAUDSOUL_ROOT/BACKLOG.md}"
BACKLOG_OPEN=$(_bl_open_count "$BACKLOG_FILE")
: "${BACKLOG_OPEN:=0}"
if [ "${BACKLOG_OPEN:-0}" -ge "${BACKLOG_ALERT_MIN:-1}" ] 2>/dev/null; then
    # Если аудит /project-health ранее запускался (маркер в файле) — свод мог устареть:
    # предлагаем ре-аудит/сведение, а не только цифру. Сам аудит НЕ проводим — Stop-хук не
    # место для авто-мутаций (это и была бы «мусорка»); детектор лишь указывает команду.
    _bl_hint=""
    grep -q "project-health" <<< "$(backlog_read "$BACKLOG_FILE" 2>/dev/null || cat -- "$BACKLOG_FILE" 2>/dev/null)" && _bl_hint=" Свод мог устареть → /project-health для ре-аудита."
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
# Без спроса убирается ТОЛЬКО долг ClaudSoul. Локальный BACKLOG.md проекта, найденный по
# папке сессии, ниже по файлу лишь считается: у него свой формат и свой владелец, и
# переносить в нём что-либо по нашим меткам — правка чужого документа без спроса.
# Спрос — признак `CG_LOCAL_BACKLOG` (D512, ветка ниже функции).
BACKLOG_ARCHIVER="${CLAUDSOUL_BACKLOG_ARCHIVER:-$CLAUDSOUL_ROOT/scripts/backlog-archive.sh}"
_bl_archive_closed() {   # <BACKLOG.md> <BACKLOG-archive.md> <чей — для сообщений, необязателен>
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
    _bl_out=$(BACKLOG_FILE="$1" BACKLOG_ARCHIVE="$2" bash "$BACKLOG_ARCHIVER" run 2>&1 || true)
    _bl_moved=$(printf '%s\n' "$_bl_out" \
                | awk -F': ' '/^Перенесено в архив:/ { split($2, a, " "); print a[1]; exit }' || true)
    if [ -z "$_bl_moved" ]; then
        # Перечень снят СО СТОРОНЫ ПРОИЗВОДИТЕЛЯ (`grep -nE '^\s*(echo|print\()'` по
        # scripts/backlog-archive.sh), а не по фразе, знакомой отсюда: первая редакция
        # знала одну строку из семи и потому объявляла отказом самый частый случай.
        case "$_bl_out" in
            # «ЗАКРЫТИЕ БЕЗ ПОКАЗАНИЯ» — НЕ «переносить нечего», и молчать о нём нельзя.
            # До 19 сентября 2026 этот исход стоял в общем ряду известных и гасился вместе
            # с ними: закрытые пункты оставались в BACKLOG.md, а владельцу об этом не
            # говорил никто. Повод — его же слова «в бэклоге висят закрытые пункты», когда
            # D445 и D448 провисели полдня. Два разных состояния мира шли одним каналом
            # (молчанием): «уносить нечего» и «есть что унести, но отказано». Теперь
            # отказ называется вместе с ПРИЧИНОЙ — первой строкой ответа архиватора, где
            # он сам пишет, какой пункт и чем заблокирован.
            *"Закрытие без показания"*)
                _bl_why=$(printf '%s\n' "$_bl_out" | awk '/^  · /{ sub(/^  · /, ""); print; exit }' || true)
                # Отказ — состояние ПОСТОЯННОЕ (пункт висит, пока его не починят), поэтому идёт
                # в ALERTS_PERSIST: до 4 октября 2026 он дописывался в очередь на каждом Stop,
                # и три хода подряд давали три одинаковые строки. Ключ дросселя — сам отказ.
                # Ключ — ВСЕ строки отказа: по одной первой второй отказанный пункт, стоящий
                # в файле ниже первого, не прозвучал бы вовсе (скептик, 4 октября 2026).
                _BL_REFUSED="${_BL_REFUSED:-}${3:-}:$(printf '%s\n' "$_bl_out" | awk '/^  · /' | cksum | awk '{print $1}')|"
                _sc_persist_proj "${1%/*}" "🗄️ Архиватор ОТКАЗАЛСЯ уносить закрытые пункты${3:-}: ${_bl_why:-причина не названа} — почини «Проверку» либо верни метку в ◐; пункты висят в BACKLOG.md. "
                _bl_moved=0 ;;
            # «ПЕРЕНОС ОТЛОЖЕН» (D1000, 17 октября 2026) — BACKLOG.md изменился за время прогона
            # «Проверок», и архиватор не записал ничего, чтобы не затереть правку агента или
            # параллельной сессии. Состояние САМОУСТРАНЯЮЩЕЕСЯ: сборщик зовёт архиватора на каждой
            # границе хода, и следующий проход идёт по свежему файлу, — поэтому молчание, а не
            # ALERTS_PERSIST (постоянного тут нет) и не «НЕ ОТВЕТИЛ» (ответ опознан). Строка стоит
            # у архиватора перед записью архива (`scripts/backlog-archive.sh`, код 1).
            *"Переносить нечего"*|*"Вложенный прогон"*|*"Перенос отложен"*\
            |*"архив недоступен"*|*"старше скрипта"*|*"нет определения пункта"*) _bl_moved=0 ;;
            *)  _sc_project_alert "${1%/*}" "🗄️ Архиватор долга${3:-} НЕ ОТВЕТИЛ ни одним известным исходом — это не «переносить нечего»; прогони руками: BACKLOG_FILE=\"$1\" bash \"$BACKLOG_ARCHIVER\" run. "
                _bl_moved=0 ;;
        esac
    fi
    if [ "${_bl_moved:-0}" -gt 0 ] 2>/dev/null; then
        _sc_project_alert "${1%/*}" "🗄️ Закрытых пунктов${3:-} унесено в BACKLOG-archive.md: ${_bl_moved} — оба файла изменены, добавь в коммит. "
    fi
    # ДОСТАВКА ОТКАЗА ВЛАДЕЛЬЦУ (D1271, 7 ноября 2026). Напоминание выше идёт с дросселем по составу: модель видит его
    # один раз, а передала ли владельцу — не сверял никто (ProjectA_NEW: 11 закрытых пунктов висели две недели). Отказ,
    # держащий пункт 12 запусков подряд (срок в работе, а не в часах — D1352), повторяется строкой «СКАЖИ владельцу»
    # без дросселя, пока итог хода не назовёт номер пункта; отказа нет — состояние снимается. Владелец сверки и довода о
    # пороге — `hooks/lib/archive_relay.py`; модуля нет — прежнее поведение (одно напоминание).
    _AR_PY="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/lib/archive_relay.py"
    if [ -f "$_AR_PY" ]; then
        _ar_in=""
        case "$_bl_out" in *"Закрытие без показания"*) _ar_in="$_bl_out" ;; esac
        _ar_line=$(printf '%s' "$_ar_in" | python3 "$_AR_PY" \
            "$STATE_DIR/archive-refusal-$(printf '%s' "$1" | cksum | awk '{print $1}').tsv" "$(date +%s)" \
            "${ARCHIVE_RELAY_RUNS:-12}" "${3:-}" "${PAYLOAD_LAST_MSG:-}" 2>/dev/null || true)
        # `if`, а не `&&`: последняя команда функции — её код, и пустая строка под `set -e` роняла бы сборщик молча.
        if [ -n "$_ar_line" ]; then _sc_project_alert "${1%/*}" "$_ar_line"; fi
    fi
}
if [ -f "$BACKLOG_ARCHIVER" ] && [ -f "$BACKLOG_FILE" ]; then
    _bl_archive_closed "$BACKLOG_FILE" "${CLAUDSOUL_BACKLOG_ARCHIVE:-${BACKLOG_FILE%/*}/BACKLOG-archive.md}"
fi

# Бэклог ПРОЕКТА убирается тем же архиватором — по признаку согласия, а не по папке (D512).
#
# Повод (4 октября 2026, слово владельца, сессия ProjectA): «странно что архиватор работает в
# ручном режиме, в клаудсоул он автоматический». Проект вёл бэклог по контракту ClaudSoul и
# включил гейт признаком `CG_LOCAL_BACKLOG`: «Проверки» его пунктов исполнялись на каждом
# Stop, а закрытые копились до ручной команды — 37 закрытых против 56 открытых. Согласие
# было объявлено одним признаком, а читал его один потребитель из двух.
#
# ПРИЗНАК — ОН ЖЕ ГРАНИЦА ДОВЕРИЯ. Архиватор ИСПОЛНЯЕТ команду «Проверки» закрытого пункта,
# поэтому файл берётся только из переменной, названной владельцем, и никогда — подъёмом от
# папки сессии: путь из cwd есть вход извне (D244, `completion-gate.sh:112-117`). Проект без
# признака хук по-прежнему только считает. Путь принимается только АБСОЛЮТНЫЙ: относительный
# читался бы от папки, где запущен хук, то есть снова от сессии.
# Папку запуска хук не меняет: «Проверки» архиватор сам исполняет из папки бэклога
# (`scripts/backlog-archive.sh`, `cwd=str(backlog.parent)`).
#
# `_SIGN_BL` — бэклог проекта, названный владельцем; один владелец факта на уборку, пересчёт
# показаний и счёт открытых ниже по файлу (D514: прежде уборка шла по признаку, а пересчёт
# и счёт — подъёмом от папки сессии, и пересчёт исполнял скрипт найденного так проекта).
# Сломанный признак НЕ молчит: файл, которого нет, и относительный путь выключают и уборку,
# и гейт, а молчание тут неотличимо от «убирать нечего». Состояние постоянное — через дроссель.
_SIGN_BL=""
case "${CG_LOCAL_BACKLOG:-}" in
    '') ;;
    /*) if [ -f "$CG_LOCAL_BACKLOG" ]; then
            _lbl_dir=$(cd -- "$(dirname -- "$CG_LOCAL_BACKLOG")" >/dev/null 2>&1 && pwd -P) || _lbl_dir=""
            [ -n "$_lbl_dir" ] && _SIGN_BL="$_lbl_dir/$(basename -- "$CG_LOCAL_BACKLOG")"
        else
            _BL_REFUSED="${_BL_REFUSED:-}cfg:${CG_LOCAL_BACKLOG}|"
            ALERTS_PERSIST="${ALERTS_PERSIST}🗄️ CG_LOCAL_BACKLOG называет файл, которого нет (${CG_LOCAL_BACKLOG}) — бэклог проекта не убирается и гейтом не проверяется; поправь путь в настройках проекта. "
        fi ;;
    *)  _BL_REFUSED="${_BL_REFUSED:-}cfg:${CG_LOCAL_BACKLOG}|"
        ALERTS_PERSIST="${ALERTS_PERSIST}🗄️ CG_LOCAL_BACKLOG задан относительным путём (${CG_LOCAL_BACKLOG}) — он читался бы от папки сессии, поэтому не принимается; нужен абсолютный путь. " ;;
esac
if [ -n "$_SIGN_BL" ] && [ -f "$BACKLOG_ARCHIVER" ] && ! [ "$_SIGN_BL" -ef "$BACKLOG_FILE" ]; then
    # Порог возраста пунктов (`BACKLOG_CONTRACT_MIN_ID`, D ниже 200 — без контракта) описывает
    # историю бэклога ClaudSoul. К чужой нумерации он неприложим: в проекте с пунктами D1–D199
    # закрытый пункт с красной «Проверкой» уезжал бы молча.
    BACKLOG_CONTRACT_MIN_ID=0 \
    _bl_archive_closed "$_SIGN_BL" "${_SIGN_BL%/*}/BACKLOG-archive.md" " проекта $(basename -- "${_SIGN_BL%/*}")"
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
    # У каждого бэклога свой счётчик (D514). Общий рос на 2 за Stop, когда пересчётчик есть
    # и у проекта, и при чётном пороге до главного бэклога очередь не доходила никогда:
    # замер скептика — порог 20, 60 ходов, главный 0 раз, проект 6.
    [ "$_rr_file" -ef "$BACKLOG_FILE" ] \
        || _rr_stamp="${_rr_stamp}-$(printf '%s' "$_rr_file" | cksum | awk '{print $1}')"
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
fi
# Пересчётчик показаний проекта — его собственный скрипт (`scripts/backlog-refresh-readings.sh`
# рядом с бэклогом), и хук его ИСПОЛНЯЕТ. До 4 октября 2026 он брался у проекта, найденного
# подъёмом от папки сессии: открытый чужой склонированный каталог с `.git`, `BACKLOG.md` и
# таким скриптом получал исполнение своего кода на Stop (D514, брат D244). Теперь — только у
# бэклога, названного владельцем. Корень по папке сессии ниже остаётся для СЧЁТА: он читает.
if [ -n "$_SIGN_BL" ] && ! [ "$_SIGN_BL" -ef "$BACKLOG_FILE" ]; then
    _bl_refresh_readings "$_SIGN_BL"
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
# Названный владельцем бэклог первее найденного по папке: из подпапки проекта со своим
# CLAUDE.md подъём отдавал подпапку, и уборка шла в одном файле, а счёт искал другой (D514).
# Имя файла тоже берётся у признака: владелец вправе назвать не BACKLOG.md. Совпадение с
# главным бэклогом сверяется по файлу (`-ef`), а не по строке пути: через симлинк строки
# расходились, и долг ClaudSoul назывался дважды.
_LOCAL_BL_NAME="BACKLOG.md"
if [ -n "$_SIGN_BL" ]; then _LOCAL_BL_ROOT="${_SIGN_BL%/*}"; _LOCAL_BL_NAME="${_SIGN_BL##*/}"; fi
if [ -n "${_LOCAL_BL_ROOT:-}" ] && [ -f "$_LOCAL_BL_ROOT/$_LOCAL_BL_NAME" ] \
   && ! [ "$_LOCAL_BL_ROOT/$_LOCAL_BL_NAME" -ef "$BACKLOG_FILE" ]; then
    _cs_root=$(cd "$CLAUDSOUL_ROOT" 2>/dev/null && pwd || printf '%s' "$CLAUDSOUL_ROOT")
    _cwd_real=$(cd "$_LOCAL_BL_ROOT" 2>/dev/null && pwd || printf '%s' "$_LOCAL_BL_ROOT")
    # В самом ClaudSoul локальный файл и есть ClaudSoul-долг — не считать дважды.
    if [ "$_cwd_real" != "$_cs_root" ]; then
        LOCAL_BL_OPEN=$(_bl_open_count "$_LOCAL_BL_ROOT/$_LOCAL_BL_NAME")
        : "${LOCAL_BL_OPEN:=0}"
        if [ "${LOCAL_BL_OPEN:-0}" -ge "${BACKLOG_ALERT_MIN:-1}" ] 2>/dev/null; then
            _sc_persist_proj "$_LOCAL_BL_ROOT" "📋 ${LOCAL_BL_OPEN} открытых пункт(ов) в BACKLOG.md этого проекта ($(basename "$_cwd_real")). "
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
            ALERTS_OWN="${ALERTS_OWN}🗣️ Кандидаты в shared vocabulary: ${SHLANG_FOUND} — если референс устойчив, добавь в словарь (мост L3↔L7). "
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
    # ОПОЗНАНИЕ КЛАССА БЕЗ РЕЕСТРА — ДОЛГ ГРАНИЦЫ ХОДА (23 сентября 2026, работа по D408).
    # Вторая обязанность срода `self_repeat` жила ТОЛЬКО в тексте напоминания, то есть на
    # уровне 2-3 лестницы. Замер сессии `9ea6931d`: напоминание выдано 14 раз, реестр назван
    # дважды, доля по корпусу сдвинулась с 50,3% на 50,5% — в пределах шума.
    # Уровень 4 (отказ в момент речи) здесь поставить нельзя: точность признака `self_repeat`
    # 15 из 20, каждый четвёртый отказ был бы ложным, а такой отказ правило возвращает в
    # подсказку. Потому обязанность перенесена с МОМЕНТА речи на ГРАНИЦУ хода: долг, который
    # виден на выходе, как виден повод разбора без исхода.
    # Оба владельца спрошены, своих копий не заведено: текст хода даёт `rc_turn_text`,
    # признак «класс опознан, реестр назван» — замер `signal-precision-corpus.py`, у него
    # измеренная точность и оба контроля. Коды владельца: 0 назван, 1 долг, 2 судить нечего.
    # БИБЛИОТЕКА ПОДКЛЮЧАЕТСЯ ЗДЕСЬ, И ЕЁ ОТСУТСТВИЕ ВИДНО (24 сентября 2026, D408).
    # Ветка ниже стояла под сторожем `command -v rc_turn_text`, а `root-cause-lib.sh` в этом
    # файле НЕ подключался ни разу — семь строк `source` подключают другие библиотеки. Прямая
    # проба: после `. hooks/lib/open-findings-lib.sh` функция недоступна. Значит перенос
    # обязанности «назвать реестр носителей» с момента речи на границу хода, объявленный
    # 23 сентября 2026, НЕ СОСТОЯЛСЯ ни разу, а показание 50,2% читалось как «данных мало».
    # Род B: молчаливый пропуск неотличим от «дефектов нет».
    _CR_RCLIB="${_CR_RCLIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/root-cause-lib.sh}"
    [ -f "$_CR_RCLIB" ] || _CR_RCLIB="$HOME/.claude/hooks/root-cause-lib.sh"
    # shellcheck source=/dev/null
    [ -f "$_CR_RCLIB" ] && . "$_CR_RCLIB" 2>/dev/null
    if ! command -v rc_turn_text >/dev/null 2>&1; then
        # Третье состояние прибора названо вслух: не «чисто», а «мерить нечем».
        ALERTS_PERSIST="${ALERTS_PERSIST}🧬 Обязанность «реестр носителей» НЕ ПРОВЕРЕНА: нет root-cause-lib.sh (искал ${_CR_RCLIB}). "
    fi
    if command -v rc_turn_text >/dev/null 2>&1 && [ -n "${PAYLOAD_TRANSCRIPT:-}" ]; then
        _cr_corpus="${CLAUDSOUL_ROOT:-$(cat "$HOME/.claude/claudsoul-repo" 2>/dev/null)}/scripts/signal-precision-corpus.py"
        if [ -f "$_cr_corpus" ] && command -v python3 >/dev/null 2>&1; then
            _cr_txt=$(rc_turn_text "$PAYLOAD_TRANSCRIPT" 2>/dev/null || true)
            if [ -n "$_cr_txt" ]; then
                # Код берётся ВЕТВЬЮ, а не `$?` после присваивания: файл идёт под
                # `set -euo pipefail`, и присваивание из подстановки с ненулевым кодом
                # убивает весь свод. Ровно так первая редакция и молчала на состоянии
                # «долг» (код 1), записывая только «реестр назван» (код 0), — то есть
                # считала бы одни успехи. Идиома взята у соседа по файлу (`of_open_counts`).
                if _cr_out=$(printf '%s' "$_cr_txt" | python3 "$_cr_corpus" --registry-in-text 2>/dev/null); then
                    _cr_rc=0
                else
                    _cr_rc=$?
                fi
                # СЛЕД ИСХОДА, А НЕ ТОЛЬКО СРАБАТЫВАНИЯ (24 сентября 2026, D408). До этого
                # дня долг ПЕЧАТАЛСЯ и нигде не записывался, а «реестр назван» не
                # записывалось вовсе. Значит на вопрос «помогло ли напоминание» ответить было
                # нечем: доля считалась только переигрыванием корпуса, то есть задним числом
                # и по речи. Это тот же разрыв, что чинился утром у стража капкана:
                # «сработал» считается, «помог» — нет. Пишутся ОБА исхода: met и owed, иначе
                # в знаменатель попадут одни долги и доля будет ложно низкой.
                # Дедуп по ключу хода: свод зовётся на Stop не единожды.
                _cr_sid="${PAYLOAD_SID:-$SESSION_ID}"
                _cr_key=$(printf '%s' "$_cr_txt" | cksum 2>/dev/null | awk '{print $1}')
                _cr_new=0; _cr_said=0
                case "$_cr_rc" in
                    0|1)
                        # Ключ ХОДА — у его владельца (`rc_turn_key`: реплика собеседника), а не `cksum` текста: ход,
                        # продолженный после перезапуска хуком Stop, — тот же ход с выросшим текстом (D1183, второй круг).
                        _cr_turn=$(rc_turn_key "$PAYLOAD_TRANSCRIPT" 2>/dev/null || true)
                        _cr_turn="${_cr_turn:-$_cr_key}"
                        _cr_f="$STATE_DIR/class-registry-fired-${_cr_sid:-nosid}.jsonl"
                        _cr_st=met; [ "$_cr_rc" = 1 ] && _cr_st=owed
                        if grep -qF "\"state\":\"owed\",\"turn\":\"${_cr_turn}\"" "$_cr_f" 2>/dev/null; then _cr_said=1; fi
                        # Запись не роняет свод под `set -e`: перенаправление в нечитаемый журнал падает раньше `2>/dev/null`.
                        # Названный предел: на журнале только для чтения запись не ложится, `_cr_said` её не увидит, и долг
                        # хода звучит на каждом Stop — громче, а не тише. Дедуп записи — по тексту, состоянию и ходу:
                        # новый ход с тем же текстом агента — своя запись и свой долг (третий круг, L-1).
                        grep -qF "\"key\":\"${_cr_key}\",\"state\":\"${_cr_st}\",\"turn\":\"${_cr_turn}\"" "$_cr_f" 2>/dev/null || {
                            printf '{"ts":"%s","key":"%s","state":"%s","turn":"%s"}\n' \
                                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_cr_key:-0}" "$_cr_st" "$_cr_turn" \
                                2>/dev/null >> "$_cr_f" || true
                            _cr_new=1; } ;;
                esac
                # Долг — СОБЫТИЕ хода, а не постоянное состояние (D1183): в `ALERTS_PERSIST` его гасил дроссель
                # состава вместе с долгами других ходов — после любого постоянного напоминания в сессии долг до
                # очереди не доходил. Строка идёт мимо дросселя и звучит один раз на ход: при первой записи долга
                # этого хода.
                case "$_cr_rc:$_cr_new:$_cr_said" in
                    1:1:0) ALERTS_OWN="${ALERTS_OWN}🧬 Класс опознан, а РЕЕСТР НОСИТЕЛЕЙ не назван рядом с опознанием: ${_cr_out}. Опознание обязывает — сколько мест того же устройства в дереве? Способ добычи: scripts/defect-class-carriers.py, поиск по УСТРОЙСТВУ, scripts/dep-index.py --impact. Без реестра класс закроется не целиком. " ;;
                esac
            fi
        fi
    fi

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

if [ -n "$ALERTS_PERSIST$_SC_PP_TEXT" ]; then
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
        case "$ALERTS_PERSIST$_SC_PP_TEXT" in *📋*) _sc_kinds="${_sc_kinds}bl" ;; esac
        case "$ALERTS_PERSIST" in *📏*) _sc_kinds="${_sc_kinds}ms" ;; esac
        # Отказ архиватора и сломанный признак согласия — в составе своим содержанием: другой
        # пункт либо другая причина обязаны прозвучать, прежние — нет (D514).
        [ -n "${_BL_REFUSED:-}" ] && _sc_kinds="${_sc_kinds}ar$(printf '%s' "$_BL_REFUSED" | cksum | awk '{print $1}')"
        case "$ALERTS_PERSIST" in *🔎*) _sc_kinds="${_sc_kinds}of" ;; esac
        _sc_thr_f=$(throttle_file "$STATE_DIR" session-persist "${PAYLOAD_SID:-$SESSION_ID}")
        if throttle_seen "$_sc_thr_f" "$_sc_kinds"; then
            # Уже звучало в этой сессии тем же составом — молчим вместе с детализацией.
            ALERTS_PERSIST=""
            _SC_PP=""
            PENDING_DETAIL=""
        else
            throttle_mark "$_sc_thr_f" "$_sc_kinds"
        fi
    fi
fi
ALERTS="${ALERTS}${ALERTS_PERSIST}"
while IFS='	' read -r _sc_pp_dir _sc_pp_line; do
    [ -n "$_sc_pp_line" ] && _sc_project_alert "$_sc_pp_dir" "$_sc_pp_line"
done <<EOF
$_SC_PP
EOF
if [ -n "$ALERTS_OWN" ]; then
    if command -v session_alert >/dev/null 2>&1; then
        session_alert "$STATE_DIR" "${PAYLOAD_SID:-}" "${_SC_PROJ_ROOT:-$PAYLOAD_CWD}" "$ALERTS_OWN"
    else
        ALERTS="${ALERTS_OWN}${ALERTS}"
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
# `error_streak_fired_<SID>.agent-<id>` — полосы СУБАГЕНТОВ этой сессии (D454, 18 сентября
# 2026). Свой файл `error-tracker` снимает сам, когда серия кончилась, но субагент часто
# обрывается ПОСРЕДИ полосы и снять его уже некому. Глоб здесь обязателен: уборка идёт
# литеральным списком путей, а общий подрезатель `scripts/state-prune.sh` посуффиксные
# файлы тоже видит только после правки того же дня — до неё каждый агент давал СВОЮ семью
# из одного файла, и окно `KEEP=60` не заполнялось никогда (находка адверсариальной
# проверки). Несовпавший глоб в bash остаётся литералом, а `[ -e ]` ниже его пропускает.
#
# УБИРАЕТСЯ ТОЛЬКО ТО, ЧТО НЕ НОВЕЕ СТАРТА ПРОГОНА (D1000, 17 октября 2026). Сборщик
# зарегистрирован фоном (`"async": true`): ответ владельцу его не ждёт, и следующий ход
# начинается, пока этот прогон ещё идёт. Эти файлы пишут хуки следующего хода —
# reformulation-tracker на самой реплике, knowledge-activator и error-tracker на первых вызовах
# инструментов, — и безусловный `rm -f` стёр бы их состояние: дедуп показов знаний, порог
# переформулировок, метрики каскада. Пока сборщик был синхронным, это окно было закрыто тем, что
# следующий ход ждал его. Файл, изменённый в секунду старта или позже, считается чужим и остаётся
# до следующей уборки. Без `file_mtime` (не подключилась portable-lib) — прежнее безусловное
# удаление.
_sc_rm_not_newer() {
    local f
    for f in "$@"; do
        [ -e "$f" ] || continue
        if command -v file_mtime >/dev/null 2>&1; then
            [ "$(file_mtime "$f")" -lt "$_SC_T0" ] 2>/dev/null || continue
        fi
        rm -f "$f" 2>/dev/null || true
    done
    return 0
}
_sc_rm_not_newer "$STATE_DIR"/error_streak_fired_"${SESSION_ID}".agent-* \
    "$STATE_DIR/had_struggle_${SESSION_ID}" "$STATE_DIR/knowledge_injected_${SESSION_ID}" \
    "$STATE_DIR/last_keywords_${SESSION_ID}" "$STATE_DIR/reformulation_last_fire_${SESSION_ID}" \
    "$STATE_DIR/cascading-events-${SESSION_ID}.jsonl" "$STATE_DIR/injection-bytes-peak-${SESSION_ID}" \
    "$CC_SURFACED_FILE"

# Intrusiveness state: NOT deleted here — stale files are removed by the state directory's
# single owner, `scripts/state-prune.sh` (D1335). Current session file survives so a re-opened terminal or
# follow-up session can still read it. Authoritative digest was already written
# to intrusiveness-history.jsonl.

exit 0
