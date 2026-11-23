#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/tests/fixtures/probe_D1029.sh
# probe_D1272 — обещание отказа стража разбора сходится с его ветками: проба D1029 (ноги по нынешнему договору — D1104,
#   D1036) зелёна; `sed -i` по BACKLOG.md при открытом поводе отбит, его отказ называет форму `cat >>`, которую страж
#   пропускает, — и эта форма проходит.
# Код: 0 — сходится; 1 — расхождение (названо); 2 — нечем мерить.
set -uo pipefail
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/five-whys-gate.sh"; P29="$R/hooks/tests/fixtures/probe_D1029.sh"
[ -f "$HOOK" ] && [ -f "$P29" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state"; P="$T/proj"; mkdir -p "$STATE_DIR" "$P/hooks"
printf '# ROOTS\n\n## R1 — x\n' > "$P/ROOTS.md"
printf '# BACKLOG\n\n- ☐ **D1** x\n' > "$P/BACKLOG.md"
# Повод с правом на отказ — полоса провалов (как у пробы D1029).
touch "$STATE_DIR/error_streak_fired_s"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$T/s.jsonl"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Правлю строку."}]}}' >> "$T/s.jsonl"
call() {   # <команда> → вывод стража
    jq -cn --arg d "$P" --arg c "$1" --arg p "$T/s.jsonl" \
      '{session_id:"s", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
      | bash "$HOOK" 2>/dev/null
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null; }
bad=0
CLAUDSOUL_REPO="$R" bash "$P29" >/dev/null 2>&1 || { echo "проба D1029 красна"; bad=1; }
out=$(call "sed -i '' 's/x/y/' BACKLOG.md")
if [ "$(decision "$out")" = deny ]; then
    grep -q 'cat >>' <<< "$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$out")" \
        || { echo "отказ на sed -i не называет форму cat >>, которую страж пропускает"; bad=1; }
else
    echo "sed -i по BACKLOG.md при открытом поводе не отбит"; bad=1
fi
out=$(call "cat >> BACKLOG.md <<'EOF'
- ☐ **D2** y
EOF")
[ "$(decision "$out")" = deny ] && { echo "форма cat >> в BACKLOG.md отбита, хотя отказ её называет"; bad=1; }
exit "$bad"
