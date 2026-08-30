#!/usr/bin/env bash
# test_adv2_bump_srccase_substring_dedup.sh
#
# Атака: дедуп `source_cases` считает ПОДСТРОКУ поля вхождением кейса.
#
# knowledge-counter-bump.sh:225 — `grep -Fq "$_tc" <<< "$_cur"`. Поиск идёт по всему
# тексту поля, а не по его элементам. В базе у поля бывают прозаические элементы в
# кавычках (реально: `pattern-*` с шестью элементами, два из них — предложения с
# датами, коммитами и именами артефактов). Стоит такой прозе упомянуть имя файла
# кейса — и настоящий кейс с этим именем уже не будет внесён в список: дедуп решит,
# что он там есть.
#
# Вход: поле
#   source_cases: [case-2026-08-20-alpha.md, "тот же признак разбирался в
#                  case-2026-08-27-beta.md, но фикс туда не дошёл"]
# и вызов с триггер-кейсом `case-2026-08-27-beta.md`, которого среди ЭЛЕМЕНТОВ нет.
#
# Факт: элемент не добавляется, скрипт печатает ✅ и возвращает 0. Односторонняя
# ссылка — ровно то, ради чего писалась ветка (D12: 23 односторонние ссылки за три
# месяца); проверка симметрии (mcp-server/tests/test_knowledge_link_symmetry.py) стоит
# ПОСЛЕ записи и поймает это уже как случившееся.
#
# Тот же промах работает и наоборот: `provenance_log` ветки `contradicted` кладёт
# `trigger_case: <кейс>` в тот же файл — но об этом отравлении в скрипте написано и
# оно закрыто сужением области поиска до поля. Не закрыто то, что внутри поля поиск
# по-прежнему подстрочный.

set -uo pipefail

BUMP="$(cd "$(dirname "$0")/.." && pwd)/knowledge-counter-bump.sh"
TMP="$(mktemp -d)"
LES="$TMP/lessons"; ST="$TMP/state"
mkdir -p "$LES" "$ST"

cat > "$LES/pattern-prose-src.md" <<'EOF'
---
type: pattern
confidence: 4
impact: 3
confirmed_count: 3
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
source_cases: [case-2026-08-20-alpha.md, "тот же признак разбирался в case-2026-08-27-beta.md, но фикс туда не дошёл"]
provenance_log: []
---

# Тело
EOF

NEW="case-2026-08-27-beta.md"
OUT=$(env -u CLAUDE_STATE_DIR -u DIS_SESSION \
      STATE_DIR="$ST" LESSONS_DIR="$LES" \
      bash "$BUMP" pattern-prose-src confirmed "признак сошёлся" "$NEW" 2>&1)
RC=$?

PASS=0; FAIL=0
say_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
say_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

F="$LES/pattern-prose-src.md"
if python3 -c 'import yaml' 2>/dev/null; then
    GOT=$(python3 - "$F" <<'PY'
import re, sys, yaml
t = open(sys.argv[1]).read()
m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
d = yaml.safe_load(m.group(1)) if m else {}
print("\n".join(d.get("source_cases") or []))
PY
)
    if grep -Fxq "$NEW" <<< "$GOT"; then
        say_pass "кейс внесён отдельным элементом source_cases"
    else
        say_fail "элемента «${NEW}» в source_cases нет (rc=${RC}, скрипт сказал: ${OUT})"
        echo "     элементы поля сейчас:"
        sed 's/^/       · /' <<< "$GOT"
    fi
else
    HITS=$(grep -c -F "$NEW" "$F")
    if [ "$HITS" -ge 2 ]; then
        say_pass "имя кейса встречается ${HITS} раза — элемент добавлен рядом с упоминанием"
    else
        say_fail "имя кейса встречается ${HITS} раз — добавления не было (rc=${RC})"
    fi
fi

echo "adv2 bump source_cases substring dedup: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
