#!/usr/bin/env bash
# test_adv3_kia_field_trailing_comment.sh
#
# АТАКА: хвостовой комментарий у поля шапки переворачивает очередь.
#
# `field()` возвращает СЫРОЙ остаток строки. Хвост `# ...` учтён ровно в одном месте —
# у `confirmed_count` (строка 157: «хвост (комментарий через #) не мешает числу»).
# Соседние поля той же шапки читаются побайтово:
#   `outcome: error  # 12 проявлений`      → outcome == "error  # 12 проявлений" ≠ "error"
#   `status: deprecated  # снято 01.08`    → status  != "deprecated"
# То есть починили там, где заметили, а класс остался.
#
# Комментарий в шапке — не гипотеза, а обычай базы: в боевой базе так записаны
# `outcome: success           # ← отличие от обычного кейса`, `blocker: false  # ...`,
# `intensity: 0  # ...` и восемь из пятнадцати `instrument_verdict: ... # ...`.
#
# Итог: очередь на производство переворачивается. Действующее знание с 30 подтверждениями
# из неё выпадает молча (и в «Не прочитано полей» не попадает), а СНЯТОЕ с учёта — стоит
# в ней, копит срок и через 31 день роняет замер требованием построить инструмент для
# знания, которое больше не действует.
#
# Ожидание: очередь совпадает с тем, как шапку прочтёт `yaml.safe_load` —
# в ней `pattern-outcome-comment`, и нет `pattern-status-comment`.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

cat > "$L/pattern-outcome-comment.md" <<'EOF'
---
description: живой класс ошибок, у outcome хвостовой комментарий
outcome: error           # ← 12 проявлений, все ошибки
status: active
confirmed_count: 30
---
тело
EOF

cat > "$L/pattern-status-comment.md" <<'EOF'
---
description: снято с учёта, у status хвостовой комментарий
outcome: error
status: deprecated       # снято 2026-08-01, заменено паттерном X
confirmed_count: 30
---
тело
EOF

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"
queue_rows="$(grep '^| 0 |' <<< "$report")"

printf -- '--- вывод замера (rc=%s) ---\n%s\n--- строки очереди ---\n%s\n' "$rc" "$out" "$queue_rows"

if grep -q 'pattern-outcome-comment' <<< "$queue_rows"; then
    ok "знание с комментарием у outcome осталось в очереди"
else
    fail "знание с 30 подтверждениями выпало из очереди из-за комментария у outcome — и о нечитаемости не сказано ни слова"
fi

if grep -q 'pattern-status-comment' <<< "$queue_rows"; then
    fail "снятое с учёта (status: deprecated с комментарием) стоит в очереди на производство и копит срок"
else
    ok "deprecated в очередь не попал"
fi

# То же самое, но словами журнала: очередь обязана быть длиной 1, а не 1-наоборот.
if grep -q 'очередь на производство: 1' <<< "$out" && grep -q 'pattern-outcome-comment' <<< "$queue_rows"; then
    ok "длина очереди и её состав сходятся"
else
    fail "состав очереди не совпадает с тем, как шапки прочтёт yaml.safe_load"
fi

exit "$FAIL"
