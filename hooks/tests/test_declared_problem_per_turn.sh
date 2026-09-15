#!/usr/bin/env bash
# test_declared_problem_per_turn.sh — носитель проверяется ПОСЛЕ находки, а не за сессию.
#
# Результат: находка в ходе требует записи в носитель В ЭТОМ ЖЕ ходе
# Проверка результата: bash hooks/tests/test_declared_problem_per_turn.sh даёт 0
#
# Повод, измеренный 29 августа 2026. `declared-problem-recorded.sh` сверял время носителя
# (BACKLOG.md, база знаний) с НАЧАЛОМ СЕССИИ. В длинной сессии носитель меняется на первом
# часе — и дальше страж молчит до конца, сколько бы находок ни прозвучало. Живой случай
# того же дня: за сессию BACKLOG.md переписан на закрытии D105-D109, после чего десять
# срабатываний `discovery:` в журнале гейта не дали ни одного напоминания, и ход, где
# разбор дошёл до корня и не оставил исхода, прошёл молча.
#
# Предмет проверки был задан ГРАНИЦЕЙ СЕССИИ, а нужное состояние — «записано ПОСЛЕ
# находки». Это тот же род, что чинили в тот же день у гейта разбора: предмет берётся
# по тому, что удобно наблюдать, а не по тому, о чём утверждение.
#
# КОНТРПРИМЕР: ход, где находка прозвучала И носитель изменён после начала хода, молчания
# не нарушает — иначе страж станет фоном на здоровой работе.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/declared-problem-recorded.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SID="turn-test"
STATE="$TMP/state"; mkdir -p "$STATE"
BACKLOG="$TMP/BACKLOG.md"
LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"

USER_TEXT="разбери это"
TURN_KEY=$(printf '%s\n' "$USER_TEXT" | cksum | awk '{print $1}')

# Времена задаются ОДНОЙ шкалой. Первая версия этой фикстуры ставила время файла через
# `touch -t` (локальная зона), а метку хода — строкой «…Z» (UTC): на машине в CEST
# расхождение в два часа переворачивало вердикт, и падал тест, а не механизм. Двух шкал
# в одной сверке быть не должно — эпоха здесь единственная.
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
NOW=$(date -u +%s)
T_SESSION_START=$((NOW - 10800))   # начало сессии
T_BEFORE_TURN=$((NOW - 7200))      # носитель менялся ДО хода
T_TURN_START=$((NOW - 3600))       # начало хода
T_IN_TURN=$((NOW - 60))            # носитель менялся В ходе
TURN_START_ISO=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$T_TURN_START")
set_mtime() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }

TRANSCRIPT="$TMP/t.jsonl"
{
  printf '{"message":{"role":"user","content":"старое"},"timestamp":"2026-01-01T00:00:00Z"}\n'
  printf '{"message":{"role":"assistant","content":"ответ"},"timestamp":"2026-01-01T00:00:05Z"}\n'
  printf '{"message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$TURN_START_ISO"
} > "$TRANSCRIPT"

# Журнал гейта: находка прозвучала В ЭТОМ ходе.
printf 'turn:%s|discovery:123|\n' "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
printf '{}' > "$STATE/intrusiveness-${SID}.json"
set_mtime "$STATE/intrusiveness-${SID}.json" "$T_SESSION_START"

