#!/usr/bin/env bash
# СУДИТ: hooks/session-registry-lib.sh hooks/session-start.sh
# test_startup_signals.sh — v1.5.1-alpha: проверка startup signals (missing CLAUDE.md + global-lessons diff).
# Изоляция через HOME=$TMP — session-registry-lib и все хуки работают в sandbox.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not found"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly present"
    else PASS=$((PASS + 1)); fi
}
# assert_eq зовут ноги T18 (D1016). До 23 октября 2026 функции здесь не было: четыре проверки через неё падали с
# «command not found» мимо счётчика, и файл показывал «39/39» — найдено положительным контролем на прежней редакции.
assert_eq() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: получено '$got', ожидалось '$want'"; fi
}

TMP=$(mktemp -d)
# Полная изоляция: sandbox HOME с копиями нужных хук-файлов
# Каталог реестра выводится ИЗ HOME намеренно — предмет пробы именно умолчание.
# Раннер даёт каждому тесту свой SR_SESSIONS_DIR (D271), и унаследованная переменная
# перебила бы выведение, сделав отрицательный контроль ложным.
unset SR_SESSIONS_DIR
SANDBOX_HOME="$TMP/home"
mkdir -p "$SANDBOX_HOME/.claude/hooks" "$SANDBOX_HOME/.claude/hooks/state" "$SANDBOX_HOME/.claude/sessions" "$SANDBOX_HOME/.claude/global-lessons"
cp "$HOOKS_DIR/session-registry-lib.sh" "$SANDBOX_HOME/.claude/hooks/" 2>/dev/null || true
cp "$HOOKS_DIR/narrative-compose-lib.sh" "$SANDBOX_HOME/.claude/hooks/" 2>/dev/null || true

trap 'rm -rf "$TMP"' EXIT

run_session_start() {
    local sid="$1" cwd="$2" last_ended="$3"
    local last_session_file="$SANDBOX_HOME/.claude/sessions/last-session.json"
    if [ -n "$last_ended" ]; then
        printf '{"session_id":"%s","ended_at":"%s"}' "$sid" "$last_ended" > "$last_session_file"
    else
        rm -f "$last_session_file"
    fi
    echo "{\"session_id\":\"$sid\",\"source\":\"startup\",\"cwd\":\"$cwd\",\"hook_event_name\":\"SessionStart\"}" | \
        HOME="$SANDBOX_HOME" \
        NARRATIVE_GAP_HOURS=999999 \
        bash "$HOOK" >/dev/null 2>"$TMP/hook-err" || echo "$?" >> "$TMP/hook-rc"
    cat "$SANDBOX_HOME/.claude/hooks/state/startup-signals-${sid}.txt" 2>/dev/null || true
}
# Хелпер зовётся через $(…) — счётчики внутри не выживают; смерть хука копится
# флаг-файлом и предъявляется перед итогом: negative-asserts (T2/T4/…) проходили
# на трупе продюсера, отличить тишину от смерти было нечем (D220).

# --- Test 1: missing CLAUDE.md → init-project signal ---
mkdir -p "$TMP/proj-without"
OUT=$(run_session_start "test-sid-1" "$TMP/proj-without" "")
assert_contains "$OUT" "нет CLAUDE.md" "T1: missing CLAUDE.md detected"
assert_contains "$OUT" "/init-project" "T1: /init-project hint present"

# --- Test 2: CLAUDE.md present → no init-project signal ---
mkdir -p "$TMP/proj-with"
touch "$TMP/proj-with/CLAUDE.md"
OUT=$(run_session_start "test-sid-2" "$TMP/proj-with" "")
assert_not_contains "$OUT" "/init-project" "T2: no hint when CLAUDE.md exists"

