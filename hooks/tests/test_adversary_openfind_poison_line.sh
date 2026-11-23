#!/usr/bin/env bash
# СУДИТ: hooks/lib/open-findings-lib.sh
# test_adversary_openfind_poison_line.sh — АТАКА 2.
#
# Разбор строки в hooks/lib/open-findings-lib.sh:84-87:
#     o = json.loads(line)   # ValueError ловится
#     if o.get("signal") not in SIG:
# Ловится ТОЛЬКО ValueError. Строка `null`, `[1,2]`, `123`, `"строка"` — валидный JSON и
# НЕ объект: `.get` у них нет, летит AttributeError. Строка с `"signal": []` — объект, но
# элемент множества нехеширумый: летит TypeError. Оба исключения не ловятся ничем.
#
# Последствие двойное:
#   1) одна порченая строка в ОДНОМ журнале обнуляет счёт по ВСЕМ 43 журналам;
#   2) функция возвращает ненулевой код, а потребитель идёт под `set -e` — весь Stop-хук
#      умирает молча (проверяется плечом B4 сквозь настоящий session-collector.sh).
#
# Ожидание: порченая строка пропускается (как не-JSON) либо прибор кричит BROKEN.
# Факт: трассировка в stderr, пустой stdout, ненулевой код, тишина у потребителя.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/open-findings-lib.sh"
COLLECTOR="$REPO/hooks/session-collector.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)   # ничего не удаляем
# shellcheck source=/dev/null
. "$LIB"

GOOD='{"ts":"2026-09-01T10:00:00Z","key":"k1","signal":"discovery","outcome":"deferred","ref":""}'

# Каждое плечо: чистый журнал с ОДНОЙ настоящей записью + один порченый сосед.
# Ждём «1 0 <время>» — порченое пропущено, настоящее посчитано.
probe() {
    _name="$1"; _poison="$2"
    _d="$TMP/$_name"; mkdir -p "$_d"
    printf '%s\n' "$GOOD" > "$_d/outcome-good.jsonl"
    printf '%s\n' "$_poison" > "$_d/outcome-poison.jsonl"
    _out=$(of_open_counts "$_d" 2>/dev/null); _rc=$?
    _def=$(printf '%s' "$_out" | awk '{print $1}')
    if [ "$_rc" -eq 0 ] && [ "${_def:-}" = "1" ]; then
        ok
    else
        bad "$_name" "порченая строка [$_poison] обнулила прибор: вывод «${_out}», код $_rc (ждали «1 0 …»)"
    fi
}

probe json-null   'null'
probe json-array  '[1,2]'
probe json-number '123'
probe json-string '"строка"'
probe signal-list '{"ts":"2026-09-02T10:00:00Z","key":"k2","signal":["discovery"],"outcome":"deferred"}'

# B4. СКВОЗЬ ПОТРЕБИТЕЛЯ. Одна строка `null` в одном журнале — и Stop-хук не делает ничего.
if [ -f "$COLLECTOR" ] && command -v jq >/dev/null 2>&1; then
    H="$TMP/e2e"; S="$H/state"; mkdir -p "$S" "$H/home" "$H/hooks"
    cp "$REPO"/hooks/*.sh "$H/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_openfind_poison_line.sh:$LINENO" >&2; exit 1; }
    cp -R "$REPO/hooks/lib" "$H/hooks/lib" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_openfind_poison_line.sh:$LINENO" >&2; exit 1; }
    printf '%s\n' "$GOOD" > "$S/outcome-good.jsonl"
    # Бэклог песочницы (D1179, M1): унаследованный корень иначе приводит сборщик к чужому BACKLOG.md и его ☑.
    run_collector() {
        printf '{"session_id":"%s","transcript_path":"","cwd":"%s"}' "$1" "$H" \
            | env HOME="$H/home" STATE_DIR="$S" CLAUDSOUL_BACKLOG="$H/none.md" CLAUDE_CODE_SESSION_ID="$1" \
                  bash "$H/hooks/session-collector.sh" 2>&1
    }
    CTRL=$(run_collector advp0)
    if grep -qF "🔎" <<< "$CTRL"; then
        printf 'null\n' > "$S/outcome-poison.jsonl"
        OUT=$(run_collector advp1); RC=$?
        [ "$RC" -eq 0 ] && ok || bad B4a "одна строка «null» убила Stop-хук: код $RC"
        [ -n "$OUT" ] && ok || bad B4b "одна строка «null» — и свод, очередь алертов и чистка состояния не выполнены"
    else
        echo "SKIP e2e: песочница не даёт свода при исправном приборе (вывод «${CTRL}»)"
    fi
fi

echo "adversary openfind poison-line: $PASS passed, $FAIL failed (песочница: $TMP)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
