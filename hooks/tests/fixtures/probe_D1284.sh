#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_impact_inject.sh
# probe_D1284 — свидетель подсказки связей судит свою песочницу, а не дерево вызывающего: в копии дерева с
# `CLAUDSOUL_REPO=<копия>` (так «Проверки» гоняет сверка архива после коммита, D1249) он зелёный, как в живой копии.
# Повод (9 ноября 2026): после af68d37d «Проверка» D1113 красна в клоне сверки — 30 ног из 60; замер 10 ноября 2026:
# по унаследованной переменной прибор карты читал кэш копии (его нет — git его не отслеживает) вместо кэша песочницы,
# и подсказка отвечала «карта связей устарела» вместо карточки (корень R6: одна переменная на два мира).
# Красная (1), пока свидетель в такой рамке красен; 2 — рамка не собралась.
# Положительный контроль (D1295, 15 ноября 2026): зелёным считается только свидетель, назвавший свои ноги итогом
#   «прошло N, упало 0» с N > 0. Код 0 без итога — выпотрошенный свидетель, и проба была зелена на мёртвом предмете.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/tests/test_impact_inject.sh" ] && [ -f "$R/hooks/frame-control-lib.sh" ] || exit 2
. "$R/hooks/frame-control-lib.sh"
command -v git >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
( cd "$R" && git ls-files -z -co --exclude-standard | tar --null -T - -cf - ) 2>/dev/null | tar -x -C "$T" 2>/dev/null
[ -f "$T/hooks/impact-inject.sh" ] && [ -f "$T/scripts/project-graph.py" ] || exit 2
[ ! -f "$T/.claude-docs/project-graph.cache.json" ] || exit 2   # копия без кэша — как клон сверки
out=$(cd "$T" && CLAUDSOUL_REPO="$T" bash hooks/tests/test_impact_inject.sh 2>&1); rc=$?
if [ "$rc" = 0 ]; then
    n=$(printf '%s\n' "$out" | sed -n 's/^test_impact_inject: прошло \([0-9][0-9]*\), упало 0$/\1/p' | tail -1)
    frame_require_nonempty "$n" "ног свидетеля подсказки связей" "итог «прошло N, упало 0» в выводе свидетеля" || exit $?
    exit 0
fi
printf '%s\n' "$out" | grep -E '^FAIL' | head -3
printf '%s\n' "$out" | tail -1
exit 1
