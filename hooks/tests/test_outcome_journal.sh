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
# (образец срода в фикстурах ниже — `repeat:`; `daily:` снят из перечня 13 сентября 2026, D358)
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
printf 'turn:%s|repeat:pattern-x|\nturn:%s|correction:42|\n' "$TURN_KEY" "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
set_mtime "$STATE/five-whys-${SID}.seen" "$T_OLD"

# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний. Очередь и дроссель сверщика чистятся перед вызовом.
run_dpr() { # [$1 = STATE_DIR, $2 = бэклог проекта] — по умолчанию общие фикстуры файла
    local st="${1:-$STATE}" bl="${2:-$BACKLOG}"
    : > "$st/pending-alerts.txt" 2>/dev/null || true
    rm -f "$st"/declared-problem-fired-*.jsonl 2>/dev/null || true
    STATE_DIR="$st" DPR_LOCAL_BACKLOG="$bl" bash "$DPR" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TR"}
PAYLOAD
    cat "$st/pending-alerts.txt" 2>/dev/null
}

# --- T1: поводы БЕЗ находки требуют исхода (прежде проверялся только discovery) ---
printf '# долг\n' > "$BACKLOG"; set_mtime "$BACKLOG" "$T_OLD"
OUT=$(run_dpr)
if grep -q 'В ЭТОМ ходе' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: повод repeat/correction без исхода не потребован: '$OUT'"; fi
if grep -q 'repeat' <<< "$OUT" && grep -q 'correction' <<< "$OUT"; then PASS=$((PASS+1))
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
STATE_DIR="$STATE" DIS_SESSION="$SID" bash "$OUTCMD" disproved repeat "признак сработал на своей же подписи" >/dev/null 2>&1
if [ "$(jq -rs 'map(select(.outcome=="disproved")) | length' "$J")" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: disproved не записан"; fi
# ...и без причины команда отказывает: исход без основания не считается
if ! STATE_DIR="$STATE" DIS_SESSION="$SID" bash "$OUTCMD" disproved repeat >/dev/null 2>&1; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5b]: исход без причины принят"; fi

# --- T6: замер считает доли и называет, чего они требуют ---
REPORT=$(STATE_DIR="$STATE" bash "$SHARE" 2>&1)
if grep -q 'repeat' <<< "$REPORT" && grep -q '%' <<< "$REPORT"; then PASS=$((PASS+1))
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
  printf '{"message":{"role":"assistant","content":"оказалось дыра (hooks/five-whys-gate.sh:318). почему один, почему два, почему три"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR8"
printf '{"session_id":"gate8","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR8" \
    | STATE_DIR="$S8" bash "$GATE" >/dev/null 2>"$S8/err"
