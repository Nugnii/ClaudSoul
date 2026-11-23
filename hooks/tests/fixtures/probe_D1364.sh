#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_five_whys_gate.sh hooks/tests/test_adversary_openfind_closure.sh hooks/tests/test_archive_select_probe_code.sh
# probe_D1364.sh — три свидетеля зелены в дереве, устроенном как открытый снимок.
#
# Повод (23 ноября 2026, D1364). Набор по снимку публикации 1.37.0 — 686 из 689: песочницы двух свидетелей брали карту
# корней ClaudSoul (в снимке её нет), третий судил сверку архива, которой без бэклога судить нечего. Рамка снимка здесь
# — копия отслеживаемых файлов рабочего дерева с маркером `.public-snapshot` и без тех путей из
# `scripts/publish/exclude.txt`, на которые свидетели опирались: BACKLOG.md, BACKLOG-archive.md, ROOTS.md,
# scripts/probes/. Свидетели идут параллельно: последовательно рамка дольше двух минут.
# Проверка результата: bash hooks/tests/fixtures/probe_D1364.sh → 0 — три свидетеля дали 0 в рамке снимка; 1 — хоть
#   один красен (назван); 2 — не измерено (нет git или свидетеля, рамка не собралась).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TESTS="test_five_whys_gate test_adversary_openfind_closure test_archive_select_probe_code"
command -v git >/dev/null 2>&1 || { echo "нет git — не измерено"; exit 2; }
for t in $TESTS; do [ -f "$REPO/hooks/tests/$t.sh" ] || { echo "нет свидетеля $t — не измерено"; exit 2; }; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
S="$W/snap"; mkdir -p "$S"
( cd "$REPO" && git ls-files -z ) | while IFS= read -r -d '' f; do
    case "$f" in BACKLOG.md|BACKLOG-archive.md|ROOTS.md|scripts/probes/*) continue ;; esac
    [ -f "$REPO/$f" ] || continue
    mkdir -p "$S/$(dirname "$f")" && cp -p "$REPO/$f" "$S/$f"
done
printf 'Публичный снимок (рамка пробы D1364)\n' > "$S/.public-snapshot"
{ git -C "$S" init -q && git -C "$S" add -A && git -C "$S" -c user.name=p -c user.email=p@example.com \
    -c commit.gpgsign=false commit -qm snap; } >/dev/null 2>&1 || { echo "рамка снимка не собралась — не измерено"; exit 2; }
# Положительный контроль рамки: маркер виден владельцу признака, иначе пропуск третьего свидетеля не проверен.
( UNIVERSE_ROOT="$S"; . "$S/hooks/lib/universe-lib.sh" 2>/dev/null && universe_partial_tree ) \
    || { echo "рамка не признана снимком — не измерено"; exit 2; }
for t in $TESTS; do
    ( cd "$S" && bash "hooks/tests/$t.sh" > "$W/$t.log" 2>&1; echo $? > "$W/$t.rc" ) &
done
wait
RC=0
for t in $TESTS; do
    rc=$(cat "$W/$t.rc" 2>/dev/null || echo 2)
    [ "$rc" = 0 ] || { echo "в рамке снимка красен $t (код $rc):"; grep -E 'FAIL|bad' "$W/$t.log" | head -5; RC=1; }
done
[ "$RC" = 0 ] && echo "три свидетеля зелены в рамке открытого снимка"
exit "$RC"
