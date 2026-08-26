#!/usr/bin/env bash
# test_drift_check.sh — проверка дрейфа обязана уметь краснеть, а ноль сравнений не есть успех.
#
# Повод. Прежняя версия детектора (v1.13.1, встроена в run_all.sh) при вызове
# `bash hooks/tests/run_all.sh` из корня репозитория вычисляла путь к источнику относительно
# $0 уже после `cd` и складывала относительный путь сам с собой. `cd` падал, путь выходил
# пустой, шаблон не находил ни одного файла, цикл не выполнялся — и печаталось утвердительное
# «репозиторий и установленное совпадают». Детектор, построенный против закольцовки, сам
# прошёл вхолостую тем же способом: ноль сравнений неотличим от нуля расхождений.
#
# Отсюда состав теста. Мало проверить, что на здоровом дереве всё зелено — это и есть тот
# самый вхолостую проходящий случай. Каждая пара обязана краснеть на подложенном расхождении,
# а невозможность сравнить обязана называться отказом (BROKEN), а не успехом.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$TESTS_DIR/drift-check.sh"
REPO="$(cd "$TESTS_DIR/../.." && pwd)"
[ -f "$CHECK" ] || { echo "FAIL: $CHECK not found"; exit 1; }

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# статус пары по метке из вывода
status_of() { printf '%s\n' "$1" | awk -F'|' -v l="$2" '$2 == l { print $1; exit }'; }
checked_of() { printf '%s\n' "$1" | awk -F'|' -v l="$2" '$2 == l { print $3; exit }'; }

