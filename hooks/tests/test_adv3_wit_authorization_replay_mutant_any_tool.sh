#!/usr/bin/env bash
# test_adv3_wit_authorization_replay_mutant_any_tool.sh — свидетель authorization-replay зелен на мутанте, считающем «агент правил файлы» по ЛЮБОМУ tool_use, а не по Edit/Write/MultiEdit.
#
# Результат: объявленная работа (scripts/authorization-replay.py:15-18,26) — число нераспознанных
#            реплик, после которых агент ПРАВИЛ ФАЙЛЫ (EDIT_TOOLS). Мутант без сверки имени
#            инструмента печатает те же строки и проходит все три ноги test_authorization_replay.sh:
#            единственный tool_use фикстуры свидетеля — Edit. На корпусе «нераспознанная реплика →
#            tool_use Read» исходник печатает «НЕ признано, но агент следом правил файлы: 0»,
#            мутант — 1, то есть цена ошибки классификатора (D207) считается по чтениям.
#            Ожидание: свидетель на мутанте красен.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

SB=$(mktemp -d)
( cd "$REPO" && git archive HEAD ) | tar -x -C "$SB" || { echo "FAIL: копия дерева не собралась"; exit 1; }
MUT="$SB/scripts/authorization-replay.py"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = 'if isinstance(c, dict) and c.get("type") == "tool_use" \\\n                               and c.get("name") in EDIT_TOOLS:'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, 'if isinstance(c, dict) and c.get("type") == "tool_use":')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — после нераспознанной реплики агент только ЧИТАЛ ----
H="$SB/home"; P="$H/.claude/projects/proj"; mkdir -p "$P"
{
    printf '{"type":"user","message":{"role":"user","content":"а почему так вышло?"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","id":"1","input":{}}]}}\n'
} > "$P/s1.jsonl"
ORIG=$(cd "$REPO" && HOME="$H" python3 scripts/authorization-replay.py 2>&1)
MUTO=$(cd "$SB" && HOME="$H" python3 scripts/authorization-replay.py 2>&1)
grep -Fq 'НЕ признано, но агент следом правил файлы: 0' <<< "$ORIG" && ok || bad T1 "исходник на корпусе с Read: «${ORIG}»"
grep -Fq 'НЕ признано, но агент следом правил файлы: 1' <<< "$MUTO" && ok || bad T1 "мутант не разошёлся с исходником: «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_authorization_replay.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте «любой tool_use — правка»: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv3 authorization-replay mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
