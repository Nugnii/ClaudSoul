#!/usr/bin/env bash
# СУДИТ: hooks/impact-inject.sh scripts/project-graph.py
# test_impact_inject.sh — тест подачи пути по карте связей при правке файла.
# Предмет: на файле с зависимыми подаёт их ЧИСЛОМ и по видам (протоколом PreToolUse);
# второй раз по тому же файлу молчит; без прибора молчит (другой проект); при устаревшем
# кэше говорит ОДИН раз за сессию, чем пересобрать; при сломанном приборе говорит BROKEN;
# на файле, которого в карте нет, молчит — это законная тишина, а не находка. Ветка Bash при отказе
# прибора узел не вносит и файл показанным не отмечает: называет отказ словами прибора (T10, D427).
set -uo pipefail
# Свой мир, а не мир вызывающего (D1284): по CLAUDSOUL_REPO прибор карты выбирает, ЧЕЙ кэш читать, и унаследованная
# переменная (сверка архива после коммита гоняет «Проверки» в клоне с CLAUDSOUL_REPO=<клон>) уводила песочницу к кэшу
# клона — его нет, и подсказка отвечала «карта устарела» вместо карточки: 30 ног из 60 красны. Песочница строит свой кэш.
unset CLAUDSOUL_REPO

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
# Модуль описания проекта — рядом с прибором (D1233): без него прибор ищет установку автора, а на раннере и в
# контейнере её нет, и договоры не узнавались («карта этого вида не знает»).
mkdir -p hooks/lib; cp "$REPO_ROOT/hooks/lib/project_map.py" hooks/lib/
{ printf '# path\tsha\tdeps\tdocs\tests\tnames\n'
  printf 'hooks/alpha.sh\taaa\t\t\thooks/tests/test_alpha.sh\t\n'
  printf 'hooks/beta.sh\tbbb\thooks/alpha.sh\t\t\t\n'
  printf 'hooks/lonely.sh\tccc\t\t\t\t\n'; } > .claude-docs/dep-index.tsv
git add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
git commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }

