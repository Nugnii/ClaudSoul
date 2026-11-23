#!/usr/bin/env bash
set -u
# СУДИТ: hooks/tests/test_completion_gate_open_items.sh hooks/completion-gate.sh
# probe_D1231 — свидетель гейта (`test_completion_gate_open_items.sh`) судит механизм, а не состояние живого бэклога:
#   он зелен на дереве, где у одного открытого пункта «Проверка» дороже срока одной команды гейта (CG_TIMEOUT), а у
#   другого уже зелёная (починен, ждёт закрытия). Рамка настоящая: копия хуков (без тестов) и этого свидетеля в песочном
#   дереве, его BACKLOG.md — два таких пункта; срок гейта сжат до 2 с, дорогая команда — `sleep 5`.
#   0 — свидетель зелен; 1 — красен на состоянии мира; 2 — нет свидетеля или гейта, рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
T=hooks/tests/test_completion_gate_open_items.sh
for f in "$T" hooks/completion-gate.sh; do [ -f "$f" ] || exit 2; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
R="$W/r"; mkdir -p "$R/hooks/tests" || exit 2
cp hooks/*.sh "$R/hooks/" && cp -R hooks/lib "$R/hooks/" && cp "$T" hooks/tests/alerts-read.sh "$R/hooks/tests/" || exit 2   # сосед свидетеля — D1309
printf -- '- ☐ **X1** открытый пункт с дорогой «Проверкой»\n  **Результат.** проба\n  **Проверка.** `sleep 5` → 0\n\n- ☐ **X2** открытый пункт, уже починенный\n  **Результат.** проба\n  **Проверка.** `true` → 0\n' > "$R/BACKLOG.md"
out=$(env -u BACKLOG_CHECKS_NESTED -u BACKLOG_CMD_RUNNING CG_TIMEOUT=2 bash "$R/hooks/tests/test_completion_gate_open_items.sh" 2>&1); rc=$?
grep -q 'completion-gate open items:' <<< "$out" || { echo "рамка: свидетель не дал итога (код $rc)"; exit 2; }
[ "$rc" -eq 0 ] && exit 0
printf '%s\n' "$out" | grep 'FAIL' | head -3
exit 1
