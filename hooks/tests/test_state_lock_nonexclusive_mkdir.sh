#!/usr/bin/env bash
# СУДИТ: hooks/state-lock-lib.sh
# test_state_lock_nonexclusive_mkdir.sh — замок состояния исключает, даже когда `mkdir` отвечает успехом обоим
# соперникам (D1320).
#
# Результат: два одновременных `lock_acquire` одного файла не бывают в замке вместе — ни при захвате, ни при срыве
#            брошенного замка, — когда `mkdir` неисключителен; оба захвата в итоге проходят (тупика нет).
# Проверка результата: этот тест.
#
# Повод (18 ноября 2026, разбор D1316). `mkdir (uutils coreutils) 0.10.0` — coreutils раннера `ubuntu-26.04` — сначала
# проверяет, есть ли каталог, а создаёт его способом, терпящим готовый: два одновременных `mkdir` оба дают 0 (175 пар из
# 200 в контейнере `ubuntu:26.04`). На macOS и с GNU `mkdir` исключителен, поэтому дефект здесь воспроизводит подделка
# того же устройства, первой в PATH; нога P0 доказывает, что подделка неисключительна, — без неё зелёные L1 и L2 значили
# бы только «гонки не было».
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/state-lock-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd) || exit 1
BIN="$TMP/bin"; mkdir -p "$BIN"
REAL_MKDIR=$(command -v mkdir)
# Подделка в духе uutils: «есть ли» до создания, между ними окно, а «уже есть» при создании терпится. Родителя она не
# создаёт, как и uutils (`mkdir /нет/sub` — код 1): первая редакция брала `-p` и воскрешала снесённый срывом каталог
# замка без владельца — тупик на 30 с, которого в мире нет.
cat > "$BIN/mkdir" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in -*) ;; *) t="\$a" ;; esac; done
[ -e "\$t" ] && exit 1
sleep 0.05
"$REAL_MKDIR" "\$t" 2>/dev/null || [ -d "\$t" ]; rc=\$?
[ -n "\${SLOW:-}" ] && sleep 0.3   # вытеснение после возврата — у помеченного соперника (L5)
exit \$rc
EOF
chmod +x "$BIN/mkdir"

# --- P0: подделка неисключительна — оба одновременных вызова дают 0 хотя бы в одной паре из десяти -------------------
both=0
for i in $(seq 1 10); do
    rm -rf "$TMP/p0"
    ( PATH="$BIN:$PATH" mkdir "$TMP/p0" 2>/dev/null && echo a ) > "$TMP/pa" &
    ( PATH="$BIN:$PATH" mkdir "$TMP/p0" 2>/dev/null && echo b ) > "$TMP/pb" &
    wait
    [ "$(cat "$TMP/pa" "$TMP/pb" | wc -l | tr -d ' ')" = 2 ] && both=$((both + 1))
done
[ "$both" -gt 0 ] && ok || bad P0 "подделка mkdir исключительна (0 пар из 10) — гонку не воспроизвести, L1 и L2 не свидетельства"

# _holder <цель> <метка> — взять замок, побыть внутри 0,2 с, отпустить; пересечение пишется в $TMP/overlap.
_holder() {
    PATH="$BIN:$PATH" bash -c '
        . "$1" || exit 3
        T="$2"
        lock_acquire "$T" || { echo "не взят" >> "$3/notgot"; exit 0; }
        [ -e "$T.inside" ] && echo "$4" >> "$3/overlap"
        : > "$T.inside"; sleep 0.2; rm -f "$T.inside"
        lock_release "$T"' _ "$LIB" "$1" "$TMP" "$2"
}

# --- L1: захват — пары одновременных lock_acquire не бывают внутри вместе --------------------------------------------
: > "$TMP/overlap"; : > "$TMP/notgot"
for i in $(seq 1 10); do
    T="$TMP/f1.$i"; : > "$T"
    _holder "$T" "L1.$i" & _holder "$T" "L1.$i" & wait
done
ov=$(sort -u "$TMP/overlap" | grep -c .); ng=$(grep -c . "$TMP/notgot")
[ "$ov" = 0 ] && ok || bad L1 "внутри замка вдвоём в $ov парах из 10: $(sort -u "$TMP/overlap" | tr '\n' ' ')"
[ "$ng" = 0 ] && ok || bad L1b "захват не прошёл $ng раз — тупик или потолок попыток"

# --- L2: срыв брошенного замка (владелец мёртв) — двое срывающих не бывают внутри вместе -----------------------------
: > "$TMP/overlap"; : > "$TMP/notgot"
dead=99999; while kill -0 "$dead" 2>/dev/null; do dead=$((dead + 1)); done
for i in $(seq 1 10); do
    T="$TMP/f2.$i"; : > "$T"; "$REAL_MKDIR" "$T.lock"; printf '%s брошен\n' "$dead" > "$T.lock/owner"
    _holder "$T" "L2.$i" & _holder "$T" "L2.$i" & wait
done
ov=$(sort -u "$TMP/overlap" | grep -c .); ng=$(grep -c . "$TMP/notgot")
[ "$ov" = 0 ] && ok || bad L2 "после срыва внутри вдвоём в $ov парах из 10: $(sort -u "$TMP/overlap" | tr '\n' ' ')"
[ "$ng" = 0 ] && ok || bad L2b "захват после срыва не прошёл $ng раз"

