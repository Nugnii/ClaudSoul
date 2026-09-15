#!/usr/bin/env bash
# test_digest_reads_own_format.sh — дайджест читает тот формат, который сам печатает.
#
# Результат: строка тренда появляется, когда прошлый дайджест существует
# Проверка результата: bash hooks/tests/test_digest_reads_own_format.sh даёт 0
#
# Повод, 7 сентября 2026. Читатель прошлого итога стоял на якоре `^\*\*Total:\*\*`
# (:361), а писатель печатал `- **Total:** N` (:394) — строка начинается с маркера списка,
# и якорь `^` не совпадал НИ РАЗУ. Замер по живым данным: 21 дайджест с W17 по W37,
# строк `Trend:` — 0, совпадений якоря — 0. Значение не читалось никогда, а следом был
# мёртв и шестой сигнал подсказки: он загейчен на непустой `trend_line`.
#
# Класс шире одного якоря: формат, который механизм САМ печатает и САМ читает, объявлен
# ДВАЖДЫ — отдельно у писателя, отдельно у читателя, и связаны они только совпадением
# строкового шаблона. Потому нога T2 проверяет не регулярку, а круг: печать → чтение.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/hooks/knowledge-audit-digest.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: нет $SCRIPT"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

LESSONS="$TMP/lessons"; HIST="$LESSONS/_audit-history"; STATE="$TMP/state"
mkdir -p "$HIST" "$STATE"
for n in a b c; do
    cat > "$LESSONS/pattern-$n.md" <<MD
---
name: $n
type: pattern
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
тело
MD
done

run() { LESSONS_DIR="$LESSONS" HISTORY_DIR="$HIST" STATE_DIR="$STATE" bash "$SCRIPT" >/dev/null 2>&1; }

# --- T1: прошлого дайджеста нет — тренда нет, и это норма ---
run
NEW=$(ls -1t "$HIST"/audit-*.md 2>/dev/null | head -1)
if [ -z "$NEW" ]; then
    bad "T0" "дайджест не создан — прогон не состоялся"
else
    ok
    if grep -q 'Trend:' "$NEW"; then bad "T1" "тренд напечатан без прошлого дайджеста"; else ok; fi

    # --- T2: КРУГ. Прошлый дайджест — это ВЫВОД САМОГО СКРИПТА, не выдуманная строка.
    # Кладём его под именем прошлой недели и ждём, что читатель его поймёт.
    cp "$NEW" "$HIST/audit-2026-W01.md"
    run
    NEW2=$(ls -1t "$HIST"/audit-*.md 2>/dev/null | grep -v 'W01' | head -1)
    if grep -q 'Trend:' "$NEW2" 2>/dev/null; then ok
    else bad "T2" "прошлый итог не прочитан из СОБСТВЕННОГО вывода — строка была: $(grep -m1 'Total:' "$HIST/audit-2026-W01.md")"; fi

    # --- T3: прочитанное значение верно (не «**Total:**», а число) ---
    if grep -qE 'Trend: (No change|[+-][0-9]+ files)' "$NEW2" 2>/dev/null; then ok
    else bad "T3" "тренд напечатан, но не числом: $(grep -m1 'Trend:' "$NEW2" 2>/dev/null)"; fi
fi

echo "digest reads own format: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
