#!/usr/bin/env bash
# test_project_survey.sh — осмотр проекта различает «своего нет» и «посмотреть не удалось», а чужое в счёт не берёт.
#
# Результат: на проекте с тестами они названы числом БЕЗ чужих из .venv, node_modules и .build; на
#            проекте без них сказано словами, что их нет; отсутствие git названо отдельно.
# Проверка результата: bash hooks/tests/test_project_survey.sh даёт 0
#
# Ноги держат ОБЕ стороны различения: без T3-T5 тест зеленел бы у прибора, который на всё
# отвечает «ничего нет», а без T1-T2 — у того, который всё считает подряд, включая чужое.
#
# Хелперы взяты у соседа (test_budget_gate.sh), а не изобретены: прувер test_guards_provable
# распознаёт доказательство по сигнатуре, ручной [ -z ] доказательством не считает.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/project-survey.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в выводе"; fi; }
assert_absent()   { if grep -Fq "$2" <<< "$1"; then bad "$3" "лишнее '$2' в выводе"; else ok; fi; }
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- Фикстура 1: проект СО своими тестами и чужими в .venv --------------------------------
P1="$TMP/withtests"
mkdir -p "$P1/src" "$P1/tests" "$P1/.venv/lib/foreign"
printf '{}\n' > "$P1/package.json"
printf 'x\n' > "$P1/tests/test_one.spec.ts"
printf 'x\n' > "$P1/tests/test_two.spec.ts"
# три чужих теста в окружении: прибор обязан их НЕ считать
for i in 1 2 3; do printf 'x\n' > "$P1/.venv/lib/foreign/test_alien_$i.py"; done
OUT1=$(bash "$TOOL" "$P1" 2>&1)

# T1: свои тесты посчитаны — ровно два, чужие три не в счёт
assert_contains "$OUT1" "файлов тестов: 2" "T1: своих тестов посчитано не 2 — чужое из .venv попало в счёт"
# T2: маркер сборки найден, значит подпроект виден
assert_contains "$OUT1" "package.json" "T2: маркер сборки не назван"

# --- Фикстура 2: проект БЕЗ тестов, без стражей, без правил, без git -----------------------
P2="$TMP/empty"
mkdir -p "$P2/docs"
printf '# readme\n' > "$P2/docs/readme.md"
OUT2=$(bash "$TOOL" "$P2" 2>&1)

# T3: отсутствие тестов названо СЛОВАМИ как законное состояние, а не пустотой
assert_contains "$OUT2" "Это законное состояние" "T3: отсутствие тестов не названо законным состоянием"
# T4: отсутствие git названо отдельно — без истории нечем откатывать
assert_contains "$OUT2" "git: НЕТ" "T4: отсутствие git не названо"
# T5: отсутствие стражей названо словами, а не молчанием
assert_contains "$OUT2" "своих стражей НЕТ" "T5: отсутствие стражей не названо"

# --- T6: прибор НЕ ПИШЕТ в осматриваемый проект -------------------------------------------
# Главная нога по существу: осмотр не должен менять предмет осмотра.
BEFORE=$(find "$P2" | sort)
bash "$TOOL" "$P2" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_survey.sh:$LINENO" >&2; exit 1; }
AFTER=$(find "$P2" | sort)
[ "$BEFORE" = "$AFTER" ] && ok || bad "T6" "осмотр изменил содержимое проекта"

# --- T7: пустой каталог — отдельный исход, а не сбой ---------------------------------------
P3="$TMP/void"; mkdir -p "$P3"
OUT3=$(bash "$TOOL" "$P3" 2>&1); RC3=$?
assert_contains "$OUT3" "интегрировать пока не во что" "T7: пустой каталог не назван отдельно"
[ "$RC3" -eq 0 ] && ok || bad "T7b" "пустой каталог дал код $RC3 — пустота объявлена ошибкой"

# --- T8: несуществующий каталог — ОТКАЗ, а не «ничего нет» --------------------------------
# Третье состояние прибора: «посмотреть не удалось» отличимо от «своего нет».
OUT4=$(bash "$TOOL" "$TMP/nope-not-here" 2>&1); RC4=$?
[ "$RC4" -eq 2 ] && ok || bad "T8" "несуществующий каталог дал код $RC4, а не 2 — отказ неотличим от пустоты"
assert_absent "$OUT4" "своих стражей НЕТ" "T8b: на несуществующем каталоге прибор отчитался как об осмотренном"

