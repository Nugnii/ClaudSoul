#!/usr/bin/env bash
# test_adv2_bump_hyphen_key_misplaces_entry.sh
#
# Атака: ключ frontmatter с дефисом сразу после открытого блока `provenance_log`.
#
#   provenance_log:
#     - date: 2026-01-01
#       kind: reinforced
#   speaker-scope: universal      <- валидный YAML-ключ, но не по вкусу разбору
#   related: []
#   ---
#
# Выход из открытого блока (knowledge-counter-bump.sh:278-279) распознаёт следующее поле
# по `^[A-Za-z_][A-Za-z0-9_]*:` — дефис в класс не входит. Блок остаётся «открытым»,
# новая запись печатается только на СЛЕДУЮЩЕМ подходящем ключе, то есть уже ПОСЛЕ
# `speaker-scope: universal`:
#
#   speaker-scope: universal
#     - date: 2026-08-29
#       kind: reinforced
#
# Список оказывается вложен в скалярное значение чужого ключа. `yaml.safe_load` на таком
# frontmatter падает (ScannerError: mapping values are not allowed here) — знание молча
# выпадает из всего, что читает базу разбором YAML.
#
# Скрипт возвращает 0 и печатает ✅.
#
# Проверка без зависимостей: у вставленной записи вычисляется ключ-владелец; он обязан
# быть `provenance_log`. Разбор PyYAML — дополнительной проверкой, если модуль есть.

set -uo pipefail

BUMP="$(cd "$(dirname "$0")/.." && pwd)/knowledge-counter-bump.sh"
TMP="$(mktemp -d)"
LES="$TMP/lessons"; ST="$TMP/state"
mkdir -p "$LES" "$ST"

cat > "$LES/pattern-hyphen-key.md" <<'EOF'
---
type: pattern
confidence: 4
impact: 3
confirmed_count: 2
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
provenance_log:
  - date: 2026-01-01
    kind: reinforced
    reason: "прежний повод"
speaker-scope: universal
related: []
---

# Тело
EOF

OUT=$(env -u CLAUDE_STATE_DIR -u DIS_SESSION \
      STATE_DIR="$ST" LESSONS_DIR="$LES" \
      bash "$BUMP" pattern-hyphen-key confirmed "новый повод" 2>&1)
RC=$?

F="$LES/pattern-hyphen-key.md"
PASS=0; FAIL=0
say_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
say_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

# 1. Владелец вставленной записи.
OWNER=$(awk '
    /^---[[:space:]]*$/ { d++; if (d >= 2) exit; next }
    d == 1 {
        if ($0 ~ /^[^[:space:]#-]/ && $0 ~ /:/) { key = $0; sub(/:.*/, "", key); next }
        if ($0 ~ /^[[:space:]]+- date: /) { last = key }
    }
    END { print last }
' "$F")
if [ "$OWNER" = "provenance_log" ]; then
    say_pass "запись легла под provenance_log"
else
    say_fail "запись легла под ключ «${OWNER}», а не под provenance_log (rc=${RC}, вывод: ${OUT})"
fi

# 2. Разбор frontmatter.
if python3 -c 'import yaml' 2>/dev/null; then
    ERR=$(python3 - "$F" <<'PY'
import re, sys, yaml
t = open(sys.argv[1]).read()
m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
if not m:
    print("frontmatter не найден")
    sys.exit()
try:
    yaml.safe_load(m.group(1))
except Exception as e:
    print("%s: %s" % (type(e).__name__, " ".join(str(e).split())))
PY
)
    if [ -z "$ERR" ]; then
        say_pass "frontmatter разбирается yaml.safe_load"
    else
        say_fail "frontmatter не разбирается: ${ERR}"
    fi
fi

echo "--- frontmatter после вызова ---"
sed -n '1,22p' "$F"

echo "adv2 bump hyphen key: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
