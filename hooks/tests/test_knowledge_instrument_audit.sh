#!/usr/bin/env bash
# test_knowledge_instrument_audit.sh — замер «знание → инструмент» обязан различать уровни.
#
# Повод. Собеседник спросил, становятся ли знания действенным инструментом или копятся.
# Замер дал 1,4% (4 записи из 280) — но случился только потому, что спросили. Отсюда
# сам скрипт, строка в реестре замеров со сроком 7 дней и этот тест.
#
# Три уровня меряются раздельно намеренно: «хранится», «доходит до контекста», «действует
# перед действием». Смешать их — значит завысить: инжект это подсказка, а инструментом
# делает только гейт. Тест проверяет, что уровни не путаются, и что очередь на производство
# не предлагает повторно то, что уже разобрано и признано невыразимым.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"
mkdir -p "$L" "$S"

mk() { # $1=имя $2=тело frontmatter
    printf -- '---\nname: %s\n%s---\nтело\n' "$1" "$2" > "$L/$1.md"
}

# действует: блокер с рабочими сигналами
mk "pattern-acting" 'outcome: error
confirmed_count: 9
status: active
blocker: true
detection_signals: |
  [{"name":"s","all_of":[{"tool_matches":["Edit"]}]}]
'
# объявлен инструментом, но сигналов нет — это НЕ «действует»
mk "pattern-hollow" 'outcome: error
confirmed_count: 7
status: active
blocker: true
'
# кандидат в очередь: ошибка, подтверждений много, гейтом не стал
mk "pattern-candidate" 'outcome: error
confirmed_count: 8
status: active
'
# уже оценён — в очередь попадать не должен
mk "pattern-assessed" 'outcome: error
confirmed_count: 8
status: active
instrument_verdict: inexpressible   # проверено разбором
instrument_assessed: 2026-07-29
'
# успех и мало подтверждений — не кандидат
mk "pattern-success" 'outcome: success
confirmed_count: 9
status: active
'
mk "pattern-weak" 'outcome: error
confirmed_count: 2
status: active
'
# кейс: в очередь не берётся вообще (очередь только для паттернов и принципов)
mk "case-something" 'outcome: error
confirmed_count: 9
status: active
'
# лог инжектов: два знания доходили до контекста
printf '{"date":"%s","file":"pattern-acting.md"}\n{"date":"%s","file":"pattern-weak.md"}\n' \
    "$(date -u +%Y-%m-%d)" "$(date -u +%Y-%m-%d)" > "$S/injection-log.jsonl"

OUT_MD="$TMP/report.md"
RES=$(LESSONS_DIR="$L" STATE_DIR="$S" KIA_OUTPUT="$OUT_MD" bash "$SCRIPT" 2>&1)
REP=$(cat "$OUT_MD" 2>/dev/null || echo "")

has() { grep -qF -- "$1" <<< "$2"; }
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- уровни считаются раздельно ---
has "хранится 7" "$RES" && ok || bad "T1" "неверное число хранимых: $RES"
has "доходит 2"  "$RES" && ok || bad "T2" "неверное число доходивших до контекста"
has "действует 1" "$RES" && ok || bad "T3" "«действует» посчитано неверно — пустой блокер не должен считаться"

# --- пустой блокер назван отдельно, а не молча пропущен ---
has "pattern-hollow" "$REP" && ok || bad "T4" "блокер без сигналов не назван в отчёте"
has "Объявлены инструментом, но не работают" "$REP" && ok || bad "T5" "нет раздела про сломанные"

# --- очередь: кандидат внутри, оценённый и посторонние снаружи ---
has "pattern-candidate" "$REP" && ok || bad "T6" "кандидат не попал в очередь"
_slice=$(printf '%s' "$REP" | grep -A100 'Очередь на производство' | grep -B100 'Оценены')
if grep -qF 'pattern-assessed' <<< "$_slice"; then
    bad "T7" "оценённое знание предложено повторно"
else ok; fi
has "pattern-success" "$REP" && bad "T8" "успех попал в очередь" || ok
has "pattern-weak"    "$REP" && bad "T9" "знание ниже порога попало в очередь" || ok
has "case-something"  "$REP" && bad "T10" "кейс попал в очередь (очередь только для паттернов и принципов)" || ok

# --- оценённое показано отдельным разделом с вердиктом ---
has "Оценены: инструментом не станут" "$REP" && ok || bad "T11" "нет раздела с оценёнными"
has "inexpressible" "$REP" && ok || bad "T12" "вердикт не показан"

# --- отрицательный контроль: убрать вердикт → знание обязано вернуться в очередь ---
# Без этого случая раздел «оценены» мог бы просто прятать знания, а не помнить решение.
python3 - "$L/pattern-assessed.md" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(re.sub(r'^instrument_verdict:.*\n', '', p.read_text(), flags=re.M))
PY
LESSONS_DIR="$L" STATE_DIR="$S" KIA_OUTPUT="$OUT_MD" bash "$SCRIPT" >/dev/null 2>&1
_slice=$(grep -A100 'Очередь на производство' "$OUT_MD" | grep -B100 'Чего этот замер')
if grep -qF 'pattern-assessed' <<< "$_slice"; then
    ok
else bad "T13 отрицательный контроль" "без вердикта знание не вернулось в очередь — раздел прячет, а не помнит"; fi

echo ""
echo "knowledge instrument audit tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
