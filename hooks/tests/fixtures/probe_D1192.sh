#!/usr/bin/env bash
# СУДИТ: scripts/deny-target-precision.py
# probe_D1192 — замер точности отказов даёт одному месту один класс при любом виде записи и любом написании дома:
#   · документ установки через Write, heredoc, `>>` и `sed -i` — «запись» (скептик D1112, шестой круг, M1: ветка
#     перенаправлений знает только «песочница/механизм», и `>>`/`sed -i` давали «механизм» при «записи» у Write);
#   · `hooks/scratchpad/` установки через `~/`, `~<имя>/`, `$HOME/`, `${HOME}/` — «механизм» (L1: `~<имя>` давал «песочницу»);
#   · относительный `'scratchpad/q.txt'` в кавычках — «песочница» (L2: левая граница `scratchpad/` у кавычки).
# Судится ответ `classify`, а не текст. Красная (1), пока хоть один класс иной; рамка (нет замера, python3, сбой) — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
DP="$R/scripts/deny-target-precision.py"
[ -f "$DP" ] && command -v python3 >/dev/null 2>&1 || exit 2
python3 - "$DP" <<'PY'
import importlib.util, os, pwd, sys
spec = importlib.util.spec_from_file_location("dtp", sys.argv[1])
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except Exception:
    sys.exit(2)
H, U = os.path.expanduser("~"), pwd.getpwuid(os.getuid()).pw_name
doc, mech = H + "/.claude/projects/-probe/memory/MEMORY.md", "/.claude/hooks/scratchpad/x.sh"
cases = [("запись", "Write", {"file_path": doc}),
         ("запись", "Bash", {"command": "cat >> \"" + doc + "\" <<'E'\nx\nE"}),
         ("запись", "Bash", {"command": "echo x >> \"" + doc + "\""}),
         ("запись", "Bash", {"command": "sed -i '' 's/a/b/' '" + doc + "'"}),
         ("механизм", "Bash", {"command": "echo x > ~" + mech}),
         ("механизм", "Bash", {"command": "echo x > ~" + U + mech}),
         ("механизм", "Bash", {"command": "echo x > \"$HOME" + mech + "\""}),
         ("механизм", "Bash", {"command": "echo x > ${HOME}" + mech}),
         ("песочница", "Bash", {"command": "echo x > 'scratchpad/q.txt'"})]
try:
    got = m.classify([("t", tool, inp) for _, tool, inp in cases])
except SystemExit:
    sys.exit(2)
except Exception:
    sys.exit(2)
bad = [(w, g, inp) for (w, _, inp), g in zip(cases, got) if w != g]
for w, g, inp in bad:
    print(f"ждём {w}, получено {g}: {(inp.get('command') or inp.get('file_path'))[:90]}", file=sys.stderr)
if not bad:
    print("одно место — один класс при любом виде записи и написании дома")
sys.exit(1 if bad else 0)
PY
