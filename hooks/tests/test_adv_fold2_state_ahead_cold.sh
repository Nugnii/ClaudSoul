#!/usr/bin/env bash
# СУДИТ: hooks/lib/transcript_window.py hooks/hook-input-lib.sh
# test_adv_fold2_state_ahead_cold.sh — противник свёртки, раунд 2 (D498): состояние свёртки, записанное соседним вызовом ПОЗЖЕ по файлу, отвергается как «впереди» — и тёплый вызов заново сворачивает весь ход.
#
# Обещание свёртки: цена вызова — дописанное с прошлого вызова, а не всё накопленное. Условие
# приёма состояния `origin <= конец_состояния <= end` отвергает состояние, конец которого дальше
# своего `end`. Такое бывает у параллельных вызовов на растущем файле: вызов A посчитал `end`
# (turn_offset), харнесс дописал строку, вызов B (другой хук того же события или хук параллельного
# субагента — у PreToolUse/PostToolUse `transcript_path` всегда родительский, paths-lib.sh:236)
# прошёл свёртку целиком и записал состояние до того, как A его прочёл. Окно A между `stat` и
# чтением состояния включает взятие замка метки (до 2 с при занятом замке). Расшифровку харнесс
# только дописывает, поэтому состояние B верно и для A — но A сворачивает ход с начала.
# Чередование воспроизведено точкой вставки после turn_offset (поведение A не меняется: его вид
# файла уже снят), шаг считает байты своего stdin. Ожидание: A читает не больше дописанного с
# прошлой свёртки (одна строка), а не весь ход.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"   # временные файлы помощника — под каталогом теста
ST="$T/st"; mkdir -p "$ST"
F="$T/t.jsonl"; LOG="$T/step.log"
case "$F$ST$LOG" in "$T"/*"$T"/*"$T"/*) ;; *) echo "FAIL [K0]: путь записи вне каталога теста"; exit 1 ;; esac

# Ход владельца ~2 МБ: реплика и пары вызов/результат инструмента.
python3 - "$F" <<'PY'
import json, sys
fill = "строка вывода инструмента " * 40
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": "сделай"}]}}, ensure_ascii=False) + "\n")
    i = 0
    while f.tell() < 2 * 1024 * 1024:
        f.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": "ls"}}]}}) + "\n")
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": fill}]}}, ensure_ascii=False) + "\n")
        i += 1
PY
# Шаг: накопленное — число прочитанных байт; каждый вызов пишет размер своего stdin в журнал.
cat > "$T/step.sh" <<EOF
n=\$(wc -c | tr -d ' ')
p=0; [ -s "\$1" ] && p=\$(cat "\$1")
printf '%s\n' "\$n" >> "$LOG"
echo \$((p + n))
EOF
fold() { python3 "$HOOKS/lib/transcript_window.py" "$F" --fold cnt --turn --state "$ST" -- bash "$T/step.sh"; }

fold >/dev/null                                   # прошлый вызов: свёртка хода прогрета
REC='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"шаг"}]}}'
printf '%s\n' "$REC" >> "$F"                      # дописано с прошлого вызова — одна строка
: > "$LOG"

# Вызов A: вид файла снят (turn_offset), затем харнесс дописывает строку и вызов B проходит целиком.
python3 - "$HOOKS/lib/transcript_window.py" "$F" "$ST" "$T/step.sh" "$REC" <<'PY' > "$T/a.out"
import importlib.util, subprocess, sys
helper, path, st, step, rec = sys.argv[1:6]
spec = importlib.util.spec_from_file_location("tw", helper)
tw = importlib.util.module_from_spec(spec); spec.loader.exec_module(tw)
real = tw.turn_offset
def interleaved(p, s=None):
    view = real(p, s)                                   # вид A: (начало хода, конец полной строки)
    with open(p, "a", encoding="utf-8") as f:
        f.write(rec + "\n")                             # харнесс дописал
    subprocess.run([sys.executable, helper, p, "--fold", "cnt", "--turn", "--state", st, "--", "bash", step],
                   stdout=subprocess.DEVNULL, check=True)  # вызов B прошёл свёртку и записал состояние
    return view
tw.turn_offset = interleaved
sys.exit(tw.fold(path, st, "cnt", ["bash", step], turn=True))
PY
ARC=$?

# Контроль: вызов A ответил свёрткой (а не отказом); шаг B был, шаг A — если был, второй.
# Починка, при которой A берёт готовое состояние соседа и шага не зовёт вовсе, — тоже зелёная.
[ "$ARC" -eq 0 ] && [ "$(head -1 "$T/a.out")" = ok ] && ok || bad K1 "вызов A не ответил свёрткой: код $ARC"
STEPS=$(grep -c . "$LOG")
{ [ "$STEPS" -ge 1 ] && [ "$STEPS" -le 2 ]; } && ok || bad K2 "ожидался шаг B и не больше одного шага A, в журнале $STEPS"
B_BYTES=$(sed -n 1p "$LOG"); A_BYTES=$(sed -n 2p "$LOG")
# Второго шага нет — A шага не звал вовсе (взял готовое состояние соседа): прочёл 0 байт. Это
# значение, а не заглушка отказа: число строк журнала сверено ногой K2. Несостоявшийся замер
# (пусто там, где шаг был) ниже краснеет, а не читается нулём (род B, сторож родов 2 октября 2026).
[ "$STEPS" = 1 ] && A_BYTES=0
# Контроль воспроизведения: B прочёл только дописанное (две строки), то есть свёртка прогрета.
[ "$B_BYTES" -lt 4096 ] 2>/dev/null && ok || bad K3 "вызов B прочёл ${B_BYTES:-?} байт — свёртка не прогрета, тест не о том"
# Предмет: A прочёл не больше дописанного с прошлой свёртки (одна строка), а не весь ход.
[ "$A_BYTES" -lt 4096 ] 2>/dev/null && ok \
    || bad S1 "тёплый вызов A свернул заново ${A_BYTES:-?} байт хода вместо одной дописанной строки — состояние соседа «впереди» отвергнуто"

# Брат того же устройства — метка начала хода (turn_offset): метка соседа с концом дальше своего
# `end` отвергается (`size <= end`), и начало хода ищется разбором ВСЕГО хода с конца. Точка
# вставки — сразу после того, как A снял конец полной строки; счёт — число разобранных строк.
printf '%s\n' "$REC" >> "$F"
LOADS=$(python3 - "$HOOKS/lib/transcript_window.py" "$F" "$ST" "$T/step.sh" "$REC" <<'PY'
import importlib.util, json, subprocess, sys, types
helper, path, st, step, rec = sys.argv[1:6]
spec = importlib.util.spec_from_file_location("tw", helper)
tw = importlib.util.module_from_spec(spec); spec.loader.exec_module(tw)
n = [0]
def counting_loads(s, *a, **k):
    n[0] += 1
    return json.loads(s, *a, **k)
tw.json = types.SimpleNamespace(loads=counting_loads)
real_end, fired = tw._complete_end, [False]
def interleaved(f, size):
    e = real_end(f, size)                               # вид A: конец полной строки снят
    if not fired[0]:
        fired[0] = True
        with open(path, "a", encoding="utf-8") as g:
            g.write(rec + "\n")                         # харнесс дописал
        subprocess.run([sys.executable, helper, path, "--state", st], stdout=subprocess.DEVNULL, check=True)
    return e                                            # сосед записал метку дальше конца A
tw._complete_end = interleaved
tw.turn_offset(path, st)
print(n[0])
PY
)
# Ожидание: разобраны только дописанные строки (единицы), а не весь ход (тысячи).
[ "$LOADS" -lt 50 ] 2>/dev/null && ok \
    || bad S2 "метка начала хода соседа «впереди» отвергнута: вызов разобрал ${LOADS:-?} строк хода вместо дописанных"

echo "test_adv_fold2_state_ahead_cold: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
