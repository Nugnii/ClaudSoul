#!/usr/bin/env bash
# backlog-open-write-guard.sh — PreToolUse[Edit|Write|MultiEdit] на BACKLOG.md: открытый пункт с зелёной или отсутствующей «Проверкой» не записывается.
# en: PreToolUse on BACKLOG.md edits — refuses to write an OPEN debt item whose check is green or missing at write time.
#
# Результат: у открытого пункта долга красная исполнимая «Проверка» появляется В МОМЕНТ записи — зелёная либо отсутствующая отбивается отказом с именем пункта
# Проверка результата: bash hooks/tests/test_backlog_open_write_guard.sh даёт 0
#
# Зачем (D264, уровень 4 по ИЗМЕРЕННОЙ точности). Контракт долга: «Проверка» открытого пункта
# красна и исполнима — зелёная значит «закрывай с показанием» либо «команда не о дефекте»,
# отсутствующая — «критерия нет». Страж границы хода `completion-gate` называл это ПОСЛЕ
# записи, и с 3 сентября 2026 копил исходы своих срабатываний (`state/cg-open-fired.jsonl`).
# Замер 13 сентября 2026: 23 срабатывания с исходом — confirmed 18, rewritten 5 (команда
# переписана по собственному предписанию канала), ложных 0. Порог ADR-015 — ложных ниже
# десятой части при n ≥ 20 — пройден, и признак получает отказ в момент записи.
#
# ПРИЗНАК С ОДНИМ ПОСЛЕДСТВИЕМ: в ЗАПИСЫВАЕМОМ тексте есть открытый пункт (☐/◐), чей блок
# «Проверки» НОВ или ИЗМЕНЁН относительно файла на диске, и команда отвечает 0 либо строки
# нет. Продолжение вызова имело бы ровно одно последствие — в долг лёг бы открытый пункт без
# красного критерия. Пункты, чья «Проверка» не менялась, здесь не исполняются: их судит
# completion-gate по сроку, а исполнять весь бэклог на каждой правке значило бы платить
# десятками команд за строку.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. Команда, не уложившаяся в бюджет (`OPEN_WRITE_TIMEOUT`, 20 с;
# ограничитель — `timeout-lib.sh`, общий с раннером и стражем возврата), зелёной не доказана
# и не отбивается — пишется в журнал видом `timeout` и называется контекстом. Правка бэклога
# через Bash (python-heredoc, sed) этому стражу не видна — он стоит на инструментах записи;
# условие снятия: разбор целей записи у Bash-вызова с чтением содержимого. Без jq, python3
# или библиотек страж молчит и выходит с 0: чужой проект, а не отказ.
#
# Журнал: `state/backlog-open-write-fired-<SID>.jsonl` — семейство `*-fired-*`, читатель у
# него уже есть (`scripts/signal-precision.sh` выводит универсум правилом).
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ "$(basename "$FILE" 2>/dev/null)" = "BACKLOG.md" ] || exit 0

_HD=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
PATHS_LIB="${PATHS_LIB:-$_HD/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"
: "${STATE_DIR:=$HOME/.claude/hooks/state}"
BL_LIB="${BL_LIB:-$_HD/backlog-lib.sh}"
[ -f "$BL_LIB" ] || BL_LIB="$HOME/.claude/hooks/backlog-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$BL_LIB" ] && . "$BL_LIB"; } || exit 0
command -v backlog_open_items >/dev/null 2>&1 || exit 0
TO_LIB="${TIMEOUT_LIB:-$_HD/timeout-lib.sh}"
[ -f "$TO_LIB" ] || TO_LIB="$HOME/.claude/hooks/timeout-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$TO_LIB" ] && . "$TO_LIB"; } || exit 0
THR_LIB="${THROTTLE_LIB:-$_HD/throttle-lib.sh}"
[ -f "$THR_LIB" ] || THR_LIB="$HOME/.claude/hooks/throttle-lib.sh"
# shellcheck source=/dev/null
[ -f "$THR_LIB" ] && . "$THR_LIB"
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
BUDGET="${OPEN_WRITE_TIMEOUT:-20}"

