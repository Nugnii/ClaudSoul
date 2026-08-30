#!/usr/bin/env bash
# test_compliance_gate.sh — «расхождений нет» на крошечной выборке это не «гейт пройден» (D58).
#
# Повод. `backfill-compliance.sh --verify-log` утверждал «✅ парсер не выдумывает событий»
# с одинаковой уверенностью при двух сессиях и при двадцати шести. Разница возникла не
# сама: уборка throttle снесла 122 файла `blocker-fired-*` (D57), и выборка гейта ужалась
# с 26 до 2 — а он продолжил печатать «пройден».
#
# При такой выборке отсутствие расхождений не отличимо от отсутствия данных. Тот же приём
# уже применён к метрикам вмешательства в v1.12.0: процент не показывается без n.
#
# Код возврата различает три вещи: 0 — выборка достаточна и расхождений нет;
# 1 — есть расхождения (парсер недостоверен); 2 — выборка мала, вывод не делается.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/backfill-compliance.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -qF -- "$1" <<< "$2"; }

# Фикстура: N сессий, у каждой лог срабатываний и совпадающий транскрипт.
# Транскрипт с ОДНИМ событием блокера на сессию — ровно столько же, сколько в логе,
# поэтому расхождений быть не должно и проверяется именно порог выборки.
_fixture() { # $1=сколько сессий
    rm -rf "$TMP/state" "$TMP/projects"
    mkdir -p "$TMP/state" "$TMP/projects/proj"
    local i sid
    i=1
    while [ "$i" -le "$1" ]; do
        sid="0000000${i}-aaaa-bbbb-cccc-dddddddddddd"
        printf '{"date":"2026-07-01T00:00:00Z","key":"k","signal":"s1"}\n' \
            > "$TMP/state/blocker-fired-${sid}.jsonl"
        printf '{"type":"user","message":{"content":[{"type":"text","text":"x"}]}}\n' \
            > "$TMP/projects/proj/${sid}.jsonl"
        i=$((i + 1))
    done
}
run() { # $1=порог
    COMPLIANCE_MIN_SESSIONS="$1" STATE_DIR="$TMP/state" \
        BACKFILL_PROJECTS_DIR="$TMP/projects" \
        bash "$SCRIPT" --verify-log 2>&1
}

# --- T1: выборка ниже порога — НЕ «пройден», и код отличается от успеха ---
_fixture 2
OUT=$(run 10); RC=$?
has "выборка мала" "$OUT" && ok || bad "T1a" "малая выборка не названа: $OUT"
has "Гейт пройден" "$OUT" && bad "T1b" "напечатано «пройден» на выборке меньше порога" || ok
[ "$RC" -eq 2 ] && ok || bad "T1c" "малая выборка вернула код $RC вместо 2"

# --- T2: выборка достаточна — гейт проходит и называет её размер ---
# Отрицательный контроль к T1: без него зелёный T1 не отличим от «гейт никогда не проходит».
_fixture 12
OUT=$(run 10); RC=$?
if has "Гейт пройден" "$OUT"; then ok; else bad "T2a" "достаточная выборка не прошла: $OUT"; fi
[ "$RC" -eq 0 ] && ok || bad "T2b" "достаточная выборка вернула код $RC вместо 0"
has "сессий в выборке" "$OUT" && ok || bad "T2c" "размер выборки не назван в утверждении"

# --- T3: порог настраивается — иначе фикстура доказывала бы одно число, а не правило ---
_fixture 3
OUT=$(run 2); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T3" "порог из окружения не учтён (код $RC)"

# --- T4: сам порог задан в коде, а не остался мечтой ---
grep -q 'COMPLIANCE_MIN_SESSIONS' "$SCRIPT" && ok || bad "T4" "порога выборки нет в скрипте"

echo ""
echo "compliance gate tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
