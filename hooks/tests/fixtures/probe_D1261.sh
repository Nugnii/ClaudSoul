#!/usr/bin/env bash
set -u
# СУДИТ: scripts/setup-call-guard.py
# probe_D1261 — признак немых подготовительных вызовов видит вызов за префиксом-присваиванием и за `env`:
#   (к) в песочнице `X=1; HOME=/h bash x >/dev/null 2>&1` и `env -u X git status >/dev/null` — два носителя;
#       `echo HOME=/h bash x >/dev/null` — не носитель (присваивание в аргументе, команда — `echo`);
#   (п) в дереве носителей 0: каждое место за префиксом разобрано по роли.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
G="$R/scripts/setup-call-guard.py"
[ -f "$G" ] && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hooks/tests" || exit 2
# Фоновый вызов (`… & p=$!`) — не носитель: кода у него в строке нет, страж за `&` повис бы на присваивании (скептик M3).
printf '%s\n' '#!/usr/bin/env bash' 'X=1; HOME=/h bash x >/dev/null 2>&1' 'env -u X git status >/dev/null' \
    'echo HOME=/h bash x >/dev/null' 'HOME=/h bash x >/dev/null 2>&1 & p=$!' > "$T/hooks/tests/test_x.sh"
k=$(python3 "$G" --root "$T" --count 2>/dev/null)
[ "$k" = 2 ] || { echo "в песочнице носителей ${k:-?}, а не 2: вызов за префиксом не виден, echo или фоновый вызов приняты за носитель"; exit 1; }
n=$(python3 "$G" --root "$R" --count 2>/dev/null)
[ "$n" = 0 ] || { echo "в дереве носителей ${n:-?}: места за префиксом не разобраны"; exit 1; }
echo "вызов за префиксом-присваиванием и за env — носитель; в дереве носителей 0"
exit 0
