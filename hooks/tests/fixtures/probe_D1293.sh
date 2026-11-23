#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh hooks/error-tracker.sh
# probe_D1293 — полоса упавших команд зовётся по своей СЕРИИ: новая полоса той же длины — новый повод, та же полоса на
# спаде — прежний. Имя было контрольной суммой содержимого флага `error_streak_fired_<sid>`, а там только длина: вторая
# полоса из двух провалов звалась как первая, и память зачёта первой снимала её отказ молча. Первая починка взяла время
# флага — и спад той же полосы (окно из 6 исходов, 3→2, флаг переписан) получил новое имя и новый отказ (скептик opus H1,
# 11 ноября 2026: 45 спадов в 22 сессиях). Флаги пишет НАСТОЯЩИЙ error-tracker по расшифровке исходов.
# Ход: провал ×2 → отказ → «показалось»; провал → длина 3 → отказ → «показалось»; успех ×4 → спад к 2 → запись проходит;
# успех → серия кончилась; новый ход, провал ×2 → отказ. Красная (1), пока спад отбит или новая полоса пропущена. Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
ET="$R/hooks/error-tracker.sh"; [ -f "$ET" ] || exit 2
P="$SB/p"; gproj "$P" || exit 2
F="$ST/error_streak_fired_s1"; TE="$SB/te.jsonl"; : > "$TE"
step() {   # e|s — исход команды в расшифровку и вызов error-tracker
    local r='{"type":"tool_result","is_error":false,"content":"ok"}'
    [ "$1" = e ] && r='{"type":"tool_result","is_error":true,"content":"Exit code 1"}'
    printf '{"type":"user","message":{"content":[%s]}}\n' "$r" >> "$TE"
    printf '{"session_id":"s1","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Bash"}' "$TE" \
        | STATE_DIR="$ST" ERROR_TRACKER_DRAFT_DIR="$SB/drafts" bash "$ET" >/dev/null 2>&1
}
flag() { cat "$F" 2>/dev/null || echo -; }
TR="$SB/tr.jsonl"; mk_tr "$TR" "Правлю x.sh."
bad=0
step e; step e; [ "$(flag)" = 2 ] || { echo "рамка: две ошибки не дали флаг 2 ($(flag))" >&2; exit 2; }
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || { echo "рамка: полоса 2 не отбита" >&2; exit 2; }
no s1 disproved streak "полоса 2 — намеренно красная проба" "$P" || exit 2
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = allow ] || { echo "рамка: исход не снял полосу 2" >&2; exit 2; }
sleep 1; step e; [ "$(flag)" = 3 ] || { echo "рамка: третья ошибка не дала 3" >&2; exit 2; }
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || { echo "рост полосы 2→3 не отбит" >&2; bad=1; }
no s1 disproved streak "полоса 3 — та же проба" "$P" || exit 2
sleep 1; step s; step s; step s; step s; [ "$(flag)" = 2 ] || { echo "рамка: спад к 2 не наступил ($(flag))" >&2; exit 2; }
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = allow ] || { echo "спад той же полосы 3→2 отбит заново" >&2; bad=1; }
step s; [ "$(flag)" = - ] || { echo "рамка: серия не кончилась ($(flag))" >&2; exit 2; }
next_turn "$TR" "дальше" "Правлю y.sh."
[ "$(dec "$(cw s1 "$P/hooks/y.sh" "$TR" "$P")")" = allow ] || { echo "рамка: без полосы запись отбита" >&2; exit 2; }
sleep 1; step e; step e; [ "$(flag)" = 2 ] || { echo "рамка: новая полоса не дала флаг 2" >&2; exit 2; }
[ "$(dec "$(cw s1 "$P/hooks/y.sh" "$TR" "$P")")" = deny ] || { echo "новая полоса той же длины прошла под памятью прежней" >&2; bad=1; }
[ "$bad" = 0 ] && echo "полоса зовётся по своей серии: рост и новая — новый повод, спад — прежний"
exit "$bad"
