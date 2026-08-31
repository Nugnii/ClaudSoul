#!/usr/bin/env bash
# test_domain_graph_lib.sh — характеризующий тест domain-graph-lib.sh.
# Либа вынесена из knowledge-activator (Ф4), прямого теста не имела — скоринг по
# графу доменов проверялся лишь косвенно через хук. Фиксирует: веса раскрытия
# (30 self / 20 parent-child / 10 overlap-applies / 5 analogous), выбор максимума,
# нормализацию hyphen/underscore, alias-матч.
# Изоляция: DOMAINS_DIR — временный каталог с синтетическим графом; lib через DG_LIB env.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DG_LIB="${DG_LIB:-$HOOKS_DIR/domain-graph-lib.sh}"

[ -f "$DG_LIB" ] || { echo "FAIL: $DG_LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$DG_LIB"

PASS=0
FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}

# --- domain_graph_score: чистая функция (без DOMAINS_DIR) ---
SET=$'alpha 30\nbeta 20\ngamma 10'
assert_eq "$(domain_graph_score alpha "$SET")" "30" "T1: self вес 30"
assert_eq "$(domain_graph_score beta  "$SET")" "20" "T2: parent/child вес 20"
assert_eq "$(domain_graph_score gamma "$SET")" "10" "T3: overlap вес 10"
assert_eq "$(domain_graph_score missing "$SET")" "0" "T4: нет в наборе → 0"
# максимум при дубле домена с разными весами
assert_eq "$(domain_graph_score x $'x 5\nx 30\nx 10')" "30" "T5: выбирает максимальный вес"
# нормализация hyphen/underscore в обе стороны
assert_eq "$(domain_graph_score cognitive_science 'cognitive-science 10')" "10" "T6: query underscore ~ set hyphen"
assert_eq "$(domain_graph_score cognitive-science 'cognitive_science 20')" "20" "T7: query hyphen ~ set underscore"

# --- expand_domains_from_context: на синтетическом графе ---
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export DOMAINS_DIR="$TMP"

mk_domain() { # $1=file basename, $2=name, $3=aliases-csv, $4=children, $5=overlaps, $6=analogous
    cat > "$DOMAINS_DIR/$1.md" <<EOF
---
name: $2
aliases: [$3]
depth: 1
---

parent: []
children: [$4]
overlaps: [$5]
applies_to: []
analogous: [$6]

Тестовый домен $2.
EOF
}
# aliases: только ASCII-слова длиной ≥2 матчатся регексом [a-z_]{2,} в либе
# (цифры/одиночные буквы/кириллица исключены — характеризуем это валидным алиасом).
mk_domain alpha alpha "aone, atwo" "beta" "gamma" "delta"
mk_domain beta  beta  "" "" "" ""
mk_domain gamma gamma "" "" "" ""
mk_domain delta delta "" "" "" ""

EXP=$(expand_domains_from_context "alpha")
assert_eq "$(domain_graph_score alpha "$EXP")" "30" "T8: matched домен self=30"
assert_eq "$(domain_graph_score beta  "$EXP")" "20" "T9: child=20"
assert_eq "$(domain_graph_score gamma "$EXP")" "10" "T10: overlap=10"
assert_eq "$(domain_graph_score delta "$EXP")" "5"  "T11: analogous=5"

# alias-матч: ключевое слово aone → домен alpha (self 30)
EXP2=$(expand_domains_from_context "aone")
assert_eq "$(domain_graph_score alpha "$EXP2")" "30" "T12: alias-матч находит домен"

# нет совпадений → пустой результат, без ошибки
EXP3=$(expand_domains_from_context "zzznomatch")
assert_eq "$(domain_graph_score alpha "$EXP3")" "0" "T13: нет матча → пусто"

echo ""
echo "domain-graph-lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
