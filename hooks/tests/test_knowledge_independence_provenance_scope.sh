#!/usr/bin/env bash
# test_knowledge_independence_provenance_scope.sh — провенанс считается по СВОЕМУ полю.
#
# Результат: scripts/knowledge-independence.py считает записи повода только внутри
#            `provenance_log`, а записи `modification_history` в след повода не попадают
# Проверка результата: этот тест
#
# Повод (род A реестра дефектов, волна 6 сентября 2026). Шаблон
# `^\s+-\s+date:` привязан к началу строки и родителя не видит: `- date:` живёт и в
# `provenance_log`, и в `modification_history`. Замер на живой базе того дня: шаблон
# насчитал 143 записи повода при 125 настоящих — 18 дат заняты у перекроек правила, доля
# прослеживаемых показана 58% вместо 51%. Ошибка БЛАГОПРИЯТНАЯ: прибор, созданный ловить
# самоподтверждение, сам занижал находку.
#
# Фикстура — три класса:
#   mixed  — провенанс 2 записи, перекроек 2: до починки 4, после 2 (голос теста);
#   clean  — только провенанс: число до и после ОДНО и то же (отрицательный контроль,
#            иначе тест зеленеет и от мутанта «считать всегда ноль»);
#   onesess— провенанс одной сессии, перекройка другой: до починки знание не попадало в
#            список «все подтверждения из ОДНОЙ сессии», после — попадает.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: нет PyYAML"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/knowledge-independence.py"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }

PASS=0; FAIL=0
assert_contains() {
    if grep -Fq "$2" <<< "$1"; then PASS=$((PASS + 1)); echo "  ok   $3"
    else FAIL=$((FAIL + 1)); echo "  FAIL $3"; echo "       ждали: $2"; echo "       было : $(head -6 <<< "$1")"; fi
}
assert_eq() {
    if [ "$1" = "$2" ]; then PASS=$((PASS + 1)); echo "  ok   $3"
    else FAIL=$((FAIL + 1)); echo "  FAIL $3 — ждали «$1», было «$2»"; fi
}

FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT

cat > "$FX/pattern-mixed.md" <<'EOF'
---
confidence: 5
confirmed_count: 4
provenance_log:
  - date: 2026-01-01
    session: s-alpha
  - date: 2026-01-02
    session: s-beta
modification_history:
  - date: 2026-02-01
    kind: narrowed
  - date: 2026-02-02
    kind: branched
status: active
---
тело
EOF

cat > "$FX/pattern-clean.md" <<'EOF'
---
confidence: 5
confirmed_count: 2
provenance_log:
  - date: 2026-03-01
    session: s-gamma
  - date: 2026-03-02
    session: s-delta
status: active
---
тело
EOF

cat > "$FX/pattern-onesess.md" <<'EOF'
---
confidence: 5
confirmed_count: 1
provenance_log:
  - date: 2026-04-01
    session: s-only
modification_history:
  - date: 2026-04-09
    session: s-other
    kind: narrowed
status: active
---
тело
EOF

OUT=$(LESSONS_DIR="$FX" python3 "$TOOL" 2>&1); RC=$?

echo "T1-T3 · счёт повода берётся из provenance_log"
# заявлено 4+2+1 = 7; повода записано 2+2+1 = 5 (а не 7+2 = 9, как считал шаблон)
assert_contains "$OUT" "подтверждений заявлено   : 7" "T1: заявленный счёт не тронут"
assert_contains "$OUT" "записано в provenance_log: 5 (71%)" "T2: перекройки в след повода не попали"
assert_contains "$OUT" "различимых дней за ними  : 5" "T3: дни считаются по тем же записям"

echo "T4 · отрицательный контроль: у чистого знания число не изменилось"
# строка отчёта: имя, conf, заявлено, записано, дней
assert_contains "$OUT" "pattern-clean" "T4a: чистое знание в отчёте"
CLEAN=$(grep -E '^\s+pattern-clean' <<< "$OUT" | awk '{print $3" "$4}')
assert_eq "2 2" "$CLEAN" "T4b: заявлено 2, записано 2 — мутант «всегда ноль» здесь краснеет"

echo "T5 · сессии берутся из того же поля"
assert_contains "$OUT" "из ОДНОЙ сессии: 1" "T5a: ровно одно знание опознано односессионным"
assert_contains "$OUT" "· pattern-onesess" "T5b: именно то, где вторая сессия — у перекройки, а не у повода"

echo "T6 · код возврата — вердикт замера"
assert_eq "0" "$RC" "T6: 71% ≥ порога 70 — зелёный"

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
