#!/usr/bin/env bash
# test_adv_kia_ledger_corruption_amnesty.sh — АТАКА: порча реестра входа списывает все сроки,
# отчитывается «находок нет» и затирает улику.
#
# Единственное место, где живут даты входа в очередь, — `STATE_DIR/knowledge-instrument-queue.json`.
# Скрипт читает его так (строки 161-166):
#     try: ledger = json.loads(...); ...
#     except Exception: ledger = {}
# Любая порча — оборванная запись, JSON-массив вместо объекта, пустой файл — молча становится
# пустым реестром. Дальше `setdefault` (строка 183) проставляет всем пунктам СЕГОДНЯШНЮЮ дату,
# `write_text` (строка 194) записывает её поверх испорченного файла, и просрочка исчезает
# вместе со свидетельством того, что она была. Ни строки в отчёт, ни строки в stdout.
#
# Достижимость. Запись реестра неатомарна: один `write_text` без временного файла и
# переименования. Два одновременных прогона (launchd-дайджест и запуск руками), падение по
# месту на диске или обрыв процесса дают оборванный файл ровно этого вида — и следующий же
# прогон превращает его в чистую страницу. Проверять после этого нечего: старого содержимого
# больше нет.
#
# Ожидание: реестр с потерянными данными называется вслух и сроки не обнуляются молча.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# probe <метка> <содержимое испорченного реестра>
probe() {
    local T; T=$(mktemp -d); mkdir -p "$T/l" "$T/s"
    cat > "$T/l/pattern-a.md" <<'KN'
---
type: pattern
confirmed_count: 9
outcome: error
status: active
description: "проба"
---
# Тело
KN
    LESSONS_DIR="$T/l" STATE_DIR="$T/s" bash "$AUDIT" >/dev/null 2>&1
    python3 - "$T/s/knowledge-instrument-queue.json" <<'PY'
import json, sys, datetime, pathlib
pathlib.Path(sys.argv[1]).write_text(json.dumps(
    {"pattern-a": (datetime.date.today() - datetime.timedelta(days=99)).isoformat()}))
PY
    LESSONS_DIR="$T/l" STATE_DIR="$T/s" bash "$AUDIT" >"$T/before" 2>&1; RC_BEFORE=$?
    printf '%s' "$2" > "$T/s/knowledge-instrument-queue.json"
    LESSONS_DIR="$T/l" STATE_DIR="$T/s" bash "$AUDIT" >"$T/after" 2>&1; RC_AFTER=$?
    AFTER_OUT=$(cat "$T/after"); LEDGER_AFTER=$(tr -d '\n ' < "$T/s/knowledge-instrument-queue.json")
    echo "  $1: до порчи rc=$RC_BEFORE ($(grep -c ПРОСРОЧЕНО "$T/before") строк просрочки), после rc=$RC_AFTER ($(grep -c ПРОСРОЧЕНО "$T/after") строк)"
    echo "     реестр стал: $LEDGER_AFTER"
}

echo "проверяем три формы порчи:"

probe "оборванная запись" '{"pattern-a": "2026-0'
if [ "$RC_BEFORE" = "1" ] && [ "$RC_AFTER" = "0" ]; then
    bad E1 "99 дн. просрочки исчезли после порчи файла: rc 1 → 0, «находок нет», испорченный реестр перезаписан сегодняшней датой"
elif grep -qi "реестр\|повреж\|не прочит" <<< "$AFTER_OUT"; then ok E1
else bad E1 "порча не названа в выводе: $AFTER_OUT"; fi

probe "массив вместо объекта" '["pattern-a"]'
if [ "$RC_AFTER" = "0" ] && ! grep -qi "реестр\|повреж\|не прочит" <<< "$AFTER_OUT"; then
    bad E2 "JSON-массив вместо объекта принят молча, сроки сброшены на сегодня"
else ok E2; fi

probe "пустой файл" ''
if [ "$RC_AFTER" = "0" ] && ! grep -qi "реестр\|повреж\|не прочит" <<< "$AFTER_OUT"; then
    bad E3 "пустой реестр неотличим от «сроков не было»: замер зелёный, даты входа потеряны"
else ok E3; fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
