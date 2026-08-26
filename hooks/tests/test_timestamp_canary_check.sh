#!/usr/bin/env bash
# test_timestamp_canary_check.sh — Stop-страж канарейки: молчит на здоровом
# ответе, алертит при пропаже/протухании таймштампа. Фикстурный транскрипт.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/timestamp-canary-check.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in: $haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Изоляция от живого маркера фазы: без него фазовая проверка молчит (T1-T8),
# фазные случаи (T9+) кладут фикстурный маркер сюда.
export ABLATION_DIR="$TMP/abl"
mkdir -p "$ABLATION_DIR"

# mktemp, не счётчик: вызов идёт через $(...), инкремент в подоболочке терялся,
# и все фикстуры молча писались в один файл (латентно с рождения теста).
make_transcript() {
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg t "$1" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    printf '%s' "$f"
}

# session_id уникален на фикстуру (basename транскрипта): маркер «уже алертили»
# ключуется сессией, общий id глушил бы алерты соседних тестов.
run_with() {
    printf '{"session_id":"sid-%s","transcript_path":"%s"}' "$(basename "$1")" "$1" | \
        CANARY_STATE_DIR="$TMP/state" \
        TIMESTAMP_INJECT_PATH="${2:-$HOOKS_DIR/timestamp-inject.sh}" bash "$SCRIPT" 2>/dev/null
}

NOW_TS=$(date '+%Y-%m-%d %H:%M')

