#!/usr/bin/env bash
# test_behavior_condition_probe.sh — свидетель прибора scripts/behavior-condition-probe.sh.
# Предмет: прибор ОТЛИЧАЕТ ложно-зелёного свидетеля от честного, считает неразрешимых и
# ломается громко. Дерево-песочница своё: живой репозиторий не читается и не правится.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; REPO="$(dirname "$REPO")"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
[ -f "$PROBE" ] || { echo "FAIL: нет $PROBE"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Песочница: предмет, честный свидетель, ложно-зелёный свидетель.
build() {  # build <каталог>
    local d="$1"
    mkdir -p "$d/hooks/tests" "$d/scripts"
    printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$d/hooks/subject.sh"
    # честный: вердикт снимается с ВЫВОДА предмета, значит выхолащивание его роняет
    {
        printf '#!/usr/bin/env bash\n'
        printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
        printf 'out=$(bash "$REPO/hooks/subject.sh" 2>&1)\n'
        printf 'case "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_honest.sh"
    # ложно-зелёный: предмет зовётся, но вердикт от него не зависит
    {
        printf '#!/usr/bin/env bash\n'
        printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
        printf 'bash "$REPO/hooks/subject.sh" >/dev/null 2>&1\n'
        printf 'exit 0\n'
    } > "$d/hooks/tests/test_adv_vacuous.sh"
    # ИСТОЧАЕМЫЙ предмет — та форма, ради которой прибор различает роль. Без неё нога M2
    # вакуумна: заглушка с немедленным выходом вредит только source, и в фикстуре из одних
    # исполняемых предметов различение роли ничего не меняет (замер мутантом 14 сентября 2026).
    printf '#!/usr/bin/env bash\nmark_value() { echo MARKER; }\n' > "$d/hooks/lib.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
        printf '. "$REPO/hooks/lib.sh"\n'
        printf 'case "$(mark_value 2>/dev/null)" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_sourced.sh"
    chmod +x "$d/hooks/subject.sh" "$d/hooks/lib.sh" "$d/hooks/tests/"*.sh
    ( cd "$d" && git init -q . && git add -A \
        && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
}

D="$TMP/repo"; build "$D"
OUT=$(CLAUDSOUL_REPO="$D" bash "$PROBE" 2>&1); RC=$?

# T1 — ложно-зелёный найден и назван поимённо.
grep -q "ложно-зелёных: 1" <<< "$OUT" && ok || bad T1 "ложно-зелёный не найден: $OUT"
grep -q "test_adv_vacuous.sh" <<< "$OUT" && ok || bad T1b "носитель не назван поимённо"

# T2 — честный свидетель ложно-зелёным НЕ считается: иначе прибор отбивает всё подряд.
grep -q "test_adv_honest.sh" <<< "$OUT" && bad T2 "честный свидетель посчитан ложно-зелёным" || ok

# T3 — находка даёт код 1, а не 0 и не 2.
[ "$RC" = 1 ] && ok || bad T3 "при находке код $RC, ожидался 1"

# T4 — ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: убери ложно-зелёного — прибор обязан замолчать и дать 0.
D2="$TMP/clean"; build "$D2"
rm -f "$D2/hooks/tests/test_adv_vacuous.sh"
( cd "$D2" && git add -A && git -c user.email=t@t -c user.name=t commit -qm drop ) >/dev/null 2>&1
OUT2=$(CLAUDSOUL_REPO="$D2" bash "$PROBE" 2>&1); RC2=$?
[ "$RC2" = 0 ] && ok || bad T4 "на чистом дереве код $RC2: $OUT2"
grep -q "ложно-зелёных: 0" <<< "$OUT2" && ok || bad T4b "на чистом дереве счёт не ноль: $OUT2"

# T5 — НЕРАЗРЕШИМЫЙ предмет считается отдельно от ложно-зелёного: это разные исходы.
D3="$TMP/opaque"; build "$D3"
rm -f "$D3/hooks/tests/test_adv_vacuous.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D3/hooks/tests/test_adv_opaque.sh"
chmod +x "$D3/hooks/tests/test_adv_opaque.sh"
( cd "$D3" && git add -A && git -c user.email=t@t -c user.name=t commit -qm opaque ) >/dev/null 2>&1
OUT3=$(CLAUDSOUL_REPO="$D3" bash "$PROBE" 2>&1); RC3=$?
grep -q "предмет не назван: 1" <<< "$OUT3" && ok || bad T5 "неразрешимый не посчитан: $OUT3"
grep -q "ложно-зелёных: 0" <<< "$OUT3" && ok || bad T5b "неразрешимый посчитан ложно-зелёным"
[ "$RC3" = 1 ] && ok || bad T5c "при неразрешимом код $RC3, ожидался 1"

# T6 — прибор ЛОМАЕТСЯ ГРОМКО: нет свидетелей-атак вовсе — это отказ прибора, а не чистота.
D4="$TMP/empty"; mkdir -p "$D4/hooks/tests"
( cd "$D4" && git init -q . && printf 'x\n' > f.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm e ) >/dev/null 2>&1
OUT4=$(CLAUDSOUL_REPO="$D4" bash "$PROBE" 2>&1); RC4=$?
[ "$RC4" = 2 ] && ok || bad T6 "пустой универсум дал код $RC4, ожидался 2 (отказ прибора)"
grep -q "BROKEN" <<< "$OUT4" && ok || bad T6b "отказ прибора не назван словом BROKEN"

echo "test_behavior_condition_probe: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
