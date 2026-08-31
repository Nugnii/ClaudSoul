#!/usr/bin/env bash
# test_adv2_bump_na_reason_backslash_journal.sh
#
# Атака: причина с обратной косой у исходов `not_applicable` / `applicable_not_followed`.
#
#   bash knowledge-counter-bump.sh <знание> not_applicable 'путь был указан как C:\'
#
# Ветка confirmed/contradicted снимает обратную косую (строка 190, с записанной ценой:
# «jq обрывает потоковый разбор на битой строке — уже стоило проекту 285 записей из
# 7665»). Ветка двух исходов без счётчика чистит СВОЕЙ строкой (строка 153) и снимает
# только двойную кавычку и перевод строки. Обратная косая и табуляция проходят насквозь
# и уезжают в JSON:
#
#   ...,"case":"путь был указан как C:\"}
#
# `\"` не закрывает строку — запись не разбирается. Скрипт печатает ✅ и возвращает 0.
#
# Цена не одной записи. `hooks/five-whys-gate.sh:113` читает этот журнал через `jq -s`,
# то есть слурпит ФАЙЛ ЦЕЛИКОМ: одна битая строка роняет jq, а `|| printf '0'` превращает
# падение в «повторов ноль». Страж повторного подтверждения слепнет молча и навсегда —
# пока журнал не починят руками.
#
# Тест: каждая строка disagreement-outcomes.jsonl обязана быть разбираемой, и `jq -s`
# по файлу обязан отработать.

set -uo pipefail

BUMP="$(cd "$(dirname "$0")/.." && pwd)/knowledge-counter-bump.sh"
TMP="$(mktemp -d)"
LES="$TMP/lessons"; ST="$TMP/state"
mkdir -p "$LES" "$ST"

cat > "$LES/pattern-json-na.md" <<'EOF'
---
type: pattern
confidence: 5
impact: 4
confirmed_count: 6
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
blocker: true
provenance_log: []
---

# Тело
EOF

REASON='путь был указан как C:\'

for ACT in not_applicable applicable_not_followed; do
    env -u CLAUDE_STATE_DIR -u DIS_SESSION \
        STATE_DIR="$ST" LESSONS_DIR="$LES" \
        bash "$BUMP" pattern-json-na "$ACT" "$REASON" >/dev/null 2>&1
done

JRN="$ST/disagreement-outcomes.jsonl"
PASS=0; FAIL=0
say_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
say_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

if [ ! -s "$JRN" ]; then
    echo "FAIL: журнал $JRN не создан — атака не воспроизведена по другой причине"
    echo "adv2 bump not_applicable json: 0/1 passed"
    exit 1
fi

# 1. Построчная разбираемость.
BROKEN=$(python3 - "$JRN" <<'PY'
import json, sys
bad = []
for i, line in enumerate(open(sys.argv[1], encoding="utf-8", errors="replace"), 1):
    line = line.strip()
    if not line:
        continue
    try:
        json.loads(line)
    except Exception as e:
        bad.append("строка %d: %s" % (i, e))
print("; ".join(bad))
PY
)
if [ -z "$BROKEN" ]; then
    say_pass "все строки журнала разбираются как JSON"
else
    say_fail "битые строки журнала: ${BROKEN}"
    echo "     содержимое:"
    sed -n '1,4p' "$JRN" | sed 's/^/       /'
fi

# 2. Чтение так, как его делает five-whys-gate.sh:113 (jq -s по всему файлу).
if command -v jq >/dev/null 2>&1; then
    JQ_ERR=$(jq -s 'length' "$JRN" 2>&1 >/dev/null)
    JQ_RC=$?
    if [ "$JQ_RC" -eq 0 ]; then
        say_pass "jq -s по журналу отрабатывает (страж повторов видит записи)"
    else
        say_fail "jq -s по журналу падает: ${JQ_ERR} — five-whys-gate получит 0 повторов при любом их числе"
    fi
else
    say_pass "jq отсутствует — проверка стража пропущена"
fi

echo "adv2 bump not_applicable json: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