# --- Test 3: knowledge delta → /reload hint ---
touch "$SANDBOX_HOME/.claude/global-lessons/case-v151-test-fixture.md"
LAST_ENDED=$(date -u -v-2d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "2 days ago" +"%Y-%m-%dT%H:%M:%SZ")
OUT=$(run_session_start "test-sid-3" "$TMP/proj-with" "$LAST_ENDED")
assert_contains "$OUT" "База знаний обновилась" "T3: knowledge delta detected"
assert_contains "$OUT" "/reload" "T3: /reload hint present"

# --- Test 4: no last session (bootstrap) → no reload hint ---
OUT=$(run_session_start "test-sid-4" "$TMP/proj-with" "")
assert_not_contains "$OUT" "/reload" "T4: no /reload hint when no last ended_at"

# --- Test 5: no new knowledge since last session → no /reload hint ---
# Age the fixture file back below the last_ended threshold
touch -t "202604200000" "$SANDBOX_HOME/.claude/global-lessons/case-v151-test-fixture.md" 2>/dev/null || true
LAST_ENDED_RECENT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OUT=$(run_session_start "test-sid-5" "$TMP/proj-with" "$LAST_ENDED_RECENT")
assert_not_contains "$OUT" "/reload" "T5: no /reload hint when knowledge older than last_ended"

# --- Test 6: ⚙️ AP3 silence debt carry-over from last history entry ---
HIST="$SANDBOX_HOME/.claude/hooks/state/intrusiveness-history.jsonl"
cat > "$HIST" <<'EOF'
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":2,"pending_topics":["topic-alpha","topic-beta"],"surfaced":0}}
EOF
OUT=$(run_session_start "test-sid-6" "$TMP/proj-with" "")
assert_contains "$OUT" "AP3 silence debt carry-over" "T6: AP3 carry-over hint present"
assert_contains "$OUT" "2 pending" "T6: pending count shown"
assert_contains "$OUT" "topic-alpha" "T6: topic list present"

# --- Test 7: AP3 skip when pending == 0 ---
cat > "$HIST" <<'EOF'
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":0,"pending_topics":[],"surfaced":3}}
EOF
OUT=$(run_session_start "test-sid-7" "$TMP/proj-with" "")
assert_not_contains "$OUT" "AP3 silence debt carry-over" "T7: AP3 hint absent when pending=0"

# --- Test 8: AP3 graceful when topics missing (legacy digest format) ---
cat > "$HIST" <<'EOF'
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":1,"surfaced":0}}
EOF
OUT=$(run_session_start "test-sid-8" "$TMP/proj-with" "")
assert_contains "$OUT" "AP3 silence debt carry-over" "T8: AP3 hint fires even without pending_topics"
assert_contains "$OUT" "1 pending" "T8: count shown without topics"

# --- Test 9: AP3 uses LAST history entry (multiple sessions) ---
cat > "$HIST" <<'EOF'
{"session_id":"old-sid","boundary":"stop","debt":{"pending":5,"pending_topics":["ancient"],"surfaced":0}}
{"session_id":"prev-sid","boundary":"stop","debt":{"pending":0,"pending_topics":[],"surfaced":2}}
EOF
OUT=$(run_session_start "test-sid-9" "$TMP/proj-with" "")
assert_not_contains "$OUT" "AP3 silence debt carry-over" "T9: uses last entry (pending=0), not earlier"

# Clear AP3 history to isolate calibration tests
rm -f "$HIST"

CALIB_FILE="$SANDBOX_HOME/.claude/hooks/state/calibration-progress.json"
DONE_MARKER="$SANDBOX_HOME/.claude/hooks/state/calibration-v1.4-done.flag"

# --- Test 10: calibration under threshold → «копим» hint ---
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":5,"gentle_events_total":12,"proactive_events_total":3,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
rm -f "$DONE_MARKER"
OUT=$(run_session_start "test-sid-10" "$TMP/proj-with" "")
assert_contains "$OUT" "Калибровка v1.4.0: 5/30" "T10: under-threshold progress line present"
assert_contains "$OUT" "копим историю" "T10: accumulation phrasing"
assert_not_contains "$OUT" "готова" "T10: does not claim readiness"

