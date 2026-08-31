#!/usr/bin/env bash
# test_injection_log_rotate_concurrent.sh — D236: строка, дописанная параллельной
# сессией во время ротации, НЕ теряется (сумма живой лог + архив сохраняет всё).
#
# Тест стохастический по природе гонки, но нагрузка подобрана так, что на
# rewrite-ротации (read_text → write_text) потери ловятся практически всегда:
# фоновый аппендер пишет нумерованные строки всё время, пока ротация 20 раз
# переписывает файл на ~20К строк; каждая APP-строка обязана оказаться ровно
# в одном из двух файлов. Тот же тест — инвариант суммы и для битых строк.
set -uo pipefail

LIBPY="$(cd "$(dirname "$0")/.." && pwd)/lib/injection-log-rotate.py"
[ -f "$LIBPY" ] || { echo "нет $LIBPY"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3"; exit 2; }

TMP=$(mktemp -d)
LOG="$TMP/injection-log.jsonl"
ARCH="$TMP/injection-log-archive.jsonl"

# Стартовый лог: одна «старая» сессия, чтобы первой же ротации было что уносить.
python3 - "$LOG" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("".join(json.dumps({"session_id": "seed", "n": i}) + "\n" for i in range(20000)))
PY

# Фоновый аппендер: нумерованные строки без пауз, пока жив файл-флаг.
FLAG="$TMP/run"
touch "$FLAG"
(
    i=0
    while [ -f "$FLAG" ]; do
        printf '{"session_id":"app","marker":"APP-%d"}\n' "$i" >> "$LOG" 2>/dev/null
        i=$((i + 1))
    done
    printf '%d' "$i" > "$TMP/appended"
) &
APP_PID=$!

# 20 ротаций подряд; keep=1 и перед каждой — свежая «старая» сессия, чтобы old
# был непуст и rewrite происходил каждый раз.
for r in $(seq 1 20); do
    python3 - "$LOG" "$r" <<'PY'
import json, sys, pathlib
p, r = pathlib.Path(sys.argv[1]), sys.argv[2]
with p.open("a", encoding="utf-8") as fh:
    for i in range(20000):
        fh.write(json.dumps({"session_id": f"old-{r}", "n": i}) + "\n")
PY
    INJECTION_LOG_MIN_BYTES=1 python3 "$LIBPY" "$LOG" "$ARCH" 1 2>/dev/null || true
done

rm -f "$FLAG"
wait "$APP_PID" 2>/dev/null || true
APPENDED=$(cat "$TMP/appended" 2>/dev/null || echo 0)

# Инвариант: каждая APP-строка ровно один раз в объединении лог+архив.
LOST=$(python3 - "$LOG" "$ARCH" "$APPENDED" <<'PY'
import pathlib, sys
log, arch, n = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3])
seen = {}
for p in (log, arch):
    if p.exists():
        for line in p.read_text(errors="replace").splitlines():
            if '"APP-' in line:
                key = line.split('"APP-')[1].split('"')[0]
                seen[key] = seen.get(key, 0) + 1
lost = [i for i in range(n) if str(i) not in seen]
dup  = [k for k, c in seen.items() if c > 1]
print(f"{len(lost)} {len(dup)} {n}")
PY
)
read -r N_LOST N_DUP N_TOTAL <<< "$LOST"

echo "аппендер записал: $N_TOTAL строк; потеряно: $N_LOST; задвоено: $N_DUP"
if [ "${N_TOTAL:-0}" -lt 200 ]; then
    echo "НЕУБЕДИТЕЛЬНО: аппендер записал слишком мало строк ($N_TOTAL) — нагрузки не было"
    exit 2
fi
if [ "${N_LOST:-1}" -gt 0 ] || [ "${N_DUP:-1}" -gt 0 ]; then
    echo "RED [D236]: ротация теряет конкурентные аппенды (rewrite-окно read→write)"
    exit 1
fi
echo "PASS: конкурентные аппенды пережили $((20)) ротаций без потерь и дублей"

# --- Сценарий 2: сирота упавшей ротации возвращается в живой лог --------------
LOG2="$TMP/log2.jsonl"; ARCH2="$TMP/arch2.jsonl"
printf '{"session_id":"live","n":1}\n' > "$LOG2"
ORPHAN="$TMP/log2.jsonl.rot.99999.1"
printf '{"session_id":"crashed","marker":"ORPHAN-LINE"}\n' > "$ORPHAN"
OLD_TS=$(date -v-10M '+%Y%m%d%H%M' 2>/dev/null || date -d '10 minutes ago' '+%Y%m%d%H%M' 2>/dev/null)
touch -t "$OLD_TS" "$ORPHAN" 2>/dev/null
# Гейт по размеру не должен мешать восстановлению: MIN_BYTES огромный — ротации нет,
# а сирота обязана вернуться.
INJECTION_LOG_MIN_BYTES=999999999 python3 "$LIBPY" "$LOG2" "$ARCH2" 1 2>/dev/null || true
if ! grep -q 'ORPHAN-LINE' "$LOG2"; then
    echo "RED [D236]: сирота упавшей ротации не вернулась в живой лог"
    exit 1
fi
if ls "$TMP"/log2.jsonl.rot* >/dev/null 2>&1; then
    echo "RED [D236]: сирота возвращена, но rot-файл остался"
    exit 1
fi
# Свежая чужая ротация (mtime сейчас) НЕ трогается.
FRESH="$TMP/log2.jsonl.rot.11111.2"
printf '{"session_id":"alive-neighbor"}\n' > "$FRESH"
INJECTION_LOG_MIN_BYTES=999999999 python3 "$LIBPY" "$LOG2" "$ARCH2" 1 2>/dev/null || true
if [ ! -f "$FRESH" ]; then
    echo "RED [D236]: свежий rot-файл живого соседа украден восстановлением"
    exit 1
fi
echo "PASS: сирота вернулась, свежий чужой rot не тронут"
exit 0
