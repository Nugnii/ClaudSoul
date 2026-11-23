#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh
# Проба D1180: «Проверка» (у пересчёта — «Показание»), не уложившаяся в срок, снимается вместе с потомками. Три ноги —
# три исполнителя, которые обрывали по сроку только `bash -c`: completion-gate (открытый пункт, CG_TIMEOUT),
# backlog-archive (закрытый пункт при переносе, BACKLOG_CHECK_TIMEOUT), backlog-refresh-readings («Показание»,
# READING_TIMEOUT). Команда каждой ноги запускает долгого внука (`sleep 40` в фоне) и ждёт его; срок 1 с. После выхода
# исполнителя внук обязан быть мёртв. Рамка — та же, что у пробы D1198.
# Код: 0 — во всех трёх ногах внука нет; 1 — жив (названо); 2 — не измерено (исполнитель не дошёл до команды, нет файла).
set -uo pipefail
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
for f in hooks/completion-gate.sh scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh; do
    [ -f "$REPO/$f" ] || { echo "нет $f"; exit 2; }
done
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1180.XXXXXX") || exit 2
trap 'for p in "$S"/pid-*; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done; rm -rf "$S"' EXIT
# Внук — на уровень глубже прямого ребёнка команды (скептик D1180, M1: мутант «снять только детей `bash -c`» проходил):
# команда → `bash deep-<нога>.sh` → `sh` → `sleep`. У 38 из 41 «Проверок» потомки глубже прямого ребёнка.
kid() { printf '%s\n' "sh -c 'echo \$\$ > \"$S/pid-$1\"; exec sleep 40'" true > "$S/deep-$1.sh"
        printf '%s' ": > \"$S/ran-$1\"; bash \"$S/deep-$1.sh\" & wait"; }

# Нога A — completion-gate, открытый пункт.
mkdir -p "$S/a-state"
printf '# BACKLOG\n\n### D301 ◐ долгий внук\n**Результат.** нет\n**Проверка.** `%s` → 0\n' "$(kid a)" > "$S/a.md"
printf '{"session_id":"probe-d1180-a","cwd":"/"}' \
    | env CG_TIMEOUT=1 CG_BACKLOG="$S/a.md" STATE_DIR="$S/a-state" bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1

# Нога B — backlog-archive, закрытый пункт.
printf '# BACKLOG\n\n### D302 ☑ долгий внук\n**Результат.** да\n**Проверка.** `%s` → 0\n' "$(kid b)" > "$S/b.md"
env BACKLOG_CHECK_TIMEOUT=1 BACKLOG_FILE="$S/b.md" BACKLOG_ARCHIVE="$S/b-arch.md" STATE_DIR="$S/b-state" \
    bash "$REPO/scripts/backlog-archive.sh" run >/dev/null 2>&1

# Нога D — пересчёт показаний.
printf -- '- ☐ **D9711** долгий внук\n  **Проверка.** `false` → 0\n  **Показание.** `%s`\n  **Последнее показание (2026-10-01).** 0\n' \
    "$(kid d)" > "$S/d.md"
env READING_TIMEOUT=1 BACKLOG_FILE="$S/d.md" STATE_DIR="$S/d-state" \
    bash "$REPO/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1

bad=0
for leg in a b d; do
    [ -e "$S/ran-$leg" ] && [ -s "$S/pid-$leg" ] || { echo "нога $leg: исполнитель не дошёл до команды — не измерено"; exit 2; }
    kill -0 "$(cat "$S/pid-$leg")" 2>/dev/null && { echo "нога $leg: внук «Проверки» жив после выхода исполнителя"; bad=1; }
done
[ "$bad" = 0 ] && echo "все три исполнителя сняли «Проверку» по сроку вместе с потомками"
exit "$bad"