# --- Test 11: calibration at threshold → «готова» hint ---
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":42,"gentle_events_total":120,"proactive_events_total":67,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
rm -f "$DONE_MARKER"
OUT=$(run_session_start "test-sid-11" "$TMP/proj-with" "")
assert_contains "$OUT" "Калибровка v1.4.0 готова" "T11: ready hint when valid>=threshold"
assert_contains "$OUT" "42/30" "T11: numerator/denominator shown"
assert_contains "$OUT" "gentle=120" "T11: gentle events total shown"
assert_contains "$OUT" "proactive=67" "T11: proactive events total shown"
assert_contains "$OUT" "scripts/calibrate.py" "T11: next-step pointer present"

# --- Test 12: done marker suppresses inject even at threshold ---
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":42,"gentle_events_total":120,"proactive_events_total":67,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
touch "$DONE_MARKER"
OUT=$(run_session_start "test-sid-12" "$TMP/proj-with" "")
assert_not_contains "$OUT" "Калибровка v1.4.0" "T12: done marker suppresses any calibration hint"

# --- Test 13: zero valid chunks → no hint (absence, not 0/30) ---
rm -f "$DONE_MARKER"
cat > "$CALIB_FILE" <<'EOF'
{"valid_chunks":0,"gentle_events_total":0,"proactive_events_total":0,"threshold":30,"last_updated":"2026-04-23T00:00:00Z"}
EOF
OUT=$(run_session_start "test-sid-13" "$TMP/proj-with" "")
assert_not_contains "$OUT" "Калибровка v1.4.0" "T13: zero valid chunks → silent (no noise)"

# --- Test 14: missing calibration file → no hint, no error ---
rm -f "$CALIB_FILE" "$DONE_MARKER"
OUT=$(run_session_start "test-sid-14" "$TMP/proj-with" "")
assert_not_contains "$OUT" "Калибровка v1.4.0" "T14: missing file → graceful skip"

# --- Test 15/16: подсказка дайджеста несёт возраст снимка (D84) ---
# Повод: 26 августа сигнал сообщил «Замеры: просрочено 2», а прямой прогон в тот же
# момент ответил «просроченных нет» — файл был собран тремя днями раньше. Дайджест
# аудита собирается раз в неделю, мостов раз в месяц, поэтому снимок штатно живёт
# до тридцати дней и подавался как текущее состояние.
HINT_FILE="$SANDBOX_HOME/.claude/hooks/state/audit-hint.txt"
printf '📏 Замеры: просрочено 2.\n' > "$HINT_FILE"
OUT=$(run_session_start "test-sid-15" "$TMP/proj-with" "")
assert_contains "$OUT" "Замеры: просрочено 2" "T15: свежий снимок печатается"
# T15b переписана 7 сентября 2026 под решение ПРЕДЫДУЩЕГО дня. Коммит 898ee7b (6 сентября,
# 21:04) постановил: «ВОЗРАСТ НАЗЫВАЕТСЯ ВСЕГДА, а не только у снимков старше суток» — порог
# в днях подавал двухчасовой снимок молча, как нынешнее состояние. Нога осталась от прежнего
# правила и с тех пор краснела, утверждая обратное коду. Теперь она проверяет то, ради чего
# правило и заведено: возраст назван, и у свежего снимка — в минутах.
assert_contains "$OUT" "Снимок ниже собран" "T15b: возраст свежего снимка назван, а не умолчан"
assert_contains "$OUT" "мин назад" "T15c: у свежего снимка возраст в МИНУТАХ, а не в днях"

# Тот же файл, датированный прошлым. Формат `-t` одинаков у BSD и GNU (POSIX).
touch -t 202601010000 "$HINT_FILE"
OUT=$(run_session_start "test-sid-16" "$TMP/proj-with" "")
assert_contains "$OUT" "Снимок ниже собран" "T16: у старого снимка возраст назван"
assert_contains "$OUT" "Замеры: просрочено 2" "T16b: содержимое печатается по-прежнему"

