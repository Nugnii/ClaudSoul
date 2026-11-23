#!/usr/bin/env bash
# test_adv2_wit_colon_mutant_contains_colon.sh — свидетель colon-lead-in-count зелен на мутанте, считающем зачином любую первую строку, СОДЕРЖАЩУЮ двоеточие, а не кончающуюся им.
#
# Результат: объявленный признак (scripts/colon-lead-in-count.py:15-16) — первая строка «кончается
#            двоеточием»; мутант `":" in head` печатает тот же ярлык «реплик с зачином-двоеточием: N»
#            и проходит все ноги test_colon_lead_in_count.sh: в фикстуре нет реплики, где двоеточие
#            стоит в середине первой строки, а строк две и больше. На корпусе «Ошибка: вот лог⏎строка»
#            исходник печатает 0, мутант — 1, то есть счёт под D92 (порог 10 реплик) набирается
#            чужими репликами. Ожидание: свидетель на мутанте красен.
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
MUT="$SB/scripts/colon-lead-in-count.py"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = 'head.endswith(":")'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, '(":" in head)')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — двоеточие в середине первой строки ---------------
H="$SB/home"; mkdir -p "$H/.claude/projects/proj"
printf '{"type":"user","message":{"role":"user","content":"Ошибка: вот лог\\nстрока лога"}}\n' > "$H/.claude/projects/proj/s1.jsonl"
ORIG=$(cd "$REPO" && HOME="$H" python3 scripts/colon-lead-in-count.py 2>&1)
MUTO=$(cd "$SB" && HOME="$H" python3 scripts/colon-lead-in-count.py 2>&1)
grep -Fq 'реплик с зачином-двоеточием: 0' <<< "$ORIG" && ok || bad T1 "исходник на корпусе с двоеточием в середине: «${ORIG}»"
grep -Fq 'реплик с зачином-двоеточием: 1' <<< "$MUTO" && ok || bad T1 "мутант не разошёлся с исходником: «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_colon_lead_in_count.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте «содержит двоеточие»: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv2 colon mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
