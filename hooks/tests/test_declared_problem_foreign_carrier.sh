#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh
# test_declared_problem_foreign_carrier.sh — находка про механизм ClaudSoul, записанная в
# бэклог ЧУЖОГО проекта, исходом не считается (D419); судится ЗАПИСАННЫЙ пункт, а не речь (D521).
#
# Результат: «записано» перестаёт быть истинным для пункта, который не увидит ни одна сессия
#            ClaudSoul; носитель называется
# Проверка результата: bash hooks/tests/test_declared_problem_foreign_carrier.sh даёт 0
#
# Повод и замер (18 сентября 2026). Страж исхода смотрел mtime бэклога ПРОЕКТА и не
# спрашивал, чей предмет записан. В бэклоге соседнего проекта 24 открытых пункта и 8 в
# архиве; предметом ClaudSoul были ЧЕТЫРЕ — B0-MIGR, B20, B21, B22 — и все четыре снял
# ВЛАДЕЛЕЦ руками 16 сентября, заметив глазами. Три из них стали D416, D417, D418.
#
# Предмет — строки, ДОБАВЛЕННЫЕ в бэклог проекта за ход (D521, 11 октября 2026): до того функция
# искала признак в речи хода, и речь с пунктом расходились в обе стороны. Добавленное — строки
# файла на диске, которых не было в файле коммита, на который HEAD указывал в начале хода (журнал
# ссылок). Ноги T10-T16 — атаки скептика на первую редакцию, судившую по патчу и датам коммитера.
# Песочные репозитории настоящие, `project_git` — из настоящего paths-lib: заглушек владельцев нет.
# Время журнала ссылок в песочнице задаёт GIT_COMMITTER_DATE — git пишет его и в журнал.
# Род M на этом тесте ПРОВЕРЕН И ОПРОВЕРГНУТ: судимый хук фильтра `*/tmp/*` не содержит
# (ноль совпадений), а песочница держит только бэклоги, не цели правок.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUT="$HOOKS_DIR/declared-problem-recorded.sh"
PL="$HOOKS_DIR/paths-lib.sh"
[ -f "$SUT" ] && [ -f "$PL" ] || { echo "SKIP: нет $SUT или $PL"; exit 0; }

PASS=0; FAIL=0; FIRED=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# Функция берётся ИЗ САМОГО ХУКА, а не переписывается: копия разошлась бы молча.
sed -n '/^dpr_foreign_carrier()/,/^}/p' "$SUT" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] || { bad T0 "в хуке нет dpr_foreign_carrier — вырезать нечего"; echo "declared problem foreign carrier: $PASS passed, $FAIL failed"; exit 1; }

# Путь хука в примере собран из частей: буквальное имя прибор родов читает как предмет теста.
CS_ITEM="- ☐ **B1** дефект в hooks/rework""-detector.sh — счётчик не обнуляется"
OWN_ITEM='- ☐ **B2** src/app.ts теряет фильтр при сбросе'
NOW=$(date +%s)

proj() {   # proj <имя> → каталог проекта с закоммиченным бэклогом без пунктов
    local d="$TMP/$1"
    mkdir -p "$d" && printf '# Бэклог\n' > "$d/BACKLOG.md" \
        && git -C "$d" init -q && git -C "$d" add -A \
        && GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git -C "$d" -c user.email=t@t -c user.name=t \
            commit -qm init --date='2026-01-01T00:00:00Z' >/dev/null 2>&1 || return 1
    printf '%s' "$d"
}
commit_at() {   # commit_at <каталог> <дата коммитера, ISO>
    git -C "$1" add -A && GIT_COMMITTER_DATE="$2" git -C "$1" -c user.email=t@t -c user.name=t \
        commit -qm item --date="$2" >/dev/null 2>&1
}
verdict() {   # verdict <корень ClaudSoul> <бэклог проекта> <начало хода, epoch> [GIT_DIR] → foreign|no
    CS="$1" BL="$2" TS="$3" GD="${4:-}" PL="$PL" FN="$TMP/fn.sh" bash -c '
        [ -n "$GD" ] && export GIT_DIR="$GD"
        . "$PL" >/dev/null 2>&1
        . "$FN"
        CLAUDSOUL_ROOT="$CS" LOCAL_BACKLOG="$BL" TURN_START="$TS" dpr_foreign_carrier \
            && echo foreign || echo no'
}