# Доставка с 12 сентября 2026 — только очередь pending-alerts.txt (systemMessage снят: в
# мобильном клиенте он рендерится построчно). Ноги ниже читают очередь, а не stdout.
run_hook() {
    # Очередь и ДРОССЕЛЬ чистятся перед каждым вызовом. Дроссель сверщика гасит повтор
    # одного состава повода в пределах сессии (`throttle_file … declared-problem …`), а ноги
    # ниже — самостоятельные случаи с одинаковым составом: без сброса четвёртый и пятый
    # вызовы молчали бы из-за дросселя, и нога мерила бы его, а не предмет.
    : > "$STATE/pending-alerts.txt" 2>/dev/null || true
    rm -f "$STATE"/*declared-problem* 2>/dev/null || true
    STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$BACKLOG" \
    bash "$HOOK" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TRANSCRIPT"}
PAYLOAD
    cat "$STATE/pending-alerts.txt" 2>/dev/null
}

# --- T1: носитель менялся ПОСЛЕ начала сессии, но ДО хода → страж обязан говорить ---
printf '# долг\n' > "$BACKLOG"
set_mtime "$BACKLOG" "$T_BEFORE_TURN"
OUT=$(run_hook)
if grep -q 'закрытого списка' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: носитель не менялся в ходе, а исход не потребован: '$OUT'"; fi
if grep -q 'В ЭТОМ ходе' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: граница проверки не названа ходом"; fi

# --- T2: КОНТРПРИМЕР — носитель изменён В ХОДЕ → молчание ---
set_mtime "$BACKLOG" "$T_IN_TURN"
OUT2=$(run_hook)
if [ -z "$OUT2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: запись в ходе есть, а страж говорит: '$OUT2'"; fi

# --- T3: КОНТРПРИМЕР — находки в ЭТОМ ходе не было → молчание ---
printf 'turn:999999|discovery:123|\n' > "$STATE/five-whys-${SID}.seen"
set_mtime "$BACKLOG" "$T_BEFORE_TURN"
OUT3=$(run_hook)
if [ -z "$OUT3" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: находки в ходе нет, а страж говорит: '$OUT3'"; fi

# --- T4: носители не менялись, но В ХОДЕ ПОЧИНЕН МЕХАНИЗМ → исход есть, страж молчит ---
# Повод, замер 7 сентября 2026 (D323): текст хука дословно признаёт решением «МЕХАНИЗМ, не
# дающий проблеме возникнуть», а наблюдал он только BACKLOG.md и базу знаний. По 51
# расшифровке: из 95 ходов, где разбор кончился исходом, 22 (23%) имели ТОЛЬКО починку
# механизма либо вердикт — и страж требовал у них исход, уже наступивший.
printf 'turn:%s|discovery:123|\n' "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
set_mtime "$BACKLOG" "$T_BEFORE_TURN"
{
  cat "$TRANSCRIPT"
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"hooks/five-whys-gate.sh"}}]},"timestamp":"%s"}\n' "$TURN_START_ISO"
} > "$TMP/t4.jsonl"
: > "$STATE/pending-alerts.txt" 2>/dev/null || true
rm -f "$STATE"/*declared-problem* 2>/dev/null || true
STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$BACKLOG" bash "$HOOK" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TMP/t4.jsonl"}
PAYLOAD
OUT4=$(cat "$STATE/pending-alerts.txt" 2>/dev/null)
if [ -z "$OUT4" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: механизм починен в ходе, а страж требует исход: '$OUT4'"; fi

# --- T4b: КОНТРПРИМЕР к T4 — тот же ход, но действие ЧИТАЕТ механизм → страж говорит ---
{
  cat "$TRANSCRIPT"
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"grep -n rc_trace hooks/five-whys-gate.sh"}}]},"timestamp":"%s"}\n' "$TURN_START_ISO"
} > "$TMP/t4b.jsonl"
: > "$STATE/pending-alerts.txt" 2>/dev/null || true
rm -f "$STATE"/*declared-problem* 2>/dev/null || true
STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$BACKLOG" bash "$HOOK" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TMP/t4b.jsonl"}
PAYLOAD
OUT4B=$(cat "$STATE/pending-alerts.txt" 2>/dev/null)
if grep -q 'закрытого списка' <<< "$OUT4B"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4b]: чтение механизма сочтено исходом: '$OUT4B'"; fi

# --- T5: СОСЕД тронул бэклог ClaudSoul, сессия идёт в чужом проекте → страж говорит (D396) ---
# Прежде время файла бэклога ClaudSoul засчитывалось ходу, кто бы его ни трогал: параллельная
# сессия, архиватор, пересчёт показаний. Измерено 11 сентября 2026 тремя состояниями.
# Здесь носитель проекта СТАРЫЙ, бэклог ClaudSoul — свежий, действий хода нет.
PROJ="$TMP/proj"; mkdir -p "$PROJ"
printf '# CLAUDE\n' > "$PROJ/CLAUDE.md"
printf '# долг проекта\n' > "$PROJ/BACKLOG.md"; set_mtime "$PROJ/BACKLOG.md" "$T_BEFORE_TURN"
CS="$TMP/cs"; mkdir -p "$CS"; printf '# долг ClaudSoul\n' > "$CS/BACKLOG.md"   # свежий: тронул сосед
printf 'turn:%s|discovery:123|\n' "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
: > "$STATE/pending-alerts.txt" 2>/dev/null || true
rm -f "$STATE"/*declared-problem* 2>/dev/null || true
STATE_DIR="$STATE" CLAUDSOUL_ROOT="$CS" bash "$HOOK" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TRANSCRIPT","cwd":"$PROJ"}
PAYLOAD
OUT5=$(cat "$STATE/pending-alerts.txt" 2>/dev/null)
if grep -q 'закрытого списка' <<< "$OUT5"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: чужая правка бэклога ClaudSoul зачлась этому ходу: '$OUT5'"; fi

# --- T6: КОНТРПРИМЕР к T5 — бэклог ClaudSoul правил САМ ход → молчание ---
# Кросс-проектная запись законна: агент в проекте X вправе записать проблему ClaudSoul в его
# бэклог. Видна она ДЕЙСТВИЕМ хода, а не состоянием файла.
{
  cat "$TRANSCRIPT"
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s/BACKLOG.md"}}]},"timestamp":"%s"}\n' "$CS" "$TURN_START_ISO"
} > "$TMP/t6.jsonl"
set_mtime "$PROJ/BACKLOG.md" "$T_BEFORE_TURN"
: > "$STATE/pending-alerts.txt" 2>/dev/null || true
rm -f "$STATE"/*declared-problem* 2>/dev/null || true
STATE_DIR="$STATE" CLAUDSOUL_ROOT="$CS" bash "$HOOK" >/dev/null 2>&1 <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TMP/t6.jsonl","cwd":"$PROJ"}
PAYLOAD
OUT6=$(cat "$STATE/pending-alerts.txt" 2>/dev/null)
if [ -z "$OUT6" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: запись в бэклог ClaudSoul сделана ходом, а страж говорит: '$OUT6'"; fi

echo "declared problem per turn: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
