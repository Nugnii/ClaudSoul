#!/usr/bin/env bash
# impact-inject.sh — PreToolUse[Edit|Write|MultiEdit], PreToolUse[Bash] и PostToolUse[Bash]: при правке файла ЛЮБЫМ путём подаёт ПОЛНЫЙ ПУТЬ по карте связей — кто на этом файле стоит (тесты, документы, знания, пункты долга, рода, корни) и на скольких стоит он сам; новый файл вносит в карту и говорит об этом, а если он попал в СЧИТАЕМОЕ множество (хуки, библиотеки, тесты, скиллы, домены, мосты) — называет сдвиг чисел документов и команду пересчёта; рядом называет, чем проверить после сохранения.
# en: PreToolUse[Edit|Write|MultiEdit], PreToolUse[Bash] and PostToolUse[Bash] — on a file edit made by ANY route, injects the FULL dependency path from the project map: who stands on this file (tests, docs, knowledge, backlog items, defect genera, roots) and how many it stands on itself; a new file is entered into the map and said so, and if it lands in a COUNTED set (hooks, libraries, tests, skills, domains, bridges) the shifted document numbers are named together with the recount command; alongside, names what to run after saving.
#
# Зачем. Потребитель карты назван владельцем 13 сентября 2026: «потребитель карты — ты,
# когда редактируешь файл, ты смотришь на карту, что ещё зависит; когда сохранил —
# смотришь, не поломал ли чего». Оставить карту командой, которую агент должен ВСПОМНИТЬ,
# нельзя: замер той же сессии — правила с механизмом исполнялись 7 раз из 7, правила
# текстом нарушены трижды (case-2026-09-13-mechanized-rules-held-text-rules-did-not).
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. `module-context-inject.sh` на том же событии подаёт МОДУЛЬ
# ДОКУМЕНТАЦИИ, описывающий файл, — предшественник остаётся, предметы разные: там «что
# про этот файл написано», здесь «что на нём стоит». `doc-impact-check.sh` и
# `dep-index.py --impact` отвечают на вопрос о документах ПОСЛЕ правки, в момент коммита;
# здесь ответ нужен ДО неё и шире документов. Вторая половина слова владельца («не
# поломал ли») владельца уже имеет — выбор тестов по изменённым файлам в
# `hooks/tests/run_all.sh --changed`; хук его НАЗЫВАЕТ, а не повторяет.
#
# ЦЕНА. Сборка карты стоит 10 с — в ходе правки и это неприемлемо, поэтому прибор зовётся
# с `PROJECT_GRAPH_NO_BUILD=1`: ответ только из кэша (0,05 с), а устаревший кэш даёт
# код 3, и тогда хук запускает пересборку фоном (D1009) и один раз за сессию говорит об этом.
# Решение о свежести принимает ПРИБОР, здесь его копии нет (род K — копия правила у потребителя).
#
# Input  (stdin): {tool_name, tool_input:{file_path}, session_id, cwd} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat); [ -z "$INPUT" ] && exit 0

