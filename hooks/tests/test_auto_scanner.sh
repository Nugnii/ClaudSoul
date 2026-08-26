#!/usr/bin/env bash
# test_auto_scanner.sh — характеризующий тест read-only сканера проектов.
# Полный прогон сканирует реальные проекты (side-effect), поэтому тест проверяет
# безопасные инварианты (F8): (1) gate «не чаще ~3ч» — при свежей метке скан
# пропускается; (2) read-only — в исходнике нет мутирующих команд (git commit/push,
# rm, edit). Комментарий хука: «КРИТИЧНО: только чтение».

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/auto-scanner.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }

PASS=0
FAIL=0
assert_rc0() { if [ "$1" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1"; fi; }
assert_true() { if [ "$1" = "1" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

# T1 — gate: свежая метка времени → скан пропускается, реальные проекты не трогаются
date +%s > "$TMP/state/last-scan-timestamp"
STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
rc=$?
assert_rc0 "$rc" "T1 gate skip → rc=0"
# при пропуске scan-results не должен появиться в изолированном STATE_DIR
[ ! -f "$TMP/state/scan-results.md" ] && SKIP_OK=1 || SKIP_OK=0
assert_true "$SKIP_OK" "T1 пропуск не пишет scan-results.md"

# T2 — read-only инвариант: в исходнике нет мутирующих команд
MUT=$(grep -nE "git (commit|push|add|reset|checkout)|[^-]rm -|>[^>]*\.(md|json)|Edit|Write" "$HOOK" \
    | grep -vE "scanner\.log|scan-results|last-scan|>> |LOG_FILE|RESULTS_FILE|2>/dev/null|# |echo " || true)
if [ -z "$MUT" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [T2 read-only]: подозрительные строки:"; echo "$MUT"; fi

echo ""
echo "auto-scanner tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
