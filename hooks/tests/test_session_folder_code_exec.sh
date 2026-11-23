#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh hooks/completion-gate.sh hooks/activity-flush-lib.sh hooks/paths-lib.sh
# test_session_folder_code_exec.sh — код из папки сессии на Stop не исполняется (D514).
#
# Держит в наборе пробу пункта: `fixtures/probe_D514.sh` судит оба хука в песочнице двумя
# путями (скрипт пересчёта показаний проекта, найденного по папке сессии; относительный
# `CG_LOCAL_BACKLOG` у гейта; признак, названный для другого проекта; программа из настроек git
# чужого репозитория) при своих контролях. Без этой обёртки проба жила бы только в
# «Проверке» закрытого пункта, то есть раз в неделю, а не на каждом прогоне.
set -uo pipefail
PROBE="$(cd "$(dirname "$0")" && pwd)/fixtures/probe_D514.sh"
[ -f "$PROBE" ] || { echo "FAIL: нет пробы $PROBE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
OUT=$(CLAUDSOUL_REPO="$(cd "$(dirname "$0")/../.." && pwd)" bash "$PROBE" 2>&1); RC=$?
echo "session folder code exec: код пробы $RC — $OUT"
# Относительный корень ClaudSoul из окружения не принимается: `.` читался бы от папки сессии.
LIB="$(cd "$(dirname "$0")/.." && pwd)/paths-lib.sh"
T=$(mktemp -d); mkdir -p "$T/home"
GOT=$(cd "$T" && HOME="$T/home" CLAUDSOUL_ROOT=. CLAUDSOUL_REPO= bash -c '. "$1" >/dev/null 2>&1; printf %s "${CLAUDSOUL_ROOT:-}"' _ "$LIB")
rm -rf "$T"
REL=0
case "$GOT" in /*|'') ;; *) REL=1; echo "FAIL: относительный CLAUDSOUL_ROOT принят как есть: «${GOT}»" ;; esac
exit $(( RC != 0 || REL != 0 ))
