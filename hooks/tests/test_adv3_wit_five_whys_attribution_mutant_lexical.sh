#!/usr/bin/env bash
# СУДИТ: scripts/five-whys-attribution-replay.py
# test_adv3_wit_five_whys_attribution_mutant_lexical.sh — свидетель five-whys-attribution-replay зелен на мутанте, снявшем фильтр LEXICAL: предмет извлекается из напоминания ЛЮБОГО срода, включая question и streak.
#
# Результат: объявленная работа (scripts/five-whys-attribution-replay.py:49-52,127-131) — предметы
#            берутся только у сигналов с лексическим предметом; streak и question «сюда НЕ входят
#            намеренно», их гасит любая цепочка. Мутант без этой проверки печатает те же строки и
#            проходит обе ноги test_five_whys_attribution_replay.sh: все напоминания фикстуры несут
#            «класс повторился». На корпусе с напоминанием без лексического предмета, в шапке
#            которого упомянут файл, а в ответе — цепочка без этого имени, исходник печатает
#            «новое правило ОТБИВАЕТ: 0», мутант — 1 и называет файл: число, ради которого
#            инструмент написан (сколько отбито по делу), завышается сродами без предмета.
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
MUT="$SB/scripts/five-whys-attribution-replay.py"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = '    if not any(k in head for k in LEXICAL):\n        return []\n'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, '')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — напоминание срода без предмета, в шапке файл --------
C="$SB/corpus"; mkdir -p "$C"
REM='🔁 Признак повторяется (собеседник задал вопрос, разбор к правке не начат; страж budget-gate.sh), а разбора причин в этом ходе не было.'
CHAIN='Почему сломалось? ← первое. Почему? ← второе. Почему? ← третье. Это pattern-alpha-beta-gamma, и корень назван.'
{
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"первый"}]}}\n'
    printf '{"type":"attachment","attachment":{"content":["%s"]}}\n' "$REM"
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$CHAIN"
} > "$C/s1.jsonl"
ORIG=$(cd "$REPO" && FWG_REPLAY_CORPUS="$C/*.jsonl" CLAUDSOUL_REPO="$REPO" python3 scripts/five-whys-attribution-replay.py 2>&1); ORC=$?
MUTO=$(cd "$SB"   && FWG_REPLAY_CORPUS="$C/*.jsonl" CLAUDSOUL_REPO="$SB"   python3 scripts/five-whys-attribution-replay.py 2>&1); MRC=$?
{ [ "$ORC" -eq 0 ] && grep -Fq 'из них прежнее правило РАЗРЕШАЛО:       1' <<< "$ORIG" \
    && grep -Fq 'новое правило ОТБИВАЕТ:                 0' <<< "$ORIG"; } && ok \
    || bad T1 "исходник на напоминании без лексического предмета: rc=$ORC — «${ORIG}»"
{ [ "$MRC" -eq 0 ] && grep -Fq 'новое правило ОТБИВАЕТ:                 1' <<< "$MUTO" \
    && grep -Fq 'budget-gate.sh' <<< "$MUTO"; } && ok \
    || bad T1 "мутант не разошёлся с исходником: rc=$MRC — «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_five_whys_attribution_replay.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте без фильтра LEXICAL: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv3 five-whys-attribution mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
