#!/usr/bin/env bash
set -u
# СУДИТ: hooks/tests/test_measurement_due.sh
# probe_D1257 — нога T4a свидетеля прогона замеров сравнивает отметку `broken` с её же значением до прогона, а не с
#   отметкой другого замера. В клоне репозитория, `date +%s` подменён шагом в секунду на вызов (секунда меняется между
#   любыми двумя отметками раскладки — то, что под нагрузкой случается само):
#   (а) свидетель на нынешнем приборе — зелёный (отметки, разошедшиеся с раскладки, не краснят T4a);
#   (б) мутант прибора, ставящий отметку и не выполнившемуся замеру, — свидетель красен по T4a (положительный контроль).
# Код: 0 — так; 1 — нет (названо); 2 — нет предмета, клон или рамка не собрались.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="hooks/tests/test_measurement_due.sh"; S="scripts/measurement-due.sh"
[ -f "$R/$T" ] && [ -f "$R/$S" ] && command -v git >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
C="$W/repo"
git clone -q --local "$R" "$C" 2>/dev/null || exit 2
for f in "$T" "$S"; do cp "$R/$f" "$C/$f" || exit 2; done
# Подменённый `date`: `+%s` — шаг в секунду на каждый вызов, прочее — настоящий date.
mkdir -p "$W/bin"; printf '%s' "$(date +%s)" > "$W/clock"
cat > "$W/bin/date" <<EOF
#!/bin/bash
if [ "\$#" -eq 1 ] && [ "\$1" = "+%s" ]; then
    n=\$(cat "$W/clock"); echo \$((n + 1)) > "$W/clock"; echo "\$n"; exit 0
fi
exec /bin/date "\$@"
EOF
chmod +x "$W/bin/date"
tst() { (cd "$C" && PATH="$W/bin:$PATH" bash "$T" 2>&1); }
a=$(tst); arc=$?
miss=""
[ "$arc" = 0 ] || miss="$miss (а) свидетель красен при разошедшихся отметках раскладки: $(grep -E 'FAIL|T4' <<< "$a" | head -2 | tr '\n' ' ');"
grep -q 'if \[ -z "\$_crash" \] && { \[ "\$_rc" -le 1 \] || \[ "\$_rc" -eq 3 \]; }; then' "$C/$S" \
    || { echo "рамка: ветка отметки выполненного замера в приборе не найдена" >&2; exit 2; }
sed -i.bak 's/if \[ -z "\$_crash" \] && { \[ "\$_rc" -le 1 \] || \[ "\$_rc" -eq 3 \]; }; then/if true; then/' "$C/$S" && rm -f "$C/$S.bak"
b=$(tst)
grep -q 'FAIL \[T4a\]' <<< "$b" || miss="$miss (б) мутант, ставящий отметку отказавшему замеру, T4a не краснит;"
[ -z "$miss" ] && { echo "T4a судит свою отметку: разошедшиеся с раскладки тихи, сдвиг отметки отказавшего замера красен"; exit 0; }
echo "не держится:$miss"
exit 1
