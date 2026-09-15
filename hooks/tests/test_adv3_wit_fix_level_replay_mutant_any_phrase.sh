#!/usr/bin/env bash
# test_adv3_wit_fix_level_replay_mutant_any_phrase.sh — свидетель fix-level-replay зелен на мутанте, считающем блок заглушённым, если заглушена ХОТЯ БЫ ОДНА из его фраз, а не все.
#
# Результат: объявленная работа (scripts/fix-level-replay.py:4-6,117) — «заглушено НЫНЕШНЕЙ логикой»
#            повторяет хук: hooks/fix-level-check.sh:187-196 глушит каждую фразу порознь и срабатывает,
#            если хоть одна осталась незаглушённой, поэтому реплей требует `all(...)`. Мутант `any(...)`
#            печатает те же строки и проходит все три ноги test_fix_level_replay.sh: в каждом блоке
#            фикстуры ровно одна фраза словаря. На блоке с двумя фразами, где маркер стоит в
#            предложении только первой, исходник печатает «стало 0%» и «доносит … стало 1», мутант —
#            «стало 100%» и «стало 0»: доля, ради которой замер D113 написан, переворачивается.
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
MUT="$SB/scripts/fix-level-replay.py"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = 'if all(muffled_in_sentence(text, p) for p in found):'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, 'if any(muffled_in_sentence(text, p) for p in found):')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — две фразы, маркер только у первой -----------------
H="$SB/home"; P="$H/.claude/projects/proj"; mkdir -p "$P"
printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Понял, надо вынести урок — заведу хук. Будем осторожнее."}]}}\n' > "$P/s1.jsonl"
ORIG=$(cd "$REPO" && HOME="$H" python3 scripts/fix-level-replay.py 2>&1)
MUTO=$(cd "$SB" && HOME="$H" python3 scripts/fix-level-replay.py 2>&1)
{ grep -Fq 'совпадений словаря: 1' <<< "$ORIG" && grep -Fq 'доля заглушённых: было 100%, стало 0%' <<< "$ORIG"; } && ok \
    || bad T1 "исходник на блоке с двумя фразами: «${ORIG}»"
grep -Fq 'доля заглушённых: было 100%, стало 100%' <<< "$MUTO" && ok \
    || bad T1 "мутант не разошёлся с исходником: «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_fix_level_replay.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте «any вместо all»: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv3 fix-level-replay mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
