#!/usr/bin/env bash
set -u
# СУДИТ: scripts/line-address-drift.py hooks/commit-trap.sh
# probe_D1251 — коммит, сдвигающий строки файла, до коммита называет адрес «файл:строка», который он не тронул, и куда
#   уехала строка. В клоне репозитория: `lib-d1251/a.sh` (10 строк), на его строку 5 ссылаются `notes-d1251.md` и
#   `lib-d1251/b.sh`; вставка трёх строк в начало `a.sh`:
#   (а) ловушка git `commit-msg` (`hooks/commit-trap.sh --commit-msg`) печатает в stderr оба адреса и «a.sh:8»;
#   (к) тот же сдвиг, но адрес в `notes-d1251.md` переписан этим же коммитом на `:8` — он не называется (решение
#       автора), а `b.sh` называется по-прежнему (контроль).
# Код: 0 — так; 1 — нет (названо); 2 — нет прибора, клон или рамка не собрались.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/line-address-drift.py" ] && [ -f "$R/hooks/commit-trap.sh" ] || exit 2
command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
C="$W/repo"
git clone -q --local "$R" "$C" 2>/dev/null || exit 2
# Рабочая копия накрывает клон: прибор и ловушка — нынешние, а не из последнего коммита.
for f in scripts/line-address-drift.py hooks/commit-trap.sh; do cp "$R/$f" "$C/$f" || exit 2; done
mkdir -p "$C/lib-d1251"
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'echo строка-%s\n' "$i"; done > "$C/lib-d1251/a.sh"
printf 'Смотри `lib-d1251/a.sh:5` — пятая строка.\n' > "$C/notes-d1251.md"
printf '# предмет: lib-d1251/a.sh:5\n' > "$C/lib-d1251/b.sh"
(cd "$C" && git add -A && git -c core.hooksPath=/dev/null -c user.email=p@p -c user.name=p commit -q --allow-empty -m base) \
    >/dev/null 2>&1 || exit 2
{ printf 'echo вставка-1\necho вставка-2\necho вставка-3\n'; cat "$C/lib-d1251/a.sh"; } > "$W/a" && mv "$W/a" "$C/lib-d1251/a.sh"
(cd "$C" && git add -A) || exit 2
printf 'test: сдвиг строк\n' > "$W/msg"
# Проверки — по месту упоминания в начале строки подсказки: в клоне закоммичена и сама проба, её строки несут те же
# адреса и попадают в подсказку (8 ноября 2026: (к) ловила «notes-d1251.md» внутри строки о самой пробе).
hint() { (cd "$C" && env -u CLAUDECODE -u AI_AGENT CLAUDSOUL_ROOT="$C" bash hooks/commit-trap.sh --commit-msg "$W/msg" 2>&1 >/dev/null); }
a=$(hint)
miss=""
grep -q '^notes-d1251.md:1 .*lib-d1251/a.sh:5.*lib-d1251/a.sh:8' <<< "$a" || miss="$miss (а) адрес в документе не назван;"
grep -q '^lib-d1251/b.sh:1 .*lib-d1251/a.sh:5.*lib-d1251/a.sh:8' <<< "$a" || miss="$miss (а) адрес в коде не назван;"
printf 'Смотри `lib-d1251/a.sh:8` — пятая строка.\n' > "$C/notes-d1251.md"
(cd "$C" && git add -A) || exit 2
k=$(hint)
grep -q '^notes-d1251.md' <<< "$k" && miss="$miss (к) адрес, переписанный этим коммитом, назван;"
grep -q '^lib-d1251/b.sh:1 ' <<< "$k" || miss="$miss (к) контроль: нетронутый адрес в коде не назван;"
[ -z "$miss" ] && { echo "сдвинутые адреса названы до коммита, переписанный автором — нет"; exit 0; }
echo "не держится:$miss"
exit 1
