#!/usr/bin/env bash
# Unit tests for the Intrusiveness trends section of metrics-collector.sh.
# Builds synthetic intrusiveness-history.jsonl fixtures and verifies the
# resulting metrics.md contains expected aggregates, trends, and warnings.
#
# Run: bash hooks/tests/test_metrics_intrusiveness.sh

set -uo pipefail

COLLECTOR="$(cd "$(dirname "$0")/.." && pwd)/metrics-collector.sh"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if grep -qF "$needle" <<< "$haystack"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: output does not contain '$needle'")
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if grep -qF "$needle" <<< "$haystack"; then
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: output unexpectedly contains '$needle'")
    else
        PASS=$((PASS + 1))
    fi
}

# Helper: set up a temporary HOME so metrics-collector reads our fixtures
# and writes to an isolated state dir. Emits the path of metrics.md.
_run_collector() {
    local history_lines="$1"   # newline-separated JSONL content
    local tmpd
    tmpd=$(mktemp -d)
    mkdir -p "$tmpd/.claude/hooks/state" "$tmpd/.claude/global-lessons"
    # Need at least one knowledge file so collector doesn't abort early
    cat > "$tmpd/.claude/global-lessons/principle-stub.md" <<'MD'
---
name: stub
type: principle
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
stub
MD
    if [ -n "$history_lines" ]; then
        printf '%s\n' "$history_lines" > "$tmpd/.claude/hooks/state/intrusiveness-history.jsonl"
    fi
    # С v1.21.1 условия возврата сигналят только по ОТКРЫТОМУ долгу (test_backlog_signal_gate).
    # Этому тесту нужен сам механизм «условие выполнено → пункт поднят», поэтому его
    # фикстура объявляет проверяемые пункты открытыми.
    cat > "$tmpd/backlog-fixture.md" <<'BL'
- ☐ **D16** фикстура
- ☐ **D17** фикстура
- ☐ **D18** фикстура
- ☐ **D19** фикстура
- ☐ **D20** фикстура
- ☐ **D25** фикстура
- ☐ **D50** фикстура
- ☐ **D51** фикстура
- ☐ **D57** фикстура
BL
    HOME="$tmpd" CLAUDSOUL_BACKLOG="$tmpd/backlog-fixture.md" bash "$COLLECTOR" \
        >/dev/null 2>"$tmpd/collector.stderr"
    echo "$?" > "$tmpd/collector.rc"
    echo "$tmpd/.claude/hooks/state/metrics.md"
    # Caller is responsible for cleaning up $tmpd; we stash it so trap can remove it.
    _LAST_TMPD="$tmpd"
}