# ФЛАГ/ДРОССЕЛЬ ГЕЙТИТ ДОСТАВКУ, а доставка идёт по АКТОРУ (D457, класс D463, 18 сентября
# 2026): «ЭТОМУ вызывающему уже показали». Без суффикса первый сработавший гасит инжект всем
# остальным, и владелец не видит того, что показали субагенту.
# Владелец суффикса один — `resolve_actor_suffix` (`paths-lib.sh`); у родителя он даёт ПУСТО,
# и имена его файлов остаются прежними.
_II_PATHS="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "${_II_PATHS}" ] || _II_PATHS="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "${_II_PATHS}" ] && . "${_II_PATHS}"
_II_ACTOR=""
command -v resolve_actor_suffix >/dev/null 2>&1 && _II_ACTOR=$(resolve_actor_suffix "$INPUT")

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)
case "$TOOL" in Edit|Write|MultiEdit|Bash) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
# ПРАВКА ИДЁТ НЕ ТОЛЬКО ИНСТРУМЕНТОМ EDIT (13 сентября 2026). Замер того дня: за сессию
# правлено 11 файлов кода, через карту прошло НОЛЬ — все правки шли командой Bash
# (`python3 - <<PY`, `sed -i`, перенаправление), а хук стоял на Edit|Write|MultiEdit.
# Признак не задевал реальный поток работы, и механизм был мнимым при зелёных тестах.
# Поэтому на Bash предмет берётся не из аргументов команды (там путь бывает собран из
# переменных и не виден), а у ГИТА: что в дереве стало изменённым или новым.
[ -n "$FILE" ] || [ "$TOOL" = "Bash" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Прибор исполняется только в рабочих копиях репозитория владельца — главной и его worktree
# (D516): файл с тем же именем в чужой папке сессии — не прибор, а чужой код, который хук исполнял
# на каждом Bash и Edit. Сверка и её довод — `project_owner_copy` в paths-lib; paths-lib не
# нашёлся — функции нет, ответ «нет», молчим: исполнять нечьё нельзя.
# В ЛЮБОМ ДРУГОМ ПРОЕКТЕ С ОПИСАНИЕМ (`.claude-docs/project-map.json`, шаг 1г, D1089) карта — его данные, а прибор —
# ClaudSoul (`CLAUDSOUL_ROOT`) с `--repo` корня проекта: код проекта не исполняется вовсе, git прибора — через
# `project_git`. Строки про выбор тестов (`run_all.sh`) и пересчёт чисел документов — устройство ClaudSoul, там они молчат.
TOOL_ARGS=(); OWN=1; II_CMD="python3 scripts/project-graph.py"
TOOL_PY="$ROOT/scripts/project-graph.py"
if ! project_owner_copy "$ROOT" "$CWD" 2>/dev/null; then
    [ -f "$ROOT/.claude-docs/project-map.json" ] && [ -n "${CLAUDSOUL_ROOT:-}" ] || exit 0
    OWN=0; TOOL_PY="$CLAUDSOUL_ROOT/scripts/project-graph.py"; TOOL_ARGS=(--repo "$ROOT")
    II_CMD="python3 \"$TOOL_PY\" --repo \"$ROOT\""
fi

# ТРИ СОСТОЯНИЯ ПРИБОРА. «Инструмента здесь нет» — другой проект, молчим.
[ -f "$TOOL_PY" ] || exit 0
_ii_graph() { (cd "$ROOT" && python3 "$TOOL_PY" ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"} "$@"); }
# ПЕРЕСБОРКУ УСТАРЕВШЕГО КЭША ИСПОЛНЯЕТ ХУК, А НЕ ПОДСКАЗКА (D1009, 23 октября 2026). Учёт двигает каждый коммит, и
# кэш карты стар после каждого; пересобирал его только человек по подсказке — с 20 сентября по 23 октября карточка
# не показалась ни разу. Сборка стоит 10–23 с (замеры 23 октября, по нагрузке; так с 13 сентября, до того — минута),
# поэтому хук, увидев код 3, запускает `--refresh` фоном и выходит, не дожидаясь: карточка приходит со следующей
# правки. Прогон один на рабочую копию — замок владельца `state-lock-lib.sh`: запись кэша не атомарна, два прогона
# писали бы его вперемешку. Отдельный процесс в своей группе — у подоболочки в bash 3.2 своего `$$` нет, а замок
# судит живость по PID (тот же довод у `backlog-reading-refresh.sh`). Нет библиотеки замка — фона нет, остаётся
# подсказка: фон без взаимоисключения хуже. Унаследованный `PROJECT_GRAPH_NO_BUILD` снимается: с ним сборка — пустышка.
# ПАДЕНИЕ ПЕРЕСБОРКИ НАЗЫВАЕТСЯ И НЕ ПОВТОРЯЕТСЯ НА КАЖДОМ ВЫЗОВЕ (вторая редакция по финальному скептику D1009).
# Первая слала вывод прогона в /dev/null: при устойчивой поломке карточки пропадали молча, а каждая правка запускала
# новую сборку. Теперь поток ошибок упавшего прогона ложится отметкой `<ключ>.fail`, повтор — не раньше чем через
# 10 минут, и падение называется один раз за сессию последней строкой ошибки и командой ручной пересборки.
# Названные пределы. Коммит, легший за время прогона, оставит кэш новее учёта, но старше содержанием — до следующей
# пересборки; условие снятия: свежесть судится по учёту, прочитанному сборкой, а не по времени файла. Ключ замка —
# корень рабочей копии, а кэш выбирает прибор: при экспортированном `CLAUDSOUL_REPO` сборки из главной копии и из
# worktree пишут один кэш параллельно (дамп сериализует замок самого прибора, теряется процессор); у каждого
# worktree своя сборка. Убийство одного держателя замка (`bash -c`) при живом питоне даёт вторую сборку.
# Условие снятия двух последних: ключ замка берётся у прибора (путь его кэша).
_II_KEY="$STATE_DIR/impact-inject-refresh-$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
_ii_refresh_bg() {   # → 0 запущено; 1 — нет библиотеки замка; 3 — пересборка недавно упала, повтор отложен
    local _sl
    _sl="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/state-lock-lib.sh"
    [ -f "$_sl" ] || _sl="$HOME/.claude/hooks/state-lock-lib.sh"
    [ -f "$_sl" ] || return 1
    if [ -f "$_II_KEY.fail" ] && [ -z "$(find "$_II_KEY.fail" -mmin +10 2>/dev/null)" ]; then return 3; fi
    set -m
    bash -c '. "$1" || exit 0; CLAUDSOUL_LOCK_TRIES=1; lock_acquire "$2" || exit 0
        ( cd "$3" && env -u PROJECT_GRAPH_NO_BUILD python3 "$4" "${@:5}" --refresh ) >/dev/null 2>"$2.err"
        if [ $? = 0 ]; then rm -f "$2.err" "$2.fail"; else mv -f "$2.err" "$2.fail"; fi
        lock_release "$2"' \
        _ "$_sl" "$_II_KEY" "$ROOT" "$TOOL_PY" ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"} </dev/null >/dev/null 2>&1 &
    set +m
    return 0
}
_ii_fail_why() { tail -n 1 "$_II_KEY.fail" 2>/dev/null | cut -c1-200; }

if [ "$TOOL" = "Bash" ]; then
    # Тишина, если изменённых нет. Каждый файл говорит ОДИН раз за сессию (дедуп ниже),
    # поэтому перечень уже правленных не гремит на каждой команде.
    SID_B=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
    # ДО ЗАПИСИ — НАМЕРЕНИЕ, ПОСЛЕ — ФАКТ (20 сентября 2026, D472, находка владельца).
    # На маршруте Bash хук стоял ТОЛЬКО на PostToolUse, и ответ о влиянии приходил, когда
    # файл уже переписан: за сессию 16dd77e3 вызовов Bash 1230, и правки шли почти только
    # ими. Довод прежнего решения записан рядом («путь бывает собран из переменных и не
    # виден, поэтому предмет берётся у гита») и был верен 13 сентября; разбор целей у
    # владельца `hooks/lib/write_targets.py` появился 16-го (D424), и довод устарел.
    # Оба события живут: PreToolUse спрашивает владельца, какой путь команда СОЗДАСТ или
    # перезапишет, PostToolUse по-прежнему смотрит, что в дереве стало изменённым, —
    # предметы разные, и путь из переменной виден только второму.
    # Промах на PreToolUse уводится в ТИШИНУ: разбор не нашёл цели либо его нет — выходим.
    if [ "${EVENT:-}" = "PreToolUse" ]; then
        _ii_cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        [ -n "$_ii_cmd" ] || exit 0
        _ii_cs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh"
        [ -f "$_ii_cs" ] || exit 0
        # shellcheck source=/dev/null
        . "$_ii_cs" 2>/dev/null || exit 0
        # Цели, известные целиком (D1037): путь через переменную или тильду карта приклеила бы к cwd узлом-призраком.
        declare -f executable_literal_write_targets >/dev/null 2>&1 || exit 0
        CHANGED=$(executable_literal_write_targets "$_ii_cmd") || exit 0
        # Пути от разбора бывают абсолютными и относительными к cwd (с каталогом `cd` той же команды — D1088); карта
        # говорит на языке путей ОТ КОРНЯ, поэтому приводим и отбрасываем то, что вне дерева. Приводит разбор путей, а не
        # склейка строк: `cd .. && cat >> f` при cwd в подкаталоге давал `mcp-server/../f`, и карточка звала
        # существующий узел «новым» (скептик D1088, находка 7). Приводит владелец ключа карты и учёта `rel_path`
        # (D1073): `..` решает файловая система — `out/../x/new.sh` при `out` → наружу лежит вне дерева, а склейка
        # `normpath` давала `x/new.sh` и призрак в карте. Владелец переводит С КЛЮЧАМИ КАРТЫ (D1073, четвёртый круг):
        # знакомое карте имя — её ключ в любой форме (удалённое коммитом, за ссылкой совместимости, из подкаталога через
        # `..`), незнакомое — с диска; так ключ получают и подпись карточки, и флаг дедупа, и `ls-files` ниже. Без
        # библиотеки или с библиотекой, которая не грузится, — прежняя склейка (L-E).
        CHANGED=$(printf '%s\n' "$CHANGED" | python3 -c '
import json, os, sys
c, r = sys.argv[1], sys.argv[2]
sys.path.insert(0, sys.argv[3])
try:
    from project_map import rel_path, outside, graph_out
    try:
        keys = {n["key"] for n in json.load(open(graph_out(None, r)))["nodes"]}
    except Exception:
        keys = set()
except Exception:
    rel_path = None
for p in sys.stdin.read().splitlines():
    if not p:
        continue
    if rel_path is not None:
        q = rel_path(r, os.path.join(c, p), keys)
        if q != "." and not outside(q):
            print(q)
    else:
        a = os.path.normpath(os.path.join(c, p))
        if a.startswith(r + "/"):
            print(a[len(r) + 1:])
' "$CWD" "$ROOT" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib" | sort -u)
    else
        # project_git (paths-lib): корень папки сессии — чужие настройки не исполняются (D515)
        CHANGED=$( { project_git -C "$ROOT" diff --name-only HEAD 2>/dev/null
                     project_git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null; } | sort -u )
    fi
    [ -n "$CHANGED" ] || exit 0
    LINES=""; SHOWN=0; REST=0
    while IFS= read -r _rel; do
        [ -n "$_rel" ] || continue
        # Отбор по виду — у прибора, а не перечнем расширений (шаг 1г): в TS-проекте `.ts` — код, и прежний перечень
        # `*.sh|*.py|*.md` его отсекал; вид, которого карта не знает, прибор называет сам — строкой ответа, не пустотой.
        _fk=$(printf '%s' "$_rel" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
        # Показанные файлы — строками ОДНОГО файла на сессию и актора, а не пустым файлом на каждый (D1300): флаг на
        # пару «сессия × файл» дал 3 084 файла у сессий тише трёх суток и держал каталог состояния над порогом.
        _keys="$STATE_DIR/impact-inject-${SID_B}${_II_ACTOR}.keys"
        grep -qxF -- "$_fk" "$_keys" 2>/dev/null && continue
        if [ "$SHOWN" -ge 3 ]; then REST=$((REST+1)); continue; fi
        _out=$(PROJECT_GRAPH_NO_BUILD=1 _ii_graph --node "$_rel" --brief 2>/dev/null)
        _rc=$?
        # ПУСТОЙ ВЫВОД — НЕ ВСЕГДА «УЗЛА НЕТ» (17 сентября 2026, D427, корень R6). Ветка кода
        # прибора не читала: отказ приходит с пустым stdout, и он шёл сюда же, в «файл новый».
        # С кодом 4 («карта НЕ ЦЕЛА», заведён тем же пунктом) это стало регрессией, и она
        # воспроизведена: alpha.sh с двумя зависимыми при висячем ребре у ПОСТОРОННЕГО узла —
        # до D427 хук подавал верное «на нём стоят 2», после — «в карте его не было, внесён»,
        # звал `--touch` в нецелый кэш, а флаг дедупа, поставленный ДО вызова, отнимал у файла
        # верную подсказку до конца сессии даже после `--refresh`. Теперь при отказе прибора
        # узел не вносится, файл показанным не отмечается, отказ называется ОДИН раз за сессию
        # словами самого прибора (первая строка его stderr — знание о коде 4 живёт у него, род K).
        # Отказ — свойство карты, а не файла, поэтому обход на нём кончается.
        # НАЗВАННЫЙ ПРЕДЕЛ: код 3 («кэш стар») по-прежнему идёт в ветку «узла нет» — то же ложное
        # «в карте его не было» по файлу, который в ней есть, а `--touch` вдобавок освежает
        # mtime кэша, и тот перестаёт выглядеть старым. Воспроизведено на механизме до правки.
        # Здесь не снято намеренно: учёт трогают 60 коммитов из последних 60, то есть кэш стар
        # после КАЖДОГО коммита, и отказ по коду 3 заглушил бы ветку до ручного `--refresh`, а
        # строку о сдвиге чисел (она вложена ниже) отнял бы в том же состоянии. Условие снятия:
        # решено, что хук делает между коммитом и пересборкой карты, — отдельный пункт долга.
        # ВТОРОЙ ПРЕДЕЛ: после починки и повторной поломки в той же сессии ветка молчит
        # (флаг сессионный, как у «устарела»); ветка Edit при этом называет отказ по файлу.
        if [ "$_rc" = "3" ]; then
            # Между коммитом и пересборкой (D1009): пересборку запускает сам хук, один раз за вызов.
            if [ -z "${_ii_how:-}" ]; then
                _ii_refresh_bg; _ii_bg=$?
                case "$_ii_bg" in
                    0) _ii_how="пересобирается фоном (10–23 с), карточки — со следующей правки" ;;
                    3) _ii_how="фоновая пересборка упала ($(_ii_fail_why)), повтор не раньше чем через 10 мин; пересобрать руками: \`${II_CMD} --refresh\`" ;;
                    *) _ii_how="пересобрать: \`${II_CMD} --refresh\`" ;;
                esac
            fi
            _sf="$STATE_DIR/impact-inject-stale-${SID_B}.flag"
            # Падение говорится своим флагом: о нём сессия могла ещё не слышать, хотя об устаревании слышала.
            [ "${_ii_bg:-0}" = 3 ] && _sf="$STATE_DIR/impact-inject-refresh-fail-${SID_B}.flag"
            if [ ! -f "$_sf" ]; then
                : > "$_sf" 2>/dev/null
                LINES="${LINES}
  · карта связей устарела (учёт новее кэша) — по \`${_rel}\` и следующим файлам сейчас не показать, что на них стоит; ${_ii_how}"
            fi
            continue
        fi
        if [ "$_rc" != "0" ] && [ "$_rc" != "3" ]; then
            _bf="$STATE_DIR/impact-inject-broken-${SID_B}.flag"
            if [ ! -f "$_bf" ]; then
                : > "$_bf" 2>/dev/null
                _why=$(PROJECT_GRAPH_NO_BUILD=1 _ii_graph --node "$_rel" --brief 2>&1 >/dev/null | head -1)
                LINES="${LINES}
  · карта связей: BROKEN — \`scripts/project-graph.py\` вернул код ${_rc} на \`${_rel}\`${_why:+ (${_why})}; узел НЕ внесён, файл показанным НЕ отмечен. Молчание тут читалось бы как «зависимостей нет», а это не проверено."
            fi
            break
        fi
        printf '%s\n' "$_fk" >> "$_keys" 2>/dev/null
        if [ -z "$_out" ]; then
            # Узла нет — файл НОВЫЙ. Вносим его в карту сразу: «при создании новое должно
            # попадать в карту» (слово владельца). Входящие рёбра появятся на --refresh.
            _add=$(_ii_graph --touch "$_rel" 2>/dev/null)
            # НОВЫЙ ФАЙЛ В СЧИТАЕМОМ МНОЖЕСТВЕ УЖЕ СДВИНУЛ ЧИСЛА ДОКУМЕНТОВ. Карта про это
            # молчит по построению: входящие рёбра появятся лишь на `--refresh`, а числа
            # живут не в ней, а в реестре `scripts/doc-claims.tsv`. Множества берутся у
            # ВЛАДЕЛЬЦА счёта (`scripts/count-stats.sh:19-25`), а не перечисляются заново.
            # Полного сверщика здесь не зовём: он идёт 48 секунд, а на границе записи это
            # неприемлемо — совпадения пути довольно, потому что новый файл такого вида
            # меняет счёт ПО ПОСТРОЕНИЮ. Повод измерен 14 сентября 2026: за день я создал
            # шесть таких файлов и ни разу не пересчитал числа — `test_derived_counts_inventory`
            # покраснел в ТРЁХ полных прогонах подряд, это около 36 минут прогонов, законченных
            # красным из-за команды, которая идёт две секунды.
            # НОВИЗНА СПРАШИВАЕТСЯ У МИРА, А НЕ У КАРТЫ (поправка 14 сентября 2026, в день
            # заведения ветки). Первая редакция считала новым всякий файл, которого НЕТ В
            # КАРТЕ, — а карта пересобирается лишь по `--refresh`, поэтому «новым» выглядел
            # любой давно не правленный файл. Ложная тревога поймана на себе в тот же день:
            # `doc-impact-check.sh` заведён 28 августа, хуков как было 82, так и осталось, а
            # ветка велела пересчитывать СЕЙЧАС. Точность была 2 из 3, и цена ложного — не
            # только лишний прогон, но и привычка не читать этот канал.
            # Признак теперь ровно тот, о котором утверждение: файл НЕ ОТСЛЕЖИВАЕТСЯ git,
            # значит он в мире новый и счёт множества сдвинут по построению. Один вызов
            # `ls-files`, около 10 мс; `count-stats.sh` (0,67 с) звать незачем, а полный
            # сверщик утверждений — тем более: 48 секунд принадлежат ему, не счётчику.
            # НАЗВАННЫЙ ПРЕДЕЛ: файл, заведённый и закоммиченный ДРУГОЙ сессией без
            # пересчёта, этой веткой не назван — он уже отслеживается. Там владелец пересчёта
            # чужой, а страж класса свой: `test_derived_counts_inventory` в наборе.
            # Условие снятия: ветка станет сверять СЧЁТ, а не новизну — `count-stats.sh`
            # по одному множеству идёт 0,67 с, и сравнение его числа с утверждением
            # документа назовёт и чужой файл. Сейчас не сделано по НАЗВАННОЙ причине:
            # владелец утверждения — реестр `scripts/doc-claims.tsv`, и чтение его отсюда
            # завело бы ВТОРОГО владельца одного факта (корень R1). Предел уйдёт, когда у
            # реестра появится режим «дай число по имени множества» — тогда звать станет кого.
            _cnt=""
            # Множества и команды пересчёта — устройство ClaudSoul (`scripts/count-stats.sh`): в чужом проекте не звучат.
            if [ "$OWN" != 1 ] || project_git -C "$ROOT" ls-files --error-unmatch -- "$_rel" >/dev/null 2>&1; then
                :
            else
            # Множества — как у владельца счёта (`scripts/count-stats.sh:19-25`): ВЕРХНИЙ уровень каталога (`find
            # -maxdepth 1`), у скиллов — `skills/<имя>/SKILL.md`, домены без `_*.md`. Судится каталог файла и его имя
            # порознь: в шаблоне `case` звёздочка проходит через «/», и `hooks/*.sh` ловил любой файл под `hooks/` —
            # новая проба в `hooks/tests/fixtures/` дважды звалась «активным хуком» при неизменных 92 (D1113, R3).
            _cdir="${_rel%/*}"; _cbase="${_rel##*/}"; [ "$_cdir" = "$_rel" ] && _cdir=""
            case "$_cdir" in
                hooks/tests)      case "$_cbase" in test_*.sh) _cnt="файлов тестов хуков" ;; esac ;;
                hooks)            case "$_cbase" in *-lib.sh) _cnt="библиотек" ;; *.sh) _cnt="активных хуков" ;; esac ;;
                skills/*/*)       ;;
                skills/*)         [ "$_cbase" = SKILL.md ] && _cnt="скиллов" ;;
                domains)          case "$_cbase" in _*) ;; *.md) _cnt="доменов" ;; esac ;;
                bridges)          case "$_cbase" in L*.md) _cnt="мостов" ;; esac ;;
                mcp-server/tests) case "$_cbase" in test_*.py) _cnt="тестов MCP" ;; esac ;;
            esac
            fi
            LINES="${LINES}
  · ${_rel} — в карте его не было, внесён (${_add:-новый узел}); кто на нём стоит, станет видно после \`${II_CMD} --refresh\`"
            [ -n "$_cnt" ] && LINES="${LINES}
    ЧИСЛА ДОКУМЕНТОВ СДВИНУЛИСЬ (${_cnt}): пересчитай СЕЙЧАС, иначе набор покраснеет —
    \`bash scripts/count-stats.sh --patch-claude-md\` и \`bash scripts/docs-refresh-claims.sh\`"
        else
            LINES="${LINES}
  · ${_rel} — ${_out}"
        fi
        SHOWN=$((SHOWN+1))
    done <<< "$CHANGED"
    [ -n "$LINES" ] || exit 0
    MSG_B="🗺 Тронуты файлы — связи по карте:${LINES}"
    [ "$REST" -gt 0 ] && MSG_B="${MSG_B}
  · и ещё ${REST} файл(ов) в этом ходу — полный путь: \`${II_CMD} --node <путь>\`"
    if [ "$OWN" = 1 ]; then
        MSG_B="${MSG_B}
Сломанное здесь вылезет там: пройди названные документы и прогони \`bash hooks/tests/run_all.sh --changed\`."
    else
        MSG_B="${MSG_B}
Сломанное здесь вылезет там: пройди названных и прогони их тесты."
    fi
    jq -cn --arg m "$MSG_B" --arg e "${EVENT:-PostToolUse}" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
    exit 0
fi

# Путь относительно корня — у владельца правила `rel_path` с ключами карты (D1073, четвёртый круг): знакомое карте имя —
# её ключ в любой форме (за ссылкой совместимости `tools -> bin` раскрытие давало `bin/b.sh`, и подсказка молчала;
# через ссылку на каталог внутри дерева — вторую карточку), незнакомое — с диска. Вне дерева — `//outside`. Без ответа
# библиотеки — обе стороны нормализуются pwd -P (macOS отдаёт /var против /private/var), как прежде.
# НАЗВАННЫЙ ПРЕДЕЛ (D1187, L3): ключи берутся разбором всей карты (1,5 МБ) на каждом вызове с целью — около 13 мс к запуску
# python (замер 2 ноября 2026 на ClaudSoul: 25,7 → 38,8 мс); тот же разбор у перевода целей команды выше. Условие снятия:
# у карты появится отдельный перечень ключей — тогда читается он.
REL=$(python3 -c 'import json, sys
sys.path.insert(0, sys.argv[3])
from project_map import rel_path, outside, graph_out
try:
    k = {n["key"] for n in json.load(open(graph_out(None, sys.argv[1])))["nodes"]}
except Exception:
    k = set()
q = rel_path(sys.argv[1], sys.argv[2], k)
print("//outside" if q == "." or outside(q) else q)' "$ROOT" "$FILE" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib" 2>/dev/null)
[ "$REL" = "//outside" ] && exit 0
if [ -z "$REL" ]; then
    FDIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P) || FDIR=""
    [ -n "$FDIR" ] && FILE="$FDIR/$(basename "$FILE")"
    ROOT_P=$(cd "$ROOT" 2>/dev/null && pwd -P) || ROOT_P="$ROOT"
    case "$FILE" in "$ROOT_P"/*) REL="${FILE#"$ROOT_P"/}" ;; "$ROOT"/*) REL="${FILE#"$ROOT"/}" ;; *) exit 0 ;; esac
fi

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
FKEY=$(printf '%s' "$REL" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/impact-inject-${SID}${_II_ACTOR}-${FKEY}.flag"   # основа имени флага отказа `.broken` (редкий)
KEYS="$STATE_DIR/impact-inject-${SID}${_II_ACTOR}.keys"                # показанные файлы сессии — строками (D1300)
grep -qxF -- "$FKEY" "$KEYS" 2>/dev/null && exit 0

OUT=$(PROJECT_GRAPH_NO_BUILD=1 _ii_graph --node "$REL" --brief 2>/dev/null)
RC=$?

if [ "$RC" = "3" ]; then
    # Кэш стар: это НЕ поломка и НЕ «чисто». Пересборку запускает хук (D1009); говорим один раз за сессию,
    # о падении пересборки — тоже один раз, своим флагом.
    _ii_refresh_bg; _ii_bg=$?
    case "$_ii_bg" in
        0) _ii_how="пересобирается фоном (10–23 с), карточка — со следующей правки" ;;
        3) _ii_how="фоновая пересборка упала ($(_ii_fail_why)), повтор не раньше чем через 10 мин; пересобрать руками: \`${II_CMD} --refresh\`" ;;
        *) _ii_how="пересобрать: \`${II_CMD} --refresh\` (10–23 с, можно фоном)" ;;
    esac
    STALE="$STATE_DIR/impact-inject-stale-${SID}.flag"
    [ "$_ii_bg" = 3 ] && STALE="$STATE_DIR/impact-inject-refresh-fail-${SID}.flag"
    [ -f "$STALE" ] && exit 0
    : > "$STALE" 2>/dev/null
    jq -cn --arg m "🗺 Карта связей устарела (учёт новее кэша) — полный путь по файлу сейчас не показать; ${_ii_how}." \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    exit 0
fi

if [ "$RC" != "0" ]; then
    # Отказ прибора — свойство карты, а не файла: показанным файл НЕ отмечается, иначе после починки карты его
    # карточка не пришла бы до конца сессии (D1009). Отказ по файлу называется один раз — своим флагом.
    [ -f "$THROTTLE.broken" ] && exit 0
    : > "$THROTTLE.broken" 2>/dev/null
    jq -cn --arg m "🗺 Карта связей: BROKEN — \`scripts/project-graph.py\` вернул код $RC. Молчание тут читалось бы как «зависимостей нет», а это не проверено." \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    exit 0
fi

printf '%s\n' "$FKEY" >> "$KEYS" 2>/dev/null

# Узла в карте нет (новый файл) — законная тишина, не находка.
[ -n "$OUT" ] || exit 0
# Вид файла карта не знает (шаг 1г): ответ прибора — его словами; «смотри, что на нём стоит» и строка о выборе тестов
# были бы ответом на неспрошенное. Ответы о стоящих начинаются с «на нём», иное — слово прибора как есть.
case "$OUT" in
    "на нём "*) ;;
    *) jq -cn --arg m "🗺 Правишь \`$REL\` — ${OUT}." '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
       exit 0 ;;
esac

# Выбор тестов смотрит учёт у всего, кроме документов `.md`, самого учёта и тестов — правка теста выбирает только его
# (`hooks/tests/run_all.sh`, функция `_changed_tests`; реестры и прочие данные — с D1203): у них «по этим же рёбрам» было
# бы ложным утверждением (F6 D1067). Перечень видов повторён литералом — его держат ноги T12d (документ), T12n (реестр),
# T12o (учёт) и T12p (тест).
case "$OWN:$REL" in
    1:*.md|1:.claude-docs/dep-index.tsv) _ii_tests="Выбор тестов (\`run_all.sh --changed\`) по рёбрам этого файла НЕ идёт — стоящих на нём прогони сам." ;;
    1:hooks/tests/test_*.sh) _ii_tests="Правка теста выбирает в \`run_all.sh --changed\` только его самого — стоящих на нём прогони сам." ;;
    1:*) _ii_tests="После сохранения — \`bash hooks/tests/run_all.sh --changed\`: выбор тестов идёт по этим же рёбрам." ;;
    *) _ii_tests="Тестов по рёбрам здесь не выбирает ничто — стоящих на нём прогони сам." ;;
esac
MSG="🗺 Правишь \`$REL\` — по карте связей ${OUT}. Смотри ПЕРЕД правкой, что на нём стоит: сломанное здесь вылезет там. ${_ii_tests} Полный путь: \`${II_CMD} --node $REL\`."

jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
