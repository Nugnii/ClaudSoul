#!/usr/bin/env bash
# probe_D463.sh — ask стража поправок, показанный СУБАГЕНТУ, гасит его владельцу.
#
# Предмет. `user-correction-guard.sh` дросселирует ask ключом `hash` — md5 ОДНОЙ РЕПЛИКИ
# (:339-341). Актора в ключе нет. Реплику говорит человек РОДИТЕЛЮ, но вызов инструмента
# идёт от любого актора, и первый сработавший записывает хеш в общий журнал
# `correction-fired-<SID>.jsonl`. Если первым оказался субагент, владелец ask не увидит
# НИКОГДА: его вызовы уходят в ветку `muted`.
#
# Коды: 0 — дефекта нет (родитель получает ask после субагента); 1 — дефект воспроизведён;
#       2 — судить нечем (положительный контроль не сработал, прибор сломан).
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$HOOKS_DIR/user-correction-guard.sh"
[ -f "$HOOK" ] || { echo "probe_D463: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D463: нет jq" >&2; exit 2; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state"
TR="$T/t.jsonl"
# ФОРМА ВЗЯТА ИЗ МИРА, а не сочинена: так расшифровку пишет харнесс и так её читает
# свидетель стража (hooks/tests/test_user_correction_guard.sh:41). Реплика несёт маркер
# словаря поправок («я же говорил»).
jq -cn --arg t "я же говорил, так делать не надо, переделай" \
   '{type:"user", origin:{kind:"human"}, message:{role:"user", content:[{type:"text", text:$t}]}}' > "$TR"

call() { # $1 — agent_id, пусто = родитель
    jq -cn --arg tp "$TR" --arg a "${1:-}" \
      'if $a == "" then {session_id:"probe-d463", transcript_path:$tp, tool_name:"Bash", tool_input:{command:"echo hi"}}
       else {session_id:"probe-d463", transcript_path:$tp, agent_id:$a, tool_name:"Bash", tool_input:{command:"echo hi"}} end' \
    | STATE_DIR="$T/state" bash "$HOOK" 2>/dev/null
}
asks() { grep -q '"permissionDecision"' <<< "${1:-}"; }

# Положительный контроль: на чистом состоянии страж ОБЯЗАН заговорить. Не заговорил —
# признак не сработал вовсе (словарь, расшифровка, jq), и судить дефект нечем.
OUT0=$(call "")
asks "$OUT0" || { echo "probe_D463: контроль — страж молчит и родителю, судить нечем" >&2; exit 2; }

# Суд: свежее состояние, ПЕРВЫМ ходит субагент.
rm -rf "$T/state"; mkdir -p "$T/state"
# Контроль «субагенту ask показан» снят с D1018 (22 октября 2026): агенту страж молчит по замыслу — реплика обращена к
# родителю. Предмет пробы прежний: вызов агента ПЕРВЫМ не гасит ask владельцу.
OUT1=$(call "sub-1")
OUT2=$(call "")
if asks "$OUT2"; then
    exit 0
fi
echo "probe_D463: дефект — ask показан субагенту, владельцу на ту же реплику молчание" >&2
exit 1
