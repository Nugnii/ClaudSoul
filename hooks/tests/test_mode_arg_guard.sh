#!/usr/bin/env bash
# test_mode_arg_guard.sh — неизвестный режим не означает разрушительное умолчание.
#
# Повод (1 сентября 2026). `bash scripts/backlog-archive.sh --check` ПЕРЕНЁС пункты в архив:
# режим там называется `check` без дефисов, а `MODE="${1:-run}"` не различал «не указан» и
# «указан неверно». Просьба проверить изменила файл. Разнобой имён делал ошибку вероятной:
# `check` у архиватора и measurement-due, `--check` у пересчётчика показаний и сверки чисел.
# Замер на фикстуре до починки: из пяти написаний (`check`, `--check`, `--bogus`, пусто,
# `run`) перенос выполняли ЧЕТЫРЕ.
#
# Проверяется ВЕСЬ класс, а не место находки: реестр носителей — четыре скрипта с режимом.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

CARRIERS="backlog-archive.sh backlog-refresh-readings.sh docs-refresh-claims.sh measurement-due.sh"

# Файл существует, иначе код 2 означал бы «нет BACKLOG», а не «неизвестный режим»: первая
# редакция этого теста мерила код возврата и утверждала про режим — предмет замера не
# совпадал с предметом утверждения (`pattern-subject-of-measurement-mismatch`).
cat > "$TMP/empty.md" <<'BLE'
# BACKLOG

- ◐ **D999** Открытый пункт без показания.
BLE

# 1. Неизвестный режим отбивается кодом 2 — у каждого носителя.
for s in $CARRIERS; do
    BACKLOG_FILE="$TMP/empty.md" bash "$REPO/scripts/$s" --bogus-mode >/dev/null 2>&1
    [ $? -eq 2 ] && ok || bad "unknown:$s" "неизвестный режим не отбит кодом 2"
done

# 2. Оба написания режима проверки приняты — иначе разнобой имён вернётся.
# Реестр сверщика чисел сужается до трёх строк: предмет этой ноги — РАЗБОР АРГУМЕНТА
# («режим опознан, код не 2»), а не работа скрипта. На полном реестре `docs-refresh-claims.sh`
# перебирает ~100 ключей, часть которых сама запускает прогоны, и один вызов стоил 33 с —
# два вызова давали 67 с из 102 с всего теста, худшего в наборе (замер 11 сентября 2026 по
# поправке владельца «102 с слишком дорогой тест»). С узкой фикстурой — 31 мс.
head -3 "$REPO/scripts/doc-claims.tsv" > "$TMP/narrow-claims.tsv" 2>/dev/null
for s in $CARRIERS; do
    for m in check --check; do
        DOC_CLAIMS_FILE="$TMP/narrow-claims.tsv" \
        BACKLOG_FILE="$TMP/empty.md" bash "$REPO/scripts/$s" "$m" >/dev/null 2>&1
        [ $? -eq 2 ] && bad "accept:$s:$m" "написание «${m}» отбито как неизвестное" || ok
    done
done

# 3. КОНТРПРИМЕР: пустой аргумент — законное умолчание, оно ДОЛЖНО работать как run.
# Проверяем на архиваторе с изолированной фикстурой: закрытый пункт переносится.
cat > "$TMP/BACKLOG.md" <<'BL'
# BACKLOG

- ☑ **D900** Закрытый пункт с исправной проверкой.
  **Результат.** Ничего.
  **Проверка.** `true` → 0

- ◐ **D901** Открытый пункт.
BL
: > "$TMP/arch.md"
BACKLOG_FILE="$TMP/BACKLOG.md" BACKLOG_ARCHIVE="$TMP/arch.md" \
    bash "$REPO/scripts/backlog-archive.sh" >/dev/null 2>&1
grep -q 'D900' "$TMP/arch.md" && ok || bad "default" "умолчание перестало переносить — страж съел законный run"
grep -q 'D901' "$TMP/BACKLOG.md" && ok || bad "default-open" "открытый пункт унесён вместе с закрытым"

# 4. Режим проверки НЕ меняет файл — то, ради чего его и зовут.
cp "$TMP/BACKLOG.md" "$TMP/work.md"; : > "$TMP/arch2.md"
_before=$(cksum < "$TMP/work.md")
BACKLOG_FILE="$TMP/work.md" BACKLOG_ARCHIVE="$TMP/arch2.md" \
    bash "$REPO/scripts/backlog-archive.sh" --check >/dev/null 2>&1
_after=$(cksum < "$TMP/work.md")
[ "$_before" = "$_after" ] && ok || bad "check-writes" "«--check» изменил файл — ровно исходный дефект"

echo "mode arg guard: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