# Новый текст файла — из payload: Write несёт его целиком, Edit/MultiEdit — правками к диску.
# Правка, чей old_string на диске не найден, не пройдёт и без нас — молчим.
TMPD=$(mktemp -d 2>/dev/null) || exit 0
trap 'rm -rf "$TMPD"' EXIT
NEWF="$TMPD/new.md"
printf '%s' "$INPUT" | FILE="$FILE" python3 -c '
import json, os, sys
d = json.load(sys.stdin); ti = d.get("tool_input") or {}; tool = d.get("tool_name")
path = os.environ["FILE"]
try:
    old = open(path, encoding="utf-8").read()
except OSError:
    old = ""
if tool == "Write":
    new = ti.get("content") or ""
else:
    edits = ti.get("edits") if tool == "MultiEdit" else [ti]
    new = old
    for e in edits or []:
        o = e.get("old_string") or ""; n = e.get("new_string") or ""
        if o == "":
            continue
        if o not in new:
            sys.exit(3)
        new = new.replace(o, n) if e.get("replace_all") else new.replace(o, n, 1)
sys.stdout.write(new)' > "$NEWF" 2>/dev/null || exit 0

_us=$(printf '\037')
if [ -f "$FILE" ]; then
    backlog_open_items "$FILE" 2>/dev/null | awk -F'\t' 'BEGIN { OFS = "\037" } { $1 = $1; print }' > "$TMPD/old.tsv"
else
    : > "$TMPD/old.tsv"
fi
backlog_open_items "$NEWF" 2>/dev/null | awk -F'\t' 'BEGIN { OFS = "\037" } { $1 = $1; print }' > "$TMPD/new.tsv"
ROOT_DIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P)
if command -v throttle_file >/dev/null 2>&1; then
    FIRED=$(throttle_file "$STATE_DIR" backlog-open-write "$SID")
else
    FIRED="$STATE_DIR/backlog-open-write-fired-${SID}.jsonl"
fi
mkdir -p "$STATE_DIR" 2>/dev/null
_journal() {  # <id> <вид>
    if command -v throttle_mark >/dev/null 2>&1; then
        throttle_mark "$FIRED" "${1}|${2}" item "$1" kind "$2" path "$FILE"
    else
        printf '{"ts":"%s","key":"%s|%s","item":"%s","kind":"%s","path":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$1" "$2" "$FILE" >> "$FIRED" 2>/dev/null
    fi
}
DENY=""; TIMED=""
while IFS="$_us" read -r id mark kind q root cmd chk; do
    [ -n "$id" ] || continue
    _old=$(awk -F"$_us" -v i="$id" '$1 == i { print "y" $7; exit }' "$TMPD/old.tsv" 2>/dev/null)
    [ "$_old" = "y$chk" ] && continue        # «Проверка» этого пункта не менялась — не наш предмет
    if [ -z "$chk" ]; then
        DENY="$DENY $id (нет строки «Проверка»)"; _journal "$id" missing; continue
    fi
    ( cd "$ROOT_DIR" && CLAUDSOUL_REPO="${CLAUDSOUL_REPO:-$ROOT_DIR}" run_with_timeout "$BUDGET" bash -c "$chk" ) >/dev/null 2>&1 </dev/null
    _rc=$?
    case "$_rc" in
        0)   DENY="$DENY $id (зелёная)"; _journal "$id" green ;;
        124) TIMED="$TIMED $id"; _journal "$id" timeout ;;
        *)   ;;
    esac
done < "$TMPD/new.tsv"

if [ -n "$DENY" ]; then
    MSG="⛔ ОТКАЗ (вызов не выполнен). «Проверка» ОТКРЫТОГО пункта обязана быть красной и исполнимой, а у записываемого:${DENY}. Зелёная значит одно из двух, и оба дефект: пора закрывать с показанием (☑) либо команда не о дефекте — перепиши её под сам дефект. «Нет строки» значит, что машинного критерия у пункта нет. Исполнимо без разрешения. Уровень 4 по замеру 13 сентября 2026: 23 срабатывания стража границы хода, ложных 0 (D264)."
    jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$m}}' 2>/dev/null
    exit 0
fi
if [ -n "$TIMED" ]; then
    jq -cn --arg m "ℹ️ backlog-open-write-guard: команда «Проверки» не уложилась в ${BUDGET} с у пунктов:${TIMED} — зелёная сторона не доказана, запись пропущена; completion-gate проверит по сроку." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}' 2>/dev/null
fi
exit 0
