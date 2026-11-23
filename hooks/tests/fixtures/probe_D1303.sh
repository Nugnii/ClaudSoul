#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh hooks/lib/rework_red_run.py
# СУД: свойство мира
# probe_D1303 — агент не снимает настоящий разворот: среди решений агента (disproved, fixed, debt, knowledge) по поводам
#   переработки, у которых между двумя последними правками файла был КРАСНЫЙ прогон (помощник
#   `hooks/lib/rework_red_run.py`, окно 10 минут, срез на время исхода), доля «показалось» (`disproved`) за последние
#   14 дней в ProjectA_NEW ниже 50%. Сессия → проект — реестр `~/.claude/sessions/registry.jsonl`, исходы —
#   `~/.claude/hooks/state/outcome-<sid>.jsonl`, расшифровки — каталог `CLAUDE_PROJECTS_DIR`.
# Повод — слово владельца 15 ноября 2026 («там даже разборы находок не делаются и поиск новых корней»). Цель сменена
#   решением владельца 22 ноября 2026: прежняя проба мерила долю по ВСЕМ поводам, а поводов о настоящем развороте около
#   трети — правдивый агент давал бы около 68%, порог был недостижим. Среди поводов с красным прогоном разворотов 60%
#   (чтение 35 случаев): правдивый агент дал бы около 40%; на 22 ноября — 73%.
# Код: 0 — доля ниже 50%; 1 — не ниже (печатается); 2 — не измерено: нет журналов, помощника, решений с красным прогоном
#   меньше 20 либо помощник не ответил.
set -uo pipefail
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"; REG="${SESSION_REGISTRY:-$HOME/.claude/sessions/registry.jsonl}"
HELPER="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)/lib/rework_red_run.py"
[ -f "$REG" ] && [ -d "$STATE" ] && [ -f "$HELPER" ] || exit 2
command -v python3 >/dev/null 2>&1 || exit 2
python3 - "$REG" "$STATE" "${D1303_PROJECT:-ProjectA_NEW}" "${D1303_DAYS:-14}" "$HELPER" \
    "${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}" <<'PY'
import collections, glob, json, os, subprocess, sys, time
reg, state, proj, days, helper, projects = sys.argv[1:7]
since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - int(days) * 86400))
sids = set()
for l in open(reg, encoding="utf-8", errors="replace"):
    try: r = json.loads(l)
    except Exception: continue
    if r.get("project_name") == proj and r.get("session_id"): sids.add(r["session_id"])
trs = {os.path.basename(f)[:-6]: f for f in glob.glob(os.path.join(projects, "*", "*.jsonl"))}
by = collections.defaultdict(list)   # сессия → [(файл повода, время исхода, исход)]
for f in glob.glob(os.path.join(state, "outcome-*.jsonl")):
    sid = os.path.basename(f)[8:-6]
    if sid not in sids or sid not in trs: continue
    for l in open(f, encoding="utf-8", errors="replace"):
        try: r = json.loads(l)
        except Exception: continue
        o = r.get("outcome")
        if r.get("signal") != "rework" or r.get("ts", "") < since or o not in ("disproved", "fixed", "debt", "knowledge"):
            continue
        paths = [t[7:].rsplit(":", 1)[0] for t in r.get("toks") or [] if t.startswith("rework:")]
        if paths: by[sid].append((paths[0], r["ts"], o))
red = dis = 0
for sid, qs in by.items():
    p = subprocess.run(["python3", "-I", helper, "--batch", trs[sid], "600"], capture_output=True, text=True,
                       input="".join("%s\t%s\n" % (path, ts) for path, ts, o in qs))
    out = p.stdout.split("\n")
    if p.returncode != 0 or len(out) < len(qs):
        print("не измерено: помощник не ответил по сессии %s (код %d)" % (sid, p.returncode), file=sys.stderr); sys.exit(2)
    for (path, ts, o), a in zip(qs, out):
        if a.startswith("red"):
            red += 1; dis += o == "disproved"
if red < 20:
    print("не измерено: решений по поводам с красным прогоном в %s за %s дн. — %d" % (proj, days, red), file=sys.stderr)
    sys.exit(2)
share = dis / red
print("%s за %s дн.: «показалось» среди поводов с красным прогоном %d из %d (%.0f%%)" % (proj, days, dis, red, share * 100))
sys.exit(0 if share < 0.5 else 1)
PY
