#!/usr/bin/env bash
# test_adv2_wit_state_size_mutant_maxdepth.sh — свидетель state-size зелен на мутанте, считающем файлы только верхнего уровня каталога состояния: фикстура плоская, а живой каталог — нет.
#
# Результат: объявленная работа (scripts/state-size.sh:3-4,26) — число файлов КАТАЛОГА состояния и
#            порог по нему; мутант `find "$STATE" -maxdepth 1 -type f` печатает те же строки и проходит
#            все ноги test_state_size.sh, потому что фикстура кладёт три файла в корень и ни одного в
#            подпапку. На подложенном каталоге «3 в корне + 1 в подпапке» при пороге 3 исходник
#            отвечает 1 «файлов больше порога», мутант — 0: решение порога переворачивается. В живом
#            `~/.claude/hooks/state` на 13 сентября 2026 подпапки есть (handoff-snapshots,
#            measurement-runs, .claude-docs): 3430 файлов всего против 3315 на верхнем уровне —
#            рост в подпапках такой мутант скрыл бы. Ожидание: свидетель на мутанте красен.
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
MUT="$SB/scripts/state-size.sh"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = 'FILES=$(find "$STATE" -type f'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, 'FILES=$(find "$STATE" -maxdepth 1 -type f')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — файл в подпапке не считается, порог не срабатывает
ST="$SB/state"; mkdir -p "$ST/sub"
: > "$ST/a.txt"; : > "$ST/b.txt"; : > "$ST/c.txt"; : > "$ST/sub/d.txt"
ORIG=$(cd "$REPO" && STATE_DIR="$ST" STATE_MAX_FILES=3 STATE_MAX_MB=40 bash scripts/state-size.sh 2>&1); ORC=$?
MUTO=$(cd "$SB" && STATE_DIR="$ST" STATE_MAX_FILES=3 STATE_MAX_MB=40 bash scripts/state-size.sh 2>&1); MRC=$?
{ [ "$ORC" -eq 1 ] && grep -Fq 'Каталог состояния: 4 файлов' <<< "$ORIG"; } && ok || bad T1 "исходник: rc=$ORC — «${ORIG}»"
{ [ "$MRC" -eq 0 ] && grep -Fq 'Каталог состояния: 3 файлов' <<< "$MUTO"; } && ok || bad T1 "мутант не разошёлся с исходником: rc=$MRC — «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_state_size.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте «-maxdepth 1»: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv2 state-size mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
