#!/usr/bin/env bash
# test_outcome_journal.sh — у каждого повода разбора записывается ИСХОД, а не срабатывание.
#
# Результат: в журнале `outcome-<SID>.jsonl` по каждому сроду повода стоит исход
#            (recorded/none/disproved), и доля исходов считается скриптом
# Проверка результата: bash hooks/tests/test_outcome_journal.sh даёт 0
#
# Повод (D112, замер 29 августа 2026): журнал стража писал срабатывания и не писал исходы —
# слепое пятно накрывало 205 правок из 315 (65%). Отдельно: след разбора проверялся ровно у
# одного срода из семи (`discovery:`), при том что в живых журналах daily 126, repeat 59,
# discovery 36, correction 6, streak 4 — у 195 срабатываний из 231 «заметил и ничего не
# сделал» было неотличимо от «сделал».
#
# КОНТРПРИМЕРЫ, оба проверяются ниже:
#   · носитель менялся в ходе → исход `recorded` и страж молчит (здоровая работа не шумит);
#   · Stop сработал дважды за ход → в журнале одна запись на пару (ход, сигнал), а не две:
#     иначе доли в замере перекошены самим фактом повторного Stop.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$ROOT/hooks"
DPR="$HOOKS/declared-problem-recorded.sh"
SHARE="$ROOT/scripts/outcome-share.sh"
OUTCMD="$ROOT/scripts/outcome.sh"
for f in "$DPR" "$SHARE" "$OUTCMD"; do [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SID="outcome-test"
STATE="$TMP/state"; mkdir -p "$STATE"
BACKLOG="$TMP/BACKLOG.md"; LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"

USER_TEXT="разбери и почини"
NOW=$(date -u +%s)
T_TURN=$((NOW - 3600)); T_OLD=$((NOW - 7200)); T_IN=$((NOW - 60))
TURN_ISO=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$T_TURN")
set_mtime() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }
TURN_KEY=$(printf '%s\n' "$USER_TEXT" | cksum | awk '{print $1}')

