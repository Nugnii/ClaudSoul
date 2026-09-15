#!/usr/bin/env bash
# test_adv2_wit_smoke_test_mutant_registered_threshold.sh — свидетель smoke-test зелен на мутанте, у которого порог регистраций хуков в settings.json снят с 15 до 1: фикстура несёт ровно 15 регистраций и ни одной ноги ниже порога.
#
# Результат: объявленная работа (scripts/smoke-test.sh:12,80-84) — хуки ЗАРЕГИСТРИРОВАНЫ в
#            settings.json, ≥15, иначе предупреждение с числом; мутант `-ge 1` печатает тот же ярлык
#            «хуков зарегистрировано в settings.json: N» и проходит все ноги test_smoke_test.sh.
#            Установка, где скопировано 16 хуков и зарегистрирован один (слияние settings.json
#            сорвалось — тот случай, ради которого шаг 3 и написан), у исходника даёт «хуков в
#            settings.json: 1 (ожидалось ≥15)» и код 2, у мутанта — «зарегистрировано: 1» и
#            «Установка прошла полностью». Ожидание: свидетель на мутанте красен.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

SB=$(mktemp -d)
( cd "$REPO" && git archive HEAD ) | tar -x -C "$SB" || { echo "FAIL: копия дерева не собралась"; exit 1; }
MUT="$SB/scripts/smoke-test.sh"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = '[ "$REGISTERED_COUNT" -ge 15 ]'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, '[ "$REGISTERED_COUNT" -ge 1 ]')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — одна регистрация из шестнадцати хуков «полная установка»
CH="$SB/claude-home"; CD="$SB/claudsoul"
mkdir -p "$CH/hooks" "$CH/commands" "$CH/global-lessons" "$CH/sessions/active" "$CD/mcp-server/.venv/bin"
i=1; while [ "$i" -le 16 ]; do : > "$CH/hooks/h$i.sh"; i=$((i + 1)); done
i=1; while [ "$i" -le 10 ]; do mkdir -p "$CH/commands/skill$i"; : > "$CH/commands/skill$i/SKILL.md"; i=$((i + 1)); done
: > "$CH/global-lessons/one.md"
printf '# правила\n<!-- ClaudSoul: managed-start -->\n<!-- ClaudSoul: managed-end -->\n' > "$CH/CLAUDE.md"
jq -n '{hooks:{PreToolUse:[{hooks:[{type:"command", command:"h1.sh"}]}]}}' > "$CH/settings.json"
printf '#!/bin/sh\nexit 0\n' > "$CD/mcp-server/.venv/bin/python"; chmod +x "$CD/mcp-server/.venv/bin/python"
ORIG=$(cd "$REPO" && CLAUDE_HOME="$CH" CLAUDSOUL_DIR="$CD" bash scripts/smoke-test.sh 2>&1)
MUTO=$(cd "$SB" && CLAUDE_HOME="$CH" CLAUDSOUL_DIR="$CD" bash scripts/smoke-test.sh 2>&1)
grep -Fq 'хуков в settings.json: 1 (ожидалось ≥15)' <<< "$ORIG" && ok || bad T1 "исходник не предупредил об одной регистрации: «${ORIG}»"
grep -Fq 'хуков зарегистрировано в settings.json: 1' <<< "$MUTO" && ok || bad T1 "мутант не разошёлся с исходником: «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_smoke_test.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте «порог регистраций 1»: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv2 smoke-test mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