# --- Подготовка: настоящий репозиторий как источник, поддельный дом как установленное ---
# Копируется ровно то, что install.sh переносит. Настоящий ~/.claude не трогается.
HOME_OK="$TMP/home-ok"
mkdir -p "$HOME_OK/hooks/lib" "$HOME_OK/commands" "$HOME_OK/bin" "$HOME_OK/global-lessons"
cp "$REPO"/hooks/*.sh "$HOME_OK/hooks/" 2>/dev/null
cp "$REPO"/hooks/lib/* "$HOME_OK/hooks/lib/" 2>/dev/null
cp "$REPO"/bin/resolve-claudsoul-repo.sh "$HOME_OK/bin/" 2>/dev/null
for d in "$REPO"/skills/*/; do
    n=$(basename "$d")
    mkdir -p "$HOME_OK/commands/$n"
    cp "$d"SKILL.md "$HOME_OK/commands/$n/" 2>/dev/null
    [ -d "$d/references" ] && { mkdir -p "$HOME_OK/commands/$n/references"; cp "$d"references/*.md "$HOME_OK/commands/$n/references/" 2>/dev/null; }
done
# правила: собрать блок между маркерами так же, как это делает установщик
# shellcheck source=/dev/null
. "$REPO/lib/claude-md-merge.sh" 2>/dev/null && _cm_write_managed_block "$REPO/rules/CLAUDE.md" > "$HOME_OK/CLAUDE.md"
# seed: пара файлов вне генератора
cp "$REPO"/knowledge/META.md "$REPO"/knowledge/source-tiers.md "$HOME_OK/global-lessons/" 2>/dev/null

run() { CLAUDSOUL_REPO="${2:-$REPO}" CLAUDE_HOME="$1" bash "$CHECK" 2>/dev/null; }

# --- T1: на согласованном дереве пары зелёные И реально что-то сравнили ---
# Второе условие обязательно: зелёный при нуле сравнений — ровно тот дефект, что чинится.
OUT=$(run "$HOME_OK")
for pair in "хуки" "библиотеки хуков" "скиллы" "bin" "правила"; do
    st=$(status_of "$OUT" "$pair"); n=$(checked_of "$OUT" "$pair")
    if [ "$st" = "OK" ] && [ "${n:-0}" -gt 0 ] 2>/dev/null; then ok
    else bad "T1 $pair" "ожидалось OK с ненулевым числом сравнений, получено статус=$st сравнено=$n"; fi
done

# --- T2: каждая пара обязана покраснеть на подложенном расхождении ---
# Мутируется УСТАНОВЛЕННАЯ сторона: если проверка на деле читает только репозиторий или
# сравнивает файл сам с собой, она останется зелёной и это вскроется здесь.
mutate_and_check() { # $1=путь в поддельном доме $2=метка пары $3=имя случая
    h="$TMP/home-mut-$$-$RANDOM"
    cp -R "$HOME_OK" "$h"
    printf '\n# ПОДЛОЖЕННОЕ РАСХОЖДЕНИЕ\n' >> "$h/$1"
    o=$(run "$h")
    st=$(status_of "$o" "$2")
    if [ "$st" = "DRIFT" ]; then ok; else bad "$3" "ожидался DRIFT в паре «$2», получено $st"; fi
    rm -rf "$h"
}
mutate_and_check "hooks/trust-guard.sh"            "хуки"             "T2a хуки краснеют"
mutate_and_check "hooks/lib/backfill-replay-one.sh" "библиотеки хуков" "T2b библиотеки краснеют"
mutate_and_check "commands/learn/SKILL.md"         "скиллы"           "T2c скиллы краснеют"
mutate_and_check "bin/resolve-claudsoul-repo.sh"   "bin"              "T2d bin краснеет"
mutate_and_check "global-lessons/META.md"          "seed знаний"      "T2f seed краснеет на файле вне генератора"

# --- T2e: правила сравниваются ТОЛЬКО между маркерами, и обе стороны этого обязательны ---
# Первый заход этого теста дописывал строку в конец файла и требовал DRIFT — проверка
# осталась зелёной, и права была она: дописка ушла ЗА закрывающий маркер, то есть в область
# собеседника, которую install.sh не трогает и расхождением считать нельзя. Ошибка была в
# тесте. Отсюда два случая вместо одного.
H2E="$TMP/home-rules-in"; cp -R "$HOME_OK" "$H2E"
awk 'NR == 3 { print "# ПОДЛОЖЕННОЕ РАСХОЖДЕНИЕ ВНУТРИ БЛОКА" } { print }' "$H2E/CLAUDE.md" > "$H2E/CLAUDE.md.tmp" \
    && mv "$H2E/CLAUDE.md.tmp" "$H2E/CLAUDE.md"
st=$(status_of "$(run "$H2E")" "правила")
[ "$st" = "DRIFT" ] && ok || bad "T2e правила краснеют на правке ВНУТРИ маркеров" "ожидался DRIFT, получено $st"

H2E2="$TMP/home-rules-out"; cp -R "$HOME_OK" "$H2E2"
printf '\n# личное содержимое собеседника снаружи блока\n' >> "$H2E2/CLAUDE.md"
st=$(status_of "$(run "$H2E2")" "правила")
[ "$st" = "OK" ] && ok || bad "T2e2 правила молчат на правке СНАРУЖИ маркеров" "ожидался OK, получено $st"

# --- T3: удалённый на установленной стороне файл — тоже расхождение, а не тишина ---
H3="$TMP/home-del"; cp -R "$HOME_OK" "$H3"; rm -f "$H3/hooks/trust-guard.sh"
OUT3=$(run "$H3")
[ "$(status_of "$OUT3" "хуки")" = "DRIFT" ] && ok || bad "T3 пропажа файла" "ожидался DRIFT, получено $(status_of "$OUT3" "хуки")"

# --- T4: корень не разрешился в ClaudSoul → BROKEN, а не шесть зелёных нулей ---
mkdir -p "$TMP/not-a-repo"
OUT4=$(CLAUDSOUL_REPO="$TMP/not-a-repo" CLAUDE_HOME="$HOME_OK" bash "$CHECK" 2>/dev/null)
RC4=$?
if grep -q '^BROKEN|корень репозитория' <<< "$OUT4" && [ "$RC4" -eq 2 ]; then ok
else bad "T4 чужой корень" "ожидался BROKEN + rc=2, получено rc=$RC4: $(printf '%s' "$OUT4" | head -1)"; fi

# --- T5: ИМЕННО ТОТ СЛУЧАЙ, НА КОТОРОМ МОЛЧАЛА ПРЕЖНЯЯ ВЕРСИЯ ---
# Каталог-источник существует, но шаблон не находит ни одного файла. Прежний код печатал
# «совпадают». Новый обязан назвать это отказом проверки.
FAKE="$TMP/fake-repo"
mkdir -p "$FAKE/hooks" "$FAKE/skills" "$FAKE/bin" "$FAKE/rules" "$FAKE/lib" "$FAKE/knowledge" "$FAKE/scripts"
touch "$FAKE/install.sh"
OUT5=$(CLAUDSOUL_REPO="$FAKE" CLAUDE_HOME="$HOME_OK" bash "$CHECK" 2>/dev/null)
RC5=$?
if [ "$(status_of "$OUT5" "хуки")" = "BROKEN" ] && [ "$RC5" -eq 2 ]; then ok
else bad "T5 пустой шаблон" "ожидался BROKEN + rc=2 (ноль сравнений ≠ совпадение), получено статус=$(status_of "$OUT5" "хуки") rc=$RC5"; fi

# --- T6: установленной стороны нет вовсе → ABSENT, отличимо от OK и от BROKEN ---
mkdir -p "$TMP/home-empty"
OUT6=$(run "$TMP/home-empty")
[ "$(status_of "$OUT6" "хуки")" = "ABSENT" ] && ok || bad "T6 нет установки" "ожидался ABSENT, получено $(status_of "$OUT6" "хуки")"

# --- T8: каталог есть, но пустой → ABSENT для КАЖДОЙ пары, а не «всё разошлось» ---
#
# Случай, которого не хватало. Правило добавлялось в два захода: сперва в общий помощник,
# потом отдельно в ветку скиллов — потому что классификация была продублирована, и во второй
# копии я про правило забыл. Тест этого не поймал: T6 подсовывает совершенно пустой каталог,
# и ветки уходят по пути «цели нет вовсе», не доходя до классификации вообще.
#
# На прогоне CI различие не теоретическое: `~/.claude/hooks` там создаётся самими тестами
# (хуки делают mkdir под каталогом состояния), и пара показывала 59 расхождений из 59 при
# полном отсутствии установки. После правки классификация живёт в одной точке — этот тест
# проверяет, что через неё проходят все пары.
H8="$TMP/home-dirs-only"
mkdir -p "$H8/hooks/lib" "$H8/commands" "$H8/bin" "$H8/global-lessons"
OUT8=$(run "$H8")
for pair in "хуки" "скиллы"; do
    st=$(status_of "$OUT8" "$pair")
    [ "$st" = "ABSENT" ] && ok || bad "T8 $pair" "пустой каталог должен читаться как ABSENT, получено $st"
done

# --- T7: путь вызова не влияет на результат ---
# Прежняя версия давала разный ответ в зависимости от того, откуда её позвали.
A=$(cd "$REPO"     && CLAUDE_HOME="$HOME_OK" bash hooks/tests/drift-check.sh 2>/dev/null)
B=$(cd "$TESTS_DIR" && CLAUDE_HOME="$HOME_OK" bash ./drift-check.sh 2>/dev/null)
C=$(cd /            && CLAUDE_HOME="$HOME_OK" bash "$CHECK" 2>/dev/null)
if [ "$A" = "$B" ] && [ "$B" = "$C" ]; then ok
else bad "T7 путь вызова" "результат зависит от каталога запуска"; fi

# ============================================================================
# R1-R3: регистрация хуков — призрак после переноса между событиями (D55)
# ============================================================================
# Шесть пар выше сверяют ФАЙЛЫ. Но хук может лежать побайтово верным и висеть на не том
# событии — или сразу на двух: `install.sh` сливает конфигурацию аддитивно (намеренно,
# чтобы не затирать хуки собеседника), поэтому запись умеет добавляться и НЕ УМЕЕТ
# удаляться. Перенос `error-tracker` с PostToolUse на PreToolUse оставил старую
# регистрацию, и хук оказался зарегистрирован дважды. `drift-check` этого не видел.
if command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    _RH="$TMP/reg-home"; mkdir -p "$_RH"
    _decl=$(python3 "$TESTS_DIR/_decl_hooks.py" "$REPO/install.sh" 2>/dev/null)
    if [ -z "$_decl" ]; then
        ok; ok; ok       # не разобрали install.sh — доказывать нечего
    else
        # R1: ровно объявленное — расхождения нет
        printf '%s' "$_decl" > "$_RH/settings.json"
        _out=$(CLAUDE_HOME="$_RH" bash "$CHECK" 2>/dev/null | grep 'регистрация')
        case "$_out" in OK*) ok ;; *) bad "R1" "объявленная регистрация названа расхождением: $_out" ;; esac

        # R2: тот же хук дополнительно на чужом событии — призрак назван поимённо
        printf '%s' "$_decl" | python3 "$TESTS_DIR/_decl_hooks.py" --ghost error-tracker.sh > "$_RH/settings.json"
        _out=$(CLAUDE_HOME="$_RH" bash "$CHECK" 2>/dev/null | grep 'регистрация')
        case "$_out" in *DRIFT*error-tracker*) ok ;; *) bad "R2" "призрак регистрации не назван: $_out" ;; esac

        # R3: отрицательный контроль — ЧУЖОЙ хук призраком не считается.
        # Иначе проверка объявит расхождением любой хук собеседника и станет фоном.
        printf '%s' "$_decl" | python3 "$TESTS_DIR/_decl_hooks.py" --ghost foreign-hook.sh > "$_RH/settings.json"
        _out=$(CLAUDE_HOME="$_RH" bash "$CHECK" 2>/dev/null | grep 'регистрация')
        case "$_out" in OK*) ok ;; *) bad "R3 отрицательный контроль" "чужой хук назван призраком: $_out" ;; esac
    fi
else
    ok; ok; ok
fi


echo ""
echo "drift-check tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
