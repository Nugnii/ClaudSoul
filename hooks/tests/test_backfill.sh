#!/usr/bin/env bash
# СУДИТ: hooks/backfill-intrusiveness.sh hooks/lib/backfill-replay-one.sh
# test_backfill.sh — backfill-replay-one.sh smoke + orchestrator coverage.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKER="$HOOKS_DIR/lib/backfill-replay-one.sh"
ORCHESTRATOR="$HOOKS_DIR/backfill-intrusiveness.sh"

[ -f "$WORKER" ] || { echo "FAIL: $WORKER not found"; exit 1; }
[ -f "$ORCHESTRATOR" ] || { echo "FAIL: $ORCHESTRATOR not found"; exit 1; }

PASS=0; FAIL=0
assert_contains() {
    local h="$1" n="$2" label="$3"
    if grep -Fq "$n" <<< "$h"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$label]: '$n' not in:"; echo "$h"; fi
}
assert_empty() {
    local a="$1" label="$2"
    if [ -z "$a" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$label]: expected empty, got: $a"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# T1: non-existent transcript → worker exits silently
# ============================================================================
OUT=$("$WORKER" /nonexistent/file.jsonl 2>/dev/null || true)
assert_empty "$OUT" "T1: missing transcript → silent"

# ============================================================================
# T2: synthetic transcript with gentle marker → produces event
# ============================================================================
TR2="$TMP/synth-gentle.jsonl"
{
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:00Z",
             message:{role:"user", content:[{type:"text", text:"напиши функцию"}]}}'
    jq -cn '{type:"assistant", timestamp:"2026-04-01T10:00:05Z",
             message:{role:"assistant", content:[{type:"text",
               text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:30Z",
             message:{role:"user", content:[{type:"text", text:"да"}]}}'
} > "$TR2"

OUT=$("$WORKER" "$TR2" 2>/dev/null)
assert_contains "$OUT" '"type":"gentle"' "T2: gentle event produced"
assert_contains "$OUT" '"outcome":"accepted"' "T2: accepted outcome"
assert_contains "$OUT" '"source":"backfill"' "T2: backfill marker"
# Historical timestamp preserved (from user record)
assert_contains "$OUT" '"ts":"2026-04-01T10:00:30Z"' "T2: historical ts"
# aggregate_sid derived from transcript basename
assert_contains "$OUT" '"aggregate_sid":"backfill-synth-gentle"' "T2: aggregate sid"

# ============================================================================
# T3: synthetic transcript with proactive tool use → produces proactive event
# ============================================================================
TR3="$TMP/synth-proactive.jsonl"
{
    jq -cn '{type:"user", timestamp:"2026-04-02T10:00:00Z",
             message:{role:"user", content:[{type:"text", text:"а какой тут план?"}]}}'
    jq -cn '{type:"assistant", timestamp:"2026-04-02T10:00:05Z",
             message:{role:"assistant", content:[
               {type:"text", text:"План готов."},
               {type:"tool_use", name:"Edit", id:"t1", input:{}}
             ]}}'
    jq -cn '{type:"user", timestamp:"2026-04-02T10:00:30Z",
             message:{role:"user", content:[{type:"text", text:"ок"}]}}'
} > "$TR3"

OUT=$("$WORKER" "$TR3" 2>/dev/null)
assert_contains "$OUT" '"type":"proactive"' "T3: proactive event"
assert_contains "$OUT" '"source":"backfill"' "T3: backfill marker"

# ============================================================================
# T4: transcript with no user→assistant→user triad → no events
# ============================================================================
TR4="$TMP/synth-user-only.jsonl"
jq -cn '{type:"user", timestamp:"2026-04-03T10:00:00Z",
         message:{role:"user", content:[{type:"text", text:"hello"}]}}' > "$TR4"
OUT=$("$WORKER" "$TR4" 2>/dev/null)
assert_empty "$OUT" "T4: no triad → no events"

# ============================================================================
# T5: orchestrator --dry-run respects --limit and reports counts
# ============================================================================
# Build mini projects dir with two synthetic transcripts
PROJ_DIR="$TMP/projects"
mkdir -p "$PROJ_DIR/sess-a" "$PROJ_DIR/sess-b"
cp "$TR2" "$PROJ_DIR/sess-a/t1.jsonl"
cp "$TR3" "$PROJ_DIR/sess-b/t2.jsonl"

OUT_FILE="$TMP/out.jsonl"
OUT=$(BACKFILL_PROJECTS_DIR="$PROJ_DIR" BACKFILL_OUT="$OUT_FILE" \
      bash "$ORCHESTRATOR" --dry-run 2>&1)
assert_contains "$OUT" "transcripts found: 2" "T5: dry-run counts 2"
assert_contains "$OUT" "dry run, no replay" "T5: dry-run marker"
[ ! -f "$OUT_FILE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5: no output on dry-run]"; }

# ============================================================================
# T6: orchestrator produces NDJSON file with events from mini dir
# ============================================================================
OUT=$(BACKFILL_PROJECTS_DIR="$PROJ_DIR" BACKFILL_OUT="$OUT_FILE" \
      BACKFILL_PARALLEL=2 bash "$ORCHESTRATOR" 2>&1)
