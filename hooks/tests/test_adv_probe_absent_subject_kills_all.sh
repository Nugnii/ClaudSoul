#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# АТАКА: одно объявление, указывающее в файл, которого нет В СНИМКЕ, убивает ВЕСЬ прибор.
#
# Вход: песочница-репозиторий, два свидетеля. Первый честен и разрешим. Второй объявляет
# `# СУДИТ: hooks/three.sh` — механизм существует в рабочем дереве, но ещё не закоммичен,
# а снимок прибора собирается `git archive HEAD` (behavior-condition-probe.sh:242).
#
# Ожидание: прибор судит то, что судимо, а на необъявляемом предмете называет ВИНОВНОГО
# свидетеля и продолжает. Его собственный договор (шапка прибора) отводит коду 2 два
# состояния: «нет свидетелей» и «снимок дерева не собрался». Устаревшее объявление внутри
# судимого файла — это ДАННЫЕ, а не поломка прибора.
#
# Факт: `sp_hollow_run` отвечает 9, прибор печатает «BROKEN: предмет … недоступен в снимке»
# и выходит кодом 2 (behavior-condition-probe.sh:337-340). Вердикта нет ни по кому, включая
# честного свидетеля; имени виновного в сообщении нет — оператору дан только путь предмета.
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
# След прогона — в свой каталог: общий журнал прибора не должен получить фикстуру.
export STATE_DIR="$TMP/state"

D="$TMP/repo"
mkdir -p "$D/scripts" "$D/hooks/tests" "$D/.claude-docs"
cp "$PROBE" "$D/scripts/"
# СОСЕДИ СВЕРЕНЫ С ТЕМ, ЧТО БИБЛИОТЕКА ЗОВЁТ (23 сентября 2026, находка замера suite-linux).
# Здесь копировались не все: `timeout-lib.sh` забыли, а библиотека выхолащивания без него
# отвечает «BROKEN: свидетелю не поставить срока». На машине автора это маскировал фоллбек на
# установленную копию в ~/.claude; в чистом контейнере копии нет, и тест падал целиком.
for _lib in subject-probe-lib.sh frame-control-lib.sh timeout-lib.sh; do
    cp "$REPO/hooks/$_lib" "$D/hooks/$_lib" || { echo "SKIP: нет hooks/$_lib"; exit 0; }
done
[ -f "$REPO/hooks/portable-lib.sh" ] && cp "$REPO/hooks/portable-lib.sh" "$D/hooks/"

printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$D/hooks/one.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_honest.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_honest.sh\n' > "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

# Новый механизм и его свидетель написаны, коммита ещё нет — обычный рабочий момент.
printf '#!/usr/bin/env bash\necho THIRD\nexit 0\n' > "$D/hooks/three.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/three.sh\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/three.sh" 2>&1)" in *THIRD*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_uncommitted.sh"

# Второй вход того же класса: объявление указывает на механизм, которого нет НИГДЕ —
# ни в коммите, ни в рабочем дереве (переименован, удалён). Добавлен 22 сентября 2026 при
# починке: первый вход (незакоммиченный механизм) стал законным — снимок теперь накрывается
# рабочим деревом, и прибор такого свидетеля судит, а не падает. Остался этот, и у него
# своё требование: прибор обязан НАЗВАТЬ виновного и продолжить, а не объявить себя сломанным.
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/renamed-away.sh\n'
    printf 'exit 0\n'
} > "$D/hooks/tests/test_adv_stale_subject.sh"

OUT=$( cd "$D" && bash scripts/behavior-condition-probe.sh 2>&1 ); RC=$?

# A1 — вердикт по судимым свидетелям обязан быть вынесен, а не съеден чужим объявлением.
if grep -q 'свидетелей-атак:' <<< "$OUT"; then ok
else bad A1 "прибор не вынес ни одного вердикта (код $RC), вывод целиком: $OUT"; fi

# A2 — виновный свидетель обязан быть НАЗВАН: без имени чинить нечего, объявлений 268.
if grep -q 'test_adv_stale_subject' <<< "$OUT"; then ok
else bad A2 "свидетель с устаревшим объявлением не назван, вывод: $OUT"; fi

# A3 — код 2 отведён поломке ПРИБОРА, а не данным внутри судимого файла.
if [ "$RC" != 2 ]; then ok
else bad A3 "прибор объявил себя сломанным (код 2) из-за объявления в чужом файле"; fi

echo "test_adv_probe_absent_subject_kills_all: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
