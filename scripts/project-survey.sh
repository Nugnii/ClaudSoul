#!/usr/bin/env bash
# project-survey.sh — что у проекта УЖЕ устроено: подпроекты, тесты, стражи, правила.
# en: project survey — what the project already has: subprojects, tests, guards, rules.
#
# Результат: перед интеграцией ClaudSoul в чужой проект названо его нынешнее устройство —
#            чем запускаются тесты, какие стражи уже стоят, какие правила уже записаны, —
#            и отдельно названо, чего нет.
# Проверка результата: bash hooks/tests/test_project_survey.sh даёт 0
#
# ЧИТАЕТ И НЕ ПИШЕТ. Ни одной записи в осматриваемый проект: осмотр не должен менять предмет
# осмотра, а интеграция решается ПОСЛЕ отчёта, отдельным шагом.
#
# ПОВОД — владелец, 11 сентября 2026: «при инициации сначала должен проходить анализ проекта
# на предмет как там что устроено и уже потом интеграция. Яркий пример проект projecta, там уже
# много тестов, наверняка есть свои хуки и сторожа». И следом: «там может быть не только
# устройство, но и полный хаос, отсутствие организации, ошибки и баги».
#
# ОТСЮДА ГЛАВНОЕ СВОЙСТВО: отсутствие порядка — законный результат, а не сбой прибора.
# У каждого раздела три исхода, и они РАЗНЫЕ (правило «Хук зовёт инструмент»):
#   · «есть, вот оно» — печатается перечнем;
#   · «своего нет» — печатается словами, это нормальное состояние проекта;
#   · «посмотреть не удалось» — печатается как НЕ ПРОВЕРЕНО с причиной, и это не «нет».
# Свалить второе с третьим значит соврать: пустой отчёт о хаосе неотличим от пустого отчёта
# о сломанном осмотре. Проверено на трёх живых проектах разом: монорепо с 522 своими тестами,
# проект из одних документов без кода, и каталог из трёх файлов вовсе без git.
#
# ЧУЖОЕ ОТДЕЛЯЕТСЯ ОТ СВОЕГО, И ЭТО ИЗМЕРЕНО. Наивный поиск тестов в ProjectA_NEW дал 833, из
# которых 297 лежат в legacy/.venv и .venv-security/lib — тесты чужих библиотек, а не
# проекта. Признак «имя начинается на test_» кода проекта от установленной библиотеки не
# отличает, поэтому исключение чужих путей — ЧАСТЬ признака, а не украшение: число 833
# попало бы в отчёт и стало бы основанием решений.
#
# ПРЕДШЕСТВЕННИК НАЙДЕН И ОСТАЁТСЯ: scripts/project-conformance.sh судит НАСТРОЙКУ ClaudSoul
# в проекте (совпадает ли она с нынешним договором), здесь же предмет — устройство САМОГО
# проекта. Исходы разные: там расхождение есть дефект, тут отсутствие порядка есть законное
# состояние. Смешение сделало бы хаос ошибкой прибора.
set -uo pipefail

TARGET="${1:-$PWD}"
[ -d "$TARGET" ] || { echo "нет такого каталога: $TARGET" >&2; exit 2; }
TARGET=$(cd "$TARGET" 2>/dev/null && pwd -P) && cd "$TARGET" \
    || { echo "не войти в каталог: ${1:-$PWD}" >&2; exit 2; }

# .build — каталог сборки SwiftPM: в нём сгенерированные сборщиком test_entry_point.* и исходники
# зависимостей (checkouts). На живом Swift-проекте 21 октября 2026 он дал 3581 из 3643 «файлов
# проекта» и все 9 «тестов», а ни одного из пяти настоящих в Tests/ осмотр не нашёл.
# Чужое ОТСЕКАЕТСЯ (-prune), а не отбрасывается после обхода: прежний фильтр по пути заходил
# в каждую чужую папку на каждом из ~20 проходов осмотра — в ProjectA_NEW это 148 817 файлов на
# проход при 5 699 своих (97 217 в одной node_modules). И он судил ВЕСЬ путь, вместе с тем, что
# выше проекта: проект в …/build/myproj давал «файлов проекта: 0». Поэтому обход идёт от корня
# проекта (cd выше), и пути — ОТНОСИТЕЛЬНЫЕ: признак, судящий путь, не видит того, что лежит
# выше проекта, по построению.
_find() { # условия find; чужое отсекается здесь, в одном месте
    find . \( -type d \( -name .git -o -name node_modules -o -name .venv -o -name venv \
        -o -name '.venv-*' -o -name vendor -o -name dist -o -name build -o -name .build -o -name __pycache__ \
        -o -name .next -o -name target \) \) -prune -o \( "$@" \) -print 2>/dev/null
}

