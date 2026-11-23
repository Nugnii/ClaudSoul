#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_recheck_unproven_is_not_broken.sh
# probe_D1294 — утверждение T3 о строке D12 судит номер целиком. Тест ищет непроверенный D12 в выводе сверки закрытых
# пунктов; образец `^  ? D12` без границы номера ловил D1233, D1244… (их «?» сверка берёт из прогона архива), и тест
# краснел на исправной D12 (11 ноября 2026). Рамка: копия теста рядом с заглушкой `scripts/backlog-recheck.sh`, которая
# печатает заданные строки. (а) «?» только у D1233 — тест зелёный; (б) «?» у самого D12 — красный (контроль: T3 жив).
# 0 — номер судится целиком; 1 — дефект; 2 — рамка (python3 нет, PyYAML виден в чистом окружении — тест пропускает).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="$R/hooks/tests/test_recheck_unproven_is_not_broken.sh"
[ -f "$T" ] || exit 2
command -v python3 >/dev/null 2>&1 || exit 2
env -i PATH=/usr/bin:/bin HOME="$HOME" python3 -c 'import yaml' 2>/dev/null && exit 2
SB=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1294.XXXXXX") || exit 2
trap 'rm -rf "$SB"' EXIT
run() {   # <строка вывода сверки> → код теста
    rm -rf "$SB/r"; mkdir -p "$SB/r/hooks/tests" "$SB/r/scripts" || exit 2
    cp "$T" "$SB/r/hooks/tests/" || exit 2
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "сверка" %q\nexit 0\n' "$1" > "$SB/r/scripts/backlog-recheck.sh"
    bash "$SB/r/hooks/tests/$(basename "$T")" >/dev/null 2>&1
}
run "  ? D12   базы знаний нет"; [ $? = 1 ] || { echo "рамка: «?» у D12 тест не ловит — контроль мёртв" >&2; exit 2; }
run "  ? D1233 архив: не ответила за 300 с"; rc=$?
[ "$rc" = 0 ] && { echo "T3 судит номер D12 целиком"; exit 0; }
echo "T3 краснеет от «?» у D1233 — номер судится префиксом" >&2
exit 1
