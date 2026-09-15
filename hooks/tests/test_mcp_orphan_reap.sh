#!/usr/bin/env bash
# test_mcp_orphan_reap.sh — уборщик осиротевших серверов MCP: обе ноги.
#
# Что доказывается:
#   · ПОЛОЖИТЕЛЬНЫЙ контроль — сирота (ppid 1) снимается;
#   · ОТРИЦАТЕЛЬНЫЙ контроль — сервер с живым родителем остаётся жив, каким бы старым он
#     ни выглядел (в выборке ему подставлен родитель-процесс самого теста);
#   · сухой прогон не убивает никого и краснеет кодом возврата, когда сироты есть;
#   · разница называется числом в отчёте;
#   · настоящие серверы машины не задеты — их число до и после совпадает.
#
# Устройство пробы: `ps` подменяется через PATH и отдаёт ВЫДУМАННУЮ таблицу, поэтому
# механизм видит только подставные процессы. Сами подставные процессы НАСТОЯЩИЕ (`sleep`),
# поэтому «убит» и «жив» проверяются ядром (`kill -0`), а не журналом-подделкой. Жульничество
# «убить всё, что вернул ps» валится на отрицательной ноге.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/mcp-orphan-reap.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

assert_dead() {
    if kill -0 "$1" 2>/dev/null; then bad "$2" "процесс $1 должен был быть снят, но жив"
    else ok; fi
}
assert_alive() {
    if kill -0 "$1" 2>/dev/null; then ok
    else bad "$2" "процесс $1 должен был остаться жив, но снят"; fi
}
# ОКНО ОЖИДАНИЯ БЕРЁТСЯ ИЗ МИРА, А НЕ ИЗ ГОЛОВЫ (D342, 14 сентября 2026).
# Утверждение об ОТСУТСТВИИ перемены после константной паузы доказывает ровно ничего:
# сухой прогон, не успевший убить, даёт тот же зелёный, что и верный. Здесь измеряется
# задержка НАСТОЯЩЕГО снятия (`wait_dead` на положительном контроле), и окно «жив»
# берётся кратным ей — тогда «не умер» означает «не умер бы и при большем сроке».
# Найдено замером устройства «проверка предполагает ВРЕМЯ»: носители — строки этого файла.
KILL_MS=0
wait_dead() {   # wait_dead <pid> <предел мс> → эхо затраченных мс; 0 если не умер
    local pid="$1" limit="$2" spent=0
    while kill -0 "$pid" 2>/dev/null; do
        [ "$spent" -ge "$limit" ] && { echo 0; return 1; }
        perl -e 'select(undef,undef,undef,0.02)' 2>/dev/null || sleep 1
        spent=$((spent + 20))
    done
    echo "$spent"
}
stays_alive() {  # stays_alive <pid> <имя> — жив ВЕСЬ измеренный срок, а не «на момент взгляда»
    local pid="$1" name="$2" win=$(( KILL_MS * 3 )); [ "$win" -lt 300 ] && win=300
    if wait_dead "$pid" "$win" >/dev/null 2>&1; then
        bad "$name" "процесс $pid снят за ${win} мс — а не должен был"
    else ok; fi
}
assert_contains() {
    if grep -Fq "$2" <<< "$1"; then ok
    else bad "$3" "'$2' нет в выводе: $1"; fi
}

TMP=$(mktemp -d)
SPAWNED=""
cleanup() {
    for p in $SPAWNED; do kill -KILL "$p" 2>/dev/null || true; done
    rm -rf "$TMP"
}
trap cleanup EXIT

# Подменённый `ps`: сколько бы аргументов ему ни дали, отдаёт фикстуру.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ps" <<'STUB'
#!/bin/sh
cat "$PS_FIXTURE"
STUB
chmod +x "$TMP/bin/ps"

# Настоящие процессы-мишени. Их argv («sleep») с признаком не совпадает — значит даже
# промах мимо подменённого `ps` не даст механизму найти их случайно: он найдёт их только
# по подставленной таблице, как и задумано.
# Два подводных камня, оба уже сработали:
#  · потоки фонового задания закрываются явно — иначе подстановка ждёт закрытия stdout,
#    который унаследовал `sleep`, и виснет на всю его жизнь;
#  · результат отдаётся через переменную, а НЕ через `$(spawn)`: подстановка — подоболочка,
#    и `SPAWNED` в ней своя, так что уборщик по trap получал пустой список, а процессы
#    оставались жить на машине (замер: 21 утёкший `sleep` за прогон мутаций).
LAST_PID=""
# `disown` — чтобы оболочка не печатала «Terminated»/«Killed» в stderr, когда мишень
# снимают: в сводном журнале прогона такие строки читаются как падение теста.
spawn() {
    sleep 60 >/dev/null 2>&1 &
    LAST_PID=$!
    SPAWNED="$SPAWNED $LAST_PID"
    disown "$LAST_PID" 2>/dev/null || true
}