TR="$TMP/t.jsonl"
{
  printf '{"message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"правлю"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR"

# Журнал гейта: в ходе сработали ДВА срода, ни один из них не discovery.
printf 'turn:%s|daily:pattern-x|\nturn:%s|correction:42|\n' "$TURN_KEY" "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
set_mtime "$STATE/five-whys-${SID}.seen" "$T_OLD"

run_dpr() {
    STATE_DIR="$STATE" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TR"}
PAYLOAD
}

# --- T1: поводы БЕЗ находки требуют исхода (прежде проверялся только discovery) ---
printf '# долг\n' > "$BACKLOG"; set_mtime "$BACKLOG" "$T_OLD"
OUT=$(run_dpr)
if grep -q 'В ЭТОМ ходе' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: повод daily/correction без исхода не потребован: '$OUT'"; fi
if grep -q 'daily' <<< "$OUT" && grep -q 'correction' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: поводы не названы поимённо: '$OUT'"; fi

# --- T2: в журнал исходов легли ОБА срода со статусом none ---
J="$STATE/outcome-${SID}.jsonl"
if [ -f "$J" ] && [ "$(jq -rs 'map(select(.outcome=="none")) | length' "$J")" = "2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: журнал исходов: $(cat "$J" 2>/dev/null)"; fi

# --- T3: КОНТРПРИМЕР — повторный Stop не удваивает записи ---
run_dpr >/dev/null
if [ "$(jq -rs 'length' "$J")" = "2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: повторный Stop удвоил журнал: $(jq -rs 'length' "$J")"; fi

# --- T4: КОНТРПРИМЕР — носитель изменён в ходе → исход recorded и страж молчит ---
rm -f "$J"
set_mtime "$BACKLOG" "$T_IN"
OUT4=$(run_dpr)
if [ -z "$OUT4" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4a]: запись в ходе есть, а страж говорит: '$OUT4'"; fi
if [ "$(jq -rs 'map(select(.outcome=="recorded")) | length' "$J" 2>/dev/null)" = "2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4b]: исход recorded не записан: $(cat "$J" 2>/dev/null)"; fi

# --- T5: вердикт «показалось» пишется командой (наблюдением его не отличить) ---
STATE_DIR="$STATE" DIS_SESSION="$SID" bash "$OUTCMD" disproved daily "признак сработал на своей же подписи" >/dev/null 2>&1
if [ "$(jq -rs 'map(select(.outcome=="disproved")) | length' "$J")" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: disproved не записан"; fi
# ...и без причины команда отказывает: исход без основания не считается
if ! STATE_DIR="$STATE" DIS_SESSION="$SID" bash "$OUTCMD" disproved daily >/dev/null 2>&1; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5b]: исход без причины принят"; fi

# --- T6: замер считает доли и называет, чего они требуют ---
REPORT=$(STATE_DIR="$STATE" bash "$SHARE" 2>&1)
if grep -q 'daily' <<< "$REPORT" && grep -q '%' <<< "$REPORT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: замер не назвал доли: '$REPORT'"; fi
if grep -q 'мало данных' <<< "$REPORT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6b]: на трёх записях замер не назвал знаменатель малым: '$REPORT'"; fi

# --- T7: КОНТРПРИМЕР — журналов нет → замер молчит с кодом 0, а не падает ---
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
OUT7=$(STATE_DIR="$EMPTY" bash "$SHARE" 2>&1); RC7=$?
if [ "$RC7" -eq 0 ] && grep -q 'журналов исходов нет' <<< "$OUT7"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7]: пустое состояние: rc=$RC7 '$OUT7'"; fi

# --- T8: УСПЕХ СТРАЖА попадает в журнал ---
# Повод: до 29 августа 2026 гейт при произнесённой цепочке выходил на 31 строку выше записи
# журнала, и ход, где разбор СОСТОЯЛСЯ, не попадал в знаменатель вовсе. Доля «без исхода»
# была завышена по построению, а на ней стоит правило эскалации.
GATE="$HOOKS/five-whys-gate.sh"
S8="$TMP/state8"; mkdir -p "$S8"
TR8="$TMP/t8.jsonl"
{
  printf '{"message":{"role":"user","content":"чини"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"оказалось дыра. почему один, почему два, почему три"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR8"
printf '{"session_id":"gate8","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR8" \
    | STATE_DIR="$S8" bash "$GATE" >/dev/null 2>&1
J8="$S8/outcome-gate8.jsonl"
if [ -f "$J8" ] && [ "$(jq -rs 'map(select(.outcome=="chain-spoken")) | length' "$J8")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8]: цепочка произнесена, исход не записан: $(cat "$J8" 2>/dev/null)"; fi
# ...и при этом гейт молчит (успех не сопровождается напоминанием)
OUT8=$(printf '{"session_id":"gate8b","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR8" \
    | STATE_DIR="$S8" bash "$GATE" 2>/dev/null)
if [ -z "$OUT8" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8b]: при произнесённой цепочке гейт говорит: '$OUT8'"; fi

# --- T9: ОТКАЗ пишет «правка отложена» ---
S9="$TMP/state9"; mkdir -p "$S9"
TR9="$TMP/t9.jsonl"
{
  printf '{"message":{"role":"user","content":"чини"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"оказалось дыра, чиню"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR9"
OUT9=$(printf '{"session_id":"gate9","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR9" \
    | STATE_DIR="$S9" bash "$GATE" 2>/dev/null)
J9="$S9/outcome-gate9.jsonl"
if grep -q '"permissionDecision":"deny"' <<< "$OUT9"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9a]: отказа не было: '$OUT9'"; fi
if [ -f "$J9" ] && [ "$(jq -rs 'map(select(.outcome=="deferred")) | length' "$J9")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9b]: отказ не записал «правка отложена»: $(cat "$J9" 2>/dev/null)"; fi

# --- T10: замер СООБЩАЕТ НАХОДКУ КОДОМ ВОЗВРАТА, а не только текстом ---
# Иначе measurement-due.sh (различает находку по коду 0/1, вывод глушит) её не увидит.
S10="$TMP/state10"; mkdir -p "$S10"
python3 - "$S10/outcome-finding.jsonl" <<'PY'
import json, sys
# 25 срабатываний одного срода, все без исхода → доля none 100% при знаменателе выше порога
with open(sys.argv[1], "w") as f:
    for i in range(25):
        f.write(json.dumps({"ts": "2026-08-29T00:00:00Z", "key": str(i),
                            "signal": "daily", "outcome": "none", "ref": ""}) + "\n")
PY
OUT10=$(STATE_DIR="$S10" bash "$SHARE" 2>&1); RC10=$?
if [ "$RC10" -eq 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10]: находка не сообщена кодом возврата: rc=$RC10 '$OUT10'"; fi
# КОНТРПРИМЕР: те же 25 записей, но с исходом → код 0, находки нет
python3 - "$S10/outcome-finding.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(25):
        f.write(json.dumps({"ts": "2026-08-29T00:00:00Z", "key": str(i),
                            "signal": "daily", "outcome": "chain-spoken", "ref": ""}) + "\n")
PY
OUT10b=$(STATE_DIR="$S10" bash "$SHARE" 2>&1); RC10b=$?
if [ "$RC10b" -eq 0 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10b]: здоровые данные приняты за находку: rc=$RC10b '$OUT10b'"; fi

# --- T11: механический пересчёт показаний внутри хода — НЕ исход `recorded` (D210) ---
# Пересчёт на границе хода переписывает BACKLOG.md; если бы он двигал mtime, сверщик считал
# бы каждый такой ход «агент записал в носитель», и доля «без исхода» занижалась бы ровно
# там, где показание сдвинулось. Пересчёт сохраняет mtime — здесь это проверяется сквозь
# оба механизма, а не по одному.
REFRESH="$ROOT/scripts/backlog-refresh-readings.sh"
S11="$TMP/state11"; mkdir -p "$S11"; P11="$TMP/proj11"; mkdir -p "$P11/scripts"; cp "$REFRESH" "$P11/scripts/"
printf '# долг\n\n### D400 ☐ Пункт\n\n**Показание.** `printf %%s\\n VAL-NEW`\n**Последнее показание (2020-01-01).** VAL-OLD\n' > "$P11/BACKLOG.md"
set_mtime "$P11/BACKLOG.md" "$T_OLD"
printf 'turn:%s|correction:42|\n' "$TURN_KEY" > "$S11/five-whys-${SID}.seen"
set_mtime "$S11/five-whys-${SID}.seen" "$T_OLD"
BACKLOG_FILE="$P11/BACKLOG.md" CLAUDSOUL_REPO="$P11" bash "$REFRESH" run >/dev/null 2>&1   # «внутри хода»
grep -q 'VAL-NEW' "$P11/BACKLOG.md" && grep -q 'Последнее показание.*VAL-NEW' "$P11/BACKLOG.md" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T11a]: пересчёт не записал показание"; }
OUT11=$(STATE_DIR="$S11" DPR_BACKLOG="$P11/BACKLOG.md" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TR"}
PAYLOAD
)
J11="$S11/outcome-${SID}.jsonl"
if [ "$(jq -rs 'map(select(.signal=="correction" and .outcome=="none")) | length' "$J11" 2>/dev/null)" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T11b]: пересчёт показаний принят за запись агента: $(cat "$J11" 2>/dev/null)"; fi
if grep -q 'В ЭТОМ ходе' <<< "$OUT11"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T11c]: после пересчёта страж замолчал, хотя агент ничего не записал: '$OUT11'"; fi

# ── След разбора в журнале (D211) ─────────────────────────────────────────────
# --- T12: цепочка БЕЗ слова «почему» (заголовки шаблона) → chain-spoken, гейт молчит, след записан ---
S12="$TMP/state12"; mkdir -p "$S12"; TR12="$TMP/t12.jsonl"
{
  printf '{"message":{"role":"user","content":"чини"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"оказалось дыра. Вширь по проявлениям: hooks/a.sh:3, hooks/b.sh:9. Вглубь: звено ← звено. Сверка: сошлись."},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR12"
OUT12=$(printf '{"session_id":"gate12","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR12" \
    | STATE_DIR="$S12" bash "$GATE" 2>/dev/null)
J12="$S12/outcome-gate12.jsonl"
if [ -z "$OUT12" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T12a]: разбор без слова «почему» не признан — гейт говорит: '$OUT12'"; fi
if [ -f "$J12" ] && [ "$(jq -rs 'map(select(.outcome=="chain-spoken" and .trace.heads >= 2)) | length' "$J12")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T12b]: исход chain-spoken без следа: $(cat "$J12" 2>/dev/null)"; fi

# --- T13: отказ (deferred) и исход сверщика (none) несут след ---
if [ "$(jq -rs 'map(select(.outcome=="deferred" and (.trace|type)=="object")) | length' "$J9")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T13a]: deferred без следа: $(cat "$J9" 2>/dev/null)"; fi
if [ "$(jq -rs 'map(select(.outcome=="none" and (.trace|type)=="object")) | length' "$J11")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T13b]: исход сверщика без следа: $(cat "$J11" 2>/dev/null)"; fi

# --- T14: замер печатает долю со следом; порог и база — по записям с полем trace ---
S14="$TMP/state14"; mkdir -p "$S14"
python3 - "$S14/outcome-trace.jsonl" <<'PY2'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(25):   # 25 поводов со следом, ни одного с цепочкой → доля 0% < базы
        f.write(json.dumps({"ts": "2026-08-30T00:00:00Z", "key": str(i), "signal": "rework",
                            "outcome": "recorded", "ref": "",
                            "trace": {"why": 0, "addr": 0, "frac": 0, "roots": 0, "heads": 0, "arrows": 0, "inputs": 0}}) + "\n")
PY2
OUT14=$(STATE_DIR="$S14" bash "$SHARE" 2>&1); RC14=$?
if grep -q 'след разбора 0%' <<< "$OUT14" && grep -q 'поводов со следом: 0 из 25' <<< "$OUT14"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T14a]: доля со следом не напечатана: '$OUT14'"; fi
[ "$RC14" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T14b]: доля со следом ниже базы при 25 записях не сообщена кодом: rc=$RC14"; }
# КОНТРПРИМЕР: те же 25 записей, у каждой два заголовка шаблона → цепочка по той же формуле, что rc_chain_spoken → код 0
python3 - "$S14/outcome-trace.jsonl" <<'PY2'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(25):
        f.write(json.dumps({"ts": "2026-08-30T00:00:00Z", "key": str(i), "signal": "rework",
                            "outcome": "recorded", "ref": "",
                            "trace": {"why": 0, "addr": 0, "frac": 0, "roots": 0, "heads": 2, "arrows": 0, "inputs": 0}}) + "\n")
PY2
OUT14b=$(STATE_DIR="$S14" bash "$SHARE" 2>&1); RC14b=$?
[ "$RC14b" -eq 0 ] && grep -q 'поводов со следом: 25 из 25' <<< "$OUT14b" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14c]: цепочки по заголовкам не засчитаны замером: rc=$RC14b '$OUT14b'"; }
# Обе формулы «след есть» на одном наборе: библиотека и замер согласны
. "$HOOKS/root-cause-lib.sh"
rc_chain_spoken '{"why":0,"addr":0,"frac":0,"roots":0,"heads":2,"arrows":0,"inputs":0}' && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14d]: библиотека не признаёт след, который засчитал замер — формулы разошлись"; }
# КОНТРПРИМЕР: до порога знаменателя доля печатается, но кодом не сообщается
python3 - "$S14/outcome-trace.jsonl" <<'PY2'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(5):
        f.write(json.dumps({"ts": "2026-08-30T00:00:00Z", "key": str(i), "signal": "rework",
                            "outcome": "recorded", "ref": "",
                            "trace": {"why": 0, "addr": 0, "frac": 0, "roots": 0, "heads": 0, "arrows": 0, "inputs": 0}}) + "\n")
PY2
OUT14e=$(STATE_DIR="$S14" bash "$SHARE" 2>&1); RC14e=$?
[ "$RC14e" -eq 0 ] && grep -q 'поводов со следом: 0 из 5' <<< "$OUT14e" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14e]: находка по следу на пяти записях — решение на малом знаменателе: rc=$RC14e"; }

echo "outcome journal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
