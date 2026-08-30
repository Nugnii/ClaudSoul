#!/usr/bin/env bash
# test_adv_kia_crash_reads_as_finding.sh — АТАКА: разбор упал, а вызывающий записал «замер
# выполнен, есть находки» и поставил отметку на 7 дней вперёд.
#
# Скрипт кончает трассой Python при любой неожиданности во входе (реестр — каталог, каталог
# состояния без права записи, нечисловой KIA_QUEUE_MAX_DAYS). Необработанное исключение даёт
# коду возврата 1. Ровно этим кодом скрипт сообщает «отработал и НАШЁЛ просрочку» — и он же
# описан в его последней строке как отличимый от отказа: «Код 1 — "отработал и нашёл", его
# measurement-due отличает от отказа (код ≥ 2)».
#
# measurement-due.sh:99-113 различия не делает: `[ "$_rc" -le 1 ]` → ставит отметку прогона,
# печатает «выполнен, ЕСТЬ НАХОДКИ» и уводит вывод замера в /dev/null. Отказ становится
# находкой, отчёт не пишется, а замер считается сделанным и не повторится 7 дней
# (scripts/measurements.tsv:22 — период 7).
#
# Ожидание: разбор, который не смог отработать, выходит кодом ≥ 2.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
DUE="$REPO/scripts/measurement-due.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

mkbase() {
    mkdir -p "$1"
    cat > "$1/pattern-a.md" <<'KN'
---
type: pattern
confirmed_count: 9
outcome: error
status: active
description: "проба"
---
# Тело
KN
}

# --- эталон: настоящая находка тоже даёт 1 (значит коды неразличимы) ---
T0=$(mktemp -d); mkbase "$T0/l"; mkdir -p "$T0/s"
LESSONS_DIR="$T0/l" STATE_DIR="$T0/s" bash "$AUDIT" >/dev/null 2>&1
python3 - "$T0/s/knowledge-instrument-queue.json" <<'PY'
import json, sys, datetime, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(json.dumps({"pattern-a": (datetime.date.today() - datetime.timedelta(days=99)).isoformat()}))
PY
LESSONS_DIR="$T0/l" STATE_DIR="$T0/s" bash "$AUDIT" >/dev/null 2>&1; RC_FIND=$?
echo "эталон — настоящая просрочка: rc=$RC_FIND"
[ "$RC_FIND" = "1" ] || { echo "SKIP: находка перестала давать 1 — сравнивать не с чем"; exit 0; }

# --- A1: реестр очереди оказался каталогом ---
T1=$(mktemp -d); mkbase "$T1/l"; mkdir -p "$T1/s/knowledge-instrument-queue.json"
OUT=$(LESSONS_DIR="$T1/l" STATE_DIR="$T1/s" bash "$AUDIT" 2>&1); RC=$?
echo "реестр-каталог: rc=$RC; отчёт написан: $([ -f "$T1/s/knowledge-instrument.md" ] && echo да || echo НЕТ)"
echo "$OUT" | tail -1
if [ "$RC" -ge 2 ]; then ok A1; else bad A1 "падение вышло кодом $RC — вызывающий прочтёт его как находку"; fi

# --- A2: каталог состояния без права записи ---
T2=$(mktemp -d); mkbase "$T2/l"; mkdir -p "$T2/s"; chmod 555 "$T2/s"
OUT=$(LESSONS_DIR="$T2/l" STATE_DIR="$T2/s" bash "$AUDIT" 2>&1); RC=$?
chmod 755 "$T2/s"
echo "состояние только на чтение: rc=$RC"
if [ "$RC" -ge 2 ]; then ok A2; else bad A2 "падение вышло кодом $RC — неотличимо от находки"; fi

# --- A3: KIA_QUEUE_MAX_DAYS не число ---
T3=$(mktemp -d); mkbase "$T3/l"; mkdir -p "$T3/s"
OUT=$(LESSONS_DIR="$T3/l" STATE_DIR="$T3/s" KIA_QUEUE_MAX_DAYS=неделя bash "$AUDIT" 2>&1); RC=$?
echo "нечисловой порог: rc=$RC"
if [ "$RC" -ge 2 ]; then ok A3; else bad A3 "падение вышло кодом $RC — неотличимо от находки"; fi

# --- A4: ДОСТИЖИМОСТЬ — measurement-due на упавшем замере ставит отметку ---
T4=$(mktemp -d); mkbase "$T4/l"; mkdir -p "$T4/s/knowledge-instrument-queue.json"
REG="$T4/registry.tsv"
printf 'knowledge-instrument\t7\tLESSONS_DIR=%s bash scripts/knowledge-instrument-audit.sh\tпроба\n' "$T4/l" > "$REG"
DUE_OUT=$(STATE_DIR="$T4/s" MEASUREMENT_REGISTRY="$REG" CLAUDSOUL_REPO="$REPO" bash "$DUE" run 2>&1); DUE_RC=$?
echo "--- measurement-due на упавшем замере (rc=$DUE_RC):"
echo "$DUE_OUT" | sed 's/^/    /'
stamped=$([ -f "$T4/s/measurement-runs/knowledge-instrument" ] && echo да || echo нет)
echo "отметка прогона поставлена: $stamped"
if grep -q "НЕ ВЫПОЛНЕН" <<< "$DUE_OUT"; then
    ok A4
else
    bad A4 "упавший замер записан как выполненный (отметка: $stamped) — 7 дней его никто не перезапустит"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