# Настоящих серверов машины механизм касаться не должен вовсе.
real_before=$(/bin/ps -eo args= 2>/dev/null | grep -c 'mcp-server/server\.py' || true)

run_reap() {
    PS_FIXTURE="$TMP/fixture.txt" PATH="$TMP/bin:$PATH" \
        bash "$SCRIPT" "$@" < /dev/null 2>&1
}

# ── 1. Сирота снимается, живой цел ────────────────────────────────────────────
spawn; ORPHAN=$LAST_PID
spawn; LIVE=$LAST_PID
cat > "$TMP/fixture.txt" <<EOF
$ORPHAN 1 /opt/venv/bin/python /repo/mcp-server/server.py
$LIVE $$ /opt/venv/bin/python /repo/mcp-server/server.py
EOF

OUT=$(run_reap)
# Задержка снятия ИЗМЕРЯЕТСЯ здесь и служит мерой окна для утверждений «жив» ниже.
KILL_MS=$(wait_dead "$ORPHAN" 2000) || KILL_MS=0
assert_dead  "$ORPHAN" "положительный контроль"
assert_alive "$LIVE"   "отрицательный контроль"
assert_contains "$OUT" "серверов MCP: 2" "отчёт: всего"
assert_contains "$OUT" "сирот: 1"        "отчёт: сирот"
assert_contains "$OUT" "снято: 1"        "отчёт: снято"
assert_contains "$OUT" "живых владельцев: 1" "отчёт: владельцы"

# ── 2. Сухой прогон никого не трогает и краснеет ──────────────────────────────
spawn; ORPHAN2=$LAST_PID
cat > "$TMP/fixture.txt" <<EOF
$ORPHAN2 1 /opt/venv/bin/python /repo/mcp-server/server.py
EOF
OUT=$(run_reap --dry-run); RC=$?
stays_alive "$ORPHAN2" "сухой прогон не убивает"
assert_contains "$OUT" "снято: 0" "сухой прогон: ничего не снято"
if [ "$RC" -eq 1 ]; then ok; else bad "сухой прогон краснеет" "ожидался код 1, получен $RC"; fi

# ── 3. Чужой процесс с тем же ppid 1, но без признака — не наш ────────────────
spawn; ALIEN=$LAST_PID
cat > "$TMP/fixture.txt" <<EOF
$ALIEN 1 /usr/bin/python /somewhere/other-server.py
EOF
OUT=$(run_reap --dry-run)
stays_alive "$ALIEN" "чужой процесс не наш"
assert_contains "$OUT" "серверов MCP: 0" "чужой не попал в счёт"

# Режим хука при чистом мире молчит: строка в конце КАЖДОЙ сессии — свой failure mode.
OUT=$(run_reap)
if [ -z "$OUT" ]; then ok; else bad "хук молчит, когда убирать нечего" "ожидалась тишина, получено: $OUT"; fi

# ── 4. Отказ прибора отличим от «сирот нет» (род B) ───────────────────────────
spawn; SURVIVOR=$LAST_PID
: > "$TMP/fixture.txt"          # ps отдал пустую таблицу — так мир не выглядит никогда
OUT=$(run_reap --dry-run); RC=$?
assert_contains "$OUT" "НЕ ИЗМЕРЕНО" "отказ ps назван, а не сосчитан нулём"
if [ "$RC" -eq 2 ]; then ok; else bad "отказ ps краснеет иначе" "ожидался код 2, получен $RC"; fi
assert_alive "$SURVIVOR" "при отказе прибора никого не трогаем"

# ── 5. Настоящие серверы машины не тронуты ────────────────────────────────────
real_after=$(/bin/ps -eo args= 2>/dev/null | grep -c 'mcp-server/server\.py' || true)
if [ "$real_before" = "$real_after" ]; then ok
else bad "настоящие серверы" "было $real_before, стало $real_after"; fi

echo "PASS: $PASS  FAIL: $FAIL"
exit $(( FAIL != 0 ))