echo "ОСМОТР ПРОЕКТА: $TARGET"
echo

# --- 1. Есть ли вообще проект -------------------------------------------------------------
_files=$(_find -type f | grep -c . || true)
echo "1. СОДЕРЖИМОЕ"
if [ "${_files:-0}" -eq 0 ]; then
    echo "   файлов проекта: 0 — каталог пуст либо всё исключено как чужое."
    echo "   Это не сбой осмотра: интегрировать пока не во что."
    exit 0
fi
echo "   файлов проекта: $_files (чужое исключено: .git, node_modules, .venv, vendor, dist, build, .build)"
if [ -d "$TARGET/.git" ]; then
    echo "   git: есть, коммитов $(git -C "$TARGET" rev-list --count HEAD 2>/dev/null || echo '?')"
else
    echo "   git: НЕТ — истории нет, и откатывать правки будет нечем"
fi
echo

# --- 2. Подпроекты по маркерам сборки -----------------------------------------------------
# Подпроект ищется по МАРКЕРУ СБОРКИ, а не по имени каталога: монорепо ProjectA_NEW несёт
# четыре разных стека (web на package.json, три на requirements.txt), и перечень имён
# («src», «app», «lib») их бы не нашёл.
echo "2. ПОДПРОЕКТЫ (по маркеру сборки)"
_sub=0
for marker in package.json pyproject.toml requirements.txt pytest.ini Cargo.toml go.mod composer.json Gemfile pom.xml build.gradle Package.swift Makefile; do
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        rel="${m#./}"; dir="${rel%/*}"; [ "$dir" = "$rel" ] && dir="(корень)"
        printf '   %-30s %s\n' "$dir" "$marker"
        _sub=$((_sub + 1))
    done <<EOF
$(_find -name "$marker" -type f | head -20)
EOF
done
[ "$_sub" -eq 0 ] && echo "   маркеров сборки НЕ НАЙДЕНО — стек не объявлен ничем машинно читаемым"
echo

# --- 3. Тесты проекта ---------------------------------------------------------------------
echo "3. ТЕСТЫ ПРОЕКТА"
_tests=$(_find -type f \( -name 'test_*' -o -name '*_test.*' -o -name '*.test.*' -o -name '*.spec.*' -o -name '*Tests.swift' \) | grep -c . || true)
if [ "${_tests:-0}" -eq 0 ]; then
    echo "   тестов не найдено по обычным именам (test_*, *_test.*, *.test.*, *.spec.*, *Tests.swift)"
    echo "   Это законное состояние: проверок у проекта пока нет, и строить их — отдельное решение."
else
    echo "   файлов тестов: $_tests"
    echo "   где лежат:"
    _find -type f \( -name 'test_*' -o -name '*_test.*' -o -name '*.test.*' -o -name '*.spec.*' -o -name '*Tests.swift' \) \
        | sed 's|^\./||' | awk -F/ 'NF>1 {print "     " $1 "/" $2} NF==1 {print "     (корень)"}' \
        | sort | uniq -c | sort -rn | head -6
    echo "   чем запускаются (по маркеру рядом):"
    _ran=0
    [ -n "$(_find -name package.json -type f | head -1)" ]   && { echo "     npm/yarn — смотреть scripts.test"; _ran=1; }
    [ -n "$(_find -name pytest.ini -type f | head -1)" ]     && { echo "     pytest"; _ran=1; }
    [ -n "$(_find -name pyproject.toml -type f | head -1)" ] && { echo "     pytest либо своя команда из pyproject"; _ran=1; }
    [ -n "$(_find -name Package.swift -type f | head -1)" ]  && { echo "     swift test"; _ran=1; }
    [ -n "$(_find -name Makefile -type f | head -1)" ]       && { echo "     make — смотреть цель test"; _ran=1; }
    [ "$_ran" -eq 0 ] && echo "     НЕ ОПРЕДЕЛЕНО — тесты есть, а объявленного способа запуска нет"
