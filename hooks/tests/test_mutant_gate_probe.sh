#!/usr/bin/env bash
# test_mutant_gate_probe.sh — свидетель прибора scripts/mutant-gate-probe.sh.
# Предмет: прибор ОТЛИЧАЕТ мутанта с гейтом применения от мутанта без гейта и ломается громко.
# Дерево-песочница своё: живой репозиторий не читается и не правится.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$REPO/scripts/mutant-gate-probe.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

[ -f "$PROBE" ] || { echo "FAIL: нет $PROBE"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Песочница: цель мутации и два мутанта — честный (гейт есть) и вакуумный (гейт есть в
# тексте, но вердикт от мутации не зависит: тест выходит нулём при любом исходе).
build() {
    local d="$1"
    mkdir -p "$d/hooks/tests" "$d/scripts"
    cp "$PROBE" "$d/scripts/"
    printf 'MARKER_ALPHA=1\n' > "$d/hooks/tests/target.txt"
}

honest() {  # honest <каталог> <имя>
    {
        printf '#!/usr/bin/env bash\n'
        printf 'D="$(cd "$(dirname "$0")" && pwd)"\n'
        printf 'cp "$D/target.txt" "$D/.t.$$"\n'
        printf 'python3 - "$D/.t.$$" <<PYX\n'
        printf 'import sys\n'
        printf 'p = sys.argv[1]\n'
        printf 's = open(p, encoding="utf-8").read()\n'
        printf 'need%s = %sMARKER_ALPHA%s\n' le "'" "'"
        printf 'if needle not in s:\n'
        printf '    sys.exit("нет места мутации")\n'
        printf 's = s.replace(needle, "MARKER_BETA")\n'
        printf 'open(p, "w", encoding="utf-8").write(s)\n'
        printf 'PYX\n'
        printf 'rc=$?\n'
        printf 'rm -f "$D/.t.$$"\n'
        printf 'exit $rc\n'
    } > "$1/hooks/tests/$2"
    chmod +x "$1/hooks/tests/$2"
}

vacuous() {  # vacuous <каталог> <имя> — слова гейта есть, но код возврата от них не зависит
    {
        printf '#!/usr/bin/env bash\n'
        printf 'D="$(cd "$(dirname "$0")" && pwd)"\n'
        printf 'cp "$D/target.txt" "$D/.v.$$"\n'
        printf 'python3 - "$D/.v.$$" <<PYY\n'
        printf 'import sys\n'
        printf 'p = sys.argv[1]\n'
        printf 's = open(p, encoding="utf-8").read()\n'
        printf 'need%s = %sMARKER_ALPHA%s\n' le "'" "'"
        printf 'if needle not in s:\n'
        printf '    print("нет места мутации")\n'
        printf 'open(p, "w", encoding="utf-8").write(s)\n'
        printf 'PYY\n'
        printf 'rm -f "$D/.v.$$"\n'
        printf 'exit 0\n'
    } > "$1/hooks/tests/$2"
    chmod +x "$1/hooks/tests/$2"
}

# T1 — ЧЕСТНЫЙ мутант: прибор молчит и даёт 0.
H="$TMP/honest"; build "$H"; honest "$H" "test_honest_mutant.sh"
O1=$(CLAUDSOUL_REPO="$H" bash "$H/scripts/mutant-gate-probe.sh" 2>&1); RC1=$?
[ "$RC1" = 0 ] && ok || bad T1 "на честном мутанте код $RC1: $O1"
grep -q "вакуумных (не заметили, что мутировать нечего): 0" <<< "$O1" && ok \
    || bad T1b "счёт вакуумных не ноль на честном мутанте: $O1"

# T2 — ВАКУУМНЫЙ мутант: прибор находит его, называет поимённо и даёт 1.
V="$TMP/vac"; build "$V"; vacuous "$V" "test_vacuous_mutant.sh"
O2=$(CLAUDSOUL_REPO="$V" bash "$V/scripts/mutant-gate-probe.sh" 2>&1); RC2=$?
[ "$RC2" = 1 ] && ok || bad T2 "вакуумный мутант не найден, код $RC2: $O2"
grep -q "test_vacuous_mutant.sh" <<< "$O2" && ok || bad T2b "вакуумный не назван поимённо"

# T3 — ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: убери вакуумного — прибор обязан замолчать. Без этой ноги
# T2 зеленела бы на приборе, который называет вакуумным кого угодно.
rm -f "$V/hooks/tests/test_vacuous_mutant.sh"; honest "$V" "test_honest2.sh"
O3=$(CLAUDSOUL_REPO="$V" bash "$V/scripts/mutant-gate-probe.sh" 2>&1); RC3=$?
[ "$RC3" = 0 ] && ok || bad T3 "после снятия вакуумного код $RC3: $O3"

# T4 — ПУСТОЙ УНИВЕРСУМ — отказ прибора (код 2), а не чистота: мутантов нет, значит
# проверять нечего, и выдавать это за «вакуумных ноль» нельзя.
E="$TMP/empty"; build "$E"
O4=$(CLAUDSOUL_REPO="$E" bash "$E/scripts/mutant-gate-probe.sh" 2>&1); RC4=$?
[ "$RC4" = 2 ] && ok || bad T4 "пустой универсум дал код $RC4, ожидался 2"
grep -q "BROKEN" <<< "$O4" && ok || bad T4b "отказ прибора не назван словом BROKEN"

echo "test_mutant_gate_probe: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