_rc=$?; [ "$_rc" -eq 0 ] || { FAIL=$((FAIL+1)); echo "FAIL [T8rc]: гейт умер rc=$_rc: $(tail -c 200 "$S8/err" 2>/dev/null)"; }
J8="$S8/outcome-gate8.jsonl"
if [ -f "$J8" ] && [ "$(jq -rs 'map(select(.outcome=="chain-spoken")) | length' "$J8")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8]: цепочка произнесена, исход не записан: $(cat "$J8" 2>/dev/null)"; fi
# ...и при этом гейт молчит (успех не сопровождается напоминанием)
OUT8=$(printf '{"session_id":"gate8b","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR8" \
    | STATE_DIR="$S8" bash "$GATE" 2>/dev/null)
if [ -z "$OUT8" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8b]: при произнесённой цепочке гейт говорит: '$OUT8'"; fi

# --- T8d/T8e: цепочка гасит только повод, чей ПРЕДМЕТ назван в ходе (D227) ---
# До этого любая цепочка писала chain-spoken ВСЕМ сигналам хода: разбор ci-red гасил
# «поправку собеседника», и непокрытые поводы были невидимы для outcome-share.
S8d="$TMP/state8d"; mkdir -p "$S8d"
printf '{"ts":"2026-01-01T00:00:00Z","kind":"ci-red","detail":"прогон 123456789 для abc: failure","status":"open"}\n' > "$S8d/pending-events.jsonl"
TR8d="$TMP/t8d.jsonl"
{
  printf '{"message":{"role":"user","content":"чини"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"почему раз (hooks/root-cause-lib.sh:73), почему два, почему три - разбор другого предмета"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR8d"
printf '{"session_id":"gate8d","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR8d" \
    | STATE_DIR="$S8d" bash "$GATE" >/dev/null 2>"$S8d/err"
_rc=$?; [ "$_rc" -eq 0 ] || { FAIL=$((FAIL+1)); echo "FAIL [T8drc]: гейт умер rc=$_rc: $(tail -c 200 "$S8d/err" 2>/dev/null)"; }
J8d="$S8d/outcome-gate8d.jsonl"
# Проверка файла отдельно: jq -s на отсутствующем файле печатает 0 (длина пустого слурпа)
# И выходит ненулевым — «|| echo 0» дописывал бы второй ноль, ломая сравнение.
if [ ! -f "$J8d" ] || [ "$(jq -rs 'map(select(.signal=="event" and .outcome=="chain-spoken")) | length' "$J8d" 2>/dev/null)" = "0" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8d]: чужая цепочка погасила событие: $(cat "$J8d" 2>/dev/null)"; fi
TR8e="$TMP/t8e.jsonl"
{
  printf '{"message":{"role":"user","content":"чини"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"почему раз (scripts/ci-status.sh:86), почему два, почему три - прогон 123456789 разобран"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR8e"
printf '{"session_id":"gate8e","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$TR8e" \
    | STATE_DIR="$S8d" bash "$GATE" >/dev/null 2>"$S8d/err8e"
_rc=$?; [ "$_rc" -eq 0 ] || { FAIL=$((FAIL+1)); echo "FAIL [T8erc]: гейт умер rc=$_rc: $(tail -c 200 "$S8d/err8e" 2>/dev/null)"; }
J8e="$S8d/outcome-gate8e.jsonl"
if [ -f "$J8e" ] && [ "$(jq -rs 'map(select(.signal=="event" and .outcome=="chain-spoken")) | length' "$J8e")" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8e]: цепочка с предметом события исход не записала: $(cat "$J8e" 2>/dev/null)"; fi

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
                            "signal": "repeat", "outcome": "none", "ref": ""}) + "\n")
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
                            "signal": "repeat", "outcome": "chain-spoken", "ref": ""}) + "\n")
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
S11="$TMP/state11"; mkdir -p "$S11"; P11="$TMP/proj11"; mkdir -p "$P11/scripts" "$P11/hooks"; cp "$REFRESH" "$P11/scripts/"
cp "$ROOT/hooks/backlog-lib.sh" "$ROOT/hooks/state-lock-lib.sh" "$P11/hooks/"   # без hooks/ скрипт уходит в ~/.claude — на CI пусто
printf '# долг\n\n### D400 ☐ Пункт\n\n**Показание.** `printf %%s\\n VAL-NEW`\n**Последнее показание (2020-01-01).** VAL-OLD\n' > "$P11/BACKLOG.md"
set_mtime "$P11/BACKLOG.md" "$T_OLD"
printf 'turn:%s|correction:42|\n' "$TURN_KEY" > "$S11/five-whys-${SID}.seen"
set_mtime "$S11/five-whys-${SID}.seen" "$T_OLD"
BACKLOG_FILE="$P11/BACKLOG.md" CLAUDSOUL_REPO="$P11" bash "$REFRESH" run >/dev/null 2>&1   # «внутри хода»
grep -q 'VAL-NEW' "$P11/BACKLOG.md" && grep -q 'Последнее показание.*VAL-NEW' "$P11/BACKLOG.md" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T11a]: пересчёт не записал показание"; }
OUT11=$(run_dpr "$S11" "$P11/BACKLOG.md")
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
                            # addr:1 — с 9 сентября 2026 адрес обязателен во всех ветвях
                            # критерия: разбор без единого адреса есть речь, а не разбор.
                            "trace": {"why": 0, "addr": 1, "frac": 0, "roots": 0, "heads": 2, "arrows": 0, "inputs": 0}}) + "\n")
