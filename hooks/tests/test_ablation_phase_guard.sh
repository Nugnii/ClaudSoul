#!/usr/bin/env bash
# test_ablation_phase_guard.sh — фаза видима и защищена: сигнал раз в сессию,
# стоп на деплой policy, тишина без фазы и на разработку в репозитории.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
SCRIPT="$HOOKS_DIR/ablation-phase-guard.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"
export STATE_DIR="$TMP/state"
mkdir -p "$ABLATION_DIR" "$STATE_DIR"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"

run_hook() { printf '%s' "$1" | HOME="$FAKE_HOME" STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null; }

# --- T1: фазы нет → тишина на обоих событиях ---
OUT=$(run_hook '{"session_id":"s1","user_prompt":"привет"}')
assert_empty "$OUT" "T1: без фазы UserPromptSubmit молчит"
OUT=$(run_hook '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cp x ~/.claude/hooks/"}}')
assert_empty "$OUT" "T1b: без фазы PreToolUse молчит"

# Фаза активна.
printf '{"phase":"phase-t","tag":"ablation-phase-t","since":"2026-08-08T18:00:00Z"}' > "$ABLATION_DIR/active-phase.json"

# --- T2: сигнал в сессию, раз на сессию ---
OUT=$(run_hook '{"session_id":"s2","user_prompt":"привет"}')
assert_contains "$OUT" "Фаза ablation" "T2: сигнал при активной фазе"
assert_contains "$OUT" "phase-t" "T2b: имя фазы в сигнале"
assert_contains "$OUT" '"systemMessage"' "T2s: сигнал видим владельцу (amendment phase-1)"
OUT=$(run_hook '{"session_id":"s2","user_prompt":"ещё"}')
# Сегмент шапки — каждый ход (очередь растёт, эхо раз в сессию устареет);
# полные правила — раз в сессию.
assert_contains "$OUT" "Сегмент шапки" "T2c: второй ход в сессии — сегмент шапки есть"
assert_contains "$OUT" "очередь 0/20" "T2c2: число в сегменте живое, не сочинённое"
if grep -Fq "Закрытие: scripts/ablation/phase.sh close" <<< "$OUT"; then
    bad "T2c3" "полные правила повторились в той же сессии"
else ok; fi
OUT=$(run_hook '{"session_id":"s3","user_prompt":"привет"}')
assert_contains "$OUT" "Фаза ablation" "T2d: новая сессия — свой сигнал"

# --- T2e-T2g: заморозка держится с ПЕРВОЙ принятой задачи, не с открытия фазы ---
# Повод: владелец, 2026-08-27 — «херли до конца замера, если по факту ничего не
# меряется». Троек ноль → сравнивать не с чем → запрет охранял пустоту.
OUT=$(run_hook '{"session_id":"s3e","user_prompt":"привет"}')
assert_contains "$OUT" "ЕЩЁ НЕ В СИЛЕ" "T2e: пустая очередь — сигнал говорит, что заморозки нет"
OUT=$(run_hook "{\"session_id\":\"s3e\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FAKE_HOME/.claude/hooks/x.sh\"}}")
assert_empty "$OUT" "T2f: пустая очередь — деплой свободен"

printf '{"e":"queue","id":"t-first","ts":"2026-08-27T18:00:00Z"}\n' >> "$ABLATION_DIR/journal.jsonl"
OUT=$(run_hook '{"session_id":"s3g","user_prompt":"привет"}')
assert_contains "$OUT" "Заморозка В СИЛЕ" "T2g: первая задача принята — заморозка включилась"
assert_contains "$OUT" "очередь 1/20" "T2h: сегмент шапки сосчитал принятую задачу"

# --- T3: деплой в установленное — стоп (очередь непуста) ---
OUT=$(run_hook "{\"session_id\":\"s4\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FAKE_HOME/.claude/hooks/x.sh\"}}")
assert_contains "$OUT" "СТОП" "T3: Edit установленного хука ловится"
assert_contains "$OUT" '"systemMessage"' "T3s: СТОП видим владельцу"
OUT=$(run_hook "{\"session_id\":\"s4\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cp hooks/x.sh $FAKE_HOME/.claude/hooks/\"}}")
assert_contains "$OUT" "СТОП" "T3b: cp в установленные хуки ловится"
OUT=$(run_hook "{\"session_id\":\"s4\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FAKE_HOME/.claude/settings.json\"}}")
assert_contains "$OUT" "СТОП" "T3c: Write settings.json ловится"
OUT=$(run_hook '{"session_id":"s4","tool_name":"Bash","tool_input":{"command":"bash install.sh"}}')
assert_contains "$OUT" "СТОП" "T3d: ЗАПУСК install.sh ловится"
OUT=$(run_hook '{"session_id":"s4","tool_name":"Bash","tool_input":{"command":"./install.sh --force"}}')
assert_contains "$OUT" "СТОП" "T3e: прямой запуск ./install.sh ловится"
OUT=$(run_hook '{"session_id":"s4","tool_name":"Bash","tool_input":{"command":"grep -n SETTINGS install.sh | head -5"}}')
assert_empty "$OUT" "T3f: чтение install.sh — не запуск (amendment phase-2)"
OUT=$(run_hook '{"session_id":"s4","tool_name":"Bash","tool_input":{"command":"git add install.sh && git commit -m x"}}')
assert_empty "$OUT" "T3g: git add install.sh — не запуск"
OUT=$(run_hook '{"session_id":"s4","tool_name":"Bash","tool_input":{"command":"bash -n install.sh"}}')
assert_empty "$OUT" "T3h: bash -n — проверка синтаксиса, не запуск"

