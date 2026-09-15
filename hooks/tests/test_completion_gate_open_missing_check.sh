#!/usr/bin/env bash
# test_completion_gate_open_missing_check.sh — открытый пункт БЕЗ строки «Проверка»
# называется на границе хода (D291, 6 сентября 2026).
#
# ПОВОД. `hooks/completion-gate.sh` на пункте без канонической строки делал `continue`
# с комментарием «отсутствие строки — предмет архиватора». Архиватор
# (`scripts/backlog-archive.sh:49`) открытых пунктов не касается ПО ПОСТРОЕНИЮ: он
# переносит только ☑ и ⊘, и `:265` спрашивает строку «Проверка» именно у ☑. Значит у
# требования контракта «у ☐/◐ обязана быть названная Проверка» исполнителей было НОЛЬ,
# тогда как у ☑ их два (гейт и архиватор). Найдено проверяющим: закрывающий текст нёс
# заголовок `**Проверка (кандидат на закрытие).**`, CHECK_RE его не подхватил, и пункт
# прошёл как пункт без проверки — молча.
#
# ПРЕДМЕТ — СОСТОЯНИЕ МИРА: тест поднимает настоящий хук на фикстуре бэклога и читает то,
# что хук сказал наружу. Позеленить правкой комментария нельзя.
#
# ГРАНИЦЫ (ноги N3-N6) — половина проверки, без которой годится загрубление «называть
# всех»: ☑ без строки остаётся предметом архиватора, ⊘ несёт «Вердикт» и команды не
# имеет, номер ниже порога контракта не судится задним числом, а красная строка у
# открытого — норма, о ней канал молчит.
#
# STATE_DIR у теста СВОЙ (mktemp): журнал срабатываний `cg-open-fired.jsonl` — знаменатель
# замера open-check-precision, и прогон теста не имеет права дописывать боевой.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/completion-gate.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний. Очередь и дроссель гейта чистятся перед вызовом.
run() { # $1 = файл бэклога
    : > "$TMP/state/pending-alerts.txt" 2>/dev/null || true
    rm -f "$TMP/state"/completion-gate-fired-*.jsonl 2>/dev/null || true
    printf '{"session_id":"cgm1","cwd":"%s"}' "$TMP" \
      | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$1" CG_LOCAL_BACKLOG="" \
        STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
    cat "$TMP/state/pending-alerts.txt" 2>/dev/null
}

has() { # $1 haystack $2 needle $3 label
    if grep -q -- "$2" <<< "$1"; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет «$2» в: $(printf '%s' "$1" | head -c 300)"; fi
}
hasnt() { # $1 haystack $2 needle $3 label
    if grep -q -- "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: лишнее «$2» в: $(printf '%s' "$1" | head -c 300)";
    else PASS=$((PASS+1)); fi
}

cat > "$TMP/B.md" <<'EOF'
# BACKLOG

- ☐ **D900** открытый пункт без строки «Проверка».
  **Дефект.** машинного критерия у пункта нет вовсе.

- ◐ **D901** взятый в работу, тоже без строки.
  **Дефект.** то же самое, другая метка.

- ☑ **D902** закрытый без строки — предмет архиватора, не этого стража.
  **Результат.** перенос не пройдёт, скажет архиватор.

- ⊘ **D903** отклонённый несёт «Вердикт», а не команду.
  **Вердикт.** признак опровергнут.

- ☐ **D100** номер ниже порога контракта — задним числом не вменяется.
  **Дефект.** старый пункт.

- ☐ **D904** открытый с КРАСНОЙ строкой — норма.
  **Проверка.** `false` → 0
EOF

OUT=$(run "$TMP/B.md")

has    "$OUT" "D900" "N1 ☐ без строки назван"
has    "$OUT" "D901" "N2 ◐ без строки назван"
hasnt  "$OUT" "D902" "N3 ☑ без строки — предмет архиватора"
hasnt  "$OUT" "D903" "N4 ⊘ несёт Вердикт, команды нет"
hasnt  "$OUT" "D100" "N5 номер ниже порога не судится"
hasnt  "$OUT" "D904" "N6 красная у открытого — норма, канал молчит"

# N7: сработка попала в журнал СВОИМ родом и держится pending, пока строки нет.
LOG="$TMP/state/cg-open-fired.jsonl"
KIND=$(python3 -c '
import json,sys
try: recs=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
except Exception: recs=[]
r=[x for x in recs if x.get("item")=="D900"]
print(r[0].get("kind","-")+"/"+r[0].get("outcome","-") if r else "нет записи")
' "$LOG" 2>/dev/null)
if [ "$KIND" = "missing/pending" ]; then PASS=$((PASS+1));
else FAIL=$((FAIL+1)); echo "FAIL [N7 журнал]: род/исход = '$KIND', ожидалось 'missing/pending'"; fi

# N8: строка появилась — исход срабатывания проставлен механизмом, а не рукой.
python3 - "$TMP/B.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
old="  **Дефект.** машинного критерия у пункта нет вовсе.\n"
assert s.count(old)==1, "якорь N8 не найден — фикстура разошлась с проверкой"
add = "  **" + "Проверка" + ".** `false` -> 0\n"
open(p,"w",encoding="utf-8").write(s.replace(old, old + add))
PY
OUT2=$(run "$TMP/B.md")
OUTCOME=$(python3 -c '
import json,sys
try: recs=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
except Exception: recs=[]
r=[x for x in recs if x.get("item")=="D900"]
print(r[0].get("outcome","-") if r else "нет записи")
' "$LOG" 2>/dev/null)
if [ "$OUTCOME" = "confirmed" ]; then PASS=$((PASS+1));
else FAIL=$((FAIL+1)); echo "FAIL [N8 исход]: outcome='$OUTCOME', ожидалось 'confirmed' после появления строки"; fi
hasnt "$OUT2" "D900" "N9 со строкой пункт больше не назван"

echo ""
echo "completion-gate open missing check: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
