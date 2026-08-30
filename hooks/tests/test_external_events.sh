#!/usr/bin/env bash
# test_external_events.sh — внешнее событие становится поводом разбора и гаснет по исходу.
#
# Результат: красный прогон своего коммита, откат, воскресшее закрытие и сбой проверки
#            дрейфа доходят до гейта разбора как повод, а после записанного исхода гаснут
# Проверка результата: bash hooks/tests/test_external_events.sh даёт 0
#
# Повод (D200-D203). Контур разбора запускался на ущерб или повтор. Мировые практики
# запускают его ещё на двух классах: «включение механизма реагирования» (Google SRE: откат
# релиза обязывает к разбору сам по себе) и «класс события независимо от исхода» (девять
# из двадцати восьми sentinel events репортятся regardless of outcome). У нас такие события
# НАБЛЮДАЛИСЬ и никуда не вели: `ci-status.sh` печатал исход, `backlog-recheck.sh` находил
# воскресшие пункты, `drift-check.sh` отличал BROKEN от DRIFT — и всё оставалось строкой
# в отчёте скрипта.
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · событий нет → гейт молчит (повод не выдумывается);
#   · закрытое событие поводом не является (иначе оно висело бы вечно и стало бы фоном);
#   · `git revert --abort` откатом решения НЕ считается — это управление идущим откатом;
#   · `git commit --amend` до публикации не считается: правка черновика, не отмена.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS/root-cause-lib.sh"
GATE="$HOOKS/five-whys-gate.sh"
DPR="$HOOKS/declared-problem-recorded.sh"
REVERT="$HOOKS/revert-signal.sh"
for f in "$LIB" "$GATE" "$DPR" "$REVERT"; do
    [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {
    if [ -z "${1//[[:space:]]/}" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"
SID="events-test"
NOW=$(date -u +%s)
TURN_ISO=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$((NOW - 3600))")

TR="$TMP/t.jsonl"
{
  printf '{"message":{"role":"user","content":"работаем"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"правлю"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR"

run_gate() {
    printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$SID" "$TR" \
        | STATE_DIR="$STATE" bash "$GATE" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# --- T1: КОНТРПРИМЕР — событий нет → гейт молчит ---
assert_empty "$(run_gate)" "T1: без событий гейт молчит"

# --- T2: событие доходит до гейта как повод ---
# shellcheck source=/dev/null
. "$LIB"
rc_note_event "$STATE" "ci-red" "прогон 42 для abc1234: failure"
# Оба утверждения проверяются на ОДНОМ выводе: гейт дедуплицирует по подписи сигналов в
# пределах хода, и второй вызов на тех же данных законно молчит. Дважды звать одно и то же
# срабатывание — значит проверять дедуп, думая, что проверяешь текст.
OUT2=$(run_gate)
assert_contains "$OUT2" "внешнее событие" "T2: событие названо поводом"
assert_contains "$OUT2" "ci-red" "T2b: назван род события"

# --- T3: дедуп — то же событие дважды не заводится ---
rc_note_event "$STATE" "ci-red" "прогон 42 для abc1234: failure"
N=$(jq -rs 'length' "$STATE/pending-events.jsonl")
if [ "$N" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: дедуп не держит, записей $N"; fi

# --- T4: КОНТРПРИМЕР — закрытое событие поводом не является ---
rc_close_events "$STATE"
assert_empty "$(run_gate)" "T4: закрытое событие не будит гейт"

# --- T5: исход хода гасит открытые события ---
rc_note_event "$STATE" "resurrected" "инвариантов перестало держаться: 2"
printf 'turn:1|event:1|\n' > "$STATE/five-whys-${SID}.seen"
BACKLOG="$TMP/BACKLOG.md"; printf '# долг\n' > "$BACKLOG"   # свежий mtime = менялся в ходе
LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"
TURN_KEY=$(printf '%s\n' "работаем" | cksum | awk '{print $1}')
printf 'turn:%s|event:1|\n' "$TURN_KEY" > "$STATE/five-whys-${SID}.seen"
STATE_DIR="$STATE" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD >/dev/null 2>&1
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TR"}
PAYLOAD
OPEN=$(jq -rs 'map(select(.status=="open")) | length' "$STATE/pending-events.jsonl")
if [ "$OPEN" = "0" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: исход записан, а событие осталось открытым ($OPEN)"; fi

# --- T6: продюсер отката заводит повод ---
S6="$TMP/state6"; mkdir -p "$S6"
printf '{"session_id":"r1","tool_name":"Bash","tool_input":{"command":"git revert abc1234"}}' \
    | STATE_DIR="$S6" bash "$REVERT" >/dev/null 2>&1
if [ -f "$S6/pending-events.jsonl" ] && grep -q '"kind":"revert"' "$S6/pending-events.jsonl"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: откат не завёл повод"; fi

# --- T7: КОНТРПРИМЕРЫ продюсера — abort и amend поводом не являются ---
S7="$TMP/state7"; mkdir -p "$S7"
for cmd in "git revert --abort" "git commit --amend --no-edit"; do
    printf '{"session_id":"r2","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"/nonexistent"}' "$cmd" \
        | STATE_DIR="$S7" bash "$REVERT" >/dev/null 2>&1
done
if [ ! -f "$S7/pending-events.jsonl" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7]: abort/amend завели повод: $(cat "$S7/pending-events.jsonl")"; fi

# --- T8: КОНТРПРИМЕР — слово в кавычках командой не является ---
S8="$TMP/state8"; mkdir -p "$S8"
printf '{"session_id":"r3","tool_name":"Bash","tool_input":{"command":"echo \\"git revert это откат\\""}}' \
    | STATE_DIR="$S8" bash "$REVERT" >/dev/null 2>&1
if [ ! -f "$S8/pending-events.jsonl" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8]: упоминание в кавычках завело повод"; fi

# --- T8b: КОНТРПРИМЕР — генерируемый файл повторной починкой не считается ---
# Поймано на первом живом срабатывании 29 августа 2026: повод завёлся на
# `.claude-docs/dep-index.tsv` — файле, который не чинят, а пересобирают скриптом после
# каждой правки механизма, и который входит почти в каждый коммит.
S8b="$TMP/state8b"; mkdir -p "$S8b"
REPO8="$TMP/repo8"; mkdir -p "$REPO8"
git -C "$REPO8" init -q 2>/dev/null
git -C "$REPO8" config user.email t@t; git -C "$REPO8" config user.name t
mkdir -p "$REPO8/.claude-docs"
for i in 1 2 3; do
    printf 'gen %s\n' "$i" > "$REPO8/.claude-docs/dep-index.tsv"
    printf 'code %s\n' "$i" > "$REPO8/real.sh"
    git -C "$REPO8" add -A >/dev/null 2>&1
    git -C "$REPO8" commit -q -m "fix(x): правка $i" >/dev/null 2>&1
done
printf '{"session_id":"r5","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$REPO8" \
    | STATE_DIR="$S8b" bash "$REVERT" >/dev/null 2>&1
if [ -f "$S8b/pending-events.jsonl" ] && grep -q 'dep-index' "$S8b/pending-events.jsonl"; then
    FAIL=$((FAIL+1)); echo "FAIL [T8b]: генерируемый файл засчитан повторной починкой"
else PASS=$((PASS+1)); fi
# ...а НАСТОЯЩИЙ файл кода в том же окне — засчитан
if [ -f "$S8b/pending-events.jsonl" ] && grep -q 'real.sh' "$S8b/pending-events.jsonl"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8c]: повторная починка кода не замечена: $(cat "$S8b/pending-events.jsonl" 2>/dev/null)"; fi

# --- T9: ОБРЫВ СВЯЗИ — нет библиотеки → продюсер молчит, не падает ---
S9="$TMP/state9"; mkdir -p "$S9"
OUT9=$(printf '{"session_id":"r4","tool_name":"Bash","tool_input":{"command":"git revert abc1234"}}' \
    | HOME="$TMP/nohome" STATE_DIR="$S9" RC_LIB="$TMP/no-lib.sh" bash "$REVERT" 2>&1); RC9=$?
if [ "$RC9" -eq 0 ] && [ -z "$OUT9" ] && [ ! -f "$S9/pending-events.jsonl" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9]: без библиотеки: rc=$RC9 out='$OUT9'"; fi

echo "external events: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
