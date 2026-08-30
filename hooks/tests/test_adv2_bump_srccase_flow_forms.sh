#!/usr/bin/env bash
# test_adv2_bump_srccase_flow_forms.sh
#
# Атака: две валидные формы поточного списка `source_cases`, которых нет в разборе.
#
#   форма A — перенос строки внутри списка:
#       source_cases: [case-old-one.md,
#         case-old-two.md]
#   форма B — комментарий после закрывающей скобки:
#       source_cases: [case-old-one.md, case-old-two.md]  # два повода
#
# Ветка непустого поточного списка (knowledge-counter-bump.sh:291) требует, чтобы строка
# ЗАКАНЧИВАЛАСЬ на `]`. Обе формы это условие не выполняют, ни одна другая ветка их тоже
# не узнаёт — состояние поля остаётся `absent`, и на выходе из frontmatter печатается
# ВТОРОЙ ключ `source_cases` (строки 266-269).
#
# Последствие названо в самом скрипте, строки 286-290: «YAML при этом валиден,
# `safe_load` берёт последний — прежние кейсы исчезли бы из графа молча». Именно это и
# происходит; ветка заведена против одной формы из трёх.
#
# Скрипт при этом печатает ✅ и возвращает 0.
#
# Проверка дешёвая и без зависимостей: во frontmatter обязан быть ровно ОДИН ключ
# `source_cases`. Если есть PyYAML — дополнительно сверяется, что прежние кейсы уцелели.

set -uo pipefail

BUMP="$(cd "$(dirname "$0")/.." && pwd)/knowledge-counter-bump.sh"
TMP="$(mktemp -d)"
LES="$TMP/lessons"; ST="$TMP/state"
mkdir -p "$LES" "$ST"

cat > "$LES/pattern-flow-wrapped.md" <<'EOF'
---
type: pattern
confidence: 4
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
source_cases: [case-old-one.md,
  case-old-two.md]
provenance_log: []
---

# Тело
EOF

cat > "$LES/pattern-flow-comment.md" <<'EOF'
---
type: pattern
confidence: 4
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
source_cases: [case-old-one.md, case-old-two.md]  # два повода
provenance_log: []
---

# Тело
EOF

PASS=0; FAIL=0
say_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
say_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

check_one() {
    kn="$1"; label="$2"
    out=$(env -u CLAUDE_STATE_DIR -u DIS_SESSION \
          STATE_DIR="$ST" LESSONS_DIR="$LES" \
          bash "$BUMP" "$kn" confirmed "повод" case-new.md 2>&1)
    rc=$?
    f="$LES/${kn}.md"
    keys=$(awk '/^---[[:space:]]*$/ {d++; if (d >= 2) exit; next} d == 1 && /^source_cases:/ {n++} END {print n + 0}' "$f")
    if [ "$keys" -eq 1 ]; then
        say_pass "${label}: во frontmatter один ключ source_cases"
    else
        say_fail "${label}: ключей source_cases во frontmatter — ${keys} (rc=${rc}, вывод: ${out})"
    fi

    if python3 -c 'import yaml' 2>/dev/null; then
        got=$(python3 - "$f" <<'PY'
import re, sys, yaml
t = open(sys.argv[1]).read()
m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
d = yaml.safe_load(m.group(1)) if m else {}
print(",".join(d.get("source_cases") or []))
PY
)
        miss=""
        grep -q 'case-old-one.md' <<< "$got" || miss="${miss} case-old-one.md"
        grep -q 'case-old-two.md' <<< "$got" || miss="${miss} case-old-two.md"
        grep -q 'case-new.md'     <<< "$got" || miss="${miss} case-new.md"
        if [ -z "$miss" ]; then
            say_pass "${label}: safe_load видит все кейсы"
        else
            say_fail "${label}: safe_load вернул source_cases = [${got}], потеряно:${miss}"
        fi
    fi
}

# Форма A (список НЕ закрыт в строке) закрывается ОТКАЗОМ, а не правкой, и это решение.
# Довод: построчной правкой многострочный поточный список не читается — `]` может лежать
# внутри кавычек, и «умный» разбор ошибётся молча, потеряв прежние кейсы (ровно тот вред,
# ради которого эта атака и написана). Отказ происходит ДО любой записи: ни счётчик, ни
# провенанс, ни журнал не тронуты, и сообщение называет починку. Проверяем именно это.
BEFORE_A=$(cat "$LES/pattern-flow-wrapped.md")
OUT_A=$(bash "$BUMP" "$LES/pattern-flow-wrapped.md" confirmed "повод" case-new.md 2>&1); RC_A=$?
AFTER_A=$(cat "$LES/pattern-flow-wrapped.md")
if [ "$RC_A" -eq 0 ]; then
    say_fail "перенос строки: отказа не было (rc=0) — правка такой формы теряет прежние кейсы"
else
    say_pass "перенос строки: отказ ненулевым кодом"
fi
if [ "$BEFORE_A" != "$AFTER_A" ]; then
    say_fail "перенос строки: файл изменён, хотя скрипт отказал"
else
    say_pass "перенос строки: файл не тронут"
fi
if grep -q "блочному списку" <<< "$OUT_A"; then
    say_pass "перенос строки: сообщение называет починку"
else
    say_fail "перенос строки: отказ без указания, что делать: $OUT_A"
fi

check_one pattern-flow-comment "комментарий после скобки"

echo "--- frontmatter после вызова (форма A) ---"
sed -n '1,20p' "$LES/pattern-flow-wrapped.md"

echo "adv2 bump source_cases flow forms: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
