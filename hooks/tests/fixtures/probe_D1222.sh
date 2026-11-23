#!/usr/bin/env bash
# СУД: свойство мира
# (судится журнал прибора свидетелей-атак `state/behavior-condition-probe.jsonl` — последняя запись по этому дереву;
#  сам прибор идёт полтора часа и в срок «Проверки» не укладывается, пишет его строка замера `behavior-condition-probe`)
# probe_D1222 — корпус свидетелей-атак судим целиком: в последней записи журнала прибора по этому репозиторию вердикт
#   вынесен у каждого разрешимого (judged = resolved) и ложно-зелёных ноль (vacuous = 0).
# Код: 0 — так; 1 — нет (числа названы); 2 — записи нет, журнал не читается, у записи нет вершины снимка либо она старше
#   срока замера (`scripts/measurements.tsv`, строка `behavior-condition-probe`, коммитами от вершины).
R="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$R" 2>/dev/null || exit 2
command -v python3 >/dev/null 2>&1 || exit 2
# Имя дерева — каноническое, как его пишет прибор (`git rev-parse --show-toplevel` разрешает ссылки: /var → /private/var).
r=$(git rev-parse --show-toplevel 2>/dev/null) || exit 2
python3 - "${STATE_DIR:-$HOME/.claude/hooks/state}/behavior-condition-probe.jsonl" "$r" <<'PY'
import json, sys
last = None
try:
    for ln in open(sys.argv[1], encoding="utf-8", errors="replace"):
        try:
            rec = json.loads(ln)
        except ValueError:
            continue
        if rec.get("repo") == sys.argv[2]:
            last = rec
except OSError:
    print("журнала прибора нет: " + sys.argv[1])
    sys.exit(2)
if last is None:
    print("записи прибора по " + sys.argv[2] + " нет")
    sys.exit(2)
j, res, v = last.get("judged"), last.get("resolved"), last.get("vacuous")
if not all(isinstance(x, int) for x in (j, res, v)):
    print("запись без чисел judged/resolved/vacuous: " + str(last.get("ts")))
    sys.exit(2)
# Свежесть — коммитами от вершины снимка, срок — у владельца, строки замера (D1222, скептик opus M1): прежде проба верила
# последней записи без возраста, и сломанный прибор, вышедший до записи, оставлял старую зелёную навсегда.
import re, subprocess
head = last.get("head") or ""
if not head:
    print("запись без вершины снимка (прибор старше D1222 M1): " + str(last.get("ts")))
    sys.exit(2)
try:
    per = next(l.split("\t")[1] for l in open("scripts/measurements.tsv", encoding="utf-8")
               if l.startswith("behavior-condition-probe\t"))
    per = int(re.fullmatch(r"(\d+)c", per).group(1))
except (OSError, StopIteration, AttributeError, IndexError):
    print("срок замера behavior-condition-probe в scripts/measurements.tsv не прочитан")
    sys.exit(2)
r = subprocess.run(["git", "rev-list", "--count", head + "..HEAD"], capture_output=True, text=True)
if r.returncode != 0 or not r.stdout.strip().isdigit():
    print("вершина записи %s — не предок HEAD" % head[:8])
    sys.exit(2)
n = int(r.stdout.strip())
if n > per:
    print("запись старше срока замера: %d коммитов от %s при сроке %d — не измерено" % (n, head[:8], per))
    sys.exit(2)
print("%s (%d коммитов от %s): вердикт у %d из %d разрешимых, ложно-зелёных %d" % (last.get("ts"), n, head[:8], j, res, v))
sys.exit(0 if (j == res and v == 0) else 1)
PY
