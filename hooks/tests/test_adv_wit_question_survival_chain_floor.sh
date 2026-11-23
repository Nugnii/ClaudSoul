#!/usr/bin/env bash
# СУДИТ: scripts/question-survival.py
# test_adv_wit_question_survival_chain_floor.sh — свидетель question-survival зелен на мутанте, считающем «с цепочкой» ЛЮБОЙ доживший до правки вопрос (порог >=3 снят).
#
# Результат: ноги свидетеля несут цепочку ровно из трёх «почему» либо ни одной правки; вопроса,
#            дожившего до правки с одним-двумя «почему», среди них нет — мутант `chain >= 0`
#            печатает те же строки и проходит обе ноги. На корпусе с одним «почему» и правкой он
#            печатает «с произнесённой цепочкой (>=3 «почему»): 1» — число, противоречащее
#            собственному ярлыку. Ожидание: свидетель на мутанте красен.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/question-survival.py"; WIT="$REPO/hooks/tests/test_question_survival.sh"
[ -f "$TOOL" ] && [ -f "$WIT" ] && [ -f "$REPO/hooks/inquiry-gap.sh" ] || { echo "FAIL: нет инструмента, свидетеля или hooks/inquiry-gap.sh"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Песочница — из mktemp: имя цели записи рождается там, писатель у него один по построению
# (род H реестра судит по происхождению имени; `SBX="$TMP/sbx"` резолва до mktemp не давало).
SBX=$(mktemp -d "$TMP/sbx.XXXXXX"); mkdir -p "$SBX/scripts" "$SBX/hooks/tests"
cp "$TOOL" "$SBX/scripts/"; cp "$WIT" "$SBX/hooks/tests/"; cp "$REPO/hooks/inquiry-gap.sh" "$SBX/hooks/"
# Реплику инструмент судит правилом владельца (`is_owner_reply`, D1153) — библиотека едет в песочницу вместе с ним.
mkdir -p "$SBX/hooks/lib"; cp "$REPO/hooks/lib/transcript_window.py" "$SBX/hooks/lib/"
n=$(python3 - "$SBX/scripts/question-survival.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "chain >= 3"
new = "chain >= 0"
print(s.count(old))
open(p, "w").write(s.replace(old, new))
PY
)
[ "${n:-0}" -eq 2 ] || { echo "FAIL: мутант не собрался (вхождений $n)"; exit 1; }

# --- T1: свидетель на мутанте обязан покраснеть ------------------------------------------------
OUT=$(bash "$SBX/hooks/tests/test_question_survival.sh" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T1 "свидетель ЗЕЛЕН на мутанте без порога цепочки: rc=$RC — $(tail -1 <<< "$OUT")"

# --- T2: доказательство — вопрос, ОДНО «почему», правка: исходный даёт 0, мутант 1 --------------
H="$TMP/home"; P="$H/.claude/projects/proj"; mkdir -p "$P"
{
    printf '{"type":"user","message":{"role":"user","content":"а почему тут не создаются механизмы?"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Почему? Потому."},{"type":"tool_use","name":"Edit","id":"1","input":{}}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":"сделай вот это"}}\n'
} > "$P/s1.jsonl"
OUT=$(cd "$REPO" && HOME="$H" python3 "$TOOL" 2>&1); RC=$?
has T2 'из них ход дошёл до правки файлов: 1'
has T2 'из них с произнесённой цепочкой (>=3 «почему»): 0'
OUT=$(cd "$SBX" && HOME="$H" python3 "$SBX/scripts/question-survival.py" 2>&1); RC=$?
has T2 'из них с произнесённой цепочкой (>=3 «почему»): 1'

echo ""
echo "adv question-survival chain floor: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
