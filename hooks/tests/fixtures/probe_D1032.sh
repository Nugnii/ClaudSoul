#!/usr/bin/env bash
# СУДИТ: hooks/lib/link_symmetry.py
# probe_D1032.sh — каждое ребро знания вверх (confirms/specializes/extends/generalizes) видно разборщику связей:
# в базе нет рёбер, записанных формой, которую `link_symmetry.parent_edges` не читает.
#
# Повод (23 октября 2026): ребро `{type: confirms, target: …}` в кейсе B535 разборщик не видит — для обхода графа
# «на чём основано» кейса нет, хотя родитель ссылается на него. Таких рёбер вверх 5 в 4 кейсах; форма записи
# объявлена только у читателя (докстрока `parent_edges`), у писателя (`knowledge/META.md`, шаблоны) её нет.
#
# Код: 0 — невидимых рёбер вверх нет; 1 — есть (названы); 2 — нечем мерить.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
KB="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
[ -f "$REPO/hooks/lib/link_symmetry.py" ] && [ -d "$KB" ] || exit 2
python3 - "$REPO/hooks/lib" "$KB" <<'EOF'
import sys, re, glob, os
sys.path.insert(0, sys.argv[1])
import link_symmetry as L
kinds = "|".join(L.PARENT_KINDS)
bad = []
for f in sorted(glob.glob(os.path.join(sys.argv[2], "*.md"))):
    t = open(f, encoding="utf-8", errors="ignore").read()
    head = t.split("\n---", 2)[0] if t.startswith("---") else ""
    written = len(re.findall(r"\{\s*type:\s*(%s)\b" % kinds, head))
    if written and len(L.parent_edges(t) or []) < written + len(re.findall(r"^\s*-\s*(%s):" % kinds, head, re.M)):
        bad.append(os.path.basename(f))
for b in bad:
    print("НЕВИДИМОЕ РЕБРО ВВЕРХ:", b)
sys.exit(1 if bad else 0)
EOF
