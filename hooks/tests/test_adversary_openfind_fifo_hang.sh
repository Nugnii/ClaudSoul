#!/usr/bin/env bash
# test_adversary_openfind_fifo_hang.sh — АТАКА 6: прибор встаёт намертво на границе хода.
#
# hooks/lib/open-findings-lib.sh:77-79 берёт ВСЁ, что подошло под `outcome-*.jsonl`, и зовёт
# `open(...).readlines()`. Тип файла не проверяется: каталог отсеивается исключением OSError,
# а ИМЕНОВАННЫЙ КАНАЛ — нет. `readlines()` на канале без писателя блокируется навсегда,
# и вместе с ним стоит Stop-хук: строка 578 session-collector.sh ждёт подстановку.
#
# ДОСТИЖИМОСТЬ НЕ ДОКАЗАНА: в каталоге состояния канал никто не создаёт. Проверено, что
# защиты от него нет вовсе — ни проверки `os.path.isfile`, ни бюджета времени у вызова.
#
# Тест сам не виснет: писатель держит канал открытым фиксированные 3 секунды и закрывает,
# отдавая EOF. Признак дефекта — ПРОСТОЙ вызова, а не его незавершённость.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/open-findings-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v mkfifo >/dev/null 2>&1 || { echo "SKIP: нет mkfifo"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)   # ничего не удаляем
S="$TMP/state"; mkdir -p "$S"
# shellcheck source=/dev/null
. "$LIB"

cat > "$S/outcome-real.jsonl" <<'J'
{"ts":"2026-09-01T10:00:00Z","key":"k1","signal":"discovery","outcome":"deferred","ref":""}
J
mkfifo "$S/outcome-pipe.jsonl" || { echo "SKIP: канал не создался"; exit 0; }

# Страховка от зависания САМОГО теста. Открытие канала на ЗАПИСЬ ждёт читателя, и когда
# прибор перестал читать нерегулярные файлы, ждать стало некого: тест повисал навсегда
# ровно потому, что починка работает. Открытие на ЧТЕНИЕ-ЗАПИСЬ (`3<>`) не блокируется
# никогда — канал остаётся живым, замер длительности прежний.
exec 3<>"$S/outcome-pipe.jsonl"
( sleep 3; exec 3>&- ) &
WRITER=$!

START=$(date +%s)
OUT=$(of_open_counts "$S" 2>/dev/null)
END=$(date +%s)
wait "$WRITER" 2>/dev/null
ELAPSED=$((END - START))

[ "$ELAPSED" -lt 2 ] \
    && ok || bad F1 "прибор простоял ${ELAPSED}с на именованном канале в каталоге состояния — Stop-хук ждёт столько же (вывод «${OUT}»)"

echo "adversary openfind fifo-hang: $PASS passed, $FAIL failed (песочница: $TMP)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
