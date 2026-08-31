#!/usr/bin/env bash
# test_backlog_closure_contract.sh — закрытие без показания в архив не уезжает.
#
# Результат: пункт ☑ без строки «Проверка» и ⊘ без «Вердикта» остаются в BACKLOG.md, а
#            архиватор называет, чего не хватает; исторические пункты не трогаются
# Проверка результата: bash hooks/tests/test_backlog_closure_contract.sh даёт 0
#
# Повод — требование владельца 29 августа 2026: «что должно считаться решением проблемы
# тоже нужно решить… результат должен быть измеримый и достижимый», и решением считается
# механизм, не дающий проблеме возникнуть. Метка ☑ этого не доказывает: она ставится
# рукой и означает лишь заявление о закрытии.
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · пункт с показанием уезжает в архив (гейт не мешает правильной работе);
#   · пункт с номером ниже порога не проверяется (исторические закрытия писались до
#     контракта; требовать с них задним числом = десятки ложных отказов);
#   · ⊘ с «Вердиктом» уезжает — отказ от работы это законный исход, если названа цена.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCH="$ROOT/scripts/backlog-archive.sh"
[ -f "$ARCH" ] || { echo "FAIL: нет $ARCH"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mk() { cat > "$TMP/BACKLOG.md"; : > "$TMP/BACKLOG-archive.md"; }
run() { BACKLOG_FILE="$TMP/BACKLOG.md" BACKLOG_ARCHIVE="$TMP/BACKLOG-archive.md" \
        bash "$ARCH" "${1:-run}" 2>&1; }

# --- T1: ☑ без «Проверки» → отказ, пункт остаётся ---
mk <<'BL'
# Долг

### D250 ☑ Починено, но чем — не сказано

**Дефект.** Что-то ломалось.
BL
OUT=$(run); RC=$?
if [ "$RC" -ne 0 ] && grep -q 'D250' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: закрытие без показания уехало: rc=$RC '$OUT'"; fi
if grep -q 'D250' "$TMP/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: пункт исчез из рабочего файла"; fi
if grep -q 'верни метку' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1c]: не назван исполнимый исход (D111)"; fi

# --- T2: КОНТРПРИМЕР — ☑ С «Проверкой» уезжает в архив ---
mk <<'BL'
# Долг

### D251 ☑ Починено и показано

**Дефект.** Что-то ломалось.
**Результат.** Страж отбивает признак, а не напоминает.
**Проверка.** `true` → 0
BL
OUT2=$(run); RC2=$?
if [ "$RC2" -eq 0 ] && grep -q 'D251' "$TMP/BACKLOG-archive.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: закрытие с показанием не уехало: rc=$RC2 '$OUT2'"; fi

# --- T3: КОНТРПРИМЕР — исторический номер (ниже порога) не проверяется ---
mk <<'BL'
# Долг

### D42 ☑ Старое закрытие без строк контракта

**Дефект.** Писалось до контракта.
BL
OUT3=$(run); RC3=$?
if [ "$RC3" -eq 0 ] && grep -q 'D42' "$TMP/BACKLOG-archive.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: исторический пункт задержан: rc=$RC3 '$OUT3'"; fi

# --- T4: ⊘ без «Вердикта» → отказ; с «Вердиктом» → уезжает ---
mk <<'BL'
# Долг

### D260 ⊘ Не делаем, а почему — молчок

**Дефект.** Признак ложный.
BL
OUT4=$(run); RC4=$?
if [ "$RC4" -ne 0 ] && grep -q 'D260' <<< "$OUT4"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: waived без вердикта уехал: rc=$RC4"; fi
mk <<'BL'
# Долг

### D261 ⊘ Не делаем, цена названа

**Дефект.** Признак ложный.
**Вердикт.** Показалось: признак сработал на подписи внутри теста, разобрано прогоном.
BL
OUT5=$(run); RC5=$?
if [ "$RC5" -eq 0 ] && grep -q 'D261' "$TMP/BACKLOG-archive.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4b]: waived с вердиктом задержан: rc=$RC5 '$OUT5'"; fi

# --- T5: КОНТРПРИМЕР — открытые пункты гейт не трогает вовсе ---
mk <<'BL'
# Долг

### D270 ☐ Открытый, показаний не требует

**Дефект.** Ещё чинится.
BL
OUT6=$(run); RC6=$?
if [ "$RC6" -eq 0 ] && grep -q 'D270' "$TMP/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: открытый пункт задет: rc=$RC6 '$OUT6'"; fi

# --- T6: порог настраивается — с MIN_ID=0 историческое тоже проверяется ---
mk <<'BL'
# Долг

### D42 ☑ Старое закрытие без строк контракта

**Дефект.** Писалось до контракта.
BL
OUT7=$(BACKLOG_CONTRACT_MIN_ID=0 BACKLOG_FILE="$TMP/BACKLOG.md" BACKLOG_ARCHIVE="$TMP/BACKLOG-archive.md" bash "$ARCH" run 2>&1); RC7=$?
if [ "$RC7" -ne 0 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: порог не настраивается: rc=$RC7"; fi

echo "backlog closure contract: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
