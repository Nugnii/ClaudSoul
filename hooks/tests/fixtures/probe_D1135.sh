#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# probe_D1135 — пока бэклог не читается, строка состояния снимка `unread` не дописывается на каждом вызове стража.
# Красная (1), пока пересмотр D1128 дописывает строку на каждом вызове (четвёртый скептик, L1: 10 вызовов — 11 строк,
# журнал `.seen` хранится без окна). Положительный контроль — после возврата права последнее состояние — cksum. Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
[ "$(id -u)" -ne 0 ] || exit 2
P="$SB/p"; gproj "$P" || exit 2
TR="$SB/tr.jsonl"; mk_tr "$TR" "$FINDING"
crp() { jq -cn --arg p "$TR" --arg d "$P" '{session_id:"s1", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:"ls"}}' | ( cd "$P" && STATE_DIR="$ST" bash "$HOOK" >/dev/null 2>&1 ); }
chmod 000 "$P/BACKLOG.md"
for i in 1 2 3 4 5 6; do crp; done
n=$(grep -c "^snapbl|.*|$P/BACKLOG.md|unread|$" "$ST/five-whys-s1.seen" 2>/dev/null)
chmod 644 "$P/BACKLOG.md"; crp
last=$(grep "^snapbl|.*|$P/BACKLOG.md|" "$ST/five-whys-s1.seen" 2>/dev/null | tail -n 1 | cut -d'|' -f4)
case "$last" in ''|unread|absent) exit 2 ;; esac
[ "${n:-0}" -le 1 ] || { echo "за 6 вызовов строк «не прочитан» — $n" >&2; exit 1; }
echo "«не прочитан» пишется при смене состояния"
exit 0
