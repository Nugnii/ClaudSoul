#!/usr/bin/env bash
# test_dose_response.sh — доза подачи считается по парам, исход группируется по корзинам.
#
# Зачем (D240). Перед расширением доставки (кириллизация якорей, семантический слот)
# нужен замер цены шума: меняется ли исход с ЧИСЛОМ повторных подач одного знания за
# сессию. Строк в журнале на пару (сессия, файл) = номер подачи — доза уже в данных.
# Вывод замера обязан жить в собственном артефакте: measurement-due глушит stdout
# (разрыв delivery-miss «писатель без читателя»).
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/dose-response.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"

# Дозы: pattern-x@sA — 3 подачи (корзина 2-3, исход not_applicable);
#       pattern-y@sA — 1 подача (корзина 1, исход confirmed_knowledge);
#       pattern-r@sB — 5 подач слотом research (отдельный срез);
#       вердикт по pattern-z@sC — без подач (сирота).
cat > "$STATE/injection-log.jsonl" << 'EOF'
{"date":"2026-09-01T10:00:00Z","file":"pattern-x.md","injected":true,"session_id":"sA","slot":"main"}
{"date":"2026-09-01T10:05:00Z","file":"pattern-x.md","injected":true,"session_id":"sA","slot":"main"}
{"date":"2026-09-01T10:10:00Z","file":"pattern-x.md","injected":true,"session_id":"sA","slot":"main"}
{"date":"2026-09-01T10:00:00Z","file":"pattern-y.md","injected":true,"session_id":"sA","slot":"main"}
{"date":"2026-09-01T11:00:00Z","file":"pattern-r.md","injected":true,"session_id":"sB","slot":"research"}
{"date":"2026-09-01T11:01:00Z","file":"pattern-r.md","injected":true,"session_id":"sB","slot":"research"}
{"date":"2026-09-01T11:02:00Z","file":"pattern-r.md","injected":true,"session_id":"sB","slot":"research"}
{"date":"2026-09-01T11:03:00Z","file":"pattern-r.md","injected":true,"session_id":"sB","slot":"research"}
{"date":"2026-09-01T11:04:00Z","file":"pattern-r.md","injected":true,"session_id":"sB","slot":"research"}
EOF
cat > "$STATE/disagreement-outcomes.jsonl" << 'EOF'
{"date":"2026-09-01T12:00:00Z","session":"sA","knowledge":"pattern-x.md","outcome":"not_applicable","case":"мимо"}
{"date":"2026-09-01T12:01:00Z","session":"sA","knowledge":"pattern-y.md","outcome":"confirmed_knowledge","case":"по делу"}
{"date":"2026-09-01T12:02:00Z","session":"sC","knowledge":"pattern-z.md","outcome":"confirmed_knowledge","case":"сирота"}
EOF

OUT=$(STATE_DIR="$STATE" DOSE_RESPONSE_SINCE="2026-09-01" bash "$SCRIPT" 2>&1); RC=$?

ck() { # $1 needle, $2 label
    if grep -qF -- "$1" <<< "$OUT"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: не найдено '$1'"; fi
}

# T1: корзины доз по парам названы числом
ck "доза 1: пар 1" "T1a: корзина 1"
ck "доза 2-3: пар 1" "T1b: корзина 2-3"
# T2: исход по корзине — not_applicable попал в корзину своей дозы
ck "not_applicable 1" "T2: исход в корзине 2-3"
# T3: research — отдельный срез, в основной не входит (в основном срезе одна пара 4+ быть не должна)
ck "slot=research" "T3a: срез research назван"
if grep -q "доза 4+: пар 1" <<< "$OUT" && ! grep -q "research.*доза 4+\|доза 4+.*research" <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [T3b]: research-пара попала в основной срез доз"
else PASS=$((PASS+1)); fi
# T4: вердикт без подачи — отдельной строкой, не молча
ck "без подачи" "T4: сирота назван"
# T5: артефакт написан
if [ -s "$STATE/dose-response-last.txt" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: артефакт state/dose-response-last.txt не написан"; fi
# T6: код возврата 0/1, не сбой
if [ "$RC" -le 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: rc=$RC"; fi

[ "$FAIL" -gt 0 ] && { echo "--- вывод ---"; printf '%s\n' "$OUT" | sed 's/^/  /'; }
echo "test_dose_response: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