assert_contains "$OUT" "=== Backfill complete" "T6: completion marker"
# Переносимость mktemp: GNU падает на шаблоне без X'ов, ошибка видна в stderr
if grep -q 'mktemp:' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [T6: mktemp not portable]: $OUT"
else PASS=$((PASS+1)); fi
[ -f "$OUT_FILE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6: output file missing]"; }
EVENTS=$(wc -l < "$OUT_FILE" | tr -d ' ')
if [ "$EVENTS" -ge 2 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6: expected >=2 events, got $EVENTS]"; cat "$OUT_FILE"; fi
# Both gentle and proactive should be present
if grep -q '"type":"gentle"' "$OUT_FILE" && grep -q '"type":"proactive"' "$OUT_FILE"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T6: both types expected]"; cat "$OUT_FILE"
fi

# ============================================================================
# T7: пустой список расшифровок — реплея нет по явному условию, код 0 (D1162: прежде это держал ключ `-r` у xargs,
# а на BSD xargs пустой вход воркер не зовёт ни с ключом, ни без — нога была зелена на мутанте)
# ============================================================================
mkdir -p "$TMP/projects-empty"
OUT=$(BACKFILL_PROJECTS_DIR="$TMP/projects-empty" BACKFILL_OUT="$TMP/out-empty.jsonl" bash "$ORCHESTRATOR" 2>&1); rc=$?
assert_contains "$OUT" "nothing to replay" "T7: empty list skipped by explicit condition"
# Код на BSD 0 при любом поведении xargs — судит, что реплей не начинался (скептик D1162, M1: мутанты «условие без exit»
# и «условие ниже реплея» проходили ногу на macOS).
grep -Fq -- "--- replaying" <<< "$OUT" && { FAIL=$((FAIL+1)); echo "FAIL [T7: replay ran on empty list]"; } || PASS=$((PASS+1))
[ "$rc" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7: empty list → rc $rc, not 0]"; }

echo ""
# ============================================================================
# T9: перезаписываются РОВНО поля контракта — ни одним больше (род G)
# ============================================================================
# Шапка backfill-replay-one.sh объявляет три перезаписи: ts, source, aggregate_sid.
# Код писал ЧЕТЫРЕ — четвёртое (`backfill_sid`) не читал никто с 25 апреля 2026, и это
# 23,5% журнала мёртвой нагрузкой. Перечень здесь ЗАКРЫТ и принадлежит системе (это сам
# контракт файла, а не словарь живой речи), поэтому сверка перечнем законна.
# Нога сравнивает поля события ДО и ПОСЛЕ прогона: добавленные обязаны быть ровно тремя.
# Рамку задаём СВОЮ: чужой $OUT к этому месту уже пуст (последний прогон был о другом),
# и нога зеленела бы на пустоте — та же ошибка, что уже стоила трёх редакций ноги T10 в
# страже прироста. Берём транскрипт T2, где событие заведомо есть.
OUT9=$("$WORKER" "$TR2" 2>/dev/null)
if [ -z "$OUT9" ]; then
    FAIL=$((FAIL+1)); echo "FAIL [T9]: прогон не дал события — проверять контракт не на чем"
else
    ADDED=$(printf '%s\n' "$OUT9" | head -1 \
        | jq -r 'keys_unsorted[]' 2>/dev/null \
        | grep -xE 'ts|source|aggregate_sid|backfill_sid' | sort | tr '\n' ' ')
    EXPECT="aggregate_sid source ts "
    if [ "$ADDED" = "$EXPECT" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); echo "FAIL [T9]: поля перезаписи разошлись с контрактом — «${ADDED}», ожидалось «${EXPECT}»"
    fi
fi

# T10 — реплика посреди хода (вложение `queued_command`) — точка повтора, и детектор судит её по ходу агента ДО неё
# (D1144): «…запускаем?» → «да» вложением → только вызов → «нет, стоп» вложением. Событие одно — «принято» на «да»;
# второго, на уже отвеченное предложение, нет. Без точки на вложении событий ноль.
T10="$TMP/t10"; mkdir -p "$T10"
{ jq -nc '{type:"user",timestamp:"2026-04-01T10:00:00Z",message:{role:"user",content:[{type:"text",text:"напиши функцию"}]}}'
  jq -nc '{type:"assistant",timestamp:"2026-04-01T10:00:05Z",message:{role:"assistant",content:[{type:"text",text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
  jq -nc '{type:"attachment",timestamp:"2026-04-01T10:00:30Z",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"да"}}'
  jq -nc '{type:"assistant",timestamp:"2026-04-01T10:00:35Z",message:{role:"assistant",content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:"make"}}]}}'
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"b1",content:"ok"}]}}'
  jq -nc '{type:"attachment",timestamp:"2026-04-01T10:00:50Z",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"нет, стоп, не так"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Остановился."}]}}'; } > "$T10/t.jsonl"
GOT10=$(BACKFILL_TMP="$T10" bash "$WORKER" "$T10/t.jsonl" 2>/dev/null | jq -r '"\(.type) \(.outcome) \(.ts)"' | tr '\n' ';')
if [ "$GOT10" = "gentle accepted 2026-04-01T10:00:30Z;" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T10]: события повтора с репликой посреди хода — «${GOT10}», ожидалось одно «принято» на «да»"
fi

echo "=== backfill tests ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit $(( FAIL != 0 ))
