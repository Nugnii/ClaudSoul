#!/usr/bin/env bash
# declared-problem-recorded.sh — Stop: названная проблема обязана лечь в носитель (D103).
# en: Stop hook — a problem named in the answer must reach a durable carrier.
#
# Повод — поправка собеседника 28 августа 2026, дословно: «ты сейчас декларируешь проблему
# и не записываешь её и если я ничего не скажу, не замечу, то она будет повторяться». И
# там же: «если не взялся сразу, то должен был в бэклог записать. А вдруг бы я вкладку
# закрыл?»
#
# Живой повод в тот же день: `producer-filter-check` назвал пять хуков без отсева чужой
# речи, агент сообщил это в ответе, закрыл пункт долга и НЕ завёл новый. Находка прожила
# три часа только в диалоге. Ответ — самый заметный носитель в моменте, и заметность
# подменяет постоянство: у текста ответа нет различия «сказано» и «сохранено».
#
# ПРИЗНАК НЕ НОВЫЙ ПЕРЕЧЕНЬ СЛОВ. Гейт разбора уже отличает находку по ходу и ведёт журнал
# срабатываний; сигналом служит запись `discovery:` в нём. Завести здесь второй словарь
# значило бы повторить D102 («перечень форм вместо правила») в день его заведения.
#
# Проверка «записано» — изменение НОСИТЕЛЯ после начала сессии: BACKLOG.md либо база
# знаний. Начало сессии берётся наблюдаемо: самый старый файл состояния этой сессии.
#
# Input  (stdin): {session_id, hook_event_name, ...}
# Output (stdout): {systemMessage} либо пусто
# Exit:  always 0 — напоминание в конце сессии, не запрет.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SID" ] || exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# Корни — из paths-lib: CLAUDSOUL_ROOT уважает указатель install.sh (клон вне
# ~/My Project/ClaudSoul раньше делал абсолютный носитель немым), find_project_root
# поднимает cwd подпапки к корню проекта.
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"

# Ключ хода — rc_turn_key из root-cause-lib: ТА ЖЕ функция, которой five-whys-gate
# подписывает журнал. До 29 августа 2026 здесь лежала своя копия формулы с комментарием
# «расходятся молча — и связь порвётся без единого падения»; теперь связь держится кодом.
# Библиотеки нет — сверщик молчит: читать журнал, не умея посчитать его ключ, нельзя.
RC_LIB="${RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/root-cause-lib.sh}"
[ -f "$RC_LIB" ] || RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$RC_LIB" ] && . "$RC_LIB"; } || exit 0

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
BACKLOG="${DPR_BACKLOG:-${CLAUDSOUL_ROOT:-$HOME/My Project/ClaudSoul}/BACKLOG.md}"
LESSONS="${DPR_LESSONS:-$HOME/.claude/global-lessons}"

# Третий носитель — ЛОКАЛЬНЫЙ BACKLOG.md проекта сессии (cwd из payload, как у
# session-collector). До этой правки запись находки в бэклог чужого инициированного
# проекта стража НЕ гасила: он напоминал на правильном поведении — ложный сигнал,
# который приучает обходить. Совпал с абсолютным (сессия в самом ClaudSoul) — не
# считается дважды.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
LOCAL_BACKLOG="${DPR_LOCAL_BACKLOG:-}"
if [ -z "$LOCAL_BACKLOG" ] && [ -n "$CWD" ] && command -v find_project_root >/dev/null 2>&1; then
    _root=$(find_project_root "$CWD")
    [ -n "$_root" ] && [ -f "$_root/BACKLOG.md" ] && LOCAL_BACKLOG="$_root/BACKLOG.md"
fi
[ "${LOCAL_BACKLOG:-}" = "$BACKLOG" ] && LOCAL_BACKLOG=""

JOURNAL="$STATE/five-whys-${SID}.seen"
[ -f "$JOURNAL" ] || exit 0
# Сроды поводов — ВСЕ, а не только находка. До 29 августа 2026 здесь стоял `discovery:`, и
# исход не проверялся у остальных шести: в живых журналах daily 126, repeat 59,
# discovery 36, correction 6, streak 4 — то есть у 195 срабатываний из 231 «заметил и
# ничего не сделал» было неотличимо от «сделал». Перечень — из root-cause-lib (RC_KINDS_RE),
# env-откат `DPR_KINDS_RE` оставлен аварийным сужением обратно к находке.
KINDS_RE="${DPR_KINDS_RE:-$RC_KINDS_RE}"
FINDS=$(grep -cE "$KINDS_RE" "$JOURNAL" 2>/dev/null || printf '0')
case "${FINDS:-}" in ''|*[!0-9]*) FINDS=0 ;; esac
[ "$FINDS" -gt 0 ] || exit 0