# --- Test 17: ДОГОВОР ИНИЦИАЦИИ ДОЕЗЖАЕТ ДО УЖЕ ИНИЦИИРОВАННОГО ПРОЕКТА (D1016) ---
# Шаблоны лежат там же, где их кладёт установка. Проект инициирован (SESSION.md + CLAUDE.md), частей договора нет:
# старт сессии заводит обе и называет их сигналом.
mkdir -p "$SANDBOX_HOME/.claude/templates"
cp "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" "$HOOKS_DIR/../templates/ROOTS.md.tmpl" "$SANDBOX_HOME/.claude/templates/"
P17="$TMP/proj-init"; mkdir -p "$P17"; touch "$P17/CLAUDE.md" "$P17/SESSION.md"
OUT=$(run_session_start "test-sid-17" "$P17" "")
cmp -s "$P17/BACKLOG.md" "$HOOKS_DIR/../templates/BACKLOG.md.tmpl"; [ $? = 0 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T17]: BACKLOG.md не заведён из шаблона"; }
cmp -s "$P17/ROOTS.md" "$HOOKS_DIR/../templates/ROOTS.md.tmpl"; [ $? = 0 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T17b]: ROOTS.md не заведён из шаблона"; }
assert_contains "$OUT" "заведены BACKLOG.md, ROOTS.md" "T17c: заведённое названо сигналом"
assert_not_contains "$OUT" "не называет исполнителя архивирования" "T17d: бэклог из шаблона исполнителя называет"
# T18 — бэклог, правленный руками, без исполнителя архивирования получает шапку из шаблона под заголовком (решение
# владельца 23 октября 2026), а работа в нём остаётся: заголовок первой строкой, пункт на месте; недостающая карта
# корней заводится. Повторный старт шапку второй раз не вставляет.
P18="$TMP/proj-old"; mkdir -p "$P18"; touch "$P18/CLAUDE.md" "$P18/SESSION.md"
printf '# BACKLOG — свой\n\n- ☐ **X1** пункт руками\n' > "$P18/BACKLOG.md"
OUT=$(run_session_start "test-sid-18" "$P18" "")
assert_eq "$(head -1 "$P18/BACKLOG.md")" "# BACKLOG — свой" "T18: заголовок бэклога на месте"
assert_eq "$(grep -c '^- ☐ \*\*X1\*\* пункт руками$' "$P18/BACKLOG.md")" "1" "T18a: пункт, правленный руками, на месте"
assert_eq "$(grep -c 'backlog-archive\.sh' "$P18/BACKLOG.md")" "1" "T18c: шапка исполнителя архивирования дописана"
assert_contains "$OUT" "заведены ROOTS.md" "T18b: недостающая карта корней заведена и названа"
assert_contains "$OUT" "дописана из шаблона" "T18d: дописанное названо сигналом"
S18=$(cksum < "$P18/BACKLOG.md")
OUT=$(run_session_start "test-sid-18b" "$P18" "")
assert_eq "$(cksum < "$P18/BACKLOG.md")" "$S18" "T18e: повторный старт бэклог не меняет"
assert_not_contains "$OUT" "Договор инициации" "T18f: повторный старт молчит"
# T19 — папка без SESSION.md не инициирована: ничего не заводится.
OUT=$(run_session_start "test-sid-19" "$TMP/proj-with" "")
[ ! -e "$TMP/proj-with/BACKLOG.md" ] && [ ! -e "$TMP/proj-with/ROOTS.md" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T19]: в неинициированной папке заведены части договора"; }
assert_not_contains "$OUT" "Договор инициации" "T19b: о неинициированной папке сигнала нет"

if [ -f "$TMP/hook-rc" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [run_session_start: хук падал, rc: $(tr '\n' ' ' < "$TMP/hook-rc"), stderr: $(tail -c 200 "$TMP/hook-err" 2>/dev/null)]"
fi

echo ""
echo "Startup signals tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
