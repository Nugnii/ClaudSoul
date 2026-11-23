#!/usr/bin/env bash
# СУДИТ: hooks/lib/transcript_window.py hooks/hook-input-lib.sh
# test_adv_fold3_catchup_stale_base.sh — противник свёртки, раунд 3 (D498): догон снимка у свёртки ХОДА обновляет начало хода, но не начало чтения — шаг получает строки ПРОШЛОГО хода, и накопленное с ними записывается под новым началом.
#
# Устройство (transcript_window.py, fold): `base` берётся равным начальному `origin` ДО чтения
# состояния. Состояние соседа «впереди» моего снимка → снимок догоняется вторым turn_offset,
# и `origin, end` меняются. Если за это время пришла новая реплика владельца, начало хода
# сдвинулось, состояние соседа (записанное ещё про прошлый ход) не годится — свёртка холодная,
# но `base` так и остаётся прежним началом. Шаг получает [прежнее начало, конец): весь хвост
# прошлого хода, новую реплику и то, что после неё. Договор `transcript_fold ... turn`
# (hook-input-lib.sh, модуль transcript-window): «новая реплика начинает свёртку заново,
# поэтому шаг не обязан сам сбрасываться на ней» — нарушен; накопленное пишется с началом
# НОВОГО хода, и следующие тёплые вызовы строят на загрязнённом.
# rc_* не видят этого только потому, что RC_TURN_STEP сбрасывается сам; цена — перечитывание
# прошлого хода (тот же род, что класс 3: тёплый вызов платит не за дописанное).
# Чередование воспроизведено точкой вставки после первого turn_offset (вид файла вызова A уже
# снят): дописаны строки без реплики, сосед N свернул ход и записал состояние, затем пришла
# новая реплика R2 и строка после неё.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"   # временные файлы помощника — под каталогом теста
ST="$T/st"; COLD="$T/cold"; mkdir -p "$ST" "$COLD"
F="$T/t.jsonl"; LOG="$T/step.log"; STEP="$T/step.py"
case "$F|$ST|$COLD|$LOG|$STEP|$TMPDIR" in
    "$T"/*"|$T"/*"|$T"/*"|$T"/*"|$T"/*"|$T"/*) ;;
    *) echo "FAIL [K0]: путь записи вне каталога теста"; exit 1 ;;
esac

# Шаг: накопленное — число записей с "x": true; размер своего stdin пишет в журнал.
cat > "$STEP" <<'PY'
import json, sys
log, accp = sys.argv[1], sys.argv[2]
data = sys.stdin.buffer.read()
# Пустое накопленное — свёртка с нуля (0); отказ чтения роняет шаг, а не читается нулём (род B).
prev = int(open(accp).read().strip() or 0)
n = sum(1 for l in data.split(b"\n") if l.strip() and json.loads(l).get("x") is True)
with open(log, "a") as g:
    g.write(f"{len(data)}\n")
print(prev + n)
PY
U1='{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"первая реплика"}]}}'
U2='{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"вторая реплика"}]}}'
X='{"type":"assistant","x":true,"message":{"role":"assistant","content":[{"type":"text","text":"шаг"}]}}'

# Ход R1: реплика и пять записей шага.
{ printf '%s\n' "$U1"; for _ in 1 2 3 4 5; do printf '%s\n' "$X"; done; } > "$F"
python3 "$HOOKS/lib/transcript_window.py" "$F" --fold cnt --turn --state "$ST" -- python3 "$STEP" "$LOG" >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_fold3_catchup_stale_base.sh:$LINENO" >&2; exit 1; }
: > "$LOG"

# Вызов A: вид снят (ход R1), затем две записи без реплики → сосед N свернул и записал
# состояние (ход R1, конец дальше снимка A) → реплика R2 и одна запись после неё.
python3 - "$HOOKS/lib/transcript_window.py" "$F" "$ST" "$STEP" "$LOG" "$X" "$U2" <<'PY' > "$T/a.out"
import importlib.util, subprocess, sys
helper, path, st, step, log, x, u2 = sys.argv[1:8]
spec = importlib.util.spec_from_file_location("tw", helper)
tw = importlib.util.module_from_spec(spec); spec.loader.exec_module(tw)
real, fired = tw.turn_offset, [False]
def interleaved(p, s=None):
    view = real(p, s)
    if not fired[0]:
        fired[0] = True
        with open(p, "a", encoding="utf-8") as f:
            f.write(x + "\n" + x + "\n")                       # харнесс дописал (без реплики)
        subprocess.run([sys.executable, helper, p, "--fold", "cnt", "--turn", "--state", st, "--",
                        "python3", step, log], stdout=subprocess.DEVNULL, check=True)  # сосед N
        with open(p, "a", encoding="utf-8") as f:
            f.write(u2 + "\n" + x + "\n")                      # новая реплика владельца
    return view
tw.turn_offset = interleaved
sys.exit(tw.fold(path, st, "cnt", ["python3", step, log], turn=True))
PY
ARC=$?
A_OUT=$(sed -n 2p "$T/a.out")

# Контроль воспроизведения: A ответил свёрткой; сосед записал состояние про ход R1
# (начало хода — 0, первая реплика стоит первой строкой) с концом дальше снимка A.
[ "$ARC" -eq 0 ] && [ "$(head -1 "$T/a.out")" = ok ] && ok || bad K1 "вызов A не ответил свёрткой: код $ARC"
HEAD=$(head -1 "$ST"/transcript-fold-cnt-* 2>/dev/null)
NEXT_ORIGIN=$(python3 -c 'import sys; print(open(sys.argv[1],"rb").read().index(sys.argv[2].encode()))' "$F" "$U2")

# Эталон — холодная свёртка хода на итоговом файле: от реплики R2 одна запись шага.
cold() { python3 "$HOOKS/lib/transcript_window.py" "$F" --fold cnt --turn --state "$1" -- python3 "$STEP" "$T/cold.log" | sed -n 2p; }
C1=$(cold "$COLD")
[ "$C1" = 1 ] && ok || bad K2 "холодная свёртка хода R2 дала «${C1}», ожидалось 1 — тест не о том"

# Предмет 1: вывод A равен холодному (ход R2 — одна запись), а не счёту двух ходов.
[ "$A_OUT" = "$C1" ] && ok \
    || bad S1 "тёплый вызов A после догона снимка дал «${A_OUT}» вместо «${C1}»: шаг свернул и прошлый ход (с прежнего начала)"
# Предмет 2 (цена): A прочёл не больше хода R2 (две строки), а не хвост прошлого хода.
A_BYTES=$(tail -1 "$LOG")
R2_BYTES=$(( $(wc -c < "$F") - NEXT_ORIGIN ))
# Пустой журнал — замер не состоялся: краснеет, а не читается нулём (род B, сторож родов).
[ "$A_BYTES" -le "$R2_BYTES" ] 2>/dev/null && ok \
    || bad S2 "вызов A прочёл ${A_BYTES:-?} байт при ходе R2 в $R2_BYTES байт — перечитан прошлый ход"
# Предмет 3: загрязнение не исчезает — следующий обычный тёплый вызов через обёртку оболочки
# строит на записанном накопленном (состояние подписано началом хода R2).
printf '%s\n' "$X" >> "$F"
W2=$(STATE_DIR="$ST" bash -c '. "$1/hook-input-lib.sh"; transcript_fold "$2" cnt turn python3 "$3" "$4"' _ "$HOOKS" "$F" "$STEP" "$LOG")
C2=$(cold "$(mktemp -d "$T/cold2.XXXX")")
[ "$W2" = "$C2" ] && ok \
    || bad S3 "следующий тёплый вызов дал «${W2}» вместо холодного «${C2}»: накопленное прошлого хода записано под началом нового (состояние: $HEAD → $(head -1 "$ST"/transcript-fold-cnt-*))"

echo "test_adv_fold3_catchup_stale_base: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