# Начало сессии — самый старый файл состояния, помеченный её идентификатором.
# Переносимое время файла берём из portable-lib: BSD `stat -f` и GNU `stat -c` расходятся.
PORTABLE="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
[ -f "$PORTABLE" ] || PORTABLE="$HOME/.claude/hooks/portable-lib.sh"
# shellcheck source=/dev/null
[ -f "$PORTABLE" ] && . "$PORTABLE"
mtime_of() {
    if command -v file_mtime >/dev/null 2>&1; then file_mtime "$1"; else printf '0'; fi
}

# ── Граница «после находки»: ХОД, а не сессия ─────────────────────────────────
# До 29 августа 2026 носитель сверялся с НАЧАЛОМ СЕССИИ. В длинной сессии носитель
# меняется на первом часе — и дальше страж молчит до конца, сколько бы находок ни
# прозвучало. Замер того же дня: за сессию BACKLOG.md переписан на закрытии D105-D109,
# после чего десять срабатываний `discovery:` не дали ни одного напоминания, и ход, где
# разбор дошёл до корня и не оставил исхода, прошёл молча.
#
# Предмет был задан ГРАНИЦЕЙ СЕССИИ, а утверждение относится к состоянию «записано ПОСЛЕ
# находки». Тот же род, что чинили в тот же день у гейта разбора: предмет берётся по
# тому, что удобно наблюдать, а не по тому, о чём утверждение.
#
# Ключ хода — rc_turn_key (root-cause-lib), одно определение с five-whys-gate.
# КОНТРПРИМЕР: ход без записи `discovery:` этой проверки не получает; ход, где носитель
# изменён после начала хода, молчит — иначе страж станет фоном на здоровой работе.
TURN_FINDS=0
TURN_START=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TURN_KEY=$(rc_turn_key "$TRANSCRIPT")
    TURN_TS=$(jq -rs '
        def role(x): x.message.role // x.role // "";
        def get_text(x):
            (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then ($c | map(select(.type == "text") | .text) | join(" "))
            elif ($c | type) == "string" then $c else "" end;
        [ .[] | select(role(.) == "user" and (get_text(.) != "")) ] | last | .timestamp // ""
    ' "$TRANSCRIPT" 2>/dev/null)
    if [ -n "${TURN_KEY:-}" ]; then
        TURN_FINDS=$(grep -cE "^turn:${TURN_KEY}\|.*(${KINDS_RE})" "$JOURNAL" 2>/dev/null || printf '0')
        case "${TURN_FINDS:-}" in ''|*[!0-9]*) TURN_FINDS=0 ;; esac
        TURN_SIGNALS=$(rc_signals_of_turn "$JOURNAL" "$TURN_KEY" | tr '\n' ' ')
    fi
    # Дробные доли секунды срезаются, ЕСЛИ они есть. Форма `${TURN_TS%%.*}Z` этого не
    # различает и к метке без долей приписывает вторую «Z» — время становится непарсимым,
    # проверка тихо выключается. Поймано собственным тестом в день заведения.
    TURN_TS_CLEAN=$(printf '%s' "${TURN_TS:-}" | sed 's/\.[0-9]*Z$/Z/')
    if [ -n "${TURN_TS_CLEAN:-}" ] && command -v iso_epoch >/dev/null 2>&1; then
        TURN_START=$(iso_epoch "$TURN_TS_CLEAN" 2>/dev/null || printf '0')
        case "${TURN_START:-}" in ''|*[!0-9]*) TURN_START=0 ;; esac
    fi
fi

