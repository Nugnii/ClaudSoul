#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# test_behavior_condition_probe.sh — свидетель прибора scripts/behavior-condition-probe.sh.
# Предмет: прибор ОТЛИЧАЕТ ложно-зелёного свидетеля от честного, считает неразрешимых и
# ломается громко. Дерево-песочница своё: живой репозиторий не читается и не правится.
set -uo pipefail
# СОСТОЯНИЕ ТЕСТА — СВОЁ (20 сентября 2026). Прибор с этого дня оставляет след прогона в
# STATE_DIR, и без изоляции песочница свидетеля писала бы в ОБЩИЙ журнал: первая же строка
# там оказалась от теста (`total:4`, четыре подставных свидетеля) вместо дерева. Показание
# пункта D342 читает последнюю строку — и прочло бы фикстуру как мир.
export STATE_DIR="${STATE_DIR_TEST:-$(mktemp -d)}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"; REPO="$(dirname "$REPO")"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
SPL="$REPO/hooks/subject-probe-lib.sh"
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
    # ЧЕСТНЫЙ СВИДЕТЕЛЬ, ИСТОЧАЮЩИЙ ПРЕДМЕТ ЧЕРЕЗ ПЕРЕМЕННУЮ (20 сентября 2026, работа по
    # D342). Обычная форма: путь кладётся в переменную, а строка `source` имени файла уже
    # не несёт. Прежний прибор узнавал источание grep-ом по базовому имени В ТОЙ ЖЕ СТРОКЕ,
    # не находил его и ставил заглушку с `exit 0` — а `source` такой заглушки завершает САМ
    # ТЕСТ кодом ноль. Честный свидетель объявлялся ложно-зелёным по построению. Замер:
    # очередь 78, после снятия развилки 48, то есть тридцать записей были оболганы; на
    # выборке 12 независимый прогон и прибор совпали 12 из 12.
    printf '#!/usr/bin/env bash\nmark_var() { echo MARKER; }\n' > "$d/hooks/lib2.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
        printf 'LIB="$REPO/hooks/lib2.sh"\n'
        printf '. "$LIB"\n'
        printf 'case "$(mark_var 2>/dev/null)" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_sourced_var.sh"
    # ПРЕДМЕТ-ГРУППА (21 сентября 2026): свидетель конвейера судит НЕСКОЛЬКО механизмов
    # сразу и краснеет от выхолащивания любого звена. Объявление с косой на конце говорит
    # прибору выхолостить весь каталог.
    mkdir -p "$d/hooks/group"
    printf '#!/usr/bin/env bash\necho ONE\n' > "$d/hooks/group/one.sh"
    printf '#!/usr/bin/env bash\necho TWO\n' > "$d/hooks/group/two.sh"
    { printf '#!/usr/bin/env bash\n'
      printf '# СУДИТ: hooks/group/\n'
      printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
      printf 'a=$(bash "$REPO/hooks/group/one.sh" 2>&1); b=$(bash "$REPO/hooks/group/two.sh" 2>&1)\n'
      printf 'case "$a$b" in *ONE*TWO*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_pipeline.sh"

    # ПРЕДМЕТ-СПИСОК (21 сентября 2026, D474): свидетель зависит от НЕСКОЛЬКИХ механизмов в
    # РАЗНЫХ каталогах — каталогом такой предмет не покрыть, а выбрать одно звено значило бы
    # гадать. Объявление перечисляет все, выхолащиваются все.
    mkdir -p "$d/hooks/lib"
    printf '#!/usr/bin/env bash\necho ALPHA\n' > "$d/hooks/alpha.sh"
    printf '#!/usr/bin/env bash\necho BETA\n' > "$d/hooks/lib/beta.sh"
    { printf '#!/usr/bin/env bash\n'
      printf '# СУДИТ: hooks/alpha.sh hooks/lib/beta.sh\n'
      printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
      printf 'a=$(bash "$REPO/hooks/alpha.sh" 2>&1); b=$(bash "$REPO/hooks/lib/beta.sh" 2>&1)\n'
      printf 'case "$a$b" in *ALPHA*BETA*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_pair.sh"

    # КРАСНЫЙ И БЕЗ ПРАВОК (22 сентября 2026, D474): свидетель, падающий на ЖИВОМ предмете,
    # даёт тот же ненулевой код, что и честный. Без контроля рамки прибор зачислял его в
    # честные, не проверив ни разу.
    printf '#!/usr/bin/env bash\necho GAMMA\n' > "$d/hooks/gamma.sh"
    { printf '#!/usr/bin/env bash\n'
      printf '# СУДИТ: hooks/gamma.sh\n'
      printf 'exit 1\n'
    } > "$d/hooks/tests/test_adv_always_red.sh"

    # ТРЕТИЙ КЛАСС ОБЯЗАН БЫТЬ В ПЕСОЧНИЦЕ (21 сентября 2026). Без свидетеля с предметом
    # «дерево» вселенная делится надвое, вычитание и перечень совпадают, и нога T9 зелена на
    # ОБЕИХ редакциях прибора — проверено прогоном против прежнего вычитания: 28 из 28.
    # Различение ставится фикстурой, а не формулировкой ноги.
    { printf '#!/usr/bin/env bash\n'
      printf '# СУДИТ: дерево\n'
      printf 'exit 0\n'
    } > "$d/hooks/tests/test_adv_tree_subject.sh"
    # ЧЕТВЁРТЫЙ КЛАСС ОБЯЗАН БЫТЬ В ПЕСОЧНИЦЕ (24 сентября 2026, D478) — по тому же доводу,
    # что и третий. Класс «требует настоящего дерева» завели, а фикстуру не тронули: в
    # рабочем дереве сумма разъехалась (583 + 17 + 0 = 600 при вселенной 601), и нога T9
    # оставалась зелена, потому что в песочнице носителя класса нет. Различение ставится
    # фикстурой, а не формулировкой ноги.
    { printf '#!/usr/bin/env bash\n'
      printf '# СУДИТ: hooks/subject.sh\n'
      printf '# СУД: только в рабочем дереве\n'
      printf 'exit 0\n'
    } > "$d/hooks/tests/test_adv_realtree_subject.sh"
    # ВХОД ПРИБОРА СМЕНИЛСЯ 20 сентября 2026 (работа по D470): предмет свидетеля он
    # спрашивает у индекса зависимостей, а не выводит регуляркой из текста теста. Песочница
    # обязана дать ему этот вход — иначе прибор отвечает BROKEN «индекса нет», и все ноги
    # краснеют не по делу. Связи ставятся ровно те, что судят ноги ниже.
    mkdir -p "$d/.claude-docs"
    { printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
      printf 'hooks/subject.sh\tx\t\t\thooks/tests/test_adv_honest.sh,hooks/tests/test_adv_vacuous.sh\t\n'
      printf 'hooks/lib.sh\tx\t\t\thooks/tests/test_adv_sourced.sh\t\n'
      printf 'hooks/lib2.sh\tx\t\t\thooks/tests/test_adv_sourced_var.sh\t\n'
    } > "$d/.claude-docs/dep-index.tsv"
    chmod +x "$d/hooks/subject.sh" "$d/hooks/lib.sh" "$d/hooks/lib2.sh" "$d/hooks/tests/"*.sh
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
# T2b: честный свидетель, источающий предмет ЧЕРЕЗ ПЕРЕМЕННУЮ, ложно-зелёным не считается.
# Снятый класс: заглушка с `exit 0`, источённая тестом, завершала его кодом ноль.
grep -q "test_adv_sourced_var.sh" <<< "$OUT" && bad T2b "источающий через переменную объявлен ложно-зелёным: заглушка снова меняет поток управления" || ok

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

# --- T7: режим --contrast отдаёт ОБА прогона, и они различимы -------------------------
# Режим вшивает в порядок работы приём «образец берётся из рамки свидетеля». Без него эта
# операция владельца не имела и делалась руками — дважды 20 сентября 2026 с ошибкой.
OUT7=$(CLAUDSOUL_REPO="$D" bash "$PROBE" --contrast hooks/tests/test_adv_honest.sh 2>&1); RC7=$?
[ "$RC7" = 0 ] && ok || bad T7 "контраст на честном свидетеле дал код $RC7"
grep -q "── ЖИВОЙ:" <<< "$OUT7" && ok || bad T7b "живой прогон не назван"
grep -q "── ВЫПОТРОШЕННЫЙ:" <<< "$OUT7" && ok || bad T7c "выпотрошенный прогон не назван"
# Оба кода напечатаны, и они РАЗНЫЕ: иначе режим не даёт образца, ради которого заведён.
_codes=$(grep -c '── код: ' <<< "$OUT7")
[ "$_codes" = 2 ] && ok || bad T7d "кодов напечатано $_codes, ожидалось 2"
grep -q '── код: 0 ──' <<< "$OUT7" && grep -q '── код: 1 ──' <<< "$OUT7" \
    && ok || bad T7e "коды живого и выпотрошенного не различаются — образца из этого не взять"
# Предмет назван: без него читатель не знает, ЧТО выхолащивалось.
grep -q "hooks/subject.sh" <<< "$OUT7" && ok || bad T7f "предмет не назван"

# T7g — предмет не разрешён: отказ с подсказкой, а не молчание и не ложный контраст.
OUT7g=$(CLAUDSOUL_REPO="$D" bash "$PROBE" --contrast hooks/tests/нет-такого.sh 2>&1); RC7g=$?
[ "$RC7g" = 2 ] && ok || bad T7g "неразрешённый предмет дал код $RC7g, ожидался 2"
grep -q "СУДИТ" <<< "$OUT7g" && ok || bad T7h "отказ не подсказывает, как объявить предмет"

# T7i — без аргумента тоже отказ, а не контраст наугад.
OUT7i=$(CLAUDSOUL_REPO="$D" bash "$PROBE" --contrast 2>&1); RC7i=$?
[ "$RC7i" = 2 ] && ok || bad T7i "вызов без свидетеля дал код $RC7i, ожидался 2"

# --- T8: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПРИБОРА (21 сентября 2026, снятие предела D342) ----------
# «Ложно-зелёных ноль» и «прибор ослеп» при одном канале неразличимы: выпотрошенный прибор
# отвечает тем же нулём, что чистое дерево. Прибор кладёт себе в вселенную канарейку —
# свидетеля, НЕ зовущего свой предмет, — и обязан назвать её ложно-зелёной; не назвал, значит
# молчит и на известном «да», и его ноль ничего не значит: код 2, а не 0.
# МУТАНТ СОБИРАЕТСЯ МИНИ-ДЕРЕВОМ, А НЕ ОДНИМ ФАЙЛОМ (22 сентября 2026, D474).
# Прибор ищет свою библиотеку выхолащивания по каталогу СЕБЯ (`dirname $0/../hooks`), потому
# что `$REPO` у него значит «дерево, которое судим». Плоская копия в $TMP оставалась бы без
# библиотеки и ломалась бы кодом 2 по другой причине — контроль зеленел бы вхолостую.
# Мутировать можно любую половину: `probe` — сам прибор, `lib` — библиотеку выхолащивания.
# СОСЕДИ БИБЛИОТЕКИ КЛАДУТСЯ В МИНИ-ДЕРЕВО ТОЖЕ (23 сентября 2026, находка замера suite-linux).
# Мутант нёс только выхолащивание, а библиотека зовёт сторожа срока `timeout-lib.sh`. На машине
# автора это маскировал фоллбек на установленную копию в ~/.claude — там сторож есть, и тест
# был зелёным. В чистом контейнере копии нет, и прибор честно отвечал «BROKEN: нет
# hooks/timeout-lib.sh», а три ноги падали. Классический зелёный-на-машине-автора: предмет
# судился не полностью, и узнал об этом только раннер без установленного ClaudSoul.
_mut_libs() {  # <мини-дерево> — соседи, без которых библиотека не работает
    local _d="$1" _l
    for _l in timeout-lib.sh portable-lib.sh; do
        [ -f "$REPO/hooks/$_l" ] && { cp "$REPO/hooks/$_l" "$_d/hooks/$_l" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }; }
    done
    return 0
}

mutant() {  # mutant <имя> <probe|lib> <выражение sed> → печатает путь к прибору
    local name="$1" which="$2" expr="$3"
    local d="$TMP/$name"
    mkdir -p "$d/scripts" "$d/hooks"
    if [ "$which" = probe ]; then
        sed "$expr" "$PROBE" > "$d/scripts/probe.sh"
        cp "$SPL" "$d/hooks/subject-probe-lib.sh"
        _mut_libs "$d"
        cmp -s "$PROBE" "$d/scripts/probe.sh" && return 1
    else
        cp "$PROBE" "$d/scripts/probe.sh"
        _mut_libs "$d"
        sed "$expr" "$SPL" > "$d/hooks/subject-probe-lib.sh"
        cmp -s "$SPL" "$d/hooks/subject-probe-lib.sh" && return 1
    fi
    printf '%s\n' "$d/scripts/probe.sh"
}

M=$(mutant probe-mutant probe 's/            VACUOUS=$((VACUOUS + 1))/            :/') || M=""
# T8a — КОНТРОЛЬ САМОЙ МУТАЦИИ, и он здесь не формальность: накануне, 20 сентября 2026,
# такой же sed-шаблон в свидетеле `costly-tests` остался от прежней редакции кода, перестал
# совпадать, и «мутант» был тождествен оригиналу — контроль зеленел вхолостую.
[ -n "$M" ] && ok || bad T8a "мутация не состоялась: шаблон sed устарел, мутант равен оригиналу"
OUTM=$(CLAUDSOUL_REPO="$D2" bash "$M" 2>&1); RCM=$?
# T8b — ослепший прибор говорит «судить нечем», а не «чисто».
[ "$RCM" = 2 ] && ok || bad T8b "ослепший прибор дал код $RCM, ожидался 2: $OUTM"
grep -q "положительный контроль НЕ сработал" <<< "$OUTM" && ok || bad T8c "отказ не назван словами: $OUTM"
# T8d — ЖИВОЙ прибор канарейку из счёта ВЫЧИТАЕТ: её след не должен попадать ни в число,
# ни в перечень имён, иначе контроль сам стал бы вечной находкой.
grep -q "ложно-зелёных: 0" <<< "$OUT2" && ok || bad T8d "канарейка утекла в счёт чистого дерева: $OUT2"
grep -q "test_adv_probe_canary" <<< "$OUT2" && bad T8e "канарейка названа носителем" || ok

# --- T9: ТРИ КЛАССА СКЛАДЫВАЮТСЯ ВО ВСЕЛЕННУЮ (21 сентября 2026) ------------------------
# Вселенная делится натрое: предмет разрешим · предмет не назван · предмет есть свойство
# дерева. Число неназванных считалось ВЫЧИТАНИЕМ разрешимых из всех, то есть несло ещё и
# третий класс: 288 в итоговой строке против 287 строк в `--unresolved`. Нога судит
# инвариант, а не конкретное число: сумма трёх обязана равняться вселенной.
# ДОЛИ БЕРУТСЯ У ВЛАДЕЛЬЦА, А НЕ ПОВТОРЯЮТСЯ ЗДЕСЬ (24 сентября 2026, D479, корень R1).
# Прежде нога перечисляла имена долей сама, и заведение четвёртой её не задело: сумма в
# рабочем дереве давала 600 при вселенной 601, а нога была зелена. Теперь прибор печатает
# машинную строку `#PARTS total=N doля=N …`, и нога складывает то, что в ней есть, не зная
# имён. Добавленная доля попадает в сумму сама; пропавшая роняет её ниже вселенной.
#
# Различение сохранено: `total` прибор считает СВОИМ счётчиком, независимо от перечня долей,
# поэтому выпавшая доля делает сумму меньше вселенной и нога краснеет. Если бы нога сверяла
# сумму с суммой, она зеленела бы при любом перечне.
T9_LINE=$(printf '%s\n' "$OUT" | grep '^#PARTS ' | tail -1)
if [ -z "$T9_LINE" ]; then
    bad T9 "прибор не назвал доли вселенной строкой #PARTS: $OUT"
else
    T9_TOT=$(printf '%s\n' "$T9_LINE" | tr ' ' '\n' | sed -n 's/^total=//p')
    T9_SUM=$(printf '%s\n' "$T9_LINE" | tr ' ' '\n' | grep -v '^total=' \
        | sed -n 's/^[a-z_][a-z_]*=\([0-9][0-9]*\)$/\1/p' | awk '{s+=$1} END{print s+0}')
    T9_N=$(printf '%s\n' "$T9_LINE" | tr ' ' '\n' | grep -v '^total=' \
        | grep -c '^[a-z_][a-z_]*=[0-9][0-9]*$')
    if [ -z "$T9_TOT" ]; then
        bad T9 "в строке #PARTS нет вселенной: $T9_LINE"
    elif [ "$T9_N" -lt 2 ]; then
        bad T9 "долей в строке #PARTS меньше двух — перечень не разобран: $T9_LINE"
    elif [ "$T9_SUM" = "$T9_TOT" ]; then ok
    else
        bad T9 "доли не складываются во вселенную: $T9_SUM != $T9_TOT ($T9_LINE)"
    fi
fi
# T9b — перечень `--unresolved` и число в итоге говорят ОДНО: у факта один владелец.
# Имя доли названо ЗДЕСЬ по делу: предикат ноги — про эту долю и ни про какую другую, он
# сравнивает перечень с её числом. Сумма (T9 выше) имён долей не знает и знать не должна.
T9_UNR=$(printf '%s\n' "$T9_LINE" | tr ' ' '\n' | sed -n 's/^unresolved=//p')
T9_LIST=$(CLAUDSOUL_REPO="$D" bash "$PROBE" --unresolved | grep -c . || true)
if [ -z "${T9_UNR:-}" ]; then
    bad T9b "владелец не назвал долю «unresolved» в строке #PARTS: $T9_LINE"
elif [ "$T9_LIST" = "$T9_UNR" ]; then ok
else bad T9b "перечень даёт $T9_LIST, итоговая строка $T9_UNR"; fi

# --- T10: ПРЕДМЕТ-ГРУППА (21 сентября 2026, решение владельца) --------------------------
# Свидетель конвейера краснеет от выхолащивания ЛЮБОГО звена: прогон показал, что у 14 из
# 41 таких свидетелей краснело больше одного кандидата, и выбрать «главное» звено нельзя —
# это была бы догадка. Объявление `# СУДИТ: <каталог>/` выхолащивает весь каталог.
grep -q "test_adv_pipeline" <<< "$OUT" && bad T10 "честный свидетель конвейера объявлен ложно-зелёным" || ok
# T10b — РАЗЛИЧЕНИЕ: прибор без поддержки каталога на этой фикстуре ломается ГРОМКО
# (cp каталога не проходит), а не молча зачисляет её в ложно-зелёные.
MG=$(mutant probe-nogroup lib 's|if \[ "${subj%/}" != "$subj" \]; then|if false; then|') || MG=""
[ -n "$MG" ] && ok || bad T10b "мутация не состоялась: шаблон устарел"
# ФОРМА ГРОМКОСТИ УТОЧНЕНА 22 сентября 2026 (починка класса I противника). Прежде нога
# требовала кода 2: прибор, не умеющий этот вид предмета, обязан был СЛОМАТЬСЯ. С тех пор
# устаревшее объявление разведено с поломкой прибора — недоступный предмет получил свой
# класс и имя свидетеля, а прогон продолжается. Предмет ноги прежний и не ослаблен: фикстура
# не должна попасть в ложно-зелёные МОЛЧА; проверяется это теперь по названному классу.
OUTG=$(CLAUDSOUL_REPO="$D" bash "$MG" 2>&1)
if grep -q 'объявление устарело.*test_adv_pipeline' <<< "$OUTG"; then ok
else bad T10c "прибор без поддержки каталога не назвал фикстуру в классе «объявление устарело»: $OUTG"; fi

# --- T11: ПРЕДМЕТ-СПИСОК (21 сентября 2026, D474) ---------------------------------------
# У 64 свидетелей из 108 краснит несколько звеньев в РАЗНЫХ каталогах: каталогом не покрыть,
# выбрать одно — догадка. Объявление перечисляет все через пробел.
grep -q "test_adv_pair" <<< "$OUT" && bad T11 "честный свидетель двух звеньев объявлен ложно-зелёным" || ok
# T11b — РАЗЛИЧЕНИЕ: прибор без поддержки списка ломается ГРОМКО (пути с пробелом нет),
# а не зачисляет фикстуру в ложно-зелёные молча.
ML=$(mutant probe-nolist lib 's|^        case "$subj" in|        case "НЕТ_СПИСКА" in|') || ML=""
[ -n "$ML" ] && ok || bad T11b "мутация не состоялась: шаблон устарел"
OUTL=$(CLAUDSOUL_REPO="$D" bash "$ML" 2>&1)
if grep -q 'объявление устарело.*test_adv_pair' <<< "$OUTL"; then ok
else bad T11c "прибор без поддержки списка не назвал фикстуру в классе «объявление устарело»: $OUTL"; fi

# --- T12: КОНТРОЛЬ РАМКИ У КАНДИДАТА В ЧЕСТНЫЕ (22 сентября 2026, D474) -----------------
# Красный на выхолощенном предмете честен, ТОЛЬКО если был зелёным до правок. Замер того
# дня: 14 свидетелей из 588 красны в снимке с привязанными CLAUDSOUL_REPO/ROOT и зелены без
# неё — привязка уводит хуки, которые тест запускает, в снимок без их окружения.
grep -q "рамка не собралась: 1" <<< "$OUT" && ok || bad T12 "красный-и-так не отнесён к «рамка не собралась»: $OUT"
grep -q "test_adv_always_red" <<< "$OUT" && ok || bad T12b "носитель несобравшейся рамки не назван поимённо"
# T12c — он НЕ ложно-зелёный: его краснота ничего не доказывает, но и обвинением не является.
grep -q "ложно-зелёных: 1" <<< "$OUT" && ok || bad T12c "счёт ложно-зелёных сдвинулся от красного-и-так: $OUT"

# T-W (D1222, 7 ноября 2026): свидетель СВОЙСТВА МИРА объявляет себя меткой `# СУД: свойство мира` — прибор не
# выхолащивает его и не зачисляет в ложно-зелёные, а называет своим классом; без метки тот же свидетель — ложно-зелёный
# (отрицательный контроль: T3 выше на `test_adv_vacuous.sh`).
DW="$TMP/world"; build "$DW"
{ printf '#!/usr/bin/env bash\n# СУДИТ: hooks/subject.sh\n# СУД: свойство мира\n'; sed 1d "$DW/hooks/tests/test_adv_vacuous.sh"; } > "$DW/hooks/tests/test_adv_world.sh"
rm -f "$DW/hooks/tests/test_adv_vacuous.sh"
( cd "$DW" && git add -A && git -c user.email=t@t -c user.name=t commit -qm world ) >/dev/null 2>&1
OUTW=$(CLAUDSOUL_REPO="$DW" bash "$PROBE" 2>&1); RCW=$?
grep -q "ложно-зелёных: 0" <<< "$OUTW" && ok || bad T-W "свидетель свойства мира зачислен в ложно-зелёные: $OUTW"
grep -q "предмет — свойство мира.*test_adv_world.sh" <<< "$OUTW" && ok || bad T-Wb "класс свойства мира не назван поимённо: $OUTW"
grep -q '^#PARTS .*world=1' <<< "$OUTW" && ok || bad T-Wc "доля world не вошла в #PARTS: $(grep '^#PARTS' <<< "$OUTW")"

# T-O (D1222, 8 ноября 2026): проба ОТКРЫТОГО пункта (`probe_D<N>.sh`, пункт ☐/◐ в BACKLOG.md) красна по договору —
# прибор не зовёт её «рамка не собралась», а называет своим классом; та же проба при ☑ — рамка (отрицательный контроль).
# Рамка фикстуры уже несёт одну несобравшуюся (`test_adv_always_red.sh`, T12), потому счёт рамок — 1 и 2.
DO="$TMP/open"; build "$DO"
cp "$REPO/hooks/backlog-lib.sh" "$DO/hooks/backlog-lib.sh"
mkdir -p "$DO/hooks/tests/fixtures"
printf '#!/usr/bin/env bash\n# СУДИТ: hooks/gamma.sh\nexit 1\n' > "$DO/hooks/tests/fixtures/probe_D9001.sh"
printf '%s\n' '# BACKLOG' '' '- ◐ **D9001** Открытый.' > "$DO/BACKLOG.md"
( cd "$DO" && git add -A && git -c user.email=t@t -c user.name=t commit -qm open ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }
OUTO=$(CLAUDSOUL_REPO="$DO" bash "$PROBE" 2>&1)
grep -q "проба ОТКРЫТОГО пункта.*probe_D9001.sh" <<< "$OUTO" && ok || bad T-O "проба открытого пункта не названа своим классом: ${OUTO}"
grep -q '^#PARTS .*open=1' <<< "$OUTO" && ok || bad T-Ob "доля open не вошла в #PARTS: $(grep '^#PARTS' <<< "$OUTO")"
grep -q "рамка не собралась: 1;" <<< "$OUTO" && ok || bad T-Oc "проба открытого пункта зачислена в рамки: ${OUTO}"
printf '%s\n' '# BACKLOG' '' '- ☑ **D9001** Закрытый.' > "$DO/BACKLOG.md"
( cd "$DO" && git add -A && git -c user.email=t@t -c user.name=t commit -qm closed ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }
OUTC=$(CLAUDSOUL_REPO="$DO" bash "$PROBE" 2>&1)
grep -q "рамка не собралась: 2;" <<< "$OUTC" && grep -q '^#PARTS .*open=0' <<< "$OUTC" && ok \
    || bad T-Od "проба ЗАКРЫТОГО пункта не судится как обычный свидетель: $(grep '^#PARTS\|рамка' <<< "$OUTC")"
# T-Oe: закрытый пункт, чей откат назван открытым («откат D<N>» в заголовке, признак `probe_D1196`), — тот же договор.
printf '%s\n' '# BACKLOG' '' '- ☑ **D9001** Закрытый.' '- ☐ **D9002** Мир ушёл — откат D9001.' > "$DO/BACKLOG.md"
( cd "$DO" && git add -A && git -c user.email=t@t -c user.name=t commit -qm rollback ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }
OUTR=$(CLAUDSOUL_REPO="$DO" bash "$PROBE" 2>&1)
grep -q "рамка не собралась: 1;" <<< "$OUTR" && grep -q '^#PARTS .*open=1' <<< "$OUTR" && ok \
    || bad T-Oe "проба закрытого пункта с названным откатом зачислена в рамки: $(grep '^#PARTS\|рамка' <<< "$OUTR")"
# T-Oe' (D1295, 15 ноября 2026): заголовок, НАЧИНАЮЩИЙСЯ со слова («Откат D474: …»), — тот же договор; строчная копия
# правила у прибора его не видела. Правило — у `backlog_revert_ids` (`hooks/backlog-lib.sh`).
printf '%s\n' '# BACKLOG' '' '- ☑ **D9001** Закрытый.' '- ☐ **D9002** Откат D9001: мир ушёл.' > "$DO/BACKLOG.md"
( cd "$DO" && git add -A && git -c user.email=t@t -c user.name=t commit -qm rollback2 ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh T-Oe'" >&2; exit 1; }
OUTR2=$(CLAUDSOUL_REPO="$DO" bash "$PROBE" 2>&1)
grep -q "рамка не собралась: 1;" <<< "$OUTR2" && grep -q '^#PARTS .*open=1' <<< "$OUTR2" && ok \
    || bad "T-Oe'" "проба закрытого пункта с откатом в начале заголовка зачислена в рамки: $(grep '^#PARTS\|рамка' <<< "$OUTR2")"

# T-C (D1222, 8 ноября 2026): свидетель с меткой `# СУД: дороже срока прибора` выводится из суда своим классом — не
# «рамка» и не «срок»; без метки тот же красный-и-так свидетель — рамка (T12 выше, `test_adv_always_red.sh`).
DC="$TMP/costly"; build "$DC"
printf '#!/usr/bin/env bash\n# СУДИТ: hooks/gamma.sh\n# СУД: дороже срока прибора\nexit 1\n' > "$DC/hooks/tests/test_adv_costly.sh"
( cd "$DC" && git add -A && git -c user.email=t@t -c user.name=t commit -qm costly ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }
OUTK=$(CLAUDSOUL_REPO="$DC" bash "$PROBE" 2>&1)
grep -q "дороже срока прибора.*test_adv_costly.sh" <<< "$OUTK" && ok || bad T-C "свидетель дороже срока не назван своим классом: ${OUTK}"
grep -q '^#PARTS .*costly=1' <<< "$OUTK" && ok || bad T-Cb "доля costly не вошла в #PARTS: $(grep '^#PARTS' <<< "$OUTK")"
grep -q "рамка не собралась: 1;" <<< "$OUTK" && ok || bad T-Cc "свидетель дороже срока зачислен в рамки: ${OUTK}"

# T-U (D1222, 8 ноября 2026): вывод прибора лежит рядом со снимком, а не в нём. Свидетель, читающий неотслеживаемое
# дерева, не видит ни `.probe-live/`, ни `.probe-out` — при выводе внутри снимка он красен и без выхолащивания (рамка 2).
DU="$TMP/untracked"; build "$DU"
{
    printf '#!/usr/bin/env bash\n# СУДИТ: hooks/subject.sh\n'   # без объявления предмет не разрешён (зовёт и git) — нога пуста
    printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'grep -q "^\\.\\(probe\\|contrast\\)" <<< "$(git -C "$REPO" ls-files --others --exclude-standard)" && exit 1\n'
    printf 'out=$(bash "$REPO/hooks/subject.sh" 2>&1)\n'
    printf 'case "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$DU/hooks/tests/test_adv_untracked.sh"
( cd "$DU" && git add -A && git -c user.email=t@t -c user.name=t commit -qm untracked ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }
OUTU=$(CLAUDSOUL_REPO="$DU" bash "$PROBE" 2>&1)
grep -q '^#PARTS .*unresolved=0' <<< "$OUTU" && grep -q "рамка не собралась: 1;" <<< "$OUTU" && ok \
    || bad T-U "свидетель в снимке видит вывод прибора неотслеживаемым либо не судим: $(grep '^#PARTS\|рамка' <<< "$OUTU")"

# T-S (D1222, скептик opus H1, 8 ноября 2026): SKIP только на выхолощенном предмете при живом прогоне без SKIP —
# ложно-зелёный (предпосылку свидетеля дал сам предмет); SKIP на обоих прогонах — «судить нечем» и из judged вычитается.
# Сверка корзин: каждый разрешимый свидетель — ровно в одной (judged либо один из классов «судить нечем»), сумма = resolved;
# при SKIP внутри judged сумма больше на число SKIP. Основная песочница опорой не годится — её журнал дописывают мутанты ниже.
DS="$TMP/skip"; build "$DS"
{ printf '#!/usr/bin/env bash\n# СУДИТ: hooks/subject.sh\n'
  printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
  printf 'case "$(bash "$REPO/hooks/subject.sh" 2>&1)" in *MARKER*) exit 0 ;; esac\n'
  printf 'echo "SKIP: предпосылка не собралась"; exit 0\n'; } > "$DS/hooks/tests/test_adv_skip_hollow.sh"
{ printf '#!/usr/bin/env bash\n# СУДИТ: hooks/subject.sh\necho "SKIP: окружения нет"; exit 0\n'; } > "$DS/hooks/tests/test_adv_skip_both.sh"
( cd "$DS" && git add -A && git -c user.email=t@t -c user.name=t commit -qm skip ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_behavior_condition_probe.sh:$LINENO" >&2; exit 1; }
OUTS=$(CLAUDSOUL_REPO="$DS" bash "$PROBE" 2>&1)
grep -q "ложно-зелёных: 2" <<< "$OUTS" && grep -q "test_adv_skip_hollow" <<< "$(grep -v 'SKIP последней' <<< "$OUTS")" && ok \
    || bad T-S "SKIP только на выхолощенном не зачислен в ложно-зелёные: $(grep 'ложно-зелёных\|SKIP' <<< "$OUTS")"
grep -q "SKIP последней строкой): test_adv_skip_both.sh$" <<< "$OUTS" && ok \
    || bad T-Sb "SKIP на обоих прогонах не назван «судить нечем»: $(grep 'SKIP' <<< "$OUTS")"
_bk=$(python3 -c 'import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
x=[x for x in r if x.get("repo")==sys.argv[2]][-1]
s=sum(x[k] for k in ("judged","skipped","framed","bound","slow","selfjudge","stale"))
print("%d %d %d" % (s, x["resolved"], x["skipped"]))' "$STATE_DIR/behavior-condition-probe.jsonl" "$(cd "$DS" && pwd -P)" 2>/dev/null)
read -r _bs _br _bsk <<< "${_bk:-x y z}"
[ "${_bsk:-0}" = 1 ] && [ "$_bs" = "$_br" ] && ok \
    || bad T-Sc "SKIP на обоих прогонах засчитан вердиктом: сумма корзин ${_bs:-?} при resolved ${_br:-?}, skipped ${_bsk:-?}"

echo "test_behavior_condition_probe: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