PY2
OUT14b=$(STATE_DIR="$S14" bash "$SHARE" 2>&1); RC14b=$?
[ "$RC14b" -eq 0 ] && grep -q 'поводов со следом: 25 из 25' <<< "$OUT14b" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14c]: цепочки по заголовкам не засчитаны замером: rc=$RC14b '$OUT14b'"; }
# Обе формулы «след есть» на одном наборе: библиотека и замер согласны
. "$HOOKS/root-cause-lib.sh"
rc_chain_spoken '{"why":0,"addr":1,"frac":0,"roots":0,"heads":2,"arrows":0,"inputs":0}' && PASS=$((PASS+1)) \
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

# --- T15: машинное число для «Проверки» D358 --------------------------------------------
# Предмет ног — ЧИСЛО и его знаменатель, а не текст отчёта: потребитель сравнивает его
# с порогом, и любая человеческая строка на stdout ломает сравнение (поймано первым же
# прогоном режима 13 сентября 2026).
S15="$TMP/state15"; mkdir -p "$S15"
python3 - "$S15/outcome-15.jsonl" <<'PY2'
import json, sys
CH = {"why": 3, "addr": 1, "frac": 1, "roots": 1, "heads": 2, "arrows": 3, "inputs": 1}
NO = {"why": 0, "addr": 0, "frac": 0, "roots": 0, "heads": 0, "arrows": 0, "inputs": 0}
rows = []
# 30 записей гейта: 12 со следом разбора = 40%
for i in range(30):
    rows.append({"ts": "2026-09-01T00:00:00Z", "key": str(i), "signal": "rework",
                 "outcome": "recorded", "ref": "", "trace": CH if i < 12 else NO})
# 20 записей `daily`, все без цепочки: войдя в счёт, они уронили бы долю до 24%
for i in range(20):
    rows.append({"ts": "2026-09-01T00:00:00Z", "key": "d%d" % i, "signal": "daily",
                 "outcome": "recorded", "ref": "", "trace": NO})
