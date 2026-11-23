#!/usr/bin/env bash
# СУДИТ: hooks/own-background-process-check.sh
# test_own_background_process_reported.sh — D1313: свой фоновый сервер на границе хода называется, чужое — нет.
#
# Что доказывается (нога на каждое условие предиката):
#   · ПОЛОЖИТЕЛЬНЫЙ контроль — задача (fd 1 на `tasks/<id>.output`, потомок корня) со слушающим портом
#     названа с номером задачи и портом; и когда слушает сама оболочка задачи, и когда её внук;
#   · без порта задача не называется (признак — сервер, а не «жива»), и исходящее соединение — не порт;
#   · слушающий потомок корня, чей вывод не файл задачи, не называется (так выглядят серверы MCP) —
#     отдельно «каталог не tasks» и «окончание не .output»;
#   · слушающий процесс вне дерева корня не называется (чужая сессия, отвязанный процесс);
#   · дроссель «задача» на сессию: повтор молчит, та же задача с новым портом молчит, новая задача
#     звучит, другая сессия звучит;
#   · сухой прогон краснеет кодом 1 при находке и зеленеет, когда серверы погашены;
#   · «не измерено» (нет корня, нет lsof) отличимо от «чисто»: в сухом прогоне код 2;
#   · корень находится подъёмом по предкам через `sh -c`, как в бою, — и когда `claude` первое слово
#     строки запуска, и когда второе; отметка дросселя не легла — молчание.
# Мутанты (15, все роняют свою ногу) — разбор при закрытии D1313 в BACKLOG.
#
# Процессы НАСТОЯЩИЕ: порт открывает ядро, fd 1 смотрит lsof, поэтому подмены `ps`/`lsof` здесь нет.
# Корень сессии — сам тест (`OWN_BG_ROOT_PID=$$`): его прямые потомки играют роль команд харнесса.
# Гасятся по PID (`$!`, `pkill -P`), а не по образцу текста: образец ловит и саму команду гашения
# (case-2026-11-14-trap-pkill-kills-foreground-command).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/own-background-process-check.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }
command -v lsof >/dev/null 2>&1 || { echo "SKIP: нет lsof"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_eq()           { if [ "$1" = "$2" ]; then ok; else bad "$3" "ожидалось «$2», получено «$1»"; fi; }
assert_contains()     { if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "«$2» нет в выводе: $1"; fi; }
assert_not_contains() { if grep -Fq -- "$2" <<< "$1"; then bad "$3" "«$2» не должно быть в выводе: $1"; else ok; fi; }
assert_empty()        { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась тишина, получено: $1"; fi; }

TMP=$(mktemp -d)
mkdir -p "$TMP/tasks" "$TMP/state"
SPAWNED=""
cleanup() {
    for p in $SPAWNED; do pkill -KILL -P "$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
    rm -rf "$TMP"
}
trap cleanup EXIT

cat > "$TMP/listen.py" <<'PY'
import socket, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(1)
print(s.getsockname()[1], flush=True)
time.sleep(120)
PY

# Результат через переменную, а не `$(spawn)`: подстановка — подоболочка, и процесс стал бы её
# потомком, а не потомком корня; SPAWNED в ней своя, и уборщик не увидел бы его.
LAST_PID=""
spawn_task() {   # spawn_task <файл вывода> <команда…> — прямой потомок теста, fd 1 на файле
    local out="$1"; shift
    "$@" > "$out" 2>&1 < /dev/null &
    LAST_PID=$!
    SPAWNED="$SPAWNED $LAST_PID"
    disown "$LAST_PID" 2>/dev/null || true
}
port_of() {      # первая строка вывода — порт; ждём до 5 с
    local f="$1" i=0 p
    while [ "$i" -lt 100 ]; do
        p=$(head -1 "$f" 2>/dev/null)
        [ -n "$p" ] && { echo "$p"; return 0; }
        perl -e 'select(undef,undef,undef,0.05)' 2>/dev/null || sleep 1
        i=$((i + 1))
    done
    return 1
}
gone() {         # gone <pid> — дождаться смерти, до 5 с
    local i=0
    while kill -0 "$1" 2>/dev/null && [ "$i" -lt 100 ]; do
        perl -e 'select(undef,undef,undef,0.05)' 2>/dev/null || sleep 1
        i=$((i + 1))
    done
}

run_hook() {
    printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$1" \
        | OWN_BG_ROOT_PID=$$ STATE_DIR="$TMP/state" bash "$SCRIPT" 2>&1
}
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<< "$1" 2>/dev/null; }

# ── Мир ───────────────────────────────────────────────────────────────────────
spawn_task "$TMP/tasks/tsk1.output" python3 "$TMP/listen.py";                 T1=$LAST_PID
spawn_task "$TMP/tasks/tsk2.output" bash -c 'python3 "$1"; :' _ "$TMP/listen.py"; T2=$LAST_PID
spawn_task "$TMP/tasks/tsk3.output" sleep 120
# Слушающие потомки корня, чей вывод — НЕ файл задачи: два условия признака снимаются поодиночке
# (скептик D1313, M3) — каталог не `tasks`, и окончание не `.output`.
mkdir -p "$TMP/notask"
spawn_task "$TMP/notask/x.output"   python3 "$TMP/listen.py"
spawn_task "$TMP/tasks/x.log"       python3 "$TMP/listen.py"
( python3 "$TMP/listen.py" > "$TMP/tasks/tsk9.output" 2>&1 < /dev/null & echo $! > "$TMP/foreign.pid" )
SPAWNED="$SPAWNED $(cat "$TMP/foreign.pid")"

P1=$(port_of "$TMP/tasks/tsk1.output") || { echo "FAIL: tsk1 не открыл порт"; exit 1; }
P2=$(port_of "$TMP/tasks/tsk2.output") || { echo "FAIL: tsk2 не открыл порт"; exit 1; }
P4=$(port_of "$TMP/notask/x.output")   || { echo "FAIL: notask не открыл порт"; exit 1; }
P4B=$(port_of "$TMP/tasks/x.log")      || { echo "FAIL: x.log не открыл порт"; exit 1; }
P9=$(port_of "$TMP/tasks/tsk9.output") || { echo "FAIL: foreign не открыл порт"; exit 1; }

# Задача с ИСХОДЯЩИМ соединением и без прослушивания (прогон к базе на 5432): клиентский порт —
# не сервер (скептик D1313, M3: без `-sTCP:LISTEN` его эфемерный порт назывался бы).
cat > "$TMP/connect.py" <<'PY'
import socket, sys, time
c = socket.create_connection(("127.0.0.1", int(sys.argv[1])))
print("connected", flush=True)
time.sleep(120)
PY
spawn_task "$TMP/tasks/tsk8.output" python3 "$TMP/connect.py" "$P4"
port_of "$TMP/tasks/tsk8.output" >/dev/null || { echo "FAIL: tsk8 не соединился"; exit 1; }

# ── 1. Находка и границы признака ─────────────────────────────────────────────
OUT=$(run_hook sid-A)
CTX=$(ctx "$OUT")
assert_eq "$(jq -r '.hookSpecificOutput.hookEventName // empty' <<< "$OUT" 2>/dev/null)" "Stop" "T1 событие Stop"
assert_contains     "$CTX" "задача tsk1 · порт :$P1" "T2 слушает оболочка задачи"
assert_contains     "$CTX" "задача tsk2 · порт :$P2" "T3 слушает внук задачи"
assert_not_contains "$CTX" "tsk3"                     "T4 задача без порта"
assert_not_contains "$CTX" ":$P4"                     "T5 вывод не в каталоге tasks"
assert_not_contains "$CTX" ":$P4B"                    "T5b вывод не .output"
assert_not_contains "$CTX" ":$P9"                     "T6 процесс вне дерева корня"
assert_not_contains "$CTX" "tsk8"                     "T21 исходящее соединение — не сервер"

# ── 2. Дроссель ───────────────────────────────────────────────────────────────
assert_empty "$(run_hook sid-A)" "T7 повтор в той же сессии молчит"
assert_contains "$(ctx "$(run_hook sid-B)")" "задача tsk1" "T8 другая сессия звучит"

spawn_task "$TMP/tasks/tsk5.output" python3 "$TMP/listen.py"; T5=$LAST_PID
P5=$(port_of "$TMP/tasks/tsk5.output") || { echo "FAIL: tsk5 не открыл порт"; exit 1; }
CTX=$(ctx "$(run_hook sid-A)")
assert_contains     "$CTX" "задача tsk5 · порт :$P5" "T9 новая задача звучит"
assert_not_contains "$CTX" "tsk1"                     "T10 названная молчит"

# Та же задача, новый порт — набор, чьи тесты слушают порт 0 (скептик D1313, H1): ключ дросселя —
# задача, а не «задача:порт», иначе ход продолжался бы заново на каждой границе до конца прогона.
kill -KILL "$T5" 2>/dev/null; gone "$T5"
spawn_task "$TMP/tasks/tsk5.output" python3 "$TMP/listen.py"; T5=$LAST_PID
P5B=$(port_of "$TMP/tasks/tsk5.output") || { echo "FAIL: tsk5 не открыл второй порт"; exit 1; }
[ "$P5B" != "$P5" ] || { echo "FAIL: второй порт совпал с первым"; exit 1; }
assert_empty "$(run_hook sid-A)" "T20 та же задача, новый порт — молчит"

# ── 3. Сухой прогон краснеет и зеленеет ───────────────────────────────────────
DRY=$(OWN_BG_ROOT_PID=$$ bash "$SCRIPT" --dry-run 2>&1); RC=$?
assert_eq "$RC" "1" "T11 сухой прогон с находкой — код 1"
assert_contains "$DRY" "задача tsk1" "T12 сухой прогон называет без дросселя"

pkill -KILL -P "$T2" 2>/dev/null
kill -KILL "$T1" "$T2" "$T5" 2>/dev/null
gone "$T1"; gone "$T2"; gone "$T5"
DRY=$(OWN_BG_ROOT_PID=$$ bash "$SCRIPT" --dry-run 2>&1); RC=$?
assert_eq "$RC" "0" "T13 серверы погашены — код 0 ($DRY)"
assert_empty "$(run_hook sid-C)" "T14 серверы погашены — хук молчит"

# ── 4. «Не измерено» отлично от «чисто» ───────────────────────────────────────
true & DEAD=$!; wait "$DEAD" 2>/dev/null
DRY=$(OWN_BG_ROOT_PID=$DEAD bash "$SCRIPT" --dry-run 2>&1); RC=$?
assert_eq "$RC" "2" "T15 корня нет — код 2"
assert_contains "$DRY" "НЕ ИЗМЕРЕНО" "T15b корня нет — названо"
OUT=$(printf '{"session_id":"sid-D"}' | OWN_BG_ROOT_PID=$DEAD STATE_DIR="$TMP/state" bash "$SCRIPT" 2>&1); RC=$?
assert_eq "$RC:$OUT" "0:" "T16 корня нет — хук молчит с кодом 0"
DRY=$(OWN_BG_ROOT_PID=$$ OWN_BG_LSOF=/nonexistent/lsof bash "$SCRIPT" --dry-run 2>&1); RC=$?
assert_eq "$RC" "2" "T17 нет lsof — код 2"

# ── 5. Корень находится по предкам, как в бою: claude → sh -c → bash хук ─────
# Подставной `claude` — сценарий, запущенный `bash …/claude` (так выглядит и `node …/claude`):
# имя корня стоит вторым словом строки запуска. Он поднимает задачу-сервер и зовёт хук через `sh -c`.
mkdir -p "$TMP/bin" "$TMP/root/tasks"
cat > "$TMP/bin/claude" <<'ROOT'
python3 "$1" > "$2/tasks/tskroot.output" 2>&1 < /dev/null &
srv=$!
i=0; while [ ! -s "$2/tasks/tskroot.output" ] && [ "$i" -lt 100 ]; do perl -e 'select(undef,undef,undef,0.05)' 2>/dev/null || sleep 1; i=$((i + 1)); done
printf '{"session_id":"sid-root"}' | STATE_DIR="$2/state" sh -c "bash '$3'"
kill -KILL "$srv" 2>/dev/null
ROOT
OUT=$(bash "$TMP/bin/claude" "$TMP/listen.py" "$TMP/root" "$SCRIPT" 2>&1)
assert_contains "$(ctx "$OUT")" "задача tskroot · порт :$(head -1 "$TMP/root/tasks/tskroot.output")" "T18 корень найден по предкам"
# Боевая форма корня — `claude` ПЕРВЫМ словом (`…/native-binary/claude --output-format …`; скептик D1313, M3:
# без этой ноги снятая проверка первого слова оставляла свидетеля зелёным, а хук в бою — немым).
# Ссылка с именем `claude` на bash, сценарий — под другим именем, чтобы второе слово `claude` не было.
mkdir -p "$TMP/bin2" "$TMP/root2/tasks"
ln -s "$(command -v bash)" "$TMP/bin2/claude"
cp "$TMP/bin/claude" "$TMP/root.sh"
OUT=$("$TMP/bin2/claude" "$TMP/root.sh" "$TMP/listen.py" "$TMP/root2" "$SCRIPT" 2>&1)
assert_contains "$(ctx "$OUT")" "задача tskroot · порт :$(head -1 "$TMP/root2/tasks/tskroot.output")" "T18b корень — первое слово"

# ── 6. Отметка дросселя не легла — хук молчит, а не зовёт ход без конца ────────
spawn_task "$TMP/tasks/tsk6.output" python3 "$TMP/listen.py"; T6=$LAST_PID
port_of "$TMP/tasks/tsk6.output" >/dev/null || { echo "FAIL: tsk6 не открыл порт"; exit 1; }
mkdir -p "$TMP/ro"; chmod 555 "$TMP/ro"
if [ -w "$TMP/ro" ]; then echo "SKIP T19: каталог только для чтения пишется (root)"
else
    OUT=$(printf '{"session_id":"sid-ro"}' | OWN_BG_ROOT_PID=$$ STATE_DIR="$TMP/ro" bash "$SCRIPT" 2>/dev/null)
    assert_empty "$OUT" "T19 дроссель не пишется — молчание"
fi
chmod 755 "$TMP/ro"
kill -KILL "$T6" 2>/dev/null

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: $PASS"
    exit 0
fi
echo "FAIL: $FAIL (PASS: $PASS)"
exit 1