build_cache() { ( cd "$REPO" && LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$REPO" python3 scripts/project-graph.py >/dev/null 2>&1 ); }
build_cache

run() {  # run <state> <файл> [репо]
    local r="${3:-$REPO}"
    printf '{"session_id":"t-%s","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/%s"}}' "$1" "$r" "$r" "$2" \
        | env STATE_DIR="$TMP/state-$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" LESSONS_DIR="$TMP/lessons" \
              CLAUDSOUL_ROOT="$r" bash "$HOOK" 2>/dev/null
}

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: у alpha.sh есть зависимые (beta зовёт, тест проверяет).
O=$(run s1 hooks/alpha.sh)
assert_contains "$O" 'на нём стоят'                  "T1: путь подан"
assert_contains "$O" 'test 1'                        "T1: тест назван видом и числом"
assert_contains "$O" '"hookEventName":"PreToolUse"'  "T1: подача протоколом, а не печатью в stdout"
assert_contains "$O" 'run_all.sh --changed'          "T1: вторая половина — чем проверить после сохранения"

# T2 — дедуп: подсказка нужна перед ПЕРВОЙ правкой файла, дальше она шум.
assert_empty "$(run s1 hooks/alpha.sh)" "T2: второй раз по тому же файлу тихо"
# T2b — показанные файлы лежат строками ОДНОГО файла сессии, а не пустым файлом на каждый (D1300).
_k=$(find "$TMP/state-s1" -maxdepth 1 -name 'impact-inject-t-s1*.keys' | wc -l | tr -d ' ')
_f=$(find "$TMP/state-s1" -maxdepth 1 -name 'impact-inject-t-s1*.flag' | wc -l | tr -d ' ')
_l=$(wc -l < "$TMP/state-s1/impact-inject-t-s1.keys" 2>/dev/null | tr -d ' ')
if [ "$_k" = 1 ] && [ "$_f" = 0 ] && [ "$_l" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T2b]: файлов ключей $_k, флагов $_f, строк ${_l:-нет}"; fi

# T3 — «инструмента здесь нет» — это другой проект, а не находка.
OTHER="$TMP/other"; mkdir -p "$OTHER/hooks"; ( cd "$OTHER" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$OTHER/hooks/alpha.sh"
assert_empty "$(run s3 hooks/alpha.sh "$OTHER")" "T3: без scripts/project-graph.py хук молчит"

# T4 — кэш старше учёта: не «чисто» и не поломка; сказать ОДИН раз за сессию.
CACHE="$REPO/mcp-server/visualization/project-graph-data.json"
# Фоновая пересборка (D1009) кончилась: кэш не старше учёта и замок прогона снят. Потолок 15 с.
wait_fresh() {
    local i=0
    while [ "$i" -lt 150 ]; do
        if ! [ "$REPO/.claude-docs/dep-index.tsv" -nt "$CACHE" ] && ! ls -d "$TMP/state-$1"/impact-inject-refresh-*.lock >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1; i=$((i + 1))
    done
    return 1
}
touch -t 200001010000 "$CACHE"
O4=$(run s4 hooks/alpha.sh)
assert_contains "$O4" 'Карта связей устарела' "T4: устаревший кэш назван"
assert_contains "$O4" 'пересобирается фоном'  "T4: пересборку запустил хук, а не подсказка (D1009)"
# T4b — РЕЗУЛЬТАТ D1009: кэш пересобран механизмом без ручного --refresh. Прежний хук только подсказывал, и кэш
# оставался старым — нога краснела бы.
if wait_fresh s4; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T4b]: кэш за 15 с не пересобран — исполнителя нет"; fi
touch -t 200001010000 "$CACHE"
assert_empty "$(run s4 hooks/beta.sh)"        "T4: второй файл той же сессии — тихо (один раз за сессию)"
wait_fresh s4 || true   # вторая пересборка не должна писать кэш под ногами следующих ног
build_cache

# T4c — ПАДЕНИЕ ФОНОВОЙ ПЕРЕСБОРКИ НАЗЫВАЕТСЯ И НЕ ПОВТОРЯЕТСЯ НА КАЖДОМ ВЫЗОВЕ (D1009, вторая редакция по финальному
# скептику). Первая слала вывод прогона в /dev/null: карточки пропадали молча, а каждая правка запускала новую сборку.
# Прибор-заглушка: кэш всегда стар (код 3), пересборка падает с причиной в потоке ошибок и считает свои запуски.
cp "$REPO/scripts/project-graph.py" "$TMP/keep4c.py"
printf '%s\n' '#!/usr/bin/env python3' 'import os, sys' 'if "--refresh" in sys.argv:' \
    '    open(os.environ["T4C_LOG"], "a").write("b\n")' \
    '    sys.stderr.write("Traceback\nPermissionError: boom-причина\n"); sys.exit(1)' 'sys.exit(3)' \
    > "$REPO/scripts/project-graph.py"
export T4C_LOG="$TMP/t4c.log"
assert_contains "$(run s4c hooks/alpha.sh)" 'пересобирается фоном' "T4c: первое касание запустило пересборку"
_i=0; until ls "$TMP/state-s4c"/impact-inject-refresh-*.fail >/dev/null 2>&1 || [ "$_i" -ge 150 ]; do sleep 0.1; _i=$((_i + 1)); done
assert_contains "$(run s4c hooks/beta.sh)" 'boom-причина' "T4c: падение пересборки названо её причиной"
assert_empty "$(run s4c hooks/lonely.sh)" "T4c: о падении сказано один раз за сессию"
sleep 1
_n4c=$(grep -c . "$T4C_LOG" 2>/dev/null); _n4c=${_n4c:-0}
if [ "$_n4c" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T4c]: упавшая пересборка запускалась $_n4c раз за три касания, ждали 1"; fi
unset T4C_LOG
cp "$TMP/keep4c.py" "$REPO/scripts/project-graph.py"
build_cache

# T5 — сломанный прибор: молчание читалось бы как «зависимостей нет».
cp "$REPO/scripts/project-graph.py" "$TMP/keep.py"
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$REPO/scripts/project-graph.py"
O5=$(run s5 hooks/alpha.sh)
assert_contains "$O5" 'BROKEN' "T5: отказ прибора назван, а не проглочен"
cp "$TMP/keep.py" "$REPO/scripts/project-graph.py"
# T5b — отказ прибора файл показанным не отмечает (D1009): карта починена — карточка того же файла в той же сессии
# приходит. Прежде флаг ставился до проверки кода, и файл молчал до конца сессии.
assert_contains "$(run s5 hooks/alpha.sh)" 'на нём стоят' "T5b: после починки карты карточка файла пришла"

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

# T9b — МНОЖЕСТВО ТО ЖЕ, ЧТО У ВЛАДЕЛЬЦА СЧЁТА (D1113, 26 октября 2026). `count-stats.sh` считает только верхний уровень
# каталога (`find -maxdepth 1`), домены без `_*.md`; а шаблон `case` пропускал `*` через «/», и новая проба
# `hooks/tests/fixtures/probe_D1112.sh` дважды за сессию дала «ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ (активных хуков)» при неизменных
# 92. Положительный контроль — T7 выше (новый хук верхнего уровня говорит).
( cd "$REPO" && git add -A >/dev/null 2>&1 && git commit -qm t9b-base >/dev/null 2>&1 )
mkdir -p "$REPO/hooks/tests/fixtures" "$REPO/hooks/lib" "$REPO/domains"
printf 'new\n' > "$REPO/hooks/tests/fixtures/probe_x.sh"
printf 'new\n' > "$REPO/hooks/lib/vlozhennaya-lib.sh"
printf 'new\n' > "$REPO/domains/_indeks.md"
O9b=$(run_bash s9b)
case "$O9b" in
    *"ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ"*) FAIL=$((FAIL+1)); echo "FAIL [T9b]: файл вне множеств владельца счёта (вложенный, _*.md), а про числа сказано: ${O9b:0:200}" ;;
    *) PASS=$((PASS+1)) ;;
