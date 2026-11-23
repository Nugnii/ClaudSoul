#!/usr/bin/env bash
set -u
# СУДИТ: scripts/project-graph.py
# probe_D1265 — карта связей судит «тест ли файл» описанием проекта, а не формой `/tests/` пути: в песочнице с
#   описанием `tests: ["**/Tests/**"]` шелл-тест `Tests/adversary/test_a.sh`, называющий `test_b.sh`, даёт ребро
#   «тест → тест» (сборка `--refresh`); у теста под `sub/tests/` прежнего вида ребро и прежде было (положительный контроль).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PG="$R/scripts/project-graph.py"; DG="$R/scripts/dep-index.py"
[ -f "$PG" ] && [ -f "$DG" ] && command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
S="$T/p"; mkdir -p "$S/Tests/adversary" "$S/sub/tests" "$S/.claude-docs" || exit 2
printf '%s\n' '{"version": 1, "code": [{"glob": "**/*.sh", "lang": "shell"}], "tests": ["**/Tests/**", "**/tests/**"]}' \
    > "$S/.claude-docs/project-map.json"
printf '%s\n' '#!/usr/bin/env bash' 'bash "$(dirname "$0")/test_b.sh"' > "$S/Tests/adversary/test_a.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo b' > "$S/Tests/adversary/test_b.sh"
printf '%s\n' '#!/usr/bin/env bash' 'bash "$(dirname "$0")/test_d.sh"' > "$S/sub/tests/test_c.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo d' > "$S/sub/tests/test_d.sh"
{ git -C "$S" init -q && git -C "$S" add -A && git -C "$S" -c user.email=t@t -c user.name=t commit -qm i; } >/dev/null 2>&1 || exit 2
( cd "$T" && python3 "$DG" --repo "$S" --all && python3 "$PG" --repo "$S" --refresh ) >/dev/null 2>&1 || exit 2
python3 - "$S/.claude-docs/project-graph.json" <<'PY'
import json, sys
try:
    g = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("рамка: карта не собрана", file=sys.stderr); sys.exit(2)
k = {n["id"]: n["key"] for n in g["nodes"]}
e = {(k.get(x["source"]), k.get(x["target"])) for x in g["edges"]}
if ("sub/tests/test_c.sh", "sub/tests/test_d.sh") not in e:
    print("рамка: и у теста под sub/tests/ ребра тест → тест нет", file=sys.stderr); sys.exit(2)
if ("Tests/adversary/test_a.sh", "Tests/adversary/test_b.sh") not in e:
    print("тест под Tests/ по описанию проекта — ребра тест → тест нет"); sys.exit(1)
print("тест судится описанием проекта: ребро тест → тест есть и под Tests/")
PY