# --- T9-T12: Swift-проект — свои тесты в Tests/, а в .build сгенерированное и чужое ----------
# Повод — живой Swift-проект 21 октября 2026: Package.swift не узнан, «тестами» названы 9 файлов
# из .build/out (test_entry_point.*, их пишет сборщик), пять настоящих в Tests/ не найдены,
# способ запуска «не определён». Фикстура держит все четыре места разом.
P4="$TMP/swift"
mkdir -p "$P4/Tests/CoreTests" "$P4/.build/out/x" "$P4/.build/checkouts/dep/Tests/DepTests"
printf '// swift-tools-version:5.9\n' > "$P4/Package.swift"
printf 'x\n' > "$P4/Tests/CoreTests/OneTests.swift"
printf 'x\n' > "$P4/Tests/CoreTests/TwoTests.swift"
printf 'x\n' > "$P4/Tests/CoreTests/Support.swift"
printf 'x\n' > "$P4/.build/out/x/test_entry_point.swift"
printf 'x\n' > "$P4/.build/checkouts/dep/Tests/DepTests/DepTests.swift"
OUT5=$(bash "$TOOL" "$P4" 2>&1)

# T9: Package.swift — маркер сборки, стек объявлен
assert_contains "$OUT5" "Package.swift" "T9: маркер сборки Package.swift не узнан"
assert_absent "$OUT5" "маркеров сборки НЕ НАЙДЕНО" "T9b: Swift-проект назван проектом без стека"
# T10: своих тестов ровно два. Число различает все поломки: без имени *Tests.swift было бы 0,
# без исключения .build — 4, без обоих — 1 (один test_entry_point).
assert_contains "$OUT5" "файлов тестов: 2" "T10: своих тестов посчитано не 2 — сгенерированное или чужое из .build в счёте, либо Tests/ не найдены"
assert_absent "$OUT5" ".build/out" "T10b: «тесты» найдены в каталоге сборки"
# T11: способ запуска назван
assert_contains "$OUT5" "swift test" "T11: способ запуска swift test не назван"
assert_absent "$OUT5" "НЕ ОПРЕДЕЛЕНО" "T11b: у Swift-проекта способ запуска назван неопределённым"
# T12: файлов проекта четыре своих, два из .build не в счёте
assert_contains "$OUT5" "файлов проекта: 4 (" "T12: содержимое .build посчитано файлами проекта"

# --- T13: проект внутри папок с «чужими» именами — своё остаётся своим ------------------------
# До 21 октября 2026 фильтр чужого судил ВЕСЬ путь, вместе с тем, что выше проекта, и проект в
# …/build/myproj давал «файлов проекта: 0». Здесь корень проекта назван build, а выше лежит
# vendor: держатся обе половины — судятся только папки ВНУТРИ проекта, и сам корень не судится.
# Файл с чужим именем (скрипт build в корне — обычное дело) отсекаться не должен: отсекаются папки.
P5="$TMP/vendor/build"
mkdir -p "$P5/src"
printf '{}\n' > "$P5/package.json"; printf 'x\n' > "$P5/src/test_a.py"; printf 'x\n' > "$P5/build"
OUT6=$(bash "$TOOL" "$P5" 2>&1)
assert_contains "$OUT6" "файлов проекта: 3 (" "T13: проект внутри папок с чужими именами объявлен пустым либо отсечён файл с чужим именем"
assert_contains "$OUT6" "файлов тестов: 1" "T13b: тест проекта внутри папок с чужими именами не найден"

# --- T8c: каталог есть, а войти в него нельзя — тоже «посмотреть не удалось», код 2 ----------
if [ "$(id -u)" -eq 0 ]; then
    echo "SKIP T8c: под root права на каталог не действуют"
else
    P6="$TMP/locked"; mkdir -p "$P6"; chmod 000 "$P6"
    OUT7=$(bash "$TOOL" "$P6" 2>&1); RC7=$?
    chmod 755 "$P6"
    [ "$RC7" -eq 2 ] && ok || bad "T8c" "в закрытый каталог войти нельзя, а код $RC7, а не 2 — отказ неотличим от пустоты"
    assert_absent "$OUT7" "файлов проекта: 0" "T8d: закрытый каталог объявлен пустым"
fi

echo "project survey: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