# --- L3, L4: питоновская половина (`hooks/lib/state_lock.py`) — тот же протокол ---------------------------------------
# Питон берёт каталог `os.mkdir` (исключительно против питона), но соперник-оболочка на uutils «создаёт» его в то же окно.
# Подменённый `os.mkdir` разыгрывает это окно: создаёт каталог и тут же кладёт то, что успел бы положить соперник.
# L3 — соперник взял `owner` (живой — этот тест): питон не берёт замок и владельца не стирает.
# L4 — замок брошен (владелец мёртв), соперник взял право на срыв `.break/by`: питон замок не сносит.
PYLIB="$HOOKS_DIR/lib/state_lock.py"
if [ -f "$PYLIB" ] && command -v python3 >/dev/null 2>&1; then
    _py() {  # <режим> <цель> → строка «взят|не взят <строка владельца>»
        CLAUDSOUL_LOCK_TRIES=5 CLAUDSOUL_LOCK_NAP=0.01 python3 - "$HOOKS_DIR/lib" "$1" "$2" "$$" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import state_lock
mode, T, rival = sys.argv[2], sys.argv[3], sys.argv[4]
d = T + ".lock"
real = os.mkdir
def racy(p, *a, **k):
    real(p, *a, **k)
    if mode == "owner" and p == d:
        with open(os.path.join(d, "owner"), "x") as f:
            f.write(f"{rival} соперник\n")
    if mode == "break" and p == os.path.join(d, ".break"):
        open(os.path.join(p, "by"), "x").close()
os.mkdir = racy
got = state_lock.lock_acquire(T)
try:
    own = open(os.path.join(d, "owner")).readline().strip()
except OSError:
    own = "-"
print(("взят" if got else "не взят") + " " + own)
PY
    }
    T="$TMP/f3"; : > "$T"
    out=$(_py owner "$T")
    case "$out" in "не взят $$ соперник") ok ;; *) bad L3 "питон взял замок, чей owner в то же окно создал соперник, либо стёр его: «${out}»" ;; esac
    T="$TMP/f4"; : > "$T"; "$REAL_MKDIR" "$T.lock"; printf '%s брошен\n' "$dead" > "$T.lock/owner"
    out=$(_py break "$T")
    case "$out" in "не взят $dead брошен") ok ;; *) bad L4 "питон снёс замок, право на срыв которого взял соперник: «${out}»" ;; esac
else
    bad L3 "нет $PYLIB или python3 — питоновская половина не проверена"
fi

# --- L5: соперник взял и отпустил замок в окне между нашим `mkdir` и созданием `owner` (скептик opus D1320, H1) ------
# B вытеснен на 0,3 с после «успешного» `mkdir`; C за это время берёт замок и отпускает — каталога больше нет; D приходит
# через 0,4 с. Прежде B, не создав `owner` в исчезнувшем каталоге, считал замок своим (фантом), и D был с ним внутри.
: > "$TMP/overlap"; : > "$TMP/phantom"
_h5() {  # <метка> <цель> <пауза до> <сколько внутри> [SLOW]
    SLOW="${5:-}" PATH="$BIN:$PATH" bash -c '
        . "$1" || exit 3; sleep "$4"; T="$3"
        lock_acquire "$T" || exit 0
        o=$(head -n 1 "$T.lock/owner" 2>/dev/null)
        [ "$o" = "$$ $_SL_TOKEN" ] || echo "$2 $([ -d "$T.lock" ] && echo с-каталогом || echo без-каталога)" >> "$6/phantom"
        ( set -C; : > "$T.inside" ) 2>/dev/null || echo "$2" >> "$6/overlap"
        sleep "$5"; rm -f "$T.inside"; lock_release "$T"' _ "$LIB" "$1" "$2" "$3" "$4" "$TMP"
}
for i in 1 2 3; do
    T="$TMP/f5.$i"; : > "$T"
    _h5 "B$i" "$T" 0 1.0 1 & _h5 "C$i" "$T" 0 0 & _h5 "D$i" "$T" 0.4 1.0 & wait
done
[ ! -s "$TMP/phantom" ] && ok || bad L5 "замок «взят» без своего owner: $(tr '\n' ' ' < "$TMP/phantom")"
[ ! -s "$TMP/overlap" ] && ok || bad L5b "внутри вдвоём: $(tr '\n' ' ' < "$TMP/overlap")"

# --- L6: питон — каталог исчез между `os.mkdir` и созданием `owner` (соперник взял и отпустил) --------------------------
if [ -f "$PYLIB" ] && command -v python3 >/dev/null 2>&1; then
    T="$TMP/f6"; : > "$T"
    out=$(CLAUDSOUL_LOCK_TRIES=5 CLAUDSOUL_LOCK_NAP=0.01 python3 - "$HOOKS_DIR/lib" "$T" <<'PY6'
import os, sys
sys.path.insert(0, sys.argv[1])
import state_lock
T = sys.argv[2]; d = T + ".lock"; real = os.mkdir; once = [True]
def racy(p, *a, **k):
    real(p, *a, **k)
    if p == d and once[0]:
        once[0] = False
        os.rmdir(d)  # соперник взял и уже отпустил
os.mkdir = racy
got = state_lock.lock_acquire(T)
own = ""
try:
    own = open(os.path.join(d, "owner")).readline().split()[-1]
except OSError:
    pass
print("взят" if got else "не взят", "свой" if own == state_lock._TOKEN else "не свой")
PY6
)
    [ "$out" = "взят свой" ] && ok || bad L6 "питон после исчезнувшего каталога: «${out}» (ждали «взят свой»)"
fi

echo "test_state_lock_nonexclusive_mkdir: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
