#!/usr/bin/env bash
# test_state_lock.sh — общее состояние переживает одновременных писателей (род H).
#
# Предмет — не библиотека сама по себе, а СВОЙСТВО МИРА: из N одновременных правок
# одного файла состояния в файле остаются все N. До 4 сентября 2026 общего помощника
# не существовало, каждый хук закрывал окно read→write по-своему, и оно не закрывалось
# ни у кого: восемь одновременных границ хода оставляли в журнале completion-gate 4-7
# записей из 8, тридцать — 20 из 30 (замер `hooks/tests/test_state_lock.sh` T6 на дереве
# до правки). Отсюда последний случай здесь: он бьёт по хуку, а не по библиотеке.
#
# Запуск: bash hooks/tests/test_state_lock.sh
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_LIB="$HOOKS_DIR/state-lock-lib.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
eq()   { if [ "$2" = "$3" ]; then ok; else bad "$1" "ожидалось «$3», получено «$2»"; fi; }

if [ ! -f "$LOCK_LIB" ]; then
    echo "FAIL [T0]: нет $LOCK_LIB — общего замка в дереве не существует"
    exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "нет jq"; exit 2; }
# shellcheck source=/dev/null
. "$LOCK_LIB"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
N=12

# --- T1: atomic_filter — из N одновременных инкрементов не теряется ни один ---------
F="$TMP/counter.json"
printf '{"n":0}\n' > "$F"
pids=""
for _ in $(seq 1 "$N"); do
    ( . "$LOCK_LIB"; atomic_filter "$F" jq '.n += 1' ) & pids="$pids $!"
done
for p in $pids; do wait "$p"; done
eq T1 "$(jq -r '.n' "$F" 2>/dev/null)" "$N"

# --- T2: write_if_changed — «изменил» говорит РОВНО ОДИН из N -----------------------
# Без замка сравнение и запись расходятся: все N читают старое значение, все N считают
# изменившими себя, и сообщение хука уходит N раз на одну и ту же серию провалов.
FLAGF="$TMP/flag"
printf 'старое' > "$FLAGF"
CNT="$TMP/changed"; : > "$CNT"
pids=""
for _ in $(seq 1 "$N"); do
    ( . "$LOCK_LIB"; write_if_changed "$FLAGF" "новое" && printf 'x' >> "$CNT" ) & pids="$pids $!"
done
for p in $pids; do wait "$p"; done
eq T2 "$(wc -c < "$CNT" | tr -d ' ')" "1"
eq T2b "$(cat "$FLAGF")" "новое"

# --- T3: drain_file — забирает всё и опустошает -------------------------------------
Q="$TMP/queue.txt"
printf 'первая\nвторая\n' > "$Q"
OUT=$(drain_file "$Q")
eq T3 "$OUT" "$(printf 'первая\nвторая')"
if [ -s "$Q" ]; then bad T3b "очередь не опустела: $(cat "$Q")"; else ok; fi
eq T3c "$(drain_file "$Q")" ""

# --- T4: чужой замок не снимается ---------------------------------------------------
# Ход, не получивший замок по таймауту, обязан уйти НЕ ТРОНУВ чужого: иначе окно
# становится шире, чем без замка вовсе.
G="$TMP/foreign"
: > "$G"
mkdir "$G.lock"
if CLAUDSOUL_LOCK_TRIES=2 CLAUDSOUL_LOCK_NAP=0.01 lock_acquire "$G"; then
    bad T4 "замок взят, хотя он занят"
else ok; fi
lock_release "$G"
if [ -d "$G.lock" ]; then ok; else bad T4b "чужой замок снят"; fi
rmdir "$G.lock"

# --- T5: брошенный замок срывается --------------------------------------------------
# Упавший хук не должен запирать файл навсегда.
S="$TMP/stale"
: > "$S"
mkdir "$S.lock"
touch -t 200001010000 "$S.lock" 2>/dev/null
if CLAUDSOUL_LOCK_TRIES=5 CLAUDSOUL_LOCK_NAP=0.01 lock_acquire "$S"; then ok
else bad T5 "брошенный замок не сорван"; fi
lock_release "$S"

# --- T6: журнал completion-gate переживает N одновременных границ хода ---------------
# Проявление рода, замеренное на живом хуке. У каждого прогона свой бэклог, значит своя
# запись в ОБЩЕМ журнале; потеря видна разницей чисел, а не рассуждением.
HOOK="$HOOKS_DIR/completion-gate.sh"
if [ -f "$HOOK" ] && command -v python3 >/dev/null 2>&1; then
    CGT="$TMP/cg"; mkdir -p "$CGT/state"
    for i in $(seq 1 8); do
        mkdir -p "$CGT/b$i"
        cat > "$CGT/b$i/BACKLOG.md" <<EOF2
# BACKLOG

