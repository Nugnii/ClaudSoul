#!/usr/bin/env bash
# test_state_reader_key.sh — хуки читают состояние собеседника тем же ключом, которым его пишет библиотека.
#
# Результат: ни один хук не читает `.state_axis` — ключа, которого в схеме состояния (v4,
#            intrusiveness-state-lib.sh) нет; при состоянии `distressed` хук с обещанным стражем
#            AP2 молчит
# Проверка результата: bash hooks/tests/test_state_reader_key.sh даёт 0
#
# Повод — аудит шапок 30 августа 2026: четыре хука (decompose-detector, inquiry-gap,
# accepted-alternative-gap, external-correction-gap) обещали в шапке «distressed → тихо (AP2)»
# и читали `.state_axis`, а библиотека кладёт состояние в `.state.current`. Ключ неверен с
# рождения decompose-detector (23 апреля 2026) и скопирован в три хука 8 августа — страж не
# работал ни разу. Класс: читатель держит СВОЮ копию имени поля (pattern-keep-list-drifts-from-its-consumers).
#
# КОНТРПРИМЕР: при состоянии `idle` тот же хук на той же реплике говорит — иначе тишина
# доказывала бы не страж, а сломанный хук.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$ROOT/hooks"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0

# --- T1: структурно — читателей .state_axis в хуках нет ---
READERS=$(grep -ln 'state_axis' "$HOOKS"/*.sh 2>/dev/null | xargs -I{} sh -c 'grep -q "^[^#]*state_axis" "{}" && echo "{}"' 2>/dev/null || true)
if [ -z "$READERS" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: читают несуществующий ключ .state_axis:"; printf '%s\n' "$READERS" | sed 's/^/  /'; fi
# T1b: фикстуры тестов тоже не пишут .state_axis — четыре теста были зелёными, потому что
# ошибались тем же ключом, что и хук (30.08: T6 «distressed глушит» прошёл при неверном поле).
FIX=$(grep -l '"state_axis"' "$HOOKS"/tests/test_*.sh 2>/dev/null | grep -v test_state_reader_key || true)
if [ -z "$FIX" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: фикстуры пишут несуществующий ключ .state_axis:"; printf '%s\n' "$FIX" | sed 's/^/  /'; fi

# --- T2: поведенчески — inquiry-gap молчит при distressed и говорит при idle ---
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"
SID="srk-test"
mk_state() { jq -n --arg st "$1" '{state:{current:$st, confidence:1, reasons:["test"]}}' > "$STATE/intrusiveness-${SID}.json"; }
payload() { jq -cn --arg s "$SID" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:"а почему страж не сработал?"}'; }
mk_state idle
OUT_IDLE=$(payload | STATE_DIR="$STATE" bash "$HOOKS/inquiry-gap.sh" 2>/dev/null)
mk_state distressed
OUT_DIS=$(payload | STATE_DIR="$STATE" bash "$HOOKS/inquiry-gap.sh" 2>/dev/null)
if [ -n "$OUT_IDLE" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2a]: при idle inquiry-gap молчит — контрпример не держится, тишина ниже ничего не докажет"; fi
if [ -z "$OUT_DIS" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2b]: при distressed inquiry-gap говорит — страж AP2 не работает: $(printf '%s' "$OUT_DIS" | head -c 160)"; fi

echo "state reader key: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
