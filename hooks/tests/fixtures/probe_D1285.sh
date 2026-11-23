#!/usr/bin/env bash
# СУДИТ: scripts/signal-precision-corpus.py hooks/portable-lib.sh
# probe_D1285 — правило совпадения речевых признаков одно на две редакции: питонская `pad_words`
# (`scripts/signal-precision-corpus.py`) отвечает байт-в-байт как шелл-владелец (`hooks/portable-lib.sh`), которым судит
# хук `fix-level-check`, и род K реестра (`scripts/defect-class-carriers.py --genus K`) без носителей. Повод (9 ноября
# 2026, D1267): реестр родов увидел копию; шапка объявляла «зеркалит хук», сверки не было. Замер 10 ноября 2026: копия
# сжимала любой пробельный символ и обрезала края, владелец сжимает только пробелы — на `\r\n`, неразрывном пробеле и
# пунктуации по краю ответы расходились (корень R1).
# Красная (1), пока редакции расходятся хоть на одном входе либо род K не пуст; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/signal-precision-corpus.py" ] && [ -f "$R/hooks/portable-lib.sh" ] || exit 2
command -v python3 >/dev/null 2>&1 || exit 2
python3 - "$R" <<'PY' || exit $?
import importlib.util, subprocess, sys
R = sys.argv[1]
spec = importlib.util.spec_from_file_location("spc", R + "/scripts/signal-precision-corpus.py")
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except Exception as e:
    print("рамка: прибор не загрузился:", e, file=sys.stderr); sys.exit(2)
cases = ["Хук поймает меня: механизма нет — и всё.", "строка\nвторая\tтаб", "  края с пробелами  ",
         "тире – среднее … многоточие", "Конец с точкой.", "(скобки) [и] {фигурные}", "a,b;c:d!e?f",
         "строка\r\nс CRLF", "неразрывный пробел", "путь hooks/x.sh:12 и «ёлочки»", "", "-флаг --длинный",
         "пробелы    подряд", "100% $HOME @user #tag ^ & * + = | \\ /"]
bad = 0
for c in cases:
    sh = subprocess.run(["bash", "-c", '. "$1"; pad_words "$2"', "_", R + "/hooks/portable-lib.sh", c],
                        capture_output=True).stdout.decode("utf-8")   # байтами: text=True перевёл бы \r в \n
    py = m.pad_words(c)
    if sh != py:
        bad += 1
        print("расходятся на %r: шелл %r, питон %r" % (c, sh, py))
sys.exit(1 if bad else 0)
PY
out=$(cd "$R" && python3 scripts/defect-class-carriers.py --genus K 2>/dev/null); rc=$?
[ "$rc" -ge 2 ] && exit 2
grep -q 'носителей: 0 файлов' <<< "$out" || { printf '%s\n' "$out" | head -3; exit 1; }
exit 0
