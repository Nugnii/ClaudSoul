#!/usr/bin/env bash
set -u
# СУДИТ: scripts/defect-class-carriers.py
# probe_D1267 — разбор исполняемых строк реестра родов (`_f_code`) решает «внутри многострочного литерала питона»
#   разборщиком, а не счётом тройных кавычек в строке:
#   (п) у каждого отслеживаемого питоновского файла дерева со строкой `if __name__ ==` разбор её видит;
#   (к) песочный текст с тройной кавычкой в комментарии и в обычной строке перед точкой входа — точка входа видна, а
#       тело настоящего многострочного литерала — нет.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
D="$R/scripts/defect-class-carriers.py"
[ -f "$D" ] && command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
cd "$R" || exit 2
python3 - "$D" <<'PY'
import importlib.util, subprocess, sys
s = importlib.util.spec_from_file_location("dc", sys.argv[1]); dc = importlib.util.module_from_spec(s); s.loader.exec_module(dc)
Q = '"' * 3
src = ("# комментарий с " + Q + " внутри\n" + "PAT = '" + Q + "'\n" + "DOC = " + Q + "\nhidden_body = 1\n" + Q + "\n"
       + "if __name__ == '__main__':\n    main()\n")
code = list(dc._f_code(src, True))
if any("hidden_body" in l for l in code):
    print("рамка: тело настоящего многострочного литерала читается кодом", file=sys.stderr); sys.exit(2)
if not any("__name__" in l for l in code):
    print("песочный текст: точка входа после кавычек в комментарии и строке не видна"); sys.exit(1)
files = [f for f in subprocess.run(["git", "ls-files", "*.py"], capture_output=True, text=True).stdout.split() if f]
miss = []
for f in files:
    try:
        t = open(f, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    if any(l.startswith("if __name__ ==") for l in t.split("\n")) and not any(l.startswith("if __name__ ==") for l in dc._f_code(t, True)):
        miss.append(f)
if miss:
    print("точка входа не видна:", " ".join(miss)); sys.exit(1)
print("точка входа видна у всех питоновских файлов дерева и в песочном тексте")
PY