with open(sys.argv[1], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY2
OUT15=$(STATE_DIR="$S15" bash "$SHARE" --gate-chain-share 2>/dev/null); RC15=$?
[ "$RC15" -eq 0 ] && [ "$OUT15" = "40" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15a]: ждали одинокое '40' (12 из 30), получили rc=$RC15 '$OUT15' — либо счёт неверен, либо на stdout попал отчёт"; }
[ "$(printf '%s' "$OUT15" | grep -c '')" = "1" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15b]: вывод режима не одна строка: '$OUT15'"; }

# T15c: КОНТРПРИМЕР — мало данных не зеленеет и числом не притворяется
S15c="$TMP/state15c"; mkdir -p "$S15c"
python3 - "$S15c/outcome-15c.jsonl" <<'PY2'
import json, sys
CH = {"why": 3, "addr": 1, "frac": 1, "roots": 1, "heads": 2, "arrows": 3, "inputs": 1}
with open(sys.argv[1], "w") as f:
    for i in range(5):
        f.write(json.dumps({"ts": "2026-09-01T00:00:00Z", "key": str(i), "signal": "rework",
                            "outcome": "recorded", "ref": "", "trace": CH}) + "\n")
PY2
OUT15c=$(STATE_DIR="$S15c" bash "$SHARE" --gate-chain-share 2>/dev/null); RC15c=$?
[ "$RC15c" -eq 2 ] && [ -z "$OUT15c" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15c]: пять записей должны дать «НЕ ИЗМЕРЕНО» кодом 2 и пустой stdout: rc=$RC15c '$OUT15c'"; }

# T15d: неизвестный аргумент — отказ, а не молчаливый отчёт
OUT15d=$(STATE_DIR="$S15" bash "$SHARE" --нет-такого 2>/dev/null); RC15d=$?
[ "$RC15d" -eq 2 ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15d]: неизвестный аргумент прошёл как обычный прогон: rc=$RC15d"; }

# --- T15e: условие ЗАКРЫТИЯ считается без журнала закрывающей сессии --------------------
# Решение владельца 13 сентября 2026. Замер того дня: показание дошло до 30 при пороге 30,
# а без журнала той сессии, которая собиралась закрывать пункт, равнялось 29 — переход
# держался на её собственных 5 цепочках из 8 поводов. Фикстура воспроизводит ровно это:
# старый журнал даёт 20%, свежий — 100%, вместе 40%.
S15e="$TMP/state15e"; mkdir -p "$S15e"
python3 - "$S15e" << 'PYT15E'
import json, sys, os
CH = {"why": 3, "addr": 1, "frac": 1, "roots": 1, "heads": 2, "arrows": 3, "inputs": 1}
NO = {"why": 0, "addr": 0, "frac": 0, "roots": 0, "heads": 0, "arrows": 0, "inputs": 0}
def rows(path, n, chained):
    with open(path, "w") as f:
        for i in range(n):
            f.write(json.dumps({"ts": "2026-09-01T00:00:00Z", "key": str(i), "signal": "rework",
                                "outcome": "recorded", "ref": "",
                                "trace": CH if i < chained else NO}) + "\n")
d = sys.argv[1]
rows(os.path.join(d, "outcome-old.jsonl"), 25, 5)     # 20%
rows(os.path.join(d, "outcome-new.jsonl"), 25, 25)    # 100%
os.utime(os.path.join(d, "outcome-old.jsonl"), (1, 1))   # старый заведомо старее
PYT15E
WITH=$(STATE_DIR="$S15e" bash "$SHARE" --gate-chain-share 2>/dev/null)
WITHOUT=$(STATE_DIR="$S15e" bash "$SHARE" --gate-chain-share --exclude-newest 2>/dev/null)
[ "$WITH" = "60" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15e]: показание со всеми журналами ждали 60, получили '$WITH'"; }
[ "$WITHOUT" = "20" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15f]: без самого свежего журнала ждали 20, получили '$WITHOUT' — закрытие опиралось бы на свою же сессию"; }

# T15g/T15h: ЕДИНИЦА ЗНАМЕНАТЕЛЯ — ПОВОД, А НЕ ХОД (D358, носитель 3).
# Повод, проживший двадцать ходов, обязан войти в знаменатель ОДИН раз. Без журнала гейта
# отпечатка повода взять негде, и прибор честно откатывается на ход — поэтому фикстура несёт
# `five-whys-<SID>.seen`, как в живом каталоге. Числа подобраны так, что старая формула и
# новая дают РАЗНЫЕ значения: по ходам 11 из 40 = 27%, по поводам 11 из 21 = 52%.
S15G="$TMP/state15g"; mkdir -p "$S15G"
python3 - "$S15G" <<'PYT15G'
import json, os, sys
d = sys.argv[1]
SID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
CH = {"why": 3, "addr": 1, "frac": 1, "roots": 1, "heads": 2, "arrows": 3, "inputs": 1}
NO = {"why": 0, "addr": 0, "frac": 0, "roots": 0, "heads": 0, "arrows": 0, "inputs": 0}
seen, rows = [], []
for i in range(20):
    # одна и та же поправка живёт все двадцать ходов; discovery у каждого хода свой
    seen.append("turn:%d|correction:C1|discovery:D%d|\n" % (i, i))
    rows.append({"ts": "2026-09-01T00:00:00Z", "key": str(i), "signal": "correction",
                 "outcome": "recorded", "ref": "", "trace": CH if i == 0 else NO})
    rows.append({"ts": "2026-09-01T00:00:00Z", "key": str(i), "signal": "discovery",
                 "outcome": "recorded", "ref": "", "trace": CH if i < 10 else NO})
open(os.path.join(d, "five-whys-%s.seen" % SID), "w").writelines(seen)
with open(os.path.join(d, "outcome-%s.jsonl" % SID), "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PYT15G
OUT15G=$(STATE_DIR="$S15G" bash "$SHARE" --gate-chain-share 2>/dev/null)
[ "$OUT15G" = "52" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15g]: повод, проживший 20 ходов, считается по ходам — ждали 52 (11 из 21), получили '$OUT15G' (27 значит старую единицу)"; }

# T15h: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — без журнала гейта отпечатка нет, и прибор ОБЯЗАН вернуться
# к счёту по ходам, а не выдумать повод. Иначе новая единица молча меняла бы старые данные.
S15H="$TMP/state15h"; mkdir -p "$S15H"
cp "$S15G/outcome-"*.jsonl "$S15H/"
OUT15H=$(STATE_DIR="$S15H" bash "$SHARE" --gate-chain-share 2>/dev/null)
[ "$OUT15H" = "27" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15h]: без журнала гейта ждали откат на ход (27), получили '$OUT15H'"; }

echo "outcome journal: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