### D6${i}0 ☐ пункт номер $i
**Проверка.** \`true\` → 0
EOF2
    done
    pids=""
    for i in $(seq 1 8); do
        ( printf '{"session_id":"cgrace","cwd":"/"}' \
          | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$CGT/b$i/BACKLOG.md" CG_LOCAL_BACKLOG="" \
            STATE_DIR="$CGT/state" bash "$HOOK" >/dev/null 2>&1 ) & pids="$pids $!"
    done
    for p in $pids; do wait "$p"; done
    GOT=$(grep -c '"item"' "$CGT/state/cg-open-fired.jsonl" 2>/dev/null || true)
    eq T6 "${GOT:-0}" "8"
else
    echo "SKIP [T6]: нет completion-gate.sh или python3"
fi

# --- T7: knowledge-link-symmetry берёт замок НА РОДИТЕЛЯ ------------------------------
# Прямой замер потерь здесь мигает (окно read→write в питоне — микросекунды, и на восьми
# ходах расходится не каждый раз), поэтому проверяется не потеря, а сам замок: пока
# чужой замок держат, хук обязан ЖДАТЬ, а не писать. Без замка он дописывает встречную
# ссылку сразу, и проверка «через секунду ещё не дописал» краснеет.
#
# ЗАМОК ПОФАЙЛОВЫЙ с 5 сентября 2026, и держится этот выбор так же, как проверялся. Прежде
# хук брал КАТАЛОЖНЫЙ (`with_lock "$LESSONS"`), и эта нога держала именно его. Взаимное
# исключение живёт на общем ИМЕНИ: `global-lessons.lock` и `<файл>.lock` — разные каталоги
# и друг друга не блокируют. У базы знаний имён было три (каталог здесь, файл у
# `knowledge-audit-digest.sh` через `atomic_filter`, никакого у `knowledge-counter-bump.sh`),
# то есть защита была мнимой, а каждая сторона считала себя защищённой. Сведено к `<файл>.lock`.
KLS="$HOOKS_DIR/knowledge-link-symmetry.sh"
if [ -f "$KLS" ] && command -v python3 >/dev/null 2>&1; then
    L="$TMP/lessons"; mkdir -p "$L"
    # Фикстура несёт frontmatter, как всякий родитель в мире (в рабочей базе таких 50 из
    # 50): хук ищет место вставки ВНУТРИ frontmatter, потому что строка `source_cases:`
    # встречается и в прозе знания, которое объясняет само поле.
    printf -- '---\nconfidence: 3\nsource_cases:\nrelated: []\n---\n\n# P\n' > "$L/pattern-target.md"
    printf -- '---\nedges:\n  - specializes: pattern-target.md\nrelated: []\n---\n' > "$L/case-x1.md"
    mkdir "$L/pattern-target.md.lock"      # замок на РОДИТЕЛЯ, а не на каталог
    ( printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$L/case-x1.md" \
      | env LESSONS_DIR="$L" CLAUDSOUL_LOCK_TRIES=3000 CLAUDSOUL_LOCK_NAP=0.02 \
        bash "$KLS" >/dev/null 2>&1 ) &
    KLS_PID=$!
    sleep 1
    if grep -q 'case-x1' "$L/pattern-target.md"; then
        bad T7 "хук дописал ссылку, хотя замок РОДИТЕЛЯ занят — замка он не берёт"
    else ok; fi
    rmdir "$L/pattern-target.md.lock"
    wait "$KLS_PID" 2>/dev/null || true
    if grep -q 'case-x1' "$L/pattern-target.md"; then ok
    else bad T7b "замок отпущен, а встречная ссылка так и не дописана"; fi
    if [ -d "$L/pattern-target.md.lock" ]; then bad T7c "замок остался висеть после хука"; else ok; fi
else
    echo "SKIP [T7]: нет knowledge-link-symmetry.sh или python3"
fi

# --- T8: писатели BACKLOG.md БЕРУТ замок (род H, 5 сентября 2026) ----------------------
# Форма проверки взята у T7, а не выдумана заново, и вот почему. Первая редакция мерила
# ПОТЕРЮ: восемь одновременных пересчётов показаний на фикстуре из восьми пунктов. Мутация
# её отвергла — без замка нога зелена трижды подряд: окно read→write в питоне длится
# микросекунды, и на восьми ходах писатели расходятся во времени сами. Тот же предел уже
# назван у T7 в этом файле. Поэтому проверяется не исчезновение потери, а НАЛИЧИЕ замка:
# пока чужой замок на BACKLOG.md держат, писатель обязан ЖДАТЬ, а не править файл.
#
# Писателей у долга трое: `scripts/backlog-archive.sh`, `scripts/backlog-refresh-readings.sh`
# и `hooks/completion-gate.sh`; первые двое зовутся из `session-collector` на границе хода и
# при параллельных сессиях сходятся во времени.
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
REFRESH="$REPO_ROOT/scripts/backlog-refresh-readings.sh"
if [ -f "$REFRESH" ] && command -v python3 >/dev/null 2>&1; then
    BT="$TMP/backlog"; mkdir -p "$BT"
    {
      printf '# BACKLOG\n\n'
      printf -- '- ☐ **D910** пункт под замком\n'
      printf -- '  **Показание.** `printf 7`\n'
      printf -- '  **Последнее показание (2026-01-01).** 0\n'
    } > "$BT/BACKLOG.md"
    BEFORE=$(cksum < "$BT/BACKLOG.md")
    mkdir -p "$BT/BACKLOG.md.lock"          # чужой замок, ещё не брошенный
    ( BACKLOG_FILE="$BT/BACKLOG.md" CLAUDSOUL_REPO="$REPO_ROOT" bash "$REFRESH" run >/dev/null 2>&1 ) &
    RPID=$!
    sleep 1                                  # меньше таймаута замка (по умолчанию 2 с)
    DURING=$(cksum < "$BT/BACKLOG.md")
    if [ "$BEFORE" = "$DURING" ]; then ok T8; else
        bad T8 "писал при чужом замке — замок не взят"
    fi
    rmdir "$BT/BACKLOG.md.lock" 2>/dev/null || true
    wait "$RPID" 2>/dev/null || true
else
    echo "SKIP [T8]: нет backlog-refresh-readings.sh или python3"
fi

echo ""
echo "=== state-lock tests ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit $(( FAIL != 0 ))
