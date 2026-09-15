#!/usr/bin/env bash
# test_impact_inject.sh — тест подачи пути по карте связей при правке файла.
# Предмет: на файле с зависимыми подаёт их ЧИСЛОМ и по видам (протоколом PreToolUse);
# второй раз по тому же файлу молчит; без прибора молчит (другой проект); при устаревшем
# кэше говорит ОДИН раз за сессию, чем пересобрать; при сломанном приборе говорит BROKEN;
# на файле, которого в карте нет, молчит — это законная тишина, а не находка.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
HOOK="$HOOK_DIR/impact-inject.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

assert_contains()     { if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2' в '${1:0:200}'"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: не ждали '$2'"; else PASS=$((PASS+1)); fi; }
assert_empty()        { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ждали пусто, '${1:0:120}'"; fi; }

# Песочница: свой репозиторий, свой учёт, ПУСТАЯ база знаний (иначе сборка читает живую).
REPO="$TMP/repo"; mkdir -p "$REPO/scripts" "$REPO/hooks" "$REPO/.claude-docs" "$TMP/lessons" "$REPO/mcp-server/visualization"
cd "$REPO"; git init -q; git config user.email t@t; git config user.name t
printf '#!/usr/bin/env bash\necho a\n' > hooks/alpha.sh
printf '#!/usr/bin/env bash\nsource hooks/alpha.sh\n' > hooks/beta.sh
printf '#!/usr/bin/env bash\necho odin\n' > hooks/lonely.sh
mkdir -p hooks/tests; printf '#!/usr/bin/env bash\nbash hooks/alpha.sh\n' > hooks/tests/test_alpha.sh
cp "$REPO_ROOT/scripts/project-graph.py" scripts/
{ printf '# path\tsha\tdeps\tdocs\tests\tnames\n'
  printf 'hooks/alpha.sh\taaa\t\t\thooks/tests/test_alpha.sh\t\n'
  printf 'hooks/beta.sh\tbbb\thooks/alpha.sh\t\t\t\n'
  printf 'hooks/lonely.sh\tccc\t\t\t\t\n'; } > .claude-docs/dep-index.tsv
git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1

build_cache() { ( cd "$REPO" && LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$REPO" python3 scripts/project-graph.py >/dev/null 2>&1 ); }
build_cache

run() {  # run <state> <файл> [репо]
    local r="${3:-$REPO}"
    printf '{"session_id":"t-%s","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/%s"}}' "$1" "$r" "$r" "$2" \
        | env STATE_DIR="$TMP/state-$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" LESSONS_DIR="$TMP/lessons" bash "$HOOK" 2>/dev/null
}

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: у alpha.sh есть зависимые (beta зовёт, тест проверяет).
O=$(run s1 hooks/alpha.sh)
assert_contains "$O" 'на нём стоят'                  "T1: путь подан"
assert_contains "$O" 'test 1'                        "T1: тест назван видом и числом"
assert_contains "$O" '"hookEventName":"PreToolUse"'  "T1: подача протоколом, а не печатью в stdout"
assert_contains "$O" 'run_all.sh --changed'          "T1: вторая половина — чем проверить после сохранения"

# T2 — дедуп: подсказка нужна перед ПЕРВОЙ правкой файла, дальше она шум.
assert_empty "$(run s1 hooks/alpha.sh)" "T2: второй раз по тому же файлу тихо"

# T3 — «инструмента здесь нет» — это другой проект, а не находка.
OTHER="$TMP/other"; mkdir -p "$OTHER/hooks"; ( cd "$OTHER" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$OTHER/hooks/alpha.sh"
assert_empty "$(run s3 hooks/alpha.sh "$OTHER")" "T3: без scripts/project-graph.py хук молчит"

# T4 — кэш старше учёта: не «чисто» и не поломка; сказать ОДИН раз за сессию.
touch -t 200001010000 "$REPO/mcp-server/visualization/project-graph-data.json"
O4=$(run s4 hooks/alpha.sh)
assert_contains "$O4" 'Карта связей устарела' "T4: устаревший кэш назван"
assert_contains "$O4" '--refresh'             "T4: назван способ пересборки"
assert_empty "$(run s4 hooks/beta.sh)"        "T4: второй файл той же сессии — тихо (один раз за сессию)"
build_cache

# T5 — сломанный прибор: молчание читалось бы как «зависимостей нет».
cp "$REPO/scripts/project-graph.py" "$TMP/keep.py"
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$REPO/scripts/project-graph.py"
O5=$(run s5 hooks/alpha.sh)
assert_contains "$O5" 'BROKEN' "T5: отказ прибора назван, а не проглочен"
cp "$TMP/keep.py" "$REPO/scripts/project-graph.py"

# T6 — файла в карте нет (новый, ещё не в учёте): законная тишина.
printf 'new\n' > "$REPO/hooks/fresh.sh"
assert_empty "$(run s6 hooks/fresh.sh)" "T6: узла в карте нет — молчим, это не находка"

# Рамка для ветки BASH: внесение нового узла живёт на ней, а не на Edit (T6 выше судит
# именно Edit и потому ждёт молчания). Здесь грязь дерева — вход, как в жизни.
run_bash() {  # run_bash <state>
    printf '{"session_id":"t-%s","tool_name":"Bash","cwd":"%s"}' "$1" "$REPO" \
        | env STATE_DIR="$TMP/state-$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" \
              LESSONS_DIR="$TMP/lessons" CLAUDSOUL_ROOT="$REPO" bash "$HOOK" 2>/dev/null
}

# T7/T8 — НОВЫЙ ФАЙЛ В СЧИТАЕМОМ МНОЖЕСТВЕ СДВИГАЕТ ЧИСЛА ДОКУМЕНТОВ, и это говорится
# в момент создания. Повод измерен 14 сентября 2026: за день создано шесть таких файлов, ни
# разу не пересчитано, и `test_derived_counts_inventory` покраснел в ТРЁХ полных прогонах —
# около 36 минут прогонов, законченных красным из-за команды на две секунды. Множества берутся
# у владельца счёта (scripts/count-stats.sh), здесь лишь совпадение пути.
printf 'new\n' > "$REPO/hooks/schitaemyy.sh"
O7=$(run_bash s7)
case "$O7" in
    *"ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ"*) PASS=$((PASS+1)) ;;
    *) FAIL=$((FAIL+1)); echo "FAIL [T7]: новый хук создан, а про сдвиг чисел не сказано: ${O7:0:160}" ;;
esac
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: файл вне считаемых множеств — молчание, иначе нога зеленела бы
# на приборе, который говорит про числа всегда.
mkdir -p "$REPO/scripts"
rm -f "$REPO/hooks/schitaemyy.sh"
( cd "$REPO" && git add -A >/dev/null 2>&1 && git commit -qm t7 >/dev/null 2>&1 )
printf 'new\n' > "$REPO/scripts/ne-schitaemyy.sh"
O8=$(run_bash s8)
case "$O8" in
    *"ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ"*) FAIL=$((FAIL+1)); echo "FAIL [T8]: файл вне считаемых множеств, а про числа сказано" ;;
    *) PASS=$((PASS+1)) ;;
esac

# T9 — НОВИЗНА СПРАШИВАЕТСЯ У МИРА, А НЕ У КАРТЫ. Файл в считаемом множестве, КОТОРОГО НЕТ
# В КАРТЕ, но который git уже отслеживает, новым не является: счёт множества он не двигал.
# Без этой ноги ветка зеленела бы на первой своей редакции, где «нет в карте» читалось как
# «новый», — а карта пересобирается лишь по `--refresh`, и «новым» выглядел любой давно не
# правленный файл. Поймано на себе 14 сентября 2026: `doc-impact-check.sh` заведён 28 августа,
# хуков как было 82, так и осталось, а ветка велела пересчитывать СЕЙЧАС. Точность 2 из 3.
printf 'old\n' > "$REPO/hooks/davnishniy.sh"
( cd "$REPO" && git add -A >/dev/null 2>&1 && git commit -qm t9 >/dev/null 2>&1 )
# Карту не трогаем: файл в неё не внесён, зато git его отслеживает — ровно разбираемый случай.
printf 'old\nправка\n' > "$REPO/hooks/davnishniy.sh"
O9=$(run_bash s9)
case "$O9" in
    *"ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ"*) FAIL=$((FAIL+1)); echo "FAIL [T9]: отслеживаемый файл назван новым — признак снят с карты, а не с мира: ${O9:0:160}" ;;
    *) PASS=$((PASS+1)) ;;
esac
# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ К T9 — это T7 ВЫШЕ, и он назван здесь, чтобы не искали третью ногу.
# Пара T7/T9 изолирует ровно предмет: оба файла ОТСУТСТВУЮТ В КАРТЕ, различаются только
# отслеживаемостью в git, и говорит о числах лишь неотслеживаемый. Снимешь проверку git —
# краснеет T9; перестанет говорить вовсе — краснеет T7. Своей ноги предмету не нужно.
# Отдельный контроль «был отслеживаем, стал неотслеживаем» писать НЕЛЬЗЯ, и это проверено
# прогоном: после первого события файл попадает в карту, а речь о числах живёт внутри ветки
# «в карте его не было». Такое состояние мира недостижимо, и нога судила бы фикцию.

echo "test_impact_inject: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
