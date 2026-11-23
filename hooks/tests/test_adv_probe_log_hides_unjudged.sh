#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# АТАКА: след прогона не знает о двух новых классах, и «Проверка» пункта D342 зеленеет,
# когда вердикта не получил НИКТО.
#
# Вход: песочница из трёх свидетелей — честный, «рамка не собралась» (красен и без
# выхолащивания) и «объявление устарело» (предмет переименован). Двое последних вердикта
# не получают: цикл прибора делает `continue` (behavior-condition-probe.sh:334, :346).
#
# Ожидание: след, по которому читается показание, обязан различать «судили и не нашли» и
# «не судили вовсе». Иначе прибор врёт о себе ровно тем способом, который сам называет
# корнем R6 — два состояния мира одним значением канала.
#
# Факт: счётчик RESOLVED инкрементируется ДО прогона (:320) и ни на одной из двух веток
# не убавляется, а в строку журнала (:447-449) поля `framed` и `stale` не пишутся вовсе.
# Журнал получает {"total":3,"resolved":3,"vacuous":0,...} — «трое разрешимы, ложно-зелёных
# нет», хотя вердикт вынесен ОДНОМУ. «Проверка» пункта D342 (BACKLOG-archive.md:15275)
# читает `"vacuous":0` последней строки и зеленеет; прибор выходит кодом 0.
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
printf '#!/usr/bin/env bash\n# СУДИТ: hooks/two.sh\nexit 3\n'            > "$D/hooks/tests/test_adv_framed.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: hooks/renamed-away.sh\nexit 0\n'   > "$D/hooks/tests/test_adv_stale.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_honest.sh\n' > "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

OUT=$( cd "$D" && bash scripts/behavior-condition-probe.sh 2>&1 ); RC=$?

# Рамка: прибор обязан был отработать и увидеть оба класса — иначе атака не о том.
# РАМКА НЕ СОБРАЛАСЬ — КОД 2, А НЕ НОЛЬ (23 сентября 2026, D474). Прибор, выхолощенный
# до заглушки, отвечает пустотой — и эта ветка выпускала тест НУЛЁМ, то есть он был
# зелен на мёртвом предмете. Назвал его сам прибор, когда класс «судит сам прибор»
# перестал быть укрытием.
grep -q 'рамка не собралась (красны' <<< "$OUT" || { echo "РАМКА НЕ СОБРАЛАСЬ: прибор не дошёл до классов на подготовленной фикстуре: $OUT" >&2; exit 2; }

LOGF="$STATE_DIR/behavior-condition-probe.jsonl"
[ -s "$LOGF" ] || { echo "SKIP: следа прогона нет — судить нечего"; exit 0; }
LINE=$(tail -1 "$LOGF")

# B1 — след обязан нести число не получивших вердикта: без него читатель следа их не увидит.
if grep -qE '"(framed|stale|unjudged)"' <<< "$LINE"; then ok
else bad B1 "в следе нет ни одного поля о не получивших вердикта; строка: $LINE"; fi

# B2 — ДВА ЧИСЛА ВМЕСТО ОДНОГО, и это намеренно (уточнено 22 сентября 2026 при починке).
# Атака требовала, чтобы `resolved` означало «вердикт вынесен». Так сделать нельзя: это же
# число входит в инвариант вселенной (`resolved + tree + unresolved = total`, нога T9
# свидетеля прибора), и убавление его на непросуженных сломало бы сумму. Развели предметы:
# `resolved` отвечает «у скольких предмет вообще можно выхолостить», `judged` — «скольким
# сказали да или нет». Нога судит их РАЗНОСТЬ: она обязана равняться числу тех, кого прибор
# сам назвал непросуженными.
J=$(sed -n 's/.*"judged":\([0-9]*\).*/\1/p' <<< "$LINE")
R=$(sed -n 's/.*"resolved":\([0-9]*\).*/\1/p' <<< "$LINE")
F=$(sed -n 's/.*"framed":\([0-9]*\).*/\1/p' <<< "$LINE")
S=$(sed -n 's/.*"stale":\([0-9]*\).*/\1/p' <<< "$LINE")
if [ -n "$J" ] && [ -n "$R" ] && [ -n "$F" ] && [ -n "$S" ] && [ "$((R - F - S))" = "$J" ]; then ok
else bad B2 "разность resolved и непросуженных не равна judged: r=$R f=$F s=$S j=$J; строка: $LINE"; fi