# --- T1: ответ начат свежим таймштампом → молчит ---
F=$(make_transcript "🕐 $NOW_TS CEST

Готово, тесты зелёные.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1: здоровый ответ — тишина"

# --- T2: ответ без таймштампа → алерт с systemMessage ---
F=$(make_transcript "Готово, тесты зелёные, коммит создан.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T2: пропажа детектирована"
assert_contains "$OUT" "systemMessage" "T2b: алерт виден собеседнику"

# --- T3: протухший таймштамп (сутки назад) → алерт ---
STALE=$(date -v-1d '+%Y-%m-%d %H:%M' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d %H:%M' 2>/dev/null)
F=$(make_transcript "🕐 $STALE CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "протухло" "T3: свежесть проверяется"

# --- T4: таймштамп не в первой строке → алерт (правило: НАЧИНАТЬ с него) ---
F=$(make_transcript "Готово.

🕐 $NOW_TS CEST")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T4: таймштамп не в начале = пропажа"

# --- T5: механизм инжекта не задеплоен → тишина (другой класс проблемы) ---
F=$(make_transcript "Готово без таймштампа.")
OUT=$(run_with "$F" "$TMP/no-such-injector.sh")
assert_empty "$OUT" "T5: без инжектора страж молчит"

# --- T6: нет transcript_path → тихий выход ---
OUT=$(printf '{"session_id":"sid"}' | bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T6: без транскрипта тихий выход"

# --- T7/T8: ход с промежуточными репликами перед tool-вызовами ---
# Контракт c71af66: граница хода — реплика СОБЕСЕДНИКА; таймштамп обязан
# стоять в ПЕРВОМ текстовом блоке хода (шапка ответа) — так его видит
# владелец, прокручивая диалог сверху.
make_transcript_multi() {
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    local t
    for t in "$@"; do
        jq -nc --arg t "$t" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    done
    printf '%s' "$f"
}

F=$(make_transcript_multi "Смотрю детектор." "Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T7: ни одного блока с шапкой — пропажа"

F=$(make_transcript_multi "🕐 $NOW_TS CEST

Смотрю детектор." "Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T8: таймштамп в первом блоке — тишина, финал без него легален"

# --- T11: цепочка ходов, запущенных хуком, без реплики владельца ---
# Регрессия 2026-08-09: Stop-хук запускает следующий ход сам, поэтому граница
# «последняя реплика владельца» не двигается, и проверка первого блока цепочки
# упиралась в ответ, который уже не изменить, — 6 ложных алертов подряд.
# Отличить «продолжение ответа» от «нового хода» в транскрипте нельзя:
# last-prompt пишется и внутри хода, а два текстовых блока подряд дают обе
# ситуации одинаково. Поэтому проверяется последняя выданная шапка.
F=$(make_transcript_multi "🕐 2000-01-01 00:00 CEST

Старый ответ без сегмента." "🕐 $NOW_TS CEST

Свежий ответ.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T11: свежая шапка в последнем ответе цепочки — тишина"

# --- T9/T10: сегмент фазы в шапке при активной фазе (amendment phase-3) ---
printf '{"phase":"phase-x","tag":"t","since":"2026-08-09T00:00:00Z"}' > "$ABLATION_DIR/active-phase.json"
F=$(make_transcript "🕐 $NOW_TS CEST · 🧪 phase-x · очередь 0/20

Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T9: шапка с сегментом фазы — тишина"
F=$(make_transcript "🕐 $NOW_TS CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "без сегмента фазы" "T10: фаза активна, сегмента нет — алерт"
rm -f "$ABLATION_DIR/active-phase.json"

# --- T12/T13: самозацикливание — один алерт на ход владельца ---
# Регрессия 2026-08-15: алерт продолжает ход (харнесс ре-инвокает модель на
# additionalContext), продолжение по построению без свежего инжекта → снова нет
# шапки → алерт на каждом Stop («Без изменений» × N). Маркер глушит повтор,
# новая реплика владельца взводит канарейку заново.
F=$(make_transcript_multi "Ответ без шапки." "Без изменений.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T12: первый Stop хода — алерт"
OUT=$(run_with "$F")
assert_empty "$OUT" "T12b: повторный Stop того же хода — тишина"

printf '{"message":{"role":"user","content":[{"type":"text","text":"ещё вопрос"}]}}\n' >> "$F"
printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Снова без шапки."}]}}\n' >> "$F"
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T13: новая реплика владельца — алерт снова"

# --- T14: stop_hook_active — ход уже продолжен Stop-хуком, тихий выход ---
F=$(make_transcript "Без шапки.")
OUT=$(printf '{"session_id":"sid-%s","transcript_path":"%s","stop_hook_active":true}' "$(basename "$F")" "$F" | \
    CANARY_STATE_DIR="$TMP/state" TIMESTAMP_INJECT_PATH="$HOOKS_DIR/timestamp-inject.sh" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T14: stop_hook_active=true — страж молчит"

# --- T15: alert дописывает debug-лог с различителями (header_blocks и пр.) ---
# Прошлые alert-кейсы уже писали в тот же $TMP/state — проверяем приращение.
DBG="$TMP/state/canary-debug.jsonl"
BEFORE=$( [ -f "$DBG" ] && wc -l < "$DBG" | tr -d ' ' || echo 0 )
F=$(make_transcript "Ответ без шапки для debug-проверки.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T15: alert сработал"
AFTER=$( [ -f "$DBG" ] && wc -l < "$DBG" | tr -d ' ' || echo 0 )
# Через подстановку, не через трубу: под `pipefail` grep -q закрывает поток рано,
# tail получает SIGPIPE, и утверждение врёт о причине провала.
LAST_DBG=$(tail -1 "$DBG" 2>/dev/null)
if [ "$AFTER" -gt "$BEFORE" ] && grep -q '"header_blocks"' <<< "$LAST_DBG"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T15b]: debug-лог не дописан или без header_blocks"; fi

# --- T16: здоровый ответ (с шапкой) НЕ пишет debug-лог ---
BEFORE=$( [ -f "$DBG" ] && wc -l < "$DBG" | tr -d ' ' || echo 0 )
F=$(make_transcript "🕐 $NOW_TS CEST

Ответ со свежей шапкой.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T16: здоровый ответ — тихо"
AFTER=$( [ -f "$DBG" ] && wc -l < "$DBG" | tr -d ' ' || echo 0 )
if [ "$AFTER" -eq "$BEFORE" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T16b]: debug-лог дописан на здоровом ответе (не должен)"; fi

echo "test_timestamp_canary_check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
