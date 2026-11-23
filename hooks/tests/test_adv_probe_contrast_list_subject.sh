#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# АТАКА: контраст не умеет СПИСКА и КАТАЛОГА — а их в дереве 70 объявлений.
#
# Вход: свидетель со списочным предметом `# СУДИТ: hooks/one.sh hooks/two.sh` — та самая
# форма, которую завели 21 сентября 2026 (D474) и которую вписывает `--apply`
# объявлятеля. Зовётся `behavior-condition-probe.sh --contrast <свидетель>`.
#
# Ожидание: контраст показывает разницу живого и выпотрошенного прогонов — он объявлен
# ЕДИНСТВЕННЫМ источником образца для контроля работы (шапка режима).
#
# Факт: `_contrast` (behavior-condition-probe.sh:233-254) выхолащивает СВОЕЙ копией кода —
# `cp "$_s" "$_s.keep"`, — а владелец `sp_hollow_run` знает три вида предмета: список,
# каталог, файл. Копия знает один. На списке `cp` не находит файла с таким именем и
# отдаёт 9 (`exit 9` = «выхолостить не удалось»), блок ВЫПОТРОШЕННЫЙ выходит пустым, и
# режим выдаёт это за образец, выйдя кодом 0. Род K реестра: правило вынесено во
# владельца, копия у потребителя осталась. В дереве 66 списочных объявлений и 4 каталожных.
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
    printf '# СУДИТ: hooks/one.sh hooks/two.sh\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *MARKER*) ;; *) exit 1 ;; esac\n'
    printf 'case "$(bash "$R/hooks/two.sh" 2>&1)" in *SECOND*) ;; *) exit 1 ;; esac\n'
    printf 'echo "оба механизма живы"\n'
    printf 'exit 0\n'
} > "$D/hooks/tests/test_adv_list.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_list.sh\n' > "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

OUT=$( cd "$D" && bash scripts/behavior-condition-probe.sh --contrast hooks/tests/test_adv_list.sh 2>&1 )

# Рамка: режим обязан был найти предмет и дойти до блоков контраста.
# РАМКА НЕ СОБРАЛАСЬ — КОД 2, А НЕ НОЛЬ (24 сентября 2026, D474). Выхолощенный прибор
# отвечает пустотой, и эта ветка выпускала тест НУЛЁМ — он был зелен на мёртвом
# предмете. Назвал его сам прибор, когда класс «судит сам прибор» перестал быть
# укрытием и все девять его членов впервые получили вердикт.
grep -q 'ВЫПОТРОШЕННЫЙ' <<< "$OUT" || { echo "РАМКА НЕ СОБРАЛАСЬ: режим не дошёл до контраста на подготовленной фикстуре: ${OUT}" >&2; exit 2; }

# C1 — «выхолостить не удалось» (9) в блоке контраста значит, что предмет не трогали.
if grep -q '── код: 9 ──' <<< "$OUT"; then
    bad C1 "контраст отдал код 9 — списочный предмет не выхолощен; вывод: $OUT"
else ok; fi

# C2 — честный свидетель на ВЫПОТРОШЕННОМ списке обязан покраснеть: его код 1, а не 9/0.
if grep -q '── код: 1 ──' <<< "$OUT"; then ok
else bad C2 "в контрасте нет ни одного красного кода — выпотрошенный прогон не состоялся"; fi

echo "test_adv_probe_contrast_list_subject: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
