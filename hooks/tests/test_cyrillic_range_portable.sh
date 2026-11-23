#!/usr/bin/env bash
# СУДИТ: дерево
# test_cyrillic_range_portable.sh — кириллический ДИАПАЗОН в скобочном классе не живёт в коде shell.
#
# Результат: в исполняемом коде (hooks, lib, scripts, install.sh — не тесты, не perl) нет строк с
#            классом вида «[а-я…]»: GNU grep 3.x в локали C.UTF-8 отвергает его («Invalid collation
#            character»), в C он распадается на байты, а на macOS проходит — дефект виден только на
#            раннере. Положительный контроль: подложенная строка с диапазоном ловится.
# Проверка результата: bash hooks/tests/test_cyrillic_range_portable.sh даёт 0
#
# Повод, 13 сентября 2026 (D325): словарь маркера повтора `RC_SELF_REPEAT_RE` нёс диапазон в
# ПЕРЕМЕННОЙ, а не в строке вызова grep; сосед `test_case_folding_portable.sh` судит по строке
# вызова и переменной не увидел. CI 05a7965 покраснел, локальный набор на macOS был зелёный.
# Правило записано в docs/development.md; здесь оно получает сверщика по ДЕРЕВУ.
#
# Сам сверщик диапазона не содержит: класс собирается из байтовых диапазонов UTF-8 (первый байт
# D0/D1 — кириллица), иначе он падал бы там же, где предмет. Байтовый grep (LC_ALL=C) намеренно.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
CYR=$(printf '(\xd0[\x80-\xbf]|\xd1[\x80-\xbf])')
RX="\\[[^]]*${CYR}-${CYR}[^]]*\\]"
# Носитель — строка, где диапазон достаётся POSIX-движку: вызов grep/sed/awk/case либо
# присваивание переменной-шаблона (`…_RE=`, `…RX=`, `…PATTERN=`), которую grep прочтёт позже.
# Регэкспы jq (Oniguruma) и Python (`re`) юникодные, диапазон им законен — они не носители;
# perl с `-CSD -Mutf8` тоже. НАЗВАННЫЙ ПРЕДЕЛ: шаблон в переменной с иным именем, поданный
# grep через две строки, сканер не увидит. Условие снятия: сверка ПОТОКОМ данных, а не строкой.
# Фильтр применяется к строке С НОМЕРОМ (`N:текст`): присваивание — сразу после номера,
# вызов — где угодно в тексте. Якорь `^` внутри общей альтернативы после номера не совпадал бы
# никогда — первая редакция теряла переменную и ловила только вызов grep.
CONSUMER='^[0-9]+:([[:space:]]*[A-Za-z_]*(_?RE|RX|PATTERN)=|.*(grep|sed|awk|expr|case ))'
# Переменная-шаблон, которую ФАЙЛ передаёт в jq (`--arg имя "$ПЕРЕМЕННАЯ"`), — не носитель:
# её движок юникодный (RC_TRACE_*_RE в root-cause-lib.sh). Это приближение к потоку данных,
# а не он сам: переменная, поданная jq через промежуточное имя, будет названа носителем ложно —
# тогда её надо переименовать или подать явно; переменная, поданная И jq, И grep, пройдёт.
scan() {  # scan <файлы…> → строки file:line:text с диапазоном у POSIX-потребителя, вне комментариев
    for f in "$@"; do
        [ -f "$f" ] || continue
        LC_ALL=C grep -nE "$RX" "$f" 2>/dev/null \
          | grep -vE '^[0-9]+:[[:space:]]*#' \
          | grep -v 'perl ' \
          | grep -E "$CONSUMER" \
          | while IFS= read -r hit; do
                name=$(printf '%s' "$hit" | sed -nE 's/^[0-9]+:[[:space:]]*([A-Za-z_]+)=.*/\1/p')
                if [ -n "$name" ] && LC_ALL=C grep -qE -- "--arg(json)? [A-Za-z_]+ \"?\\\$\{?${name}\}?" "$f" 2>/dev/null; then
                    continue
                fi
                printf '%s:%s\n' "$f" "$hit"
            done
    done
}
FILES=$(cd "$ROOT" && ls hooks/*.sh hooks/lib/*.sh lib/*.sh scripts/*.sh install.sh uninstall.sh 2>/dev/null)
HITS=$(cd "$ROOT" && scan $FILES)
N=$(printf '%s\n' "$HITS" | grep -c . || true)
if [ "$N" -eq 0 ]; then ok; else bad "T1" "кириллический диапазон в коде shell ($N):"$'\n'"$HITS"; fi
# Положительный контроль: сканер ловит подложенный диапазон и в переменной, и в строке grep.
# Фикстура собирается из байтов, чтобы сам файл теста форму не нёс.
TMP=$(mktemp -d)
A=$(printf '\xd0\xb0'); YA=$(printf '\xd1\x8f'); YO=$(printf '\xd1\x91')
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'RE="(втор|трет)[%s-%s%s]* раз"\n' "$A" "$YA" "$YO"
  printf 'grep -qE "проб[%s-%s]" x\n' "$A" "$YA"
  printf '# [%s-%s] в комментарии не считается\n' "$A" "$YA"
  printf 'perl -pe "s/крон[%s-%s%s]*/в/"\n' "$A" "$YA" "$YO"
} > "$TMP/carrier.sh"
C=$(scan "$TMP/carrier.sh"); CN=$(printf '%s\n' "$C" | grep -c . || true)
[ "$CN" = 2 ] && ok || bad "T2" "положительный контроль: ждали 2 находки (переменная и grep), получили $CN: $C"
# Отрицательный контроль: POSIX-классы и перечень букв без дефиса не ловятся.
printf '%s\n' 'grep -qE "[[:alpha:]]+ раз" x' 'grep -qE "[аеё]" x' > "$TMP/clean.sh"
[ -z "$(scan "$TMP/clean.sh")" ] && ok || bad "T3" "отрицательный контроль: ложная находка на $(scan "$TMP/clean.sh")"
echo "cyrillic range portable: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
