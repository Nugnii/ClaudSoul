#!/usr/bin/env bash
# СУДИТ: scripts/world-locale-run.sh lib/env-pin.jq
# test_world_locale_run.sh — рамка окружения хука терминальной сессии отличает мир с закреплением от мира без него.
#
# Результат: на мирах без закрепления (нет настроек, не один JSON-объект, env без закрепления, LC_ALL в env)
#            код 1; на мире с закреплением awk читает «1.5» как 1.5 и не равняет «☐» и «◐» (код команды 0);
#            `--bare` даёт окружение без закрепления; без команды — 2 — из ЛЮБОГО окружения вызывающего
# Проверка результата: bash hooks/tests/test_world_locale_run.sh даёт 0
#
# Повод — D1176, третий круг скептика (L3): ветки кода 1 не судил ни один тест. Четвёртый круг (M3, L5): ожидание
# нельзя брать у судимой программы и нельзя мерить из одного окружения. Имена ключей и живость локали тест знает
# САМ; рамка гоняется из двух враждебных окружений вызывающего — `LC_ALL=ru_RU.UTF-8` (пропуск снятия LC_ALL дал
# бы «2 1» на мире с закреплением) и `LC_NUMERIC=C LC_COLLATE=C`, как в оболочке агента после D1176 (`--bare` без
# снятия ключей дал бы «3 0»). На машине без ru_RU.UTF-8 тест называет себя неисполненным.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
W="$REPO/scripts/world-locale-run.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
[ -f "$W" ] || { echo "FAIL: нет $W"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
AWK=/usr/bin/awk; [ -x "$AWK" ] || AWK=$(command -v awk)
# Независимое ожидание: имена закрепляемых категорий — LC_NUMERIC и LC_COLLATE (D1176), не из программы.
if [ "$(printf '1.5\n' | env -u LC_ALL -u LC_NUMERIC -u LC_COLLATE LANG=ru_RU.UTF-8 "$AWK" '{ printf "%d %d", $1 * 2, ("☐" == "◐") }')" != "2 1" ]; then
    echo "НЕ СУДИТ: ru_RU.UTF-8 здесь не живая"; exit 0
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
home() { mkdir -p "$T/$1/.claude"; [ -n "${2:-}" ] && printf '%s\n' "$2" > "$T/$1/.claude/settings.json"; echo "$T/$1"; }
CALLERS=("LC_ALL=ru_RU.UTF-8" "LC_NUMERIC=C LC_COLLATE=C")
probe() {  # <дом> <окружение вызывающего> [--bare]
    # shellcheck disable=SC2086
    printf '1.5\n' | env -u LC_ALL -u LC_NUMERIC -u LC_COLLATE $2 HOME="$1" bash "$W" ${3:+"$3"} "$AWK" '{ printf "%d %d", $1 * 2, ("☐" == "◐") }' 2>/dev/null
}

P=$(home pinned '{"env":{"LC_NUMERIC":"C","LC_COLLATE":"C"}}')
for c in "${CALLERS[@]}"; do
    out=$(probe "$P" "$c"); rc=$?
    [ "$rc" -eq 0 ] && [ "$out" = "3 0" ] && ok || bad W1 "мир с закреплением, вызывающий «${c}»: код $rc, вывод «${out}»"
    out=$(probe "$P" "$c" --bare); rc=$?
    [ "$rc" -eq 0 ] && [ "$out" = "2 1" ] && ok || bad W2 "--bare, вызывающий «${c}»: код $rc, вывод «${out}» — ждали окружение без закрепления"
done
for w in "nofile|" 'twodocs|{"a":1}
{"b":2}' 'array|[1]' 'nopin|{"env":{"A":"1"}}' 'foreign|{"env":{"LC_NUMERIC":"ru_RU.UTF-8","LC_COLLATE":"C"}}' \
         'lcall|{"env":{"LC_ALL":"ru_RU.UTF-8","LC_NUMERIC":"C","LC_COLLATE":"C"}}'; do
    name=${w%%|*}; body=${w#*|}
    H=$(home "$name" "$body")
    probe "$H" "${CALLERS[1]}" >/dev/null; rc=$?
    [ "$rc" -eq 1 ] && ok || bad "W-$name" "мир без закрепления ($name): код $rc, ждали 1"
done
HOME="$P" bash "$W" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok || bad W9 "без команды: код $rc, ждали 2"

echo "world-locale-run tests: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
