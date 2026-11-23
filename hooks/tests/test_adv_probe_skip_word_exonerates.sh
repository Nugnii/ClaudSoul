#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# АТАКА: слово «SKIP:» ГДЕ УГОДНО в выводе свидетеля снимает с него обвинение.
#
# Вход: песочница-репозиторий, один свидетель устройства КАНАРЕЙКИ прибора — он не зовёт
# свой предмет вовсе (`behavior-condition-probe.sh:339` сам называет это известным
# ложно-зелёным), но печатает строку «SKIP: необязательная половина проверки пропущена»
# и ПРОДОЛЖАЕТ работу, выходя нулём.
#
# Ожидание: прибор обязан назвать его ложно-зелёным. Строка SKIP у договора дерева значит
# «судить нечем» ЦЕЛИКОМ, а не «одна половина пропущена»; свидетель, который отказался
# судить, до своей итоговой строки не доходит.
#
# Факт: признак — `grep -qE '(^|[^A-Za-z])SKIP[: ]' "$OUTF"` по ВСЕМУ выводу
# (behavior-condition-probe.sh:561). Одна строка в любом месте переводит свидетеля в класс
# «судить нечем», счётчик ложно-зелёных остаётся нулём, и прибор выходит кодом 0.
# Это тот же R6, ради которого прибор построен: два состояния мира на одном канале —
# «отказался судить» и «судил не тем».
set -uo pipefail

command -v git     >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
[ -f "$PROBE" ] || { echo "SKIP: нет $PROBE"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"

D="$TMP/repo"
mkdir -p "$D/scripts" "$D/hooks/tests" "$D/.claude-docs"
cp "$PROBE" "$D/scripts/"
for f in subject-probe-lib.sh frame-control-lib.sh timeout-lib.sh portable-lib.sh; do
    [ -f "$REPO/hooks/$f" ] && cp "$REPO/hooks/$f" "$D/hooks/"
done
[ -f "$D/hooks/subject-probe-lib.sh" ] || { echo "SKIP: нет hooks/subject-probe-lib.sh"; exit 0; }

printf '#!/usr/bin/env bash\necho MARKER\n' > "$D/hooks/one.sh"
printf '#!/usr/bin/env bash\necho SECOND\n' > "$D/hooks/two.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/one.sh\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_honest.sh"
# Устройство канарейки прибора: предмет свой НЕ зовёт. Отличие одно — печатает SKIP-строку
# про НЕОБЯЗАТЕЛЬНУЮ половину и работает дальше.
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/two.sh\n'
    printf 'echo "SKIP: необязательная половина проверки пропущена"\n'
    printf 'echo "основная половина: прошла"\n'
    printf 'exit 0\n'
} > "$D/hooks/tests/test_adv_fakegreen.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_honest.sh\n' >  "$D/.claude-docs/dep-index.tsv"
printf 'hooks/two.sh\t\t\t\thooks/tests/test_adv_fakegreen.sh\n' >> "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

OUT=$( cd "$D" && bash scripts/behavior-condition-probe.sh 2>&1 ); RC=$?

# A1 — свидетель, не зовущий свой предмет, обязан быть назван ложно-зелёным.
if grep -q 'test_adv_fakegreen' <<< "$OUT"; then ok
else bad A1 "ложно-зелёный не назван; вывод: $OUT"; fi

# A2 — прибор обязан покраснеть: известное ложно-зелёное поведение в дереве есть.
if [ "$RC" != 0 ]; then ok
else bad A2 "прибор вышел нулём при ложно-зелёном свидетеле в дереве (код $RC)"; fi

# A3 — счётчик ложно-зелёных не может быть нулём.
if grep -q 'ложно-зелёных: 0;' <<< "$OUT"; then
    bad A3 "прибор объявил «ложно-зелёных: 0», зачислив свидетеля в «судить нечем (SKIP)»"
else ok; fi

echo "test_adv_probe_skip_word_exonerates: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
