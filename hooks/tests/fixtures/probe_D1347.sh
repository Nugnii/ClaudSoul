#!/usr/bin/env bash
# СУДИТ: scripts/measurement-due.sh hooks/tests/test_bash_write_dispatch.sh hooks/tests/test_root_cause_doctrine_drift.sh
# probe_D1347.sh — свидетели зелёны, когда их гоняет ежедневное задание замеров: launchd даёт ему один PATH.
#
# Повод (21 ноября 2026). Ежедневное задание (`launchd/com.claudsoul.measurements.plist`) задаёт только PATH: ни LANG,
# ни LC_ALL. В таком окружении красны `test_bash_write_dispatch.sh` (T9: хвост сообщения стража отрезан — резка идёт по
# байтам, а не по знакам), `test_root_cause_doctrine_drift.sh` (маркеры доктрины не найдены: поиск без учёта регистра
# кириллицы) и `test_class_registry_owed.sh` (T4n); в сессии, где язык настроен, все три зелёные. Ночной замер цены
# тестов записывает им код 1, а прибор свидетелей-атак относит их к «рамка не собралась».
# Рамка — вход самого задания: `/bin/bash scripts/measurement-due.sh run` в окружении из PATH и HOME, с реестром из
# двух команд-представителей; каждая пишет код своего теста в файл. Реестр и состояние — во временной папке.
# Проверка результата: bash hooks/tests/fixtures/probe_D1347.sh → 0 — оба представителя зелёны под заданием;
#   1 — хотя бы один красен; 2 — не измерено (нет тестов или скрипта задания, команда не исполнилась, либо
#   положительный контроль не сошёлся: с настроенным языком представитель обязан быть зелёным — иначе рамка не
#   отличает язык от поломки).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T1="hooks/tests/test_root_cause_doctrine_drift.sh"; T2="hooks/tests/test_bash_write_dispatch.sh"
DUE="$REPO/scripts/measurement-due.sh"
[ -f "$REPO/$T1" ] && [ -f "$REPO/$T2" ] && [ -f "$DUE" ] || { echo "нет тестов-представителей либо скрипта задания — не измерено"; exit 2; }
BARE_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
( cd "$REPO" && env -i HOME="$HOME" USER="${USER:-x}" PATH="$BARE_PATH" TMPDIR="${TMPDIR:-/tmp}" LC_ALL=en_US.UTF-8 /bin/bash "$T1" >/dev/null 2>&1 ) \
    || { echo "контроль: с настроенным языком $T1 красен — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/state"
{ printf 'd1347-a\t1\tbash "%s" >/dev/null 2>&1; echo $? > "%s"\tпредставитель\n' "$REPO/$T1" "$W/rc1"
  printf 'd1347-b\t1\tbash "%s" >/dev/null 2>&1; echo $? > "%s"\tпредставитель\n' "$REPO/$T2" "$W/rc2"; } > "$W/m.tsv"
env -i HOME="$HOME" USER="${USER:-x}" PATH="$BARE_PATH" TMPDIR="${TMPDIR:-/tmp}" \
    MEASUREMENT_REGISTRY="$W/m.tsv" STATE_DIR="$W/state" /bin/bash "$DUE" run >/dev/null 2>&1
r1=$(cat "$W/rc1" 2>/dev/null); r2=$(cat "$W/rc2" 2>/dev/null)
[ -n "$r1" ] && [ -n "$r2" ] || { echo "задание не исполнило команды-представители — не измерено"; exit 2; }
red=""
[ "$r1" = 0 ] || red="$red ${T1##*/}"
[ "$r2" = 0 ] || red="$red ${T2##*/}"
if [ -n "$red" ]; then
    echo "под заданием без настроек языка красны:${red}"
    exit 1
fi
echo "свидетели зелёны под заданием без настроек языка"
exit 0