fi
echo

# --- 4. Стражи, которые уже стоят ---------------------------------------------------------
echo "4. СТРАЖИ ПРОЕКТА (уже стоят)"
_g=0
if [ -d "$TARGET/.git/hooks" ]; then
    _gh=$(ls "$TARGET/.git/hooks" 2>/dev/null | grep -vc '\.sample$' || true)
    [ "${_gh:-0}" -gt 0 ] && { echo "   git-хуки: $_gh (кроме .sample)"; _g=1; }
fi
[ -f "$TARGET/.pre-commit-config.yaml" ] && { echo "   pre-commit: .pre-commit-config.yaml"; _g=1; }
if [ -d "$TARGET/.github/workflows" ]; then
    _ci=$(ls "$TARGET/.github/workflows" 2>/dev/null | grep -c . || true)
    [ "${_ci:-0}" -gt 0 ] && { echo "   CI: $_ci workflow — $(ls "$TARGET/.github/workflows" 2>/dev/null | head -3 | tr '\n' ' ')"; _g=1; }
fi
for lint in .eslintrc.json .eslintrc.js .flake8 .ruff.toml setup.cfg .golangci.yml; do
    [ -f "$TARGET/$lint" ] && { echo "   линтер: $lint"; _g=1; }
done
[ "$_g" -eq 0 ] && echo "   своих стражей НЕТ — ни git-хуков, ни pre-commit, ни CI, ни конфигурации линтера"
echo

# --- 5. Правила, которые уже записаны -----------------------------------------------------
echo "5. ПРАВИЛА ПРОЕКТА (уже записаны)"
_r=0
for rules in CLAUDE.md AGENTS.md .cursorrules CONTRIBUTING.md CONSTITUTION.md; do
    # `grep -c` при пустом файле печатает «0» И выходит кодом 1 — запас `|| echo '?'`
    # дописывал вторую строку, и человек читал «0 ?» (D477). Счёт строк берётся у своего
    # владельца — `wc -l`, он не путает «сколько» с «нашёл ли».
    [ -f "$TARGET/$rules" ] && { printf '   %-20s %s строк\n' "$rules" "$(wc -l < "$TARGET/$rules" 2>/dev/null | tr -d ' ' || true)"; _r=1; }
done
[ -d "$TARGET/.claude" ] && { echo "   .claude/: $(ls "$TARGET/.claude" 2>/dev/null | head -4 | tr '\n' ' ')"; _r=1; }
[ "$_r" -eq 0 ] && echo "   записанных правил НЕТ — договор о работе с проектом нигде не зафиксирован"
echo

# --- 6. Что от ClaudSoul уже стоит --------------------------------------------------------
# Отдельным разделом: интеграция в уже интегрированный проект — не то же, что первая.
echo "6. CLAUDSOUL В ЭТОМ ПРОЕКТЕ"
_c=0
for f in BACKLOG.md SESSION.md ROOTS.md .claude-docs; do
    [ -e "$TARGET/$f" ] && { echo "   есть: $f"; _c=1; }
done
if [ -f "$TARGET/CLAUDE.md" ] && grep -q 'ClaudSoul' "$TARGET/CLAUDE.md" 2>/dev/null; then
    echo "   CLAUDE.md поминает ClaudSoul — проект, похоже, уже инициирован"; _c=1
fi
[ "$_c" -eq 0 ] && echo "   следов нет — инициация здесь будет первой"
echo

echo "── ОСМОТР ЗАВЕРШЁН. Это материал для решения, а не решение: что из найденного оставить,"
echo "   что позвать, а что заменить — отдельный шаг, и он требует слова владельца."
