#!/usr/bin/env bash
# СУДИТ: scripts/disagreement-revocation-check.sh scripts/knowledge-coverage.sh
# test_adv2_wit_coverage_green_without_instrument.sh — knowledge-coverage.sh и disagreement-revocation-check.sh отвечают 0 «находок нет», когда проверять нечем: нет базы знаний либо нет python3; свидетели этого не видят, потому что сами уходят в SKIP без python3 и ноги «базы нет» не ставят.
#
# Результат: контракт реестра замеров назван в scripts/stop-context-restart.sh:30-31 — 0 «отработал,
#            находок нет», 2 «не смог отработать»; правило «у прибора три состояния» стоит в
#            .claude/rules/claudsoul-hooks.md § «Хук зовёт инструмент»: сломанный инструмент обязан говорить, «молчание
#            читается как чисто». `knowledge-coverage.sh:29-30` на отсутствии базы и python3 пишет
#            жалобу в stderr и выходит 0; `disagreement-revocation-check.sh:36` без python3 — тоже 0,
#            и журнал с нарушением формата проходит как «формат един». Шапки обоих обещают
#            «даёт 0, когда необъяснённых нет» / «даёт 0» при едином формате. Ожидание: код 2.
# Проверка результата: этот тест.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COV="$REPO/scripts/knowledge-coverage.sh"
DIS="$REPO/scripts/disagreement-revocation-check.sh"
[ -f "$COV" ] || { echo "FAIL: $COV not found"; exit 1; }
[ -f "$DIS" ] || { echo "FAIL: $DIS not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/lessons" "$TMP/state"
# Урезанный PATH: только bash — python3 в нём нет, всё остальное у инструментов встроенное.
ln -s "$(command -v bash)" "$BIN/bash"

# --- T1: базы нет — «не измерено» (2), а не «объяснено» (0) ------------------------------------
OUT=$(cd "$REPO" && LESSONS_DIR="$TMP/nope" STATE_DIR="$TMP/state" bash "$COV" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T1 "knowledge-coverage без базы: rc=$RC (ожидалось 2) — «${OUT}»"

# --- T2: python3 нет — тот же отказ, а не зелёный код ---------------------------------------
OUT=$(cd "$REPO" && PATH="$BIN" LESSONS_DIR="$TMP/lessons" STATE_DIR="$TMP/state" bash "$COV" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T2 "knowledge-coverage без python3: rc=$RC (ожидалось 2) — «${OUT}»"

# --- T3: брат корня — disagreement-revocation-check без python3 на журнале с нарушением -------
printf '{"date": "2026-09-01","session":"s1","knowledge":"pattern-y","confidence":4,"outcome":"confirmed","case":"c1"}\n' > "$TMP/state/disagreement-outcomes.jsonl"
OUT=$(cd "$REPO" && PATH="$BIN" STATE_DIR="$TMP/state" bash "$DIS" check 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T3 "disagreement-revocation-check без python3 на журнале в чужом формате: rc=$RC (ожидалось 2) — «${OUT}»"

echo ""
echo "adv2 coverage-green-without-instrument tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