# Смерть коллектора — отдельное утверждение с причиной, а не «нет стрелки» сорока
# строками ниже. Повод: 30 августа 2026 на CI (прогон 33330392685) коллектор умер молча
# — вывод шёл в /dev/null, metrics.md не появился, и падало первое содержательное
# утверждение теста 5 без единого следа причины; локально и в контейнере не
# воспроизвелось. Код возврата и stderr теперь сохраняются рядом с metrics.md;
# функция выше выполняется в подстановке $(...), поэтому tmpd восстанавливается
# из METRICS_PATH, а не из _LAST_TMPD (тот в подстановке теряется).
_assert_collector_ok() {
    local tmpd="${METRICS_PATH%/.claude/hooks/state/metrics.md}"
    local rc
    rc=$(cat "$tmpd/collector.rc" 2>/dev/null || echo "нет файла rc")
    if [ "$rc" = "0" ] && [ -f "$METRICS_PATH" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("collector alive: rc=${rc}, metrics.md $([ -f "$METRICS_PATH" ] && echo есть || echo отсутствует); stderr: $(tail -c 300 "$tmpd/collector.stderr" 2>/dev/null | tr '\n' ' ')")
    fi
}

_cleanup_last() {
    [ -n "${_LAST_TMPD:-}" ] && rm -rf "$_LAST_TMPD"
    _LAST_TMPD=""
}

# Helper: generate N history lines with specified per-session metrics.
# Args: n gentle_acc_per gentle_ign_per proactive_per override_per debt_pending_per [start_idx]
#
# start_idx (v1.12.0) — абсолютный номер первой сессии. Нужен с тех пор, как
# metrics-collector свёртывает историю по session_id: раньше два вызова генератора
# давали ОДНИ И ТЕ ЖЕ id `s1..sN`, и «40 сессий» на деле были 20 сессий по два раза.
# При счёте по строкам это не замечалось, при счёте по сессиям — схлопывается.
# Номер задаёт и id, и дату, поэтому closed_at строго возрастает через все группы.
_gen_sessions() {
    local n="$1" ga="$2" gi="$3" pr="$4" ov="$5" pending="$6" start="${7:-1}"
    local i idx mon day
    for i in $(seq 1 "$n"); do
        idx=$((start + i - 1))
        # 28 дней на месяц — хватает на сотни сессий без коллизий по времени.
        mon=$(( 4 + (idx - 1) / 28 ))
        day=$(( (idx - 1) % 28 + 1 ))
        printf '{"session_id":"s%d","date":"2026-%02d-%02d","created_at":"2026-%02d-%02dT10:00:00Z","closed_at":"2026-%02d-%02dT10:30:00Z","duration_min":30,"events_total":10,"budget":{"gentle_used":%d,"gentle_max":5,"proactive_used":%d,"proactive_max":2,"shrink_events":%d},"metrics":{"gentle_accepted":%d,"gentle_ignored":%d,"proactive_events":%d,"override_events":%d,"silence_debt_surfaced":0},"debt":{"surfaced":0,"pending":%d},"cost_peaks":{"timing_max":2,"silence_max":2,"closing":1}}\n' \
            "$idx" "$mon" "$day" "$mon" "$day" "$mon" "$day" \
            "$ga" "$pr" "$gi" "$ga" "$gi" "$pr" "$ov" "$pending"
    done
}

# ============================================================================
# Test 1: no history file → no intrusiveness section
# ============================================================================
METRICS_PATH=$(_run_collector "")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_not_contains "no history: no Intrusiveness section" "$OUTPUT" "## Intrusiveness trends"
_cleanup_last

# ============================================================================
# Test 2: < 20 sessions → cumulative view with "недостаточно данных" note
# ============================================================================
HIST=$(_gen_sessions 10 3 1 1 0 0)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "small history: shows section"       "$OUTPUT" "## Intrusiveness trends"
assert_contains "small history: notes insufficient"  "$OUTPUT" "Недостаточно данных"
assert_contains "small history: shows cumulative"    "$OUTPUT" "### Кумулятивные метрики"
assert_contains "small history: session count=10"    "$OUTPUT" "**Сессий всего:** 10"
# 10 sessions × 3 accepted = 30, × 1 ignored = 10 → acceptance = 75%
assert_contains "small history: acceptance 75%"      "$OUTPUT" "75%"
_cleanup_last

# ============================================================================
# Test 3: exactly 20 sessions → last-20 block, no prev-20 comparison
# ============================================================================
HIST=$(_gen_sessions 20 4 1 1 0 0)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "20 sessions: shows last-20 header"  "$OUTPUT" "### Последние 20 сессий"
# Prev column should be em-dash (no prev data)
assert_contains "20 sessions: prev column shows —"   "$OUTPUT" "| —"
_cleanup_last

# ============================================================================
# Test 4: 40+ sessions with rising acceptance → trend arrow ↑
# Prev-20 (sessions 1-20): 2 acc / 3 ign each → 40% acceptance
# Last-20 (sessions 21-40): 4 acc / 1 ign each → 80% acceptance
# Expected trend: ↑
# ============================================================================
PREV=$(_gen_sessions 20 2 3 1 0 0 1)
LAST=$(_gen_sessions 20 4 1 1 0 0 21)
HIST="${PREV}
${LAST}"
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "trend ↑: last-20 acceptance 80%"    "$OUTPUT" "80%"
assert_contains "trend ↑: prev-20 acceptance 40%"    "$OUTPUT" "40%"
assert_contains "trend ↑: arrow present"             "$OUTPUT" "↑"
_cleanup_last

# ============================================================================
# Test 5: falling acceptance → trend arrow ↓
# ============================================================================
PREV=$(_gen_sessions 20 4 1 1 0 0 1)   # 80%
LAST=$(_gen_sessions 20 2 3 1 0 0 21)  # 40%
HIST="${PREV}
${LAST}"
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
# Warning: acceptance 40% is below 30% threshold? No — 40% is above. Sanity check.
assert_contains "trend ↓: arrow present"             "$OUTPUT" "↓"
_cleanup_last

# ============================================================================
# Test 6: low acceptance triggers warning (<30%)
# ============================================================================
HIST=$(_gen_sessions 25 1 4 1 0 0)  # 20% acceptance
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "low acceptance: warning emitted"    "$OUTPUT" "gentle_acceptance_rate"
assert_contains "low acceptance: < 30% wording"      "$OUTPUT" "< 30%"
assert_contains "low acceptance: miscalibrated flag" "$OUTPUT" "cost model miscalibrated"
_cleanup_last

# ============================================================================
# Test 7: high override rate triggers warning (>20%)
# 20 sessions × (1 acc + 1 ign + 1 pro + 5 ovr) = 160 total, 100 overrides → 62%
# Expected: warning about override rate miscalibration
# ============================================================================
HIST=$(_gen_sessions 20 1 1 1 5 0)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
# Утверждения по ПОВЕДЕНИЮ, не по формулировке. Прежние сверяли фразы «override rate»
# и «> 20%»; текст предупреждения переписан (он утверждал причину — «cost model
# miscalibrated», — которая не измерена), и обе проверки покраснели, хотя поведение
# не менялось. Признак остаётся: предупреждение вышло и назвало долю с числами.
assert_contains "high override: предупреждение вышло"  "$OUTPUT" "бюджет проактивных действий превышен"
assert_contains "high override: доля названа с числами" "$OUTPUT" "(100/160)"
_cleanup_last

# ============================================================================
# Test 8: history file present but empty → no crash, no section
# ============================================================================
METRICS_PATH=$(_run_collector "")   # no history lines
_assert_collector_ok
# But also simulate truly-empty history file
tmpd=$(mktemp -d)
mkdir -p "$tmpd/.claude/hooks/state" "$tmpd/.claude/global-lessons"
cat > "$tmpd/.claude/global-lessons/principle-stub.md" <<'MD'
---
name: stub
type: principle
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
MD
: > "$tmpd/.claude/hooks/state/intrusiveness-history.jsonl"   # create empty file
HOME="$tmpd" bash "$COLLECTOR" >/dev/null 2>"$tmpd/collector.stderr"
_rc=$?
if [ "$_rc" -ne 0 ]; then FAIL=$((FAIL + 1)); FAILED_TESTS+=("empty history: collector died rc=$_rc: $(tail -c 200 "$tmpd/collector.stderr" 2>/dev/null | tr '\n' ' ')"); fi
OUTPUT=$(cat "$tmpd/.claude/hooks/state/metrics.md")
assert_not_contains "empty history file: no trends section" "$OUTPUT" "## Intrusiveness trends"
rm -rf "$tmpd"

# ============================================================================
# Test 9 (v1.3.3): state distribution row appears when history has state_distribution
# ============================================================================

# Helper: generate N sessions with custom state_distribution counts.
# Args: n ga gi pr ov pending  focus stuck exploration idle
_gen_sessions_state() {
    local n="$1" ga="$2" gi="$3" pr="$4" ov="$5" pending="$6"
    local sf="$7" ss="$8" se="$9" si="${10}"
    local i
    for i in $(seq 1 "$n"); do
        printf '{"session_id":"s%d","date":"2026-04-%02d","created_at":"2026-04-%02dT10:00:00Z","closed_at":"2026-04-%02dT10:30:00Z","duration_min":30,"events_total":10,"budget":{"gentle_used":%d,"gentle_max":5,"proactive_used":%d,"proactive_max":2,"shrink_events":%d},"metrics":{"gentle_accepted":%d,"gentle_ignored":%d,"proactive_events":%d,"override_events":%d,"silence_debt_surfaced":0},"debt":{"surfaced":0,"pending":%d},"cost_peaks":{"timing_max":2,"silence_max":2,"closing":1},"state_distribution":{"focus":%d,"stuck":%d,"exploration":%d,"idle":%d}}\n' \
            "$i" "$((i % 28 + 1))" "$((i % 28 + 1))" "$((i % 28 + 1))" \
            "$ga" "$pr" "$gi" "$ga" "$gi" "$pr" "$ov" "$pending" \
            "$sf" "$ss" "$se" "$si"
    done
}

# 10 sessions × (focus=6, stuck=1, exploration=1, idle=2) → 60% / 10% / 10% / 20%
HIST=$(_gen_sessions_state 10 3 1 1 0 0  6 1 1 2)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "state dist: row present"                    "$OUTPUT" "state focus/stuck/exploration/idle"
assert_contains "state dist: 60% focus reported"             "$OUTPUT" "60%"
assert_contains "state dist: 20% idle reported"              "$OUTPUT" "20%"
_cleanup_last

# ============================================================================
# Test 10 (v1.3.3): high stuck% (>30) triggers warning
# ============================================================================
# 25 sessions × (focus=2, stuck=5, exploration=1, idle=2) → 50% stuck
HIST=$(_gen_sessions_state 25 3 1 1 0 0  2 5 1 2)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "high stuck: warning emitted"                "$OUTPUT" "state stuck"
assert_contains "high stuck: > 30% wording"                  "$OUTPUT" "> 30%"
_cleanup_last

# ============================================================================
# Test 11 (v1.3.3): history without state_distribution (legacy pre-v1.3.3)
# → section works, no state row (backward compat)
# ============================================================================
HIST=$(_gen_sessions 10 3 1 1 0 0)   # uses legacy helper, no state_distribution
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains     "legacy history: section still renders"       "$OUTPUT" "## Intrusiveness trends"
assert_not_contains "legacy history: no state row when missing"   "$OUTPUT" "state focus/stuck/exploration/idle"
_cleanup_last

# ============================================================================
# Test: свёртка по сессии — файл дописывается на КАЖДЫЙ Stop (v1.12.0)
#
# Регрессия на живые данные: 2879 строк истории оказались 213 сессиями, максимум
# 156 строк на одну. Каждая строка — накопительный снимок сессии, поэтому счёт по
# строкам считал одни и те же события многократно и взвешивал сессии по болтливости.
# Здесь одна сессия записана 5 раз: в агрегате обязана быть одна, с событиями × 1.
# ============================================================================
ONE_SESSION_LINE='{"session_id":"dup","date":"2026-04-01","created_at":"2026-04-01T10:00:00Z","closed_at":"2026-04-01T10:30:00Z","duration_min":30,"events_total":10,"budget":{"gentle_used":1,"gentle_max":5,"proactive_used":1,"proactive_max":2,"shrink_events":0},"metrics":{"gentle_accepted":3,"gentle_ignored":1,"proactive_events":7,"override_events":2,"silence_debt_surfaced":0},"debt":{"surfaced":0,"pending":0},"cost_peaks":{"timing_max":2,"silence_max":2,"closing":1}}'
HIST=$(for _ in 1 2 3 4 5; do echo "$ONE_SESSION_LINE"; done)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains     "dedup: 5 строк Stop = 1 сессия"        "$OUTPUT" "**Сессий всего:** 1"
assert_contains     "dedup: события посчитаны один раз"     "$OUTPUT" "| gentle accepted / ignored | 3 / 1 |"
assert_not_contains "dedup: события не умножены на 5"       "$OUTPUT" "| gentle accepted / ignored | 15 / 5 |"
assert_contains     "dedup: proactive посчитан один раз"    "$OUTPUT" "| proactive events | 7 |"
_cleanup_last

# ============================================================================
# Test: окно режется по СЕССИЯМ, а не по строкам
#
# 25 сессий, каждая записана по 4 раза = 100 строк. `tail -20` по строкам взял бы
# 5 сессий; по сессиям обязан взять 20 и увидеть prev-окно из оставшихся 5.
# ============================================================================
HIST=""
for i in $(seq 1 25); do
    LINE=$(_gen_sessions 1 2 2 1 0 0 "$i")
    for _ in 1 2 3 4; do HIST="${HIST}${LINE}"$'\n'; done
done
METRICS_PATH=$(_run_collector "${HIST%$'\n'}")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "window: 100 строк = 25 сессий"        "$OUTPUT" "**Сессий всего:** 25"
assert_contains "window: показан блок последних 20"    "$OUTPUT" "### Последние 20 сессий"
# 20 сессий × 2/2 → 40 accepted / 40 ignored, а не 160/160
assert_contains "window: срез по сессиям, не строкам"  "$OUTPUT" "| gentle accepted / ignored | 40 / 40 |"
_cleanup_last

# ============================================================================
# Test: минимальная выборка — процент ниже порога, но n мал → это не тревога
#
# До v1.12.0 предупреждение «0% < 30%» горело при четырёх наблюдениях.
# Проверка, которая срабатывает на шуме, обесценивает и себя, и остальные.
# ============================================================================
HIST=$(_gen_sessions 20 0 1 1 0 0 1)   # 20 сессий × (0 принято / 1 проигнорировано) = n=20
METRICS_PATH=$(ITR_MIN_GENTLE=50 _run_collector "$HIST")
OUTPUT=$(cat "$METRICS_PATH")
assert_contains     "min-n: мала выборка помечена"      "$OUTPUT" "выборка мала (n=20 < 50)"
assert_not_contains "min-n: тревоги нет"                "$OUTPUT" "⚠️ gentle_acceptance_rate"
_cleanup_last

# ============================================================================
# Test: выборки хватает и процент ниже порога → тревога есть, и с размером n
# ============================================================================
HIST=$(_gen_sessions 20 0 1 1 0 0 1)
METRICS_PATH=$(ITR_MIN_GENTLE=5 _run_collector "$HIST")
OUTPUT=$(cat "$METRICS_PATH")
assert_contains     "min-n: тревога при достаточной выборке" "$OUTPUT" "⚠️ gentle_acceptance_rate 0% (0/20) < 30%"
assert_not_contains "min-n: пометки о малой выборке нет"     "$OUTPUT" "выборка мала"
_cleanup_last

# ============================================================================
# Test: процент нигде не показывается без размера выборки
# ============================================================================
HIST=$(_gen_sessions 20 3 1 1 0 0 1)
METRICS_PATH=$(_run_collector "$HIST")
_assert_collector_ok
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "n рядом с процентом в таблице" "$OUTPUT" "| gentle_acceptance_rate | 75% (60/80) |"
_cleanup_last

# ============================================================================
# Условия возврата отложенных пунктов BACKLOG (v1.14.0)
#
# «Отложено» без проверяемого условия — фраза, которую некому перечитать: так за одну
# сессию накопилось 30 незакрытых пунктов. Условие обязано проверяться механически,
# иначе оно повторяет судьбу раздела «Ограничения» в CHANGELOG.
#
# Обе стороны обязательны: условие выполнено → пункт поднимается; не выполнено → тишина.
# Иначе получится сигнал, который горит всегда, и его начнут проматывать.
# ============================================================================
HIST_SMALL=$(_gen_sessions 20 0 1 1 0 0 1)     # gentle n=20
METRICS_PATH=$(ITR_MIN_GENTLE=50 _run_collector "$HIST_SMALL")
OUTPUT=$(cat "$METRICS_PATH")
assert_not_contains "возврат: n ниже условия → пункт не поднимается" "$OUTPUT" "BACKLOG D16"
_cleanup_last

METRICS_PATH=$(ITR_MIN_GENTLE=5 _run_collector "$HIST_SMALL")
OUTPUT=$(cat "$METRICS_PATH")
assert_contains "возврат: n достигло условия → пункт поднят" "$OUTPUT" "BACKLOG D16"
assert_contains "возврат: формулировка называет условие" "$OUTPUT" "условие возврата выполнено"
_cleanup_last

# ============================================================================
# Report
# ============================================================================
# ============================================================================
# Условия возврата отложенных пунктов: у каждого должен быть ПРОВЕРЯЮЩИЙ (2026-08-01)
# ============================================================================
# Замер: из 13 отложенных пунктов девять несли условие возврата ПРОЗОЙ, хотя правило
# самого BACKLOG это запрещает. Цена измерена: условие D16 было выполнено в 132 раза
# (2645 gentle-событий при пороге 20) и лежало непрочитанным, потому что гейт смотрел
# в ОКНО последних сессий вместо корпуса — то есть отвечал не на тот вопрос.

# Общая фикстура: корпус с gentle-событиями, окно при этом крошечное.
_COND_HIST='{"session_id":"c1","boundary":"stop","date":"2026-04-01","budget":{"gentle_used":1,"proactive_used":1,"gentle_max":5,"proactive_max":3,"shrink_events":0},"metrics":{"gentle_accepted":10,"gentle_ignored":15,"proactive_events":1,"proactive_accepted":1},"cost_peaks":{},"debt":{},"state_distribution":{},"cascading":{}}'

# C1: условие D16 проверяется по КОРПУСУ, а не по окну последних сессий.
MD=$(_run_collector "$_COND_HIST")
assert_contains "C1 D16 по корпусу" "$(cat "$MD")" "gentle-событий в корпусе 25"
assert_contains "C1b окно названо отдельно" "$(cat "$MD")" "в окне последних сессий"
_cleanup_last

# C2: отрицательный контроль — корпус ниже порога, условие молчит.
# Без него зелёный C1 не отличим от «строка печатается всегда».
_SMALL='{"session_id":"c2","boundary":"stop","date":"2026-04-01","budget":{"gentle_used":0,"proactive_used":1,"gentle_max":5,"proactive_max":3,"shrink_events":0},"metrics":{"gentle_accepted":1,"gentle_ignored":1,"proactive_events":1,"proactive_accepted":1},"cost_peaks":{},"debt":{},"state_distribution":{},"cascading":{}}'
MD=$(_run_collector "$_SMALL")
assert_not_contains "C2 отрицательный контроль" "$(cat "$MD")" "gentle-событий в корпусе"
_cleanup_last

# C3-C4: у D25 и D57 появились проверяющие — до 2026-08-01 их условия были прозой.
_TMPC=$(mktemp -d)
mkdir -p "$_TMPC/.claude/hooks/state" "$_TMPC/.claude/global-lessons"
cat > "$_TMPC/.claude/global-lessons/principle-stub.md" <<'MD2'
---
name: stub
type: principle
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
stub
MD2
printf '%s\n' "$_COND_HIST" > "$_TMPC/.claude/hooks/state/intrusiveness-history.jsonl"
_i=1
while [ "$_i" -le 35 ]; do
    printf '{"date":"2026-08-01","key":"k"}\n' > "$_TMPC/.claude/hooks/state/correction-fired-s${_i}.jsonl"
    _i=$((_i + 1))
done
_i=1
while [ "$_i" -le 12 ]; do
    printf '{"signal":"s"}\n' > "$_TMPC/.claude/hooks/state/blocker-fired-b${_i}.jsonl"
    _i=$((_i + 1))
done
printf -- '- \xe2\x98\x90 **D25** фикстура\n- \xe2\x98\x90 **D57** фикстура\n' > "$_TMPC/backlog-fixture.md"
HOME="$_TMPC" CLAUDSOUL_BACKLOG="$_TMPC/backlog-fixture.md" bash "$COLLECTOR" >/dev/null 2>"$_TMPC/collector.stderr"
_rc=$?
if [ "$_rc" -ne 0 ]; then FAIL=$((FAIL + 1)); FAILED_TESTS+=("C3/C4 fixture: collector died rc=$_rc: $(tail -c 200 "$_TMPC/collector.stderr" 2>/dev/null | tr '\n' ' ')"); fi
_OUT=$(cat "$_TMPC/.claude/hooks/state/metrics.md" 2>/dev/null)
assert_contains "C3 D25 имеет проверяющего" "$_OUT" "BACKLOG D25"
assert_contains "C4 D57 имеет проверяющего" "$_OUT" "BACKLOG D57"
rm -rf "$_TMPC"

# C5: отрицательный контроль — ниже порогов оба молчат.
_TMPD=$(mktemp -d)
mkdir -p "$_TMPD/.claude/hooks/state" "$_TMPD/.claude/global-lessons"
cp /dev/null "$_TMPD/.claude/global-lessons/.keep" 2>/dev/null || true
cat > "$_TMPD/.claude/global-lessons/principle-stub.md" <<'MD3'
---
name: stub
type: principle
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
stub
MD3
printf '%s\n' "$_COND_HIST" > "$_TMPD/.claude/hooks/state/intrusiveness-history.jsonl"
printf '{"date":"2026-08-01","key":"k"}\n' > "$_TMPD/.claude/hooks/state/correction-fired-one.jsonl"
printf '{"signal":"s"}\n' > "$_TMPD/.claude/hooks/state/blocker-fired-one.jsonl"
HOME="$_TMPD" bash "$COLLECTOR" >/dev/null 2>"$_TMPD/collector.stderr"
_rc=$?
if [ "$_rc" -ne 0 ]; then FAIL=$((FAIL + 1)); FAILED_TESTS+=("C5 fixture: collector died rc=$_rc: $(tail -c 200 "$_TMPD/collector.stderr" 2>/dev/null | tr '\n' ' ')"); fi
_OUT2=$(cat "$_TMPD/.claude/hooks/state/metrics.md" 2>/dev/null)
assert_not_contains "C5a D25 молчит ниже порога" "$_OUT2" "BACKLOG D25"
assert_not_contains "C5b D57 молчит ниже порога" "$_OUT2" "BACKLOG D57"
rm -rf "$_TMPD"

TOTAL=$((PASS + FAIL))
echo ""
echo "metrics-collector intrusiveness tests: $PASS/$TOTAL passed"


if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failures:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
exit 0