# B3 — «Проверка» пункта D342 читает ровно эту строку и зеленеет на непросуженном дереве.
# Команда берётся У ВЛАДЕЛЬЦА — из самого пункта, — а не воспроизводится здесь: копия
# формулы у потребителя и была бы тем родом K, который нога судит (уточнено 22 сентября
# 2026 при починке). Прогоняется она на ФИКСТУРНОМ журнале: свой STATE_DIR, своё дерево.
# КОМАНДА БЕРЁТСЯ У НАЗВАННОГО ПУНКТА, А НЕ У ПЕРВОГО ПОПАВШЕГОСЯ (24 сентября 2026).
# Прежняя редакция брала «первый файл, поминающий журнал, и первую в нём строку Проверки».
# Пока пункт с сильным критерием лежал в BACKLOG.md, нога проходила; едва он закрылся и уехал
# в архив, первым стал исторический D342, чей критерий (`vacuous == 0` и `judged > 0`) на этой
# фикстуре ЗЕЛЕН — и нога покраснела, хотя в приборе ничего не менялось. Выбор «по соседству»
# и есть состояние проверки без владельца.
#
# Владелец назван: D474, его критерий `judged == resolved` — ровно то, что нога и утверждает
# (непросуженные обязаны рушить показание). НАЗВАННЫЙ ПРЕДЕЛ: если команду D474 перепишут,
# нога пойдёт за ней; если пункт исчезнет из обоих файлов — SKIP с названной причиной, а не
# молчаливый переход на чужую команду.
D342_CMD=$(python3 - "$REPO/BACKLOG.md" "$REPO/BACKLOG-archive.md" <<'PYEOF'
import io, re, sys
for path in sys.argv[1:]:
    try:
        text = io.open(path, encoding="utf-8").read()
    except OSError:
        continue
    m = re.search(r"^- [^\n]*\*\*D474\*\*.*?(?=^- [☐◐☑⊘] \*\*D|\Z)", text, re.S | re.M)
    if not m:
        continue
    c = re.search(r"\*\*Проверка\.\*\* `(.+?)`", m.group(0), re.S)
    if c:
        sys.stdout.write(c.group(1))
        break
PYEOF
)
if [ -z "$D342_CMD" ]; then
    echo "SKIP: пункт D474 с «Проверкой» по журналу прибора не найден ни в BACKLOG.md, ни в архиве"; exit 0
fi
D342_RC=$( cd "$D" && CLAUDSOUL_REPO="$D" STATE_DIR="$STATE_DIR" bash -c "$D342_CMD" >/dev/null 2>&1; echo $? )
if [ "$D342_RC" != 0 ]; then ok
else bad B3 "«Проверка» пункта зелена, хотя двое из трёх не судимы (её команда: $D342_CMD)"; fi

# B4 — НЕПРОСУЖЕННЫЕ НАЗВАНЫ ЧИСЛОМ И ИМЕНАМИ (уточнено 22 сентября 2026 при починке).
# Атака требовала ненулевого кода. Так сделать нельзя: несобравшаяся рамка — это «судить
# нечем», такое же, как SKIP, а не находка; своя фикстура `test_adv_always_red.sh` красна
# ПО ЗАМЫСЛУ, и прибор краснел бы на дереве, где находок нет. Полнота суда — вопрос
# ПОКАЗАНИЯ пункта (нога B3 выше), а код возврата остаётся про находки. Здесь судится то,
# без чего показание слепо: прибор обязан СКАЗАТЬ о непросуженных, а не умолчать.
if grep -q 'рамка не собралась: *[1-9]' <<< "$OUT" && grep -q 'объявление устарело: *[1-9]' <<< "$OUT"; then ok
else bad B4 "прибор не назвал непросуженных числом; вывод: $OUT"; fi

echo "test_adv_probe_log_hides_unjudged: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
