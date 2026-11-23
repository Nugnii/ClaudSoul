#!/usr/bin/env bash
# СУДИТ: scripts/deny-target-precision.py
# probe_D1220 — цель `$VAR/…` судится по пути, который переменная получила В ТОЙ ЖЕ команде, а не по расширению и не
# по имени переменной:
#   · один каталог песочницы через `$M/a.out`, `$M/a.sh`, heredoc в `"$M/a.sh"` и полный путь — один класс «песочница»;
#   · `S=/p/hooks; … $S/x.sh` — «механизм» (имя `S` не делает песочницей), `M=/p/docs; … $M/a.log` — «запись»;
#   · цепочка `O=$S/out`, `$(mktemp -d)`, `"$TMPDIR/d"` — по раскрытому; последнее присваивание до цели решает;
#   · нераскрываемая (подстановка, не задана, префикс-присваивание `M=… cmd`, которое раскрытию не служит) — «не разобрано».
# Судится ответ `classify`. Красная (1), пока хоть один класс иной; рамка (нет замера, python3, сбой) — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
DP="$R/scripts/deny-target-precision.py"
[ -f "$DP" ] && command -v python3 >/dev/null 2>&1 || exit 2
python3 - "$DP" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dtp", sys.argv[1])
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except Exception:
    sys.exit(2)
SP = "/private/tmp/probe-d1220-sp"
cases = [("песочница", f"M={SP}; echo x > $M/a.out"),
         ("песочница", f"M={SP}; echo x > $M/a.sh"),
         ("песочница", f"M={SP}; cat > \"$M/a.sh\" <<'E'\nx\nE"),
         ("песочница", f"echo x > {SP}/a.sh"),
         ("механизм", "S=/p/hooks; echo x > $S/x.sh"),
         ("запись", "M=/p/docs; echo x > $M/a.log"),
         ("запись", "O=/p/docs/run; echo x >> $O.log"),
         ("механизм", "echo x > \"$TMPDIR/../../Users/u/.claude/hooks/x.sh\""),
         ("песочница", f"S={SP}; O=$S/out; echo x > \"$O/a.sh\""),
         ("песочница", "T=$(mktemp -d); echo x > $T/a.sh"),
         ("песочница", "S=\"$TMPDIR/d\"; echo x > ${S}/a.sh"),
         ("механизм", f"M={SP}; M=/p/hooks; echo x > $M/x.sh"),
         ("механизм", f"M={SP}; echo x > $M/x.sh; M=/p/hooks; echo y > $M/x.sh"),
         ("не разобрано", "Q=$(cat f); echo x > $Q/a.out"),
         ("не разобрано", "echo x > $UNSET/a.sh"),
         ("не разобрано", "Q=$(cat f); cat > \"$Q/a.md\" <<'E'\nx\nE"),
         ("не разобрано", "Q=$(cat f); cat > /p/docs/a.md <<'E'\nx\nE\ncat > \"$Q/b.md\" <<'F'\ny\nF"),
         ("не разобрано", f"echo x > $M/a.sh; M={SP}"),
         ("не разобрано", f"M={SP} echo x > $M/a.sh"),
         # Круг скептика opus по 5416bcba: формы мира, а не только текста пункта.
         ("песочница", f"cd /p && S={SP}; echo x > $S/a.sh"),
         ("не разобрано", f"cat > \"$M/a.sh\" <<'E'\nx\nE\nM={SP}"),
         ("песочница", "T=$(mktemp); echo x > $T"),
         ("песочница", "T=\"$(mktemp -d \"$TMPDIR/x.XXXX\")\"; echo x > $T/a.sh"),
         ("песочница", f"T=$(mktemp -d -p {SP} x.XXXX); echo x > $T/a.sh"),
         ("механизм", "T=$(mktemp -d /p/hooks/x.XXXX); echo x > $T/a.sh"),
         ("песочница", f"cat > \"{SP}/n.txt\" <<'E'\nx\nE\nS={SP}\ncat > \"$S/a.sh\" <<'F'\ny\nF"),
         ("песочница", f"S={SP} || S=/p/hooks; echo x > $S/a.sh"),
         ("не разобрано", f"true | S={SP}; echo x > $S/a.out"),
         ("не разобрано", f"cat > \"{SP}/n.txt\" <<'E'\nS=/p/hooks\nE\ncat > \"$S/a.sh\" <<'F'\ny\nF"),
         ("песочница", f"for i in 1; do S={SP}; done; echo x > $S/a.sh"),
         ("механизм", "Q=$(cat f); echo x > $Q/a.out; echo y > /p/hooks/x.sh"),
         ("не разобрано", "S=`pwd`; echo x > $S/a.sh")]
try:
    got = m.classify([("t", "Bash", {"command": c}) for _, c in cases])
except SystemExit:
    sys.exit(2)
except Exception:
    sys.exit(2)
bad = [(w, g, c) for (w, c), g in zip(cases, got) if w != g]
for w, g, c in bad:
    print(f"ждём {w}, получено {g}: {c[:90]}", file=sys.stderr)
if not bad:
    print("цель с переменной судится по пути, заданному той же командой")
sys.exit(1 if bad else 0)
PY
