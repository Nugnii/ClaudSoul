#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D1036.sh — отказ стража разбора не бьёт по ЗАПИСЯМ: правка документа файловым инструментом и одиночное
# дописывание `cat >> документ <<'EOF'` проходят при стоячем поводе; документы, ведущие поведение (SKILL.md), маркер
# без кавычек, команда после маркера и запись в код по-прежнему отбиваются.
#
# Повод (23 октября 2026, ветвь В2 разбора стража, решение владельца «узкое освобождение + замер»): с 4 октября из 460
# отказов по дереву проекта (код, тесты) 45 %, остальное — песочница 17 %, git 17 %, документы и журналы 13 %; за 22–23
# октября документы и журналы — 31 % из 96. Признак «пишет ли» решал роль «правит ли механизм» (корень R3). Разбор
# целей Bash по тексту удалён 5 сентября (приманки, род C); по тексту доказуемы только формы с полным квантором.
#
# Ноги: (1) Write в docs/notes.md при поводе — проходит; (2) Write в skills/x/SKILL.md — отказ; (3) Bash
# `cat >> SESSION.md <<'EOF' … EOF` — проходит; (4) тот же heredoc с маркером без кавычек — отказ; (5) heredoc с командой
# после строки-маркера — отказ; (6) Write в hooks/x.sh — отказ.
# Код: 0 — все ноги держат; 1 — нога красная (названа); 2 — нечем мерить.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GATE="$REPO/hooks/five-whys-gate.sh"
[ -f "$GATE" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/hooks" "$P/docs" "$P/skills/x" "$T/state"
export STATE_DIR="$T/state"
RED=0
TR="$T/a.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$TR"
jq -cn --arg t "Правлю строку." '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
wr() { jq -cn --arg d "$P" --arg f "$1" --arg p "$TR" \
         '{session_id:"a", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Write", cwd:$d, tool_input:{file_path:$f, content:"x"}}' \
       | bash "$GATE" 2>/dev/null; }
sh_() { jq -cn --arg d "$P" --arg c "$1" --arg p "$TR" \
         '{session_id:"a", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
       | bash "$GATE" 2>/dev/null; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null)" = "deny" ]; }
touch "$STATE_DIR/error_streak_fired_a"
denied "$(wr "$P/hooks/x.sh")" || { echo "КОНТРОЛЬ: запись в код при поводе не отказана — пробе нечего судить"; exit 2; }
denied "$(wr "$P/docs/notes.md")"        && { echo "КРАСНАЯ: правка документа docs/notes.md отбита при стоячем поводе"; RED=1; }
denied "$(wr "$P/skills/x/SKILL.md")"    || { echo "КРАСНАЯ: правка SKILL.md (документ, ведущий поведение) прошла без разбора"; RED=1; }
denied "$(sh_ "cd \"$P\" && cat >> SESSION.md <<'EOF'
- 16:30: запись в журнал
EOF")" && { echo "КРАСНАЯ: одиночное дописывание cat >> SESSION.md <<'EOF' отбито при стоячем поводе"; RED=1; }
denied "$(sh_ "cd \"$P\" && cat >> SESSION.md <<EOF
\$(echo тело)
EOF")" || { echo "КРАСНАЯ: heredoc с маркером без кавычек прошёл — тело раскрывает подстановки"; RED=1; }
denied "$(sh_ "cd \"$P\" && cat >> SESSION.md <<'EOF'
- запись
EOF
sed -i '' 's/a/b/' hooks/x.sh")" || { echo "КРАСНАЯ: команда после строки-маркера прошла вместе с дописыванием"; RED=1; }
denied "$(wr "$P/hooks/y.sh")" || { echo "КРАСНАЯ: запись в код прошла без разбора"; RED=1; }
exit "$RED"
