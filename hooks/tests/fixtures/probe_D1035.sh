#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1035.sh — отказ стража разбора снимается НАЗВАННЫМ ИСХОДОМ повода, а не числом чтений; текст отказа речи не требует.
#
# Повод (23 октября 2026, решение владельца после отката D1033): с 4 октября (D513) три разные цели чтения снимали отказ
# без разбора — «разбор сделан» и «место правки перечитано трижды» давали одно значение (R6); в октябре снятий чтениями
# 507 против 55 разборов с цепочкой. Требование речи (D1033) дало два обрыва фильтра API за полтора часа и откачено.
# Архитектура (docs/mechanism-errors-and-backlog.ru.md, этап 5): отказ сторожа снимается названным исходом — починил /
# долг / знание / «показалось»; признак снимается с действия, а не с речи.
#
# Ноги: (1) запись при поводе отказана, текст отказа не требует произнести цепочку и называет команду исхода;
# (2) три чтения разных мест после повода отказ НЕ снимают; (3) запись исхода повода в журнал исходов — в форме писателя
# `rc_log_outcome` (ts, key manual-<N>, signal, outcome, ref), как её пишет `scripts/outcome.sh`, — снимает отказ, и
# ПОСЛЕДНИЙ исход пары «ход, вид» в журнале — `recorded`.
# Код: 0 — все ноги держат; 1 — нога красная (названа); 2 — нечем мерить.
set -uo pipefail
# Рамка — outcome_frame_lib.sh (D1109): исход принимает настоящая команда `scripts/outcome.sh` (с D1104/D1106 — только
# сверенный: свежий пункт с корнем и адресом цели отказа); прежняя редакция писала строку журнала руками.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
GATE="$HOOK"; STATE_DIR="$ST"; T="$SB"
P="$SB/proj"; gproj "$P" || exit 2
RED=0
TR="$T/a.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$TR"
jq -cn --arg t "Правлю строку." '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
write() { cw a "$P/hooks/x.sh" "$TR" "$P"; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null)" = "deny" ]; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "${1:-}" 2>/dev/null; }
read_add() { jq -cn --arg f "$P/hooks/$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:$f}}]}}' >> "$TR"; }

# (1) повод с правом на отказ, разбора и исхода нет.
touch "$STATE_DIR/error_streak_fired_a"
OUT=$(write)
denied "$OUT" || { echo "КОНТРОЛЬ: запись при поводе не отказана — пробе нечего судить"; exit 2; }
J="$STATE_DIR/outcome-a.jsonl"
SIG=$(jq -r 'select(.outcome == "deferred") | .signal' "$J" 2>/dev/null | head -1)
[ -n "$SIG" ] || { echo "КОНТРОЛЬ: отказ не записал deferred — вида повода не узнать"; exit 2; }
grep -qE "произнесена|произнес[ти]|цепочк[ауи] «почему»|звен|рассужден" <<< "$(reason "$OUT")" \
    && { echo "КРАСНАЯ: текст отказа требует РЕЧИ модели (довод ADR-022)"; RED=1; }
grep -q "outcome.sh" <<< "$(reason "$OUT")" \
    || { echo "КРАСНАЯ: текст отказа не называет команду исхода (scripts/outcome.sh)"; RED=1; }

# (2) три чтения разных мест отказ не снимают.
read_add a.sh; read_add b.sh; read_add c.sh
denied "$(write)" || { echo "КРАСНАЯ: три чтения сняли отказ без названного исхода"; RED=1; }

# (3) названный исход повода снимает отказ; пара хода кончается recorded.
item "$P/BACKLOG.md" D9935 "hooks/x.sh:5"
no a debt "$SIG" D9935 "$P" || { echo "КОНТРОЛЬ: команда исхода не приняла свежий пункт по цели отказа — рамка не собралась"; exit 2; }
OUT=$(write)
if denied "$OUT"; then echo "КРАСНАЯ: названный исход повода «${SIG}» отказ не снял"; RED=1
else
    LAST=$(jq -r --arg s "$SIG" 'select(.signal == $s and ((.key|tostring)|startswith("manual-")|not)) | .outcome' "$J" | tail -1)
    [ "$LAST" = "recorded" ] || { echo "КРАСНАЯ: после снятия пара хода кончается «${LAST}», а не recorded"; RED=1; }
fi
exit "$RED"