# --- T1 (ГЛАВНАЯ): чужой бэклог, добавлен пункт о хуке ClaudSoul → не тот носитель ---------
P=$(proj t1) || { echo "FAIL [рамка]: проект не собрался"; exit 1; }
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
if [ "$V" = foreign ]; then ok; FIRED=$((FIRED + 1)); else
    bad T1 "пункт о механизме ClaudSoul в чужом бэклоге засчитан как записанный ($V)"; fi

# --- T2: чужой бэклог, пункт о СВОЁМ коде → обычная работа, молчим -----------------------
P=$(proj t2) || exit 1
printf '%s\n' "$OWN_ITEM" >> "$P/BACKLOG.md"
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T2 "пункт про собственный код проекта назван чужим носителем ($V)"

# --- T3: работаем В ClaudSoul — носитель свой ---------------------------------------------
P=$(proj t3) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
V=$(verdict "$P" "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T3 "свой же бэклог назван чужим ($V)"

# --- T4: корень ClaudSoul неизвестен → судить нечем, молчим -------------------------------
# «Не знаю» не равно «чужой»: без корня различить носители нельзя.
V=$(verdict "" "$TMP/t1/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T4 "без известного корня ClaudSoul вынесен вердикт ($V)"

# --- T6: пункт ЗАКОММИЧЕН в этом же ходу → всё равно добавлен в ходу ---------------------
# Коммит входит в «сделано»: пункт коммитят тем же ходом, и голый diff его бы уже не видел.
P=$(proj t6) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" "@$NOW" || { echo "FAIL [рамка]: коммит T6"; exit 1; }
V=$(verdict /cs "$P/BACKLOG.md" "$((NOW - 60))")
if [ "$V" = foreign ]; then ok; FIRED=$((FIRED + 1)); else
    bad T6 "пункт о ClaudSoul, закоммиченный в ходу, не замечен ($V)"; fi

# --- T7: пункт закоммичен ДО начала хода, в ходу ничего не добавлено → молчим ------------
# Старый пункт уже был предметом прошлого хода; этот ход судится по своему.
P=$(proj t7) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" '2026-02-01T00:00:00Z' || { echo "FAIL [рамка]: коммит T7"; exit 1; }
printf '%s\n' "$OWN_ITEM" >> "$P/BACKLOG.md"
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T7 "старый пункт о ClaudSoul поднял тревогу за ход с пунктом о своём коде ($V)"

# --- T8: пункт ДОБАВЛЕН В ИНДЕКС (git add), не закоммичен → замечен ----------------------
P=$(proj t8) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"; git -C "$P" add BACKLOG.md
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
if [ "$V" = foreign ]; then ok; FIRED=$((FIRED + 1)); else
    bad T8 "пункт о ClaudSoul в индексе не замечен — сравнение не с HEAD ($V)"; fi

# --- T9: строка о ClaudSoul УДАЛЕНА из бэклога → молчим ----------------------------------
# Предмет — добавленное: снятая строка ничего не записывает.
P=$(proj t9) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" '2026-02-01T00:00:00Z' || { echo "FAIL [рамка]: коммит T9"; exit 1; }
printf '# Бэклог\n' > "$P/BACKLOG.md"
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T9 "удалённая строка о ClaudSoul засчитана записью ($V)"

# Ноги T10-T16 — атаки скептика на первую редакцию (судила по патчу и датам коммитера).
fires() {   # fires <нога> <проект> <начало хода> <что не так> — ожидается foreign
    local V; V=$(verdict /cs "$2/BACKLOG.md" "$3")
    if [ "$V" = foreign ]; then ok; FIRED=$((FIRED + 1)); else bad "$1" "$4 ($V)"; fi
}

# --- T10: признак в НАЧАЛЕ строки — первый символ строки не съедается ---------------------
P=$(proj t10) || exit 1
printf 'ClaudSoul: страж молчит на пустом выводе\n' >> "$P/BACKLOG.md"
fires T10 "$P" "$NOW" "строка, начинающаяся с признака, не замечена"

# --- T11: пункт списка с маркером «+» -----------------------------------------------------
P=$(proj t11) || exit 1
printf '+ ☐ **B1** дефект в hooks/rework''-detector.sh\n' >> "$P/BACKLOG.md"
fires T11 "$P" "$NOW" "пункт с маркером + не замечен"

# --- T12: бэклог не отслеживается git — судится целиком (названный предел 2) ------------
P="$TMP/t12"; mkdir -p "$P" && git -C "$P" init -q && printf 'x\n' > "$P/README" && git -C "$P" add README \
    && git -C "$P" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || exit 1
printf '%s\n' "$CS_ITEM" > "$P/BACKLOG.md"
fires T12 "$P" "$NOW" "пункт в неотслеживаемом бэклоге не замечен"

# --- T13: настройки репозитория меняют вид патча — цвет и showRoot ------------------------
P=$(proj t13) || exit 1
git -C "$P" config color.ui always; git -C "$P" config log.showRoot false
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" "@$NOW" || { echo "FAIL [рамка]: коммит T13"; exit 1; }
fires T13 "$P" "$((NOW - 60))" "пункт не замечен при color.ui=always"

# --- T14: amend коммита, сделанного ДО хода, — старый пункт не становится новым ----------
P=$(proj t14) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
printf '%s\n' "$OWN_ITEM" >> "$P/BACKLOG.md"
git -C "$P" add -A && GIT_COMMITTER_DATE="@$NOW" git -C "$P" -c user.email=t@t -c user.name=t \
    commit -q --amend --no-edit >/dev/null 2>&1 || exit 1
V=$(verdict /cs "$P/BACKLOG.md" "$((NOW - 60))")
[ "$V" = no ] && ok || bad T14 "amend старого коммита сделал старый пункт о ClaudSoul добавленным ($V)"

# --- T15: добавлен и закоммичен в ходу, затем удалён — в файле его нет -------------------
P=$(proj t15) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" "@$NOW" || exit 1
printf '# Бэклог\n' > "$P/BACKLOG.md"
V=$(verdict /cs "$P/BACKLOG.md" "$((NOW - 60))")
[ "$V" = no ] && ok || bad T15 "пункт, удалённый тем же ходом, засчитан ($V)"

# --- T16: GIT_DIR окружения указывает на чужой репозиторий — судится свой ---------------
# Файл читается с диска, поэтому чужой GIT_DIR портит только БАЗУ: старый пункт о ClaudSoul,
# которого нет в чужом репозитории, стал бы «добавленным».
P=$(proj t16) || exit 1
O=$(proj t16other) || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
printf '%s\n' "$OWN_ITEM" >> "$P/BACKLOG.md"
V=$(verdict /cs "$P/BACKLOG.md" "$NOW" "$O/.git")
[ "$V" = no ] && ok || bad T16 "GIT_DIR окружения подменил репозиторий бэклога ($V)"

# Ноги T17-T25 — атаки скептика на вторую редакцию (база по новейшей записи журнала не позже
# начала хода, разность через tr и grep -f). OLD_PTR — строка-указатель, закоммиченная до хода.
OLD_PTR='- ☑ **B20** перенесено в бэклог ClaudSoul как D418'
old_proj() {   # old_proj <имя> → проект, где указатель о ClaudSoul закоммичен до хода
    local d; d=$(proj "$1") || return 1
    printf '%s\n' "$OLD_PTR" >> "$d/BACKLOG.md"
    commit_at "$d" '2026-02-01T00:00:00Z' || return 1
    printf '%s' "$d"
}

# --- T17: журнал ссылок усечён сборщиком мусора — старое не становится новым --------------
P=$(old_proj t17) || exit 1
git -C "$P" reflog expire --expire=now --all
printf '%s\n' "$OWN_ITEM" >> "$P/BACKLOG.md"; commit_at "$P" "@$NOW" || exit 1
V=$(verdict /cs "$P/BACKLOG.md" "$((NOW - 60))")
[ "$V" = no ] && ok || bad T17 "усечённый журнал прочитан как «репозиторий рождён в ходу» ($V)"

# --- T18: файл с именем HEAD рядом с бэклогом -------------------------------------------
P=$(proj t18) || exit 1
: > "$P/HEAD"; printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"; commit_at "$P" "@$NOW" || exit 1
fires T18 "$P" "$((NOW - 60))" "файл HEAD в каталоге сбил вывод базы"

# --- T19: бэклог — симлинк: blob симлинка — путь цели, судить нечем (предел 3) -----------
P=$(proj t19) || exit 1
mkdir -p "$P/docs"; printf '# Бэклог\n%s\n' "$OLD_PTR" > "$P/docs/BACKLOG.md"
rm -f "$P/BACKLOG.md"; ln -s docs/BACKLOG.md "$P/BACKLOG.md"; commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T19 "симлинк без правок в ходу поднял тревогу ($V)"

# --- T20: неверный байт UTF-8 в старой строке не обрывает чтение --------------------------
P=$(proj t20) || exit 1
printf 'старая строка \320\n' >> "$P/BACKLOG.md"; commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
V=$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 verdict /cs "$P/BACKLOG.md" "$NOW")
if [ "$V" = foreign ]; then ok; FIRED=$((FIRED + 1)); else bad T20 "неверный байт оборвал чтение, пункт не замечен ($V)"; fi

# --- T21: старая строка длиннее 64 КБ ---------------------------------------------------
P=$(proj t21) || exit 1
{ head -c 70000 /dev/zero | tr '\0' 'x'; echo; } >> "$P/BACKLOG.md"; commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
fires T21 "$P" "$NOW" "длинная строка базы сломала сравнение"

# --- T22: копия уже бывшей строки с признаком — тоже добавление -------------------------
P=$(old_proj t22) || exit 1
printf '%s\n' "$OLD_PTR" >> "$P/BACKLOG.md"
fires T22 "$P" "$NOW" "дубль строки с признаком не засчитан"

# --- T23: git отказывается читать репозиторий (чужой владелец) — молчим (предел 3) -------
P=$(old_proj t23) || exit 1
printf '%s\n' "$OWN_ITEM" >> "$P/BACKLOG.md"
V=$(GIT_TEST_ASSUME_DIFFERENT_OWNER=1 verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T23 "отказ git прочитан как «файла нет в коммите» ($V)"

# --- T24: бэклог в подкаталоге репозитория (монорепо) -----------------------------------
P="$TMP/t24"; mkdir -p "$P/proj" && printf '# Бэклог\n%s\n' "$OLD_PTR" > "$P/proj/BACKLOG.md" \
    && git -C "$P" init -q && commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
printf '%s\n' "$OWN_ITEM" >> "$P/proj/BACKLOG.md"
V=$(verdict /cs "$P/proj/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T24a "старый указатель в подкаталоге стал добавленным ($V)"
printf '%s\n' "$CS_ITEM" >> "$P/proj/BACKLOG.md"
V=$(verdict /cs "$P/proj/BACKLOG.md" "$NOW")
if [ "$V" = foreign ]; then ok; FIRED=$((FIRED + 1)); else bad T24b "пункт о ClaudSoul в подкаталоге не замечен ($V)"; fi

# --- T25: цена линейна — 6000 строк за доли секунды. Замер 11 октября 2026 на этой фикстуре:
#     вторая редакция (BSD grep -f) — 8,0 с, нынешняя (awk) — 0,09 с; порог 3 с ловит вторую с запасом.
# ------------------------------------------------------------------------------------------
P=$(proj t25) || exit 1
awk 'BEGIN { for (i = 1; i <= 6000; i++) printf "- ☐ **B%d** строка номер %d\n", i, i }' >> "$P/BACKLOG.md"
commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
printf '%s\n' "$CS_ITEM" >> "$P/BACKLOG.md"
T0=$SECONDS; V=$(verdict /cs "$P/BACKLOG.md" "$NOW"); DT=$((SECONDS - T0))
if [ "$V" = foreign ] && [ "$DT" -le 3 ]; then ok; FIRED=$((FIRED + 1)); else bad T25 "6000 строк: $V за $DT с"; fi

# Ноги T27-T29 — атаки скептика, раунд 3.
# --- T27: бэклог самого ClaudSoul в его worktree, при корне с «/» и корне-симлинке — свой --
CSR=$(proj t27cs) || exit 1
git -C "$CSR" worktree add -q "$TMP/t27wt" >/dev/null 2>&1 || { echo "FAIL [рамка]: worktree T27"; exit 1; }
printf '%s\n' "$CS_ITEM" >> "$TMP/t27wt/BACKLOG.md"; printf '%s\n' "$CS_ITEM" >> "$CSR/BACKLOG.md"
ln -s "$CSR" "$TMP/t27link"
for _case in "worktree|$CSR|$TMP/t27wt/BACKLOG.md" "слеш|$CSR/|$CSR/BACKLOG.md" "симлинк|$TMP/t27link|$CSR/BACKLOG.md"; do
    IFS='|' read -r _n _root _bl <<< "$_case"
    V=$(verdict "$_root" "$_bl" "$NOW")
    [ "$V" = no ] && ok || bad "T27-$_n" "бэклог самого ClaudSoul назван чужим ($V)"
done

# --- T28: бэклог под фильтром clean/smudge — blob в форме хранилища; молчим (предел 7) ----
P=$(proj t28) || exit 1
git -C "$P" config filter.r13.clean 'tr A-Za-z N-ZA-Mn-za-m'; git -C "$P" config filter.r13.smudge 'tr A-Za-z N-ZA-Mn-za-m'
printf 'BACKLOG.md filter=r13\n' > "$P/.gitattributes"; printf '%s\n' "$OLD_PTR" >> "$P/BACKLOG.md"
commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T28 "нетронутый бэклог под фильтром поднял тревогу ($V)"

# --- T29: строка с NUL, файл не тронут — обе стороны читаются одним инструментом ----------
P=$(proj t29) || exit 1
printf -- '- B1 ClaudSoul\000x\n' >> "$P/BACKLOG.md"; commit_at "$P" '2026-02-01T00:00:00Z' || exit 1
V=$(verdict /cs "$P/BACKLOG.md" "$NOW")
[ "$V" = no ] && ok || bad T29 "строка с NUL без правок в ходу поднята ($V)"

# --- T5: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — различение вообще срабатывало --------------------------
# Без него ноги молчания (T2-T4, T7, T9, T14-T17, T19, T23, T24a, T27-T29) зеленеют на функции, которая всегда отвечает «no».
[ "$FIRED" -ge 13 ] && ok || bad T5 "признак сработал $FIRED раз из 13 — ноги молчания зеленеют от неработающей функции"

echo "declared problem foreign carrier: $PASS passed, $FAIL failed (сработал $FIRED раз)"
exit $(( FAIL != 0 ))
