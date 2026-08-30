#!/usr/bin/env bash
# test_usage_outcome_audit.sh — внешний замер обязан краснеть на протухшем входе и
# обязан печатать два окна раздельно.
#
# Повод. Сам отчёт Claude Code Insights в шапке пишет одно окно («117 сессий, 18.06 →
# 20.08»), а качественные числа считает по другому (50 сессий, 8–20 августа). Читатель
# соединяет их в одно и получает картину впятеро мягче реальной. Замер, повторяющий эту
# склейку, был бы хуже отсутствия замера: он придавал бы ошибке вид измерения.
#
# Поэтому проверяется не «работает ли скрипт», а именно те три вещи, на которых он может
# соврать молча: смешать окна, промолчать о протухших данных, промолчать о дырявом
# покрытии. Плюс отказ на пустом входе — отличать «находок нет» от «не измеряли».

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/usage-outcome-audit.py"
[ -f "$SCRIPT" ] || { echo "FAIL: не найден $SCRIPT"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

# Песочница: своя копия структуры отчёта, реальный ~/.claude/usage-data не трогается.
mk_data() {           # mk_data <dir> <старых_сессий> <размеченных>
    local d="$1" old="$2" lab="$3" i sid
    rm -rf "$d"; mkdir -p "$d/facets" "$d/session-meta"
    for ((i=0; i<old; i++)); do
        sid=$(printf 'old-%04d' "$i")
        cat > "$d/session-meta/$sid.json" <<J
{"session_id":"$sid","project_path":"/x/Старый","start_time":"2026-06-2${i:0:1}T10:00:00.000Z","user_message_count":3}
J
    done
    for ((i=0; i<lab; i++)); do
        sid=$(printf 'new-%04d' "$i")
        cat > "$d/session-meta/$sid.json" <<J
{"session_id":"$sid","project_path":"/x/Свежий","start_time":"2026-08-1${i:0:1}T10:00:00.000Z","user_message_count":3}
J
        cat > "$d/facets/$sid.json" <<J
{"session_id":"$sid","outcome":"mostly_achieved","friction_counts":{"wrong_approach":3},
 "user_satisfaction_counts":{"likely_satisfied":2}}
J
    done
}

run() { USAGE_DATA_DIR="$1" python3 "$SCRIPT" 2>&1; }

# --- 1. Пустой вход — это отказ (2), а не «находок нет» (0).
mkdir -p "$TMP/empty"
out=$(USAGE_DATA_DIR="$TMP/empty" python3 "$SCRIPT" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "пустой вход → код 2 (не смог отработать)" \
                || bad "пустой вход дал код $rc, ожидался 2"

# --- 2. Два окна печатаются раздельно и не совпадают.
mk_data "$TMP/d" 8 4
out=$(run "$TMP/d")
if grep -q "2026-06" <<<"$out" && grep -q "2026-08-1" <<<"$out"; then
    ok "оба окна названы: техническое (июнь) и окно разметки (август)"
else
    bad "окна не разделены — в выводе нет обеих дат"; printf '%s\n' "$out" | head -6
fi
grep -q "ТОЛЬКО ко второму окну" <<<"$out" \
    && ok "сказано явно, к какому окну относятся выводы" \
    || bad "нет оговорки про окно выводов"

# --- 3. Дырявое покрытие — находка (4 из 12 = 33%).
rc=0; USAGE_DATA_DIR="$TMP/d" python3 "$SCRIPT" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "покрытие 33% → находка (код 1)" \
                || bad "покрытие 33% дало код $rc, ожидался 1"
grep -q "меньшая часть сессий" <<<"$out" \
    && ok "находка про покрытие названа словами" \
    || bad "код 1 есть, объяснения нет"

# --- 4. Полное покрытие, свежие данные, трений нет — молчит (код 0).
# Именно «трений нет»: любая ненулевая разметка на такой выборке даёт перекос в один
# из классов, и код 0 стал бы недостижим. Чистый случай должен быть чистым по существу.
mk_data "$TMP/full" 0 6
for f in "$TMP/full"/facets/*.json; do
    python3 - "$f" <<'''J'''
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["friction_counts"]={}
json.dump(d,open(p,"w"))
J
done
rc=0; USAGE_DATA_DIR="$TMP/full" python3 "$SCRIPT" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "полное свежее покрытие → код 0" \
                || bad "чистый случай дал код $rc, ожидался 0"

# --- 5. Протухшие данные — находка, даже когда покрытие полное.
mk_data "$TMP/stale" 0 6
find "$TMP/stale" -type f -exec touch -t 202601010000 {} +
out=$(run "$TMP/stale"); rc=0
USAGE_DATA_DIR="$TMP/stale" python3 "$SCRIPT" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "данные старше порога → находка (код 1)" \
                || bad "протухшие данные дали код $rc, ожидался 1"
grep -q "старше" <<<"$out" \
    && ok "возраст данных назван" \
    || bad "про возраст ничего не сказано"

# --- 6. Перекос вход/выход называется, и называется правильной стороной.
mk_data "$TMP/skew" 0 6
# session_id берётся из ИМЕНИ файла: одинаковый id во всех записях схлопнул бы шесть
# сессий в одну и обнулил бы саму проверку — так первая версия этого теста и падала.
for f in "$TMP/skew"/facets/*.json; do
    sid=$(basename "$f" .json)
    cat > "$f" <<J
{"session_id":"$sid","outcome":"mostly_achieved","friction_counts":{"buggy_code":4},
 "user_satisfaction_counts":{"likely_satisfied":1}}
J
done
out=$(run "$TMP/skew")
if grep -q "трение на выходе" <<<"$out"; then
    ok "перекос в сторону выхода назван выходом"
elif grep -q "трение на входе" <<<"$out"; then
    bad "перекос по buggy_code назван входом — классы перепутаны"
else
    bad "двукратный перекос не назван вовсе"
fi

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
