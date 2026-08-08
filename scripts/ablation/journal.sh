#!/usr/bin/env bash
# journal.sh — журнал задач ablation-замера (протокол §3–§4, D64).
#
# Приватный append-only jsonl ВНЕ репозитория (формулировки задач могут нести
# личный контекст): ABLATION_DIR, по умолчанию ~/.claude/ablation. В публичный
# снимок уходит только воронка числами (`funnel`).
#
# Дисциплина протокола, зашитая гвардами:
#   - task_id неизменяем, выдаётся при регистрации; повторной регистрации нет;
#   - классификация ровно одна (до вычисления сэмплера) — повторная запрещена;
#   - журнал append-only: никакая команда не переписывает прошлые строки.
#
# Команды:
#   register "<текст рабочего запроса>" [project]  → печатает task_id
#   classify <task_id> eligible|ineligible|nonsubstantive [reason] [type] [complexity]
#       type: bugfix|feature|maintenance (для eligible)
#   show <task_id>       → все события задачи
#   funnel               → числа воронки: registered/substantive/eligible/selected/queued
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "journal: нужен jq" >&2; exit 1; }

DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
mkdir -p "$DIR"
J="$DIR/journal.jsonl"
touch "$J"

now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

CMD="${1:-}"
[ -n "$CMD" ] && shift || { echo "journal: команда обязательна (register|classify|show|funnel)" >&2; exit 1; }

case "$CMD" in
register)
    TEXT="${1:?journal register: текст запроса обязателен}"
    PROJECT="${2:-$PWD}"
    RAND=$(od -An -tx1 -N2 /dev/urandom | tr -d ' \n')
    ID="t-$(date -u +%Y%m%d%H%M%S)-${RAND}"
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg text "$TEXT" --arg p "$PROJECT" \
        '{e:"register", id:$id, ts:$ts, text:$text, project:$p}' >> "$J"
    printf '%s\n' "$ID"
    ;;
classify)
    ID="${1:?task_id обязателен}"
    CLASS="${2:?класс обязателен}"
    case "$CLASS" in eligible|ineligible|nonsubstantive) ;; *)
        echo "journal classify: класс — eligible|ineligible|nonsubstantive" >&2; exit 1 ;; esac
    grep -q "\"id\":\"$ID\"" "$J" || { echo "journal: $ID не зарегистрирована" >&2; exit 1; }
    if jq -es --arg id "$ID" '[.[] | select(.e=="classify" and .id==$id)] | length > 0' "$J" >/dev/null 2>&1; then
        echo "journal: $ID уже классифицирована — классификация одна, до сэмплера (протокол §4)" >&2; exit 1
    fi
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg c "$CLASS" \
        --arg r "${3:-}" --arg t "${4:-}" --arg x "${5:-}" \
        '{e:"classify", id:$id, ts:$ts, class:$c, reason:$r, type:$t, complexity:$x}' >> "$J"
    ;;
show)
    ID="${1:?task_id обязателен}"
    grep "\"id\":\"$ID\"" "$J" || { echo "journal: $ID не найдена" >&2; exit 1; }
    ;;
funnel)
    jq -s '
        def cnt(f): [.[] | select(f)] | length;
        {registered:  cnt(.e=="register"),
         substantive: cnt(.e=="classify" and (.class=="eligible" or .class=="ineligible")),
         eligible:    cnt(.e=="classify" and .class=="eligible"),
         selected:    cnt(.e=="sampler" and .selected==true),
         queued:      cnt(.e=="queue"),
         completed:   cnt(.e=="pair_done")}' "$J"
    ;;
*)
    echo "journal: неизвестная команда '$CMD'" >&2; exit 1
    ;;
esac
