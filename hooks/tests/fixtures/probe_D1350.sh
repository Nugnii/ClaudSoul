#!/usr/bin/env bash
# СУДИТ: scripts/measurement-due.sh hooks/root-cause-lib.sh
# probe_D1350.sh — находка замера, сделанная ежедневным заданием, записывается поводом с адресом ПРОЕКТА, а не каталога
# процесса.
#
# Повод (21 ноября 2026). launchd запускает задание из каталога «/»; `rc_note_event` берёт проект у каталога процесса,
# и находка замера ложится в `pending-events.jsonl` с `project: "/"`. Читатель поводов (`rc_open_events`) отдаёт сессии
# только поводы её проекта — такие записи не доходят ни до одной сессии: 108 из 148 поводов `measure-found`, все
# открыты. Так красная сверка карты корней (`root-map-drift`, 20 октября) месяц оставалась без пункта.
# Рамка: настоящий скрипт задания из каталога «/», реестр из одной команды-находки и состояние — во временной папке.
# Проверка результата: bash hooks/tests/fixtures/probe_D1350.sh → 0 — повод записан с адресом репозитория скрипта;
#   1 — с другим адресом; 2 — не измерено (нет скрипта или jq, повод не записан вовсе).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
DUE="$REPO/scripts/measurement-due.sh"
[ -f "$DUE" ] && command -v jq >/dev/null 2>&1 || { echo "нет скрипта задания либо jq — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/state"
printf 'zond-addr\t1\techo "проба: находка замера"; exit 1\tзонд\n' > "$W/m.tsv"
( cd / && env -u CLAUDSOUL_REPO -u RC_EVENT_PROJECT MEASUREMENT_REGISTRY="$W/m.tsv" STATE_DIR="$W/state" bash "$DUE" run >/dev/null 2>&1 )
P=$(jq -r 'select(.kind == "measure-found") | .project' "$W/state/pending-events.jsonl" 2>/dev/null | head -1)
[ -n "$P" ] || { echo "повод о находке не записан — не измерено"; exit 2; }
WANT=$(cd "$(dirname "$DUE")/.." && pwd -P)
if [ "$P" = "$WANT" ]; then
    echo "находка задания записана с адресом проекта"
    exit 0
fi
echo "находка задания записана с адресом «${P}», а не проекта"
exit 1
