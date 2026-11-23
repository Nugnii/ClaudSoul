#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# АТАКА: свидетель выпивает очередь контрастов, а прибор винит в пропаже свой потолок.
#
# Вход: два ложно-зелёных свидетеля, первый из них читает стандартный вход (`cat >/dev/null`
# — обычная форма у тестов, разбирающих payload хука). Потолок VPRINT_MAX по умолчанию 3,
# то есть развернуться обязаны ОБА.
#
# Ожидание: контраст печатается для обоих. Ровно этот дефект чинили 22 сентября 2026 у
# владельца прогона — `sp_run_witness` запускает свидетеля с `< /dev/null`
# (subject-probe-lib.sh:92), потому что «тест, читающий stdin, выпивает остаток очереди».
#
# Факт: цикл вывода находок читает `$VPAIRS` here-строкой (behavior-condition-probe.sh:479-487),
# а `_contrast` (:233-254) зовёт `bash "$_t"` БЕЗ `< /dev/null` — своей копией прогона, мимо
# владельца. Первый же свидетель выпивает here-строку, цикл кончается после одной итерации,
# и прибор печатает «(ещё 1 контрастов не развёрнуто: VPRINT_MAX=3)» — объясняя пропажу
# потолком, которого не достиг. Вторая половина той же дыры: копия не ставит и СРОКА,
# снятого у владельца тем же днём.
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

printf '#!/usr/bin/env bash\necho M1\n' > "$D/hooks/one.sh"
printf '#!/usr/bin/env bash\necho M2\n' > "$D/hooks/two.sh"
# Первым по алфавиту — пьющий вход. Оба ложно-зелены: своего предмета не зовут.
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/one.sh\n'
    printf 'cat > /dev/null\n'
    printf 'echo "первый ложно-зелёный"\n'
    printf 'exit 0\n'
} > "$D/hooks/tests/test_adv_a_drinker.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/two.sh\n'
    printf 'echo "второй ложно-зелёный"\n'
    printf 'exit 0\n'
} > "$D/hooks/tests/test_adv_b_plain.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_a_drinker.sh\n' >  "$D/.claude-docs/dep-index.tsv"
printf 'hooks/two.sh\t\t\t\thooks/tests/test_adv_b_plain.sh\n'   >> "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

OUT=$( cd "$D" && VPRINT_MAX=3 bash scripts/behavior-condition-probe.sh 2>&1 )

# Рамка: оба обязаны быть найдены ложно-зелёными, иначе атака не о контрастах.
# РАМКА НЕ СОБРАЛАСЬ — КОД 2, А НЕ НОЛЬ (23 сентября 2026, D474). Прибор, выхолощенный
# до заглушки, отвечает пустотой — и эта ветка выпускала тест НУЛЁМ, то есть он был
# зелен на мёртвом предмете. Назвал его сам прибор, когда класс «судит сам прибор»
# перестал быть укрытием.
grep -q 'ложно-зелёных: 2;' <<< "$OUT" || { echo "РАМКА НЕ СОБРАЛАСЬ: прибор нашёл не двоих на подготовленной фикстуре: $OUT" >&2; exit 2; }

# D1 — контраст второй находки обязан быть напечатан: потолок 3, находок 2.
if grep -q 'контраст: hooks/tests/test_adv_b_plain.sh' <<< "$OUT"; then ok
else bad D1 "контраст второй находки не напечатан — очередь выпита первым свидетелем"; fi

# D2 — прибор не смеет объяснять пропажу потолком, которого не достиг.
if grep -q 'не развёрнуто: VPRINT_MAX=3' <<< "$OUT"; then
    bad D2 "прибор списал пропажу на VPRINT_MAX=3, развернув всего один контраст из двух"
else ok; fi

echo "test_adv_probe_contrast_drinks_queue: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