esac
rm -f "$REPO/hooks/tests/fixtures/probe_x.sh" "$REPO/hooks/lib/vlozhennaya-lib.sh" "$REPO/domains/_indeks.md"

# T10 — ВЕТКА BASH × ОТКАЗ ПРИБОРА (17 сентября 2026, D427). Ветка кода прибора не читала: отказ
# приходит с пустым stdout и шёл в «узла нет, файл новый». С кодом 4 («карта НЕ ЦЕЛА») это стало
# регрессией: alpha.sh с двумя зависимыми получал «в карте его не было, внесён», `--touch` писал в
# нецелый кэш, а флаг дедупа отнимал верную подсказку до конца сессии. Висячее ребро дописано
# ПОСТОРОННЕМУ узлу (beta → 99999): alpha не задет, и ложь о нём была бы чистой ложью.
# Пересборка здесь СИЛОЙ: `build_cache` свежий кэш не трогает, а нецелый свежий кэш лечит только `--refresh`.
refresh_cache() { ( cd "$REPO" && LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$REPO" python3 scripts/project-graph.py --refresh >/dev/null 2>&1 ); }
refresh_cache
CACHE10="$REPO/mcp-server/visualization/project-graph-data.json"
python3 - "$CACHE10" <<'PY10'
import json, sys
p = sys.argv[1]; g = json.load(open(p))
b = [n for n in g['nodes'] if n['key'] == 'hooks/beta.sh'][0]
g['edges'].append({'source': b['id'], 'target': 99999, 'type': 'использует x', 'strength': 1})
json.dump(g, open(p, 'w'), ensure_ascii=False)
PY10
printf '#!/usr/bin/env bash\necho a\n# правка\n' > "$REPO/hooks/alpha.sh"
# Запись судится по mtime, а не по сумме: `--touch` узла без своих рёбер пишет кэш байт в байт прежним.
mt10() { python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$CACHE10"; }
SUM10=$(mt10)
O10=$(run_bash s10)
assert_contains     "$O10" 'BROKEN'               "T10: отказ прибора в ветке Bash назван"
assert_contains     "$O10" 'НЕ ЦЕЛА'              "T10: причина — словами самого прибора, а не копией его знания"
assert_not_contains "$O10" 'в карте его не было'  "T10: узел из карты не объявлен новым"
if [ "$(mt10)" = "$SUM10" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T10]: хук писал в нецелый кэш (--touch при отказе прибора)"; fi
assert_empty "$(run_bash s10)" "T10: второй раз в той же сессии — тихо (отказ назван один раз)"
# Флаг дедупа при отказе НЕ ставится: после пересборки тот же файл той же сессии получает верную подсказку.
refresh_cache
assert_contains "$(run_bash s10)" 'hooks/alpha.sh — на нём стоят' "T10: после пересборки подсказка по файлу приходит"

# T11 — ПРИБОР ИЗ ЧУЖОЙ ПАПКИ СЕССИИ НЕ ИСПОЛНЯЕТСЯ (D516): проба пункта гонит хук в песочном
# проекте с подложенным `scripts/project-graph.py` — при адресе владельца, названном на другой
# каталог, и при пустом адресе. Контроль внутри пробы: по адресу владельца прибор исполняется.
# Без этой ноги проба жила бы только в «Проверке» закрытого пункта, то есть раз в неделю.
P11=$(CLAUDSOUL_REPO="$REPO_ROOT" bash "$HOOK_DIR/tests/fixtures/probe_D516.sh" 2>&1); R11=$?
if [ "$R11" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T11]: проба D516, код $R11 — ${P11}"; fi

# T12 — ЦЕЛЬ ЧЕРЕЗ ПЕРЕМЕННУЮ НЕ ЛОЖИТСЯ В КАРТУ (D1037). Маршрут PreToolUse[Bash] спрашивает разбор целей, а тот
# отдавал `$S/ghost.sh` буквально: хук приклеивал cwd и вносил узел-призрак. Положительный контроль в той же
# команде — литеральная цель `hooks/real12.sh` названа. Путь cwd — настоящий (`pwd -P`): маршрут сверяет цель с
# корнем от git буквально, и `/var/folders` против `/private/var/folders` отбросил бы и литеральную цель.
refresh_cache
REPO_P=$(cd "$REPO" && pwd -P)
printf '{"session_id":"t-s12","tool_name":"Bash","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"command":"cp hooks/alpha.sh \\"$S/ghost.sh\\"; cp hooks/alpha.sh ~/tilde12.sh; touch hooks/real12.sh"}}' "$REPO_P" > "$TMP/in12.json"
O12=$(env STATE_DIR="$TMP/state-s12" PATHS_LIB="$HOOK_DIR/paths-lib.sh" LESSONS_DIR="$TMP/lessons" CLAUDSOUL_ROOT="$REPO" \
      bash "$HOOK" < "$TMP/in12.json" 2>/dev/null)
assert_not_contains "$O12" 'ghost.sh'  "T12: цель через переменную в карту не внесена"
assert_not_contains "$O12" 'tilde12.sh' "T12b: цель через тильду в карту не внесена (финальный скептик D1037)"
assert_contains     "$O12" 'real12.sh' "T12: литеральная цель той же команды названа"
# T12c — названа И ВНЕСЕНА: файла на PreToolUse ещё нет, а узел обязан лечь в кэш (D1071, F1). Прежняя проверка судила
# только текст «внесён», и редакция `--touch`, отказывавшая несуществующему файлу, прошла её зелёной.
if python3 -c 'import json,sys; g=json.load(open(sys.argv[1])); sys.exit(0 if any(n["key"]=="hooks/real12.sh" for n in g["nodes"]) else 1)' "$CACHE" 2>/dev/null
then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T12c]: hooks/real12.sh назван внесённым, а в кэше карты узла нет"; fi
# T12d — ЦЕЛЬ ОТНОСИТЕЛЬНО `cd` ТОЙ ЖЕ КОМАНДЫ (D1088). Каталог запроса — hooks/, команда переходит в корень: узел ложится
# в корне, а не призраком `hooks/real12d.md` (повод — `cd <корень> && cat >> SESSION.md` при каталоге запроса mcp-server).
refresh_cache
printf '{"session_id":"t-s12d","tool_name":"Bash","hook_event_name":"PreToolUse","cwd":"%s/hooks","tool_input":{"command":"cd \\"%s\\" && touch real12d.md"}}' "$REPO_P" "$REPO_P" > "$TMP/in12d.json"
O12d=$(env STATE_DIR="$TMP/state-s12d" PATHS_LIB="$HOOK_DIR/paths-lib.sh" LESSONS_DIR="$TMP/lessons" CLAUDSOUL_ROOT="$REPO" \
      bash "$HOOK" < "$TMP/in12d.json" 2>/dev/null)
assert_not_contains "$O12d" 'hooks/real12d.md' "T12d: цель после cd не приклеена к каталогу запроса"
assert_contains     "$O12d" 'real12d.md'       "T12d: цель после cd названа"
# T12e — `cd ..` из подкаталога: путь приводится разбором, а не склейкой — `hooks/../real12e.md` не называется (скептик
# D1088, находка 7: карточка звала существующий узел «новым»).
printf '{"session_id":"t-s12e","tool_name":"Bash","hook_event_name":"PreToolUse","cwd":"%s/hooks","tool_input":{"command":"cd .. && touch real12e.md"}}' "$REPO_P" > "$TMP/in12e.json"
O12e=$(env STATE_DIR="$TMP/state-s12e" PATHS_LIB="$HOOK_DIR/paths-lib.sh" LESSONS_DIR="$TMP/lessons" CLAUDSOUL_ROOT="$REPO" \
      bash "$HOOK" < "$TMP/in12e.json" 2>/dev/null)
assert_not_contains "$O12e" 'hooks/../'  "T12e: путь после cd .. приведён к пути от корня"
assert_contains     "$O12e" 'real12e.md' "T12e: цель после cd .. названа"
# T12f — `ссылка/..` в цели решает файловая система (D1073, M3 скептика): `out12f` ведёт наружу, и `out12f/../x/…`
# лежит вне дерева; склейка `normpath` давала `x/new12f.sh` и узел-призрак. Ссылка снимается сразу: до D1185 учёт читал
# ссылку на каталог как файл; снятие осталось.
mkdir -p "$TMP/o12f/x"; ln -s "$TMP/o12f" "$REPO/out12f"
printf '{"session_id":"t-s12f","tool_name":"Bash","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"command":"cat > out12f/../x/new12f.sh"}}' "$REPO_P" > "$TMP/in12f.json"
O12f=$(env STATE_DIR="$TMP/state-s12f" PATHS_LIB="$HOOK_DIR/paths-lib.sh" LESSONS_DIR="$TMP/lessons" CLAUDSOUL_ROOT="$REPO" \
      bash "$HOOK" < "$TMP/in12f.json" 2>/dev/null)
rm -f "$REPO/out12f"
assert_not_contains "$O12f" 'new12f.sh' "T12f: цель за ссылкой наружу не названа"
if python3 -c 'import json,sys; g=json.load(open(sys.argv[1])); sys.exit(1 if any(n["key"].endswith("new12f.sh") for n in g["nodes"]) else 0)' "$CACHE" 2>/dev/null
then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T12f]: цель за ссылкой наружу легла узлом в карту"; fi

# T12d — карточка ДОГОВОРА называет читателя, но выбор тестов по его рёбрам не обещает (F6 D1067): `run_all.sh`
# смотрит учёт только у изменённых .sh/.py. Положительная сторона той же фразы — T1 (alpha.sh).
printf -- '- x\n' > "$REPO/BACKLOG.md"
printf '#!/usr/bin/env bash\nsource hooks/alpha.sh\ncat "$REPO/BACKLOG.md"\n' > "$REPO/hooks/beta.sh"
python3 - "$REPO/.claude-docs/dep-index.tsv" <<'EOF'
import sys
p = sys.argv[1]; t = open(p).read(); old = "hooks/beta.sh\tbbb\thooks/alpha.sh\t"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "hooks/beta.sh\tbbb\tBACKLOG.md,hooks/alpha.sh\t"))
EOF
( cd "$REPO" && git add -A && git commit -qm d12 ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
refresh_cache
O12d=$(run s12d BACKLOG.md)
assert_contains     "$O12d" 'на нём стоят'                        "T12d: у договора читатель назван"
assert_not_contains "$O12d" 'выбор тестов идёт по этим же рёбрам' "T12d: выбор тестов по рёбрам договора не обещан"
# T12n — у РЕЕСТРА выбор тестов по рёбрам идёт (D1203): `run_all.sh` с тех пор смотрит учёт у всего, кроме документов.
printf 'a\tb\n' > "$REPO/scripts/reg.tsv"
printf '#!/usr/bin/env bash\nsource hooks/alpha.sh\ncat "$REPO/BACKLOG.md" "$REPO/scripts/reg.tsv"\n' > "$REPO/hooks/beta.sh"
python3 - "$REPO/.claude-docs/dep-index.tsv" <<'EOF'
import sys
p = sys.argv[1]; t = open(p).read(); old = "hooks/beta.sh\tbbb\tBACKLOG.md,hooks/alpha.sh\t"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "hooks/beta.sh\tbbb\tBACKLOG.md,hooks/alpha.sh,scripts/reg.tsv\t"))
EOF
( cd "$REPO" && git add -A && git commit -qm d12n ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
refresh_cache
O12n=$(run s12n scripts/reg.tsv)
assert_contains "$O12n" 'на нём стоят'                        "T12n: у реестра читатель назван"
assert_contains "$O12n" 'выбор тестов идёт по этим же рёбрам' "T12n: выбор тестов по рёбрам реестра обещан"
# T12o, T12p — скептик opus по af02bfce (L1, L2): учёт выбора не даёт, правка теста выбирает только его самого — обещание
# «по этим же рёбрам» у обоих ложно. У обоих узлов в карте есть стоящие: иначе карточки нет и нога зелена вхолостую.
printf '#!/usr/bin/env bash\nsource hooks/alpha.sh\ncat "$REPO/BACKLOG.md" "$REPO/scripts/reg.tsv" "$REPO/.claude-docs/dep-index.tsv"\n' > "$REPO/hooks/beta.sh"
printf '#!/usr/bin/env bash\nbash hooks/tests/test_alpha.sh\n' > "$REPO/hooks/tests/test_beta.sh"
python3 - "$REPO/.claude-docs/dep-index.tsv" <<'EOF'
import sys
p = sys.argv[1]; t = open(p).read(); old = "hooks/beta.sh\tbbb\tBACKLOG.md,hooks/alpha.sh,scripts/reg.tsv\t"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "hooks/beta.sh\tbbb\t.claude-docs/dep-index.tsv,BACKLOG.md,hooks/alpha.sh,scripts/reg.tsv\t"))
EOF
( cd "$REPO" && git add -A && git commit -qm d12o ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
refresh_cache
O12o=$(run s12o .claude-docs/dep-index.tsv)
assert_contains     "$O12o" 'на нём стоят'                        "T12o: у учёта читатель назван"
assert_not_contains "$O12o" 'выбор тестов идёт по этим же рёбрам' "T12o: выбор тестов по рёбрам учёта не обещан"
O12p=$(run s12p hooks/tests/test_alpha.sh)
assert_contains     "$O12p" 'на нём стоят'                        "T12p: у теста стоящий назван"
assert_not_contains "$O12p" 'выбор тестов идёт по этим же рёбрам' "T12p: выбор тестов по рёбрам теста не обещан"

# T12g–T12i — третий круг D1073 (скептик adac200f): хук отдаёт карте путь от корня ТЕКСТОМ, ключ подбирает карта по
# своим узлам. T12g — имя, удалённое переименованием регистра; T12h — каталог за ссылкой совместимости: карточка
# прежнего узла, второго узла нет (M-B). T12i — библиотека, которая не грузится, — прежняя склейка, а не тишина (L-E).
bash_card() {  # bash_card <state> <команда> [каталог хука] [каталог вызова]
    printf '{"session_id":"t-%s","tool_name":"Bash","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "${4:-$REPO_P}" "$2" \
        | env STATE_DIR="$TMP/state-$1" PATHS_LIB="${3:-$HOOK_DIR}/paths-lib.sh" LESSONS_DIR="$TMP/lessons" CLAUDSOUL_ROOT="$REPO" \
              bash "${3:-$HOOK_DIR}/impact-inject.sh" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
}
has_node() { python3 -c 'import json,sys; sys.exit(0 if sys.argv[2] in {n["key"] for n in json.load(open(sys.argv[1]))["nodes"]} else 1)' "$CACHE" "$1"; }
# Четвёртый круг (скептик 2f892efb): клетки хука обходом перечня — класс × форма {из корня, из подкаталога через `../`,
# `cd … &&`, абсолютный путь}. M1: из подкаталога через `..` хук заводил второй узел.
( cd "$REPO" && git mv hooks/alpha.sh hooks/Alpha.sh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
for f in "rel|$REPO_P|cat >> hooks/alpha.sh" "up|$REPO_P/hooks/tests|cat >> ../../hooks/alpha.sh" \
         "cd|$REPO_P|cd hooks/tests && cat >> ../alpha.sh" "abs|$REPO_P|cat >> $REPO_P/hooks/alpha.sh"; do
    IFS='|' read -r nm cw cmd <<< "$f"
    assert_contains "$(bash_card "s12g$nm" "$cmd" "" "$cw")" 'hooks/alpha.sh — на нём стоят' "T12g×$nm: удалённое переименованием имя — карточка прежнего узла"
done
( cd "$REPO" && git mv hooks/Alpha.sh hooks/alpha.sh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
if has_node hooks/Alpha.sh; then FAIL=$((FAIL+1)); echo "FAIL [T12g]: второй узел hooks/Alpha.sh"; else PASS=$((PASS+1)); fi
mkdir -p "$REPO/tools12"; printf '#!/usr/bin/env bash\necho g\n' > "$REPO/tools12/g.sh"
( cd "$REPO" && git add -A && git commit -qm t12h ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }; refresh_cache
( cd "$REPO" && git mv tools12 bin12 && ln -s bin12 tools12 ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }
for f in "rel|$REPO_P|cat >> tools12/g.sh" "up|$REPO_P/hooks/tests|cat >> ../../tools12/g.sh" \
         "cd|$REPO_P|cd hooks/tests && cat >> ../../tools12/g.sh" "abs|$REPO_P|cat >> $REPO_P/tools12/g.sh"; do
    IFS='|' read -r nm cw cmd <<< "$f"
    assert_contains "$(bash_card "s12h$nm" "$cmd" "" "$cw")" 'tools12/g.sh —' "T12h×$nm: каталог за ссылкой совместимости — карточка прежнего узла"
done
if has_node bin12/g.sh; then FAIL=$((FAIL+1)); echo "FAIL [T12h]: второй узел bin12/g.sh"; else PASS=$((PASS+1)); fi
# T12j, T12m — ветка правки файла (пятый потребитель): за ссылкой совместимости и через ссылку на каталог внутри
# дерева подпись — ключ карты (`pwd -P` уводил в `bin12/g.sh`, текст давал `tl12/beta.sh` — вторую карточку, L2).
assert_contains "$(run s12j tools12/g.sh)" 'Правишь `tools12/g.sh`' "T12j: правка файла за ссылкой совместимости — карточка прежнего узла"
ln -s hooks "$REPO/tl12"
assert_contains "$(run s12m tl12/beta.sh)" 'Правишь `hooks/beta.sh`' "T12m: правка через ссылку на каталог внутри дерева — подпись ключом карты"
# T12k — L-C у хука: каталог знакомого узла стал ссылкой наружу — это чужой файл, его карточки нет.
mkdir -p "$REPO/tools13" "$TMP/o13"; printf '#!/usr/bin/env bash\necho k\n' > "$REPO/tools13/k.sh"; cp "$REPO/tools13/k.sh" "$TMP/o13/"
( cd "$REPO" && git add -A && git commit -qm t12k ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_impact_inject.sh:$LINENO" >&2; exit 1; }; refresh_cache
mv "$REPO/tools13" "$TMP/o13old"; ln -s "$TMP/o13" "$REPO/tools13"
assert_not_contains "$(bash_card s12k 'cat >> tools13/k.sh')" 'tools13/k.sh —' "T12k: каталог узла — ссылка наружу, карточки нет"
mkdir -p "$TMP/hk_bad"; cp "$HOOK_DIR"/*.sh "$TMP/hk_bad/"; cp -R "$HOOK_DIR/lib" "$TMP/hk_bad/"
printf 'def rel_path(:\n' > "$TMP/hk_bad/lib/project_map.py"
O12i=$(bash_card s12i 'cat >> hooks/beta.sh' "$TMP/hk_bad")
assert_contains "$O12i" 'hooks/beta.sh —' "T12i: библиотека с ошибкой синтаксиса — карточка прежней склейкой"

echo "test_impact_inject: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