# --- T4: разработка в репозитории свободна (§6) ---
OUT=$(run_hook '{"session_id":"s4","tool_name":"Edit","tool_input":{"file_path":"/repo/hooks/x.sh"}}')
assert_empty "$OUT" "T4: правка хука в репо — тишина"
OUT=$(run_hook "{\"session_id\":\"s4\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash $FAKE_HOME/.claude/hooks/knowledge-counter-bump.sh p confirmed x\"}}")
assert_empty "$OUT" "T4b: ЗАПУСК установленного хука — не деплой, тишина"
# Имя команды без границы ловило «rm» внутри слова перед путём (2026-08-27).
OUT=$(run_hook "{\"session_id\":\"s4\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add hooks/reformulation-tracker.sh $FAKE_HOME/.claude/hooks/\"}}")
assert_empty "$OUT" "T4c: «rm» внутри reformulation — не деплой"
OUT=$(run_hook '{"session_id":"s4","tool_name":"Bash","tool_input":{"command":"bash /var/folders/rm5/x/.claude/hooks/y.sh"}}')
assert_empty "$OUT" "T4d: «rm» во временном пути — не деплой"

# Дальше проверяется динамика сигнала — очередь обнуляем, чтобы счёт в T7 был точным.
: > "$ABLATION_DIR/journal.jsonl"

# --- T5: phase.sh status/close снимает маркер, страж затихает ---
OUT=$(bash "$ROOT/scripts/ablation/phase.sh" status)
assert_contains "$OUT" "phase-t" "T5: status видит фазу"
bash "$ROOT/scripts/ablation/phase.sh" close phase-t >/dev/null
OUT=$(bash "$ROOT/scripts/ablation/phase.sh" status 2>/dev/null); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T5b" "status после close не пуст"
assert_contains "$(cat "$ABLATION_DIR/journal.jsonl")" '"e":"phase_closed"' "T5c: событие закрытия"
OUT=$(run_hook "{\"session_id\":\"s5\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FAKE_HOME/.claude/hooks/x.sh\"}}")
assert_empty "$OUT" "T5d: после закрытия фазы деплой свободен"

# Фаза снова активна — для проверок динамического содержимого сигнала.
printf '{"phase":"phase-d","tag":"t","since":"2026-08-01T00:00:00Z"}' > "$ABLATION_DIR/active-phase.json"

# --- T6: обязанность регистрации в сигнале, пока регистраций сегодня нет ---
OUT=$(run_hook '{"session_id":"d1","user_prompt":"привет"}')
assert_contains "$OUT" "Регистраций сегодня нет" "T6: обязанность регистрации в сигнале"
printf '{"e":"register","id":"t-x","ts":"%sT10:00:00Z","text":"x","project":"p"}\n' "$(date -u '+%Y-%m-%d')" >> "$ABLATION_DIR/journal.jsonl"
OUT=$(run_hook '{"session_id":"d2","user_prompt":"привет"}')
if grep -Fq "Регистраций сегодня нет" <<< "$OUT"; then bad "T6b" "напоминание при живой регистрации"
else ok; fi

# --- T7: условие остановки — 20 в очереди → сигнал «достигнуто»; status его видит ---
OUT=$(run_hook '{"session_id":"d3","user_prompt":"привет"}')
if grep -Fq "ДОСТИГНУТО" <<< "$OUT"; then bad "T7" "стоп-сигнал при 1 регистрации без очереди"
else ok; fi
for i in $(seq 1 20); do
    printf '{"e":"queue","id":"t-%s","ts":"2026-08-02T00:00:0%sZ"}\n' "$i" "0" >> "$ABLATION_DIR/journal.jsonl"
done
OUT=$(run_hook '{"session_id":"d4","user_prompt":"привет"}')
assert_contains "$OUT" "ДОСТИГНУТО" "T7b: очередь 20 — условие остановки в сигнале"
OUT=$(bash "$ROOT/scripts/ablation/phase.sh" status)
assert_contains "$OUT" '"stop_condition_met": true' "T7c: status считает условие"
assert_contains "$OUT" '"queued": 20' "T7d: счёт очереди в status"

echo "test_ablation_phase_guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
