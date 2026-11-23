#!/usr/bin/env bash
set -u
. "$(dirname "$0")/../alerts-read.sh"
# СУДИТ: hooks/lib/backlog_cmd.py hooks/completion-gate.sh scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh hooks/backlog-lib.sh
# probe_D1238 — питонские исполнители команд бэклога судят кольцо правилом ВЛАДЕЛЬЦА (`hooks/backlog-lib.sh`), а не
#   своей копией: в копии дерева правило предела глубины меняется в библиотеке (сравнение `-ge "$BACKLOG_CMD_DEPTH_MAX"`
#   → `-ge 99`), и решение меняется вместе с ним. Рамка: две записи этого бэклога выше по дереву (глубина 2 при пределе 2)
#   — исходное правило отбивает «Проверку», изменённое пропускает. Судятся гейт границы хода (поведением) и модуль
#   ограды, который зовут архиватор и пересчёт показаний (поведением на обоих правилах); у архиватора и пересчёта —
#   ещё отсутствие своей копии правила.
#   0 — решения следуют библиотеке; 1 — исполнитель держит своё правило; 2 — рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in hooks/lib/backlog_cmd.py hooks/completion-gate.sh hooks/backlog-lib.sh scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh; do
    [ -f "$f" ] || exit 2
done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
for side in orig mut; do
    mkdir -p "$W/$side/hooks" && cp hooks/*.sh "$W/$side/hooks/" && cp -R hooks/lib "$W/$side/hooks/" || exit 2
done
o='if [ "$n" -ge "$BACKLOG_CMD_DEPTH_MAX" ]; then'
[ "$(grep -cF "$o" "$W/mut/hooks/backlog-lib.sh")" = 1 ] || { echo "рамка: правило предела в библиотеке не найдено"; exit 2; }
python3 - "$W/mut/hooks/backlog-lib.sh" "$o" <<'PY' || exit 2
import sys
p, o = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace(o, 'if [ "$n" -ge 99 ]; then'))
PY
B="$W/BACKLOG.md"
printf -- '- ☑ **X1** закрытый пункт пробы\n  **Результат.** проба\n  **Проверка.** `true` → 0\n' > "$B"
RUN=$(env -u BACKLOG_CMD_RUNNING bash -c '. "$1"; r=$(BACKLOG_CMD_RUNNING= backlog_cmd_env "$2" check X8 "a"); BACKLOG_CMD_RUNNING="$r" backlog_cmd_env "$2" check X9 "b"' _ hooks/backlog-lib.sh "$B") || exit 2
gate() {  # <сторона> → вывод очереди
    mkdir -p "$W/st-$1"
    printf '{"session_id":"probe-d1238","cwd":"/"}' | env -u BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING="$RUN" CG_BACKLOG="$B" STATE_DIR="$W/st-$1" \
        bash "$W/$1/hooks/completion-gate.sh" >/dev/null 2>&1
    alerts_of "$W/st-$1"
}
bad=0
grep -q 'кольцо' <<< "$(gate orig)" || { echo "рамка: исходное правило не отбило «Проверку» на глубине 2"; exit 2; }
grep -q 'кольцо' <<< "$(gate mut)" && { echo "гейт держит своё правило: изменённая библиотека пропускает, гейт отбил"; bad=1; }
mod() {  # <сторона> → «B» (отбито) либо «R» (пропущено)
    BACKLOG_CMD_RUNNING="$RUN" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import backlog_cmd
why, run = backlog_cmd.blocked(sys.argv[2], "check", "X1", "true"); print("B" if why else "R")' "$W/$1/hooks/lib" "$B"
}
[ "$(mod orig)" = B ] || { echo "рамка: модуль на исходном правиле не отбил"; exit 2; }
[ "$(mod mut)" = R ] || { echo "модуль ограды держит своё правило"; bad=1; }
# Своя копия правила — сборка ключа записи кольца; вызов модуля — точной формой (мутант скептика opus по f8006ea0, M1:
# `_bc_blocked = lambda *a, **k: ("", None)` выключал ограду при «import backlog_cmd» на месте).
for f in scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh hooks/completion-gate.sh; do
    grep -qF 'key = f"{cmd}#{iid}#{kind}"' "$f" && { echo "$f: своя копия правила кольца"; bad=1; }
    grep -qE '^[[:space:]]*_bc_blocked = lambda b, k, i, c: backlog_cmd\.blocked\(b, k, i, c, lib=' "$f" || { echo "$f: не зовёт модуль ограды"; bad=1; }
done
# Модуля нет — ограда закрыта: гейт в копии без backlog_cmd.py «Проверку» не исполняет и называет (H2 скептика).
mkdir -p "$W/nomod/hooks" && cp hooks/*.sh "$W/nomod/hooks/" && cp -R hooks/lib "$W/nomod/hooks/" && rm -f "$W/nomod/hooks/lib/backlog_cmd.py" || exit 2
mkdir -p "$W/st-nomod"
printf '{"session_id":"probe-d1238n","cwd":"/"}' | env -u BACKLOG_CHECKS_NESTED -u BACKLOG_CMD_RUNNING HOME="$W" CG_BACKLOG="$B" STATE_DIR="$W/st-nomod" \
    bash "$W/nomod/hooks/completion-gate.sh" >/dev/null 2>&1
alerts_of "$W/st-nomod" | grep -q '«Проверка» не исполнена.*X1' \
    || { echo "без модуля ограды гейт не назвал причину (молчит либо исполнил)"; bad=1; }
exit "$bad"
