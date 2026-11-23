#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py scripts/dep-index.py
# probe_D1003.sh — карта связей видит запись в журнал через переменную (проба E5 аудита связей).
#
# Коды: 0 — у скрипта, пишущего `printf … >> "$LOG"` после `LOG="$STATE_DIR/events.jsonl"`, в
#       карте есть ребро «пишет» к журналу; 1 — ребра нет (дефект D1003); 2 — рамка не поднялась
#       либо карта не видит даже ПРЯМУЮ запись (положительный контроль: без него «нет ребра»
#       неотличимо от карты, которая не видит записей вовсе).
# Рамка — как у hooks/tests/test_project_graph_gaps_characterized.sh: копии обоих приборов в
# песочнице-репозитории, живые ~/.claude, учёт и кэш карты не трогаются.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
T=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$T"' EXIT
P="$T/proj"
mkdir -p "$P/scripts" "$P/hooks" "$P/.claude-docs" "$P/mcp-server/visualization" \
         "$T/home" "$T/lessons" "$T/state" || exit 2
cp "$REPO/scripts/project-graph.py" "$REPO/scripts/dep-index.py" "$P/scripts/" 2>/dev/null || exit 2
printf '#!/usr/bin/env bash\nprintf x >> "$STATE_DIR/direct.jsonl"\n' > "$P/hooks/direct.sh"
printf '#!/usr/bin/env bash\nLOG="$STATE_DIR/events.jsonl"\nprintf x >> "$LOG"\ncat "$LOG"\n' > "$P/hooks/viavar.sh"
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || exit 2
export HOME="$T/home" LESSONS_DIR="$T/lessons" STATE_DIR="$T/state" CLAUDSOUL_REPO="$P" PYTHONDONTWRITEBYTECODE=1
( cd "$P" && python3 scripts/dep-index.py --all && python3 scripts/project-graph.py --refresh ) >/dev/null 2>&1 || exit 2

python3 - "$P/mcp-server/visualization/project-graph-data.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(2)
key = {n["id"]: n.get("key") for n in d.get("nodes", [])}
def writes(src, journal):
    return any(key.get(e.get("source")) == src and e.get("type") == "пишет"
               and key.get(e.get("target")) == journal for e in d.get("edges", []))
if not writes("hooks/direct.sh", "журнал:direct.jsonl"):
    sys.exit(2)
sys.exit(0 if writes("hooks/viavar.sh", "журнал:events.jsonl") else 1)
PY
