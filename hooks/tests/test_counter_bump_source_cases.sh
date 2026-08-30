#!/usr/bin/env bash
# test_counter_bump_source_cases.sh — обратная сторона ссылки пишется писателем, а не рукой.
#
# Результат: подтверждение знания кейсом кладёт имя кейса в source_cases родителя.
# Проверка результата: bash hooks/tests/test_counter_bump_source_cases.sh даёт 0
#
# Зачем. Ребро кейс → паттерн живёт в двух файлах: `edges` кейса и `source_cases`
# родителя. Обход графа идёт сверху вниз, поэтому кейс без обратной записи для обхода
# не существует. До 28 августа 2026 вторую сторону писала рука: knowledge-counter-bump
# заполнял provenance_log и source_cases не трогал вовсе. Цена измерена дважды — 23
# односторонние ссылки за три месяца (D12, v1.14.5) и ещё 2 в тот же день, когда
# требование дописали в knowledge/META.md, а писателя не тронули.
#
# Проверка симметрии (mcp-server/tests/test_knowledge_link_symmetry.py) стоит ПОСЛЕ
# записи; этот тест держит место, ГДЕ требование выполняется.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$HOOKS_DIR/knowledge-counter-bump.sh"
[ -f "$BUMP" ] || { echo "FAIL: $BUMP не найден"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Каталог состояния — свой. Без изоляции `dis_close_outcome` пишет исходы по тестовым
# именам знаний в НАСТОЯЩИЙ `disagreement-outcomes.jsonl`, и метрики контура несогласия
# начинают считать выдумку: первый прогон этого теста добавил туда 48 записей.
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

# Здесь-строка, а не труба: под `set -o pipefail` `grep -q` выходит на первом совпадении,
# `printf` получает SIGPIPE, и статус конвейера становится провалом — утверждение соврало бы
# под нагрузкой. Ловится стражем hooks/tests/test_assert_no_sigpipe.sh.
assert_contains() {
    if grep -Fq -- "$1" <<< "$2"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$1' в:"; sed 's/^/    /' <<< "$2"; fi
}
assert_absent() {
    if grep -Fq -- "$1" <<< "$2"; then
        FAIL=$((FAIL+1)); echo "FAIL [$3]: неожиданно найдено '$1'"
    else PASS=$((PASS+1)); fi
}

# mk <файл> <тело-source_cases>  — паттерн с заданным состоянием поля.
mk() {
    cat > "$1" <<PAT
---
type: pattern
confidence: 3
impact: 4
confirmed_count: 2
contradicted_count: 0
last_confirmed: 2026-01-01
$2
status: active
---

# Тело
PAT
}

CASE="case-2026-08-28-probe.md"

# --- T1: поле — открытый блок со списком ---
mk "$TMP/pattern-block.md" "source_cases:
  - case-2026-01-01-old.md"
bash "$BUMP" "$TMP/pattern-block.md" confirmed "повод" "$CASE" >/dev/null 2>&1
OUT=$(cat "$TMP/pattern-block.md")
assert_contains "  - $CASE" "$OUT" "T1: дописан в блочный список"
assert_contains "  - case-2026-01-01-old.md" "$OUT" "T1b: прежний элемент цел"
assert_contains "confirmed_count: 3" "$OUT" "T1c: счётчик по-прежнему растёт"

# --- T2: поле пустое (`[]`) ---
mk "$TMP/pattern-empty.md" "source_cases: []"
bash "$BUMP" "$TMP/pattern-empty.md" confirmed "повод" "$CASE" >/dev/null 2>&1
OUT=$(cat "$TMP/pattern-empty.md")
assert_contains "source_cases:" "$OUT" "T2: пустой список раскрыт"
assert_contains "  - $CASE" "$OUT" "T2b: кейс записан"
assert_absent "source_cases: []" "$OUT" "T2c: пустая форма не осталась"

# --- T3: поля нет вовсе ---
mk "$TMP/pattern-absent.md" "domain: [testing]"
bash "$BUMP" "$TMP/pattern-absent.md" confirmed "повод" "$CASE" >/dev/null 2>&1
OUT=$(cat "$TMP/pattern-absent.md")
assert_contains "source_cases:" "$OUT" "T3: поле заведено"
assert_contains "  - $CASE" "$OUT" "T3b: кейс записан"
assert_contains "provenance_log:" "$OUT" "T3c: провенанс не потерян соседством"

# --- T4: повторный вызов не дублирует ---
bash "$BUMP" "$TMP/pattern-block.md" confirmed "повод" "$CASE" >/dev/null 2>&1
N=$(grep -Fc "  - $CASE" "$TMP/pattern-block.md")
if [ "$N" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T4]: кейс записан $N раз"; fi

# --- T5: КОНТРПРИМЕР — contradicted обосновывает не паттерн, а сомнение в нём ---
mk "$TMP/pattern-contra.md" "source_cases: []"
bash "$BUMP" "$TMP/pattern-contra.md" contradicted "разошлось" "$CASE" >/dev/null 2>&1
# Смотрим только на поле, а не на весь файл: в provenance_log имя кейса попадает и при
# опровержении (`trigger_case:`) — и это верно, там записано, ЧТО разошлось.
OUT=$(cat "$TMP/pattern-contra.md")
assert_contains "source_cases: []" "$OUT" "T5: contradicted не кладёт кейс в source_cases"
assert_contains "trigger_case: $CASE" "$OUT" "T5c: но провенанс повод запоминает"
assert_contains "contradicted_count: 1" "$OUT" "T5b: счётчик опровержений вырос"

# --- T6: КОНТРПРИМЕР — без файла кейса писать нечего ---
mk "$TMP/pattern-nocase.md" "source_cases: []"
bash "$BUMP" "$TMP/pattern-nocase.md" confirmed "повод" >/dev/null 2>&1
assert_contains "source_cases: []" "$(cat "$TMP/pattern-nocase.md")" "T6: без кейса поле не тронуто"

# --- T7: КОНТРПРИМЕР — у кейса поля source_cases нет по построению ---
mk "$TMP/case-2026-08-28-target.md" "source_cases: []"
bash "$BUMP" "$TMP/case-2026-08-28-target.md" confirmed "повод" "$CASE" >/dev/null 2>&1
assert_absent "  - $CASE" "$(cat "$TMP/case-2026-08-28-target.md")" "T7: кейс-родителем не становится"

# --- T8: суффикс .md проставляется — проверка симметрии ищет имя файла ---
mk "$TMP/pattern-suffix.md" "source_cases: []"
bash "$BUMP" "$TMP/pattern-suffix.md" confirmed "повод" "case-2026-08-28-probe" >/dev/null 2>&1
assert_contains "  - case-2026-08-28-probe.md" "$(cat "$TMP/pattern-suffix.md")" "T8: имя нормализовано с .md"

# --- T9: изоляция каталога состояния РАБОТАЕТ, а не объявлена ---
# Дефект, ради которого проверка заведена: функция закрытия исхода читала только
# `CLAUDE_STATE_DIR`, тогда как общесистемное имя — `STATE_DIR` (`paths-lib.sh:61`).
# Изоляция через `STATE_DIR` молча не работала, и прогон этого теста добавил 57 записей
# о выдуманных знаниях в боевой `disagreement-outcomes.jsonl`. Утверждение об изоляции
# нельзя проверить чтением кода — только записью и взглядом на ОБА каталога.
REAL="$HOME/.claude/hooks/state/disagreement-outcomes.jsonl"
BEFORE=$(grep -c '' "$REAL" 2>/dev/null || echo 0)
mk "$TMP/pattern-isolation.md" "source_cases: []"
bash "$BUMP" "$TMP/pattern-isolation.md" confirmed "проба изоляции" "$CASE" >/dev/null 2>&1
AFTER=$(grep -c '' "$REAL" 2>/dev/null || echo 0)
if [ "$BEFORE" = "$AFTER" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9]: боевой журнал вырос с $BEFORE до $AFTER — изоляция не работает"; fi
if [ -s "$STATE_DIR/disagreement-outcomes.jsonl" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9b]: запись не попала и в тестовый журнал — проверка ничего не доказывает"; fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