carrier_touched_after() {   # <epoch> → 0, если носитель менялся позже этой отметки
    _after="${1:-0}"
    [ "$_after" -gt 0 ] || return 1
    if [ -f "$BACKLOG" ]; then
        _m=$(mtime_of "$BACKLOG")
        case "$_m" in ''|*[!0-9]*) _m=0 ;; esac
        [ "$_m" -gt "$_after" ] && return 0
    fi
    if [ -n "${LOCAL_BACKLOG:-}" ] && [ -f "$LOCAL_BACKLOG" ]; then
        _m=$(mtime_of "$LOCAL_BACKLOG")
        case "$_m" in ''|*[!0-9]*) _m=0 ;; esac
        [ "$_m" -gt "$_after" ] && return 0
    fi
    if [ -d "$LESSONS" ]; then
        for _f in "$LESSONS"/*.md; do
            [ -e "$_f" ] || continue
            _m=$(mtime_of "$_f")
            case "$_m" in ''|*[!0-9]*) continue ;; esac
            [ "$_m" -gt "$_after" ] && return 0
        done
    fi
    return 1
}

# ── Журнал ИСХОДОВ, а не срабатываний (D112) ──────────────────────────────────
# Исход определяется наблюдаемо: изменился носитель после начала хода — значит повод
# чем-то кончился (`recorded`); не изменился — `none`. Декларация агента исходом не
# считается: «сказано» и «сохранено» в тексте ответа выглядят одинаково, и именно на этом
# различии стоит весь хук. Вердикт «показалось» пишется отдельной командой
# `scripts/outcome.sh` — он единственный, который наблюдением не отличить от бездействия.
if [ "$TURN_FINDS" -gt 0 ] && [ "$TURN_START" -gt 0 ] && [ -n "${TURN_KEY:-}" ]; then
    if carrier_touched_after "$TURN_START"; then _TURN_OUTCOME="recorded"; else _TURN_OUTCOME="none"; fi
    # След разбора (D211) пишется вместе с исходом: по нему замер считает долю поводов, где
    # разбор оставил проверяемые формы, а не только долю с записанным исходом.
    _TRACE=$(rc_trace "$TRANSCRIPT")
    for _sig in ${TURN_SIGNALS:-}; do
        rc_log_outcome "$STATE" "$SID" "$TURN_KEY" "$_sig" "$_TURN_OUTCOME" "" "$_TRACE"
    done
    # Внешние поводы (красный прогон, откат, воскресший пункт, сбой проверки дрейфа)
    # гасятся, когда исход записан: иначе событие висело бы открытым вечно и стало бы
    # фоном — гейт называл бы его поводом в каждом ходе до конца времён. Гасим только на
    # `recorded`: «ничего не сделано» повод не закрывает, он для того и открыт.
    if [ "$_TURN_OUTCOME" = "recorded" ] && command -v rc_close_events >/dev/null 2>&1; then
        rc_close_events "$STATE"
    fi
fi

if [ "$TURN_FINDS" -gt 0 ] && [ "$TURN_START" -gt 0 ] && ! carrier_touched_after "$TURN_START"; then
    _WHAT_FIRED="${TURN_SIGNALS:-повод разбора}"
    MSG_TURN="📌 В ЭТОМ ходе сработал гейт разбора ($TURN_FINDS раз; поводы: ${_WHAT_FIRED% }), а носитель не менялся: ни BACKLOG.md (ни локальный, ни ClaudSoul), ни база знаний.

Разбор — не исход. Исход это состояние мира, и он называется из закрытого списка:
$(rc_resolution_kinds).

Решением считается и МЕХАНИЗМ, не дающий проблеме возникнуть: тогда у пункта названы
измеримый результат и команда проверки. «Жду слова» без названного плана исходом не
является: закроется вкладка — не останется ничего.
Признал повод ложным — так и запиши: bash scripts/outcome.sh disproved <сигнал> \"<чем опровергнуто>\""
    jq -cn --arg m "$MSG_TURN" '{systemMessage: $m}' 2>/dev/null || true
    exit 0
fi

START=""
for f in "$STATE"/*"$SID"*; do
    [ -e "$f" ] || continue
    m=$(mtime_of "$f")
    case "$m" in ''|*[!0-9]*) continue ;; esac
    if [ -z "$START" ] || [ "$m" -lt "$START" ]; then START="$m"; fi
done
[ -n "$START" ] || exit 0

RECORDED=0
if [ -f "$BACKLOG" ]; then
    m=$(mtime_of "$BACKLOG")
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    [ "$m" -gt "$START" ] && RECORDED=1
fi
if [ "$RECORDED" -eq 0 ] && [ -n "${LOCAL_BACKLOG:-}" ] && [ -f "$LOCAL_BACKLOG" ]; then
    m=$(mtime_of "$LOCAL_BACKLOG")
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    [ "$m" -gt "$START" ] && RECORDED=1
fi
if [ "$RECORDED" -eq 0 ] && [ -d "$LESSONS" ]; then
    for f in "$LESSONS"/*.md; do
        [ -e "$f" ] || continue
        m=$(mtime_of "$f")
        case "$m" in ''|*[!0-9]*) continue ;; esac
        if [ "$m" -gt "$START" ]; then RECORDED=1; break; fi
    done
fi

[ "$RECORDED" -eq 1 ] && exit 0

MSG="📌 За сессию гейт разбора срабатывал $FINDS раз, и ни один повод не оставил следа: ни BACKLOG.md (ни локальный, ни ClaudSoul), ни база знаний не менялись.

Названное в ответе живёт только в открытой вкладке. Закроется — следа не останется, и то же самое всплывёт заново.

Исход из закрытого списка: $(rc_resolution_kinds). Решением считается и МЕХАНИЗМ, не дающий проблеме возникнуть — тогда у пункта названы измеримый результат и команда проверки. Если находка уже починена — этого сообщения быть не должно: правка носителя фиксируется тем же способом."

jq -cn --arg m "$MSG" '{systemMessage: $m}' 2>/dev/null || true
exit 0
