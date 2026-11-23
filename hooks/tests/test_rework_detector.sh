#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh
# test_rework_detector.sh — детектор третьего захода на тот же файл.
#
# Отрицательный контроль обязателен по построению (правило v1.12.4): проверка,
# про которую не показано, что она способна упасть, ничего не доказывает. Поэтому
# у каждого случая есть пара — вход, на котором детектор ОБЯЗАН молчать.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/rework-detector.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ПОРОГ СНИЖЕН ДО 2 (9 сентября 2026, поправка владельца: «триггером есть твоя остановка
# при разработке и проба иначе или снова»). Ловить надо не хроническую переработку, а
# первый разворот: попробовал, проверил, не сошлось, пробую иначе. До этого о втором
# заходе не знал никто — молчали оба детектора, потому что прогоны были зелёные.
# Замер по 1421 цели: порог 3 → 243 срабатывания, порог 2 → 464 (около 8 на сессию).
# Громкость разведена: второй заход — короткий вопрос, третий и дальше — полная доктрина.

assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {
    if [ -z "$1" ] || [ "$1" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}

edit() { # sid, path
    jq -cn --arg s "$1" --arg p "$2" \
        '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
run() { # sid [каталог сессии] — без каталога мир ног `$WORLD` (D1287); ноги с целью во временном каталоге подают свой (D1268)
    jq -cn --arg s "$1" --arg d "${2:-$WORLD}" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:"bash test.sh"}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
mkdir -p "$TMP/state"
# Мир ног — свой чистый репозиторий, неподвижный за прогон, поле `cwd` у каждого вызова оболочки (D1287): без поля
# детектор судит дерево процесса — на грязном живом дереве ноги D449 были зелёными при сломанной записи снимка, а
# дозапись в живое дерево посреди прогона засчитывалась правкой в цепочке ног T1 и T4 (скептик opus, M3).
WORLD="$TMP/world"; mkdir -p "$WORLD"
( cd "$WORLD" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=t -c user.email=t@t commit -qm 0 ) \
    || { echo "подготовка мира не удалась (репозиторий ног)" >&2; exit 1; }

# === T1: правка → прогон → правка → прогон → правка = третий заход, горит ===
OUT=$(edit s1 /repo/test_x.sh); assert_empty "$OUT" "T1a: первая правка → тишина"
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh); assert_contains "$OUT" "Второй заход" "T1b: вторая правка в цепочке → короткий вопрос (порог 2 с 9 сентября 2026)"
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T1c: третья правка в цепочке → горит"
assert_contains "$OUT" "test_x.sh" "T1d: назван файл"
# Проверяется НАЛИЧИЕ доктрины разбора, а не её формулировка. Прежде здесь стоял кусок
# собственной редакции хука («Почему предыдущая правка не сработала») — пять готовых
# «почему», то есть фикс-глубина, отменённая /retro 3.1. Тест на дословный текст своей
# редакции держал её же: он был бы зелёным ровно до тех пор, пока хук расходится с каноном.
# Единственность текста держит test_root_cause_doctrine_drift; здесь — что текст доехал.
assert_contains "$OUT" "НИ ОДНИМ путём" "T1e: дана доктрина разбора (признак корня)"
# T1f (D1030): журнал переработки несёт время ПЕРВЫМ полем — вход будущей меры действия стража миром
# (повтор правки после починки). `cycles` остаётся последним: гашение повтора ищет подстроку
# `"path":…,"cycles":N}` с закрывающей скобкой, и поле после `cycles` её бы сломало (скептик opus, 23.10.2026:
# прежде форму писателя не держала ни одна нога, проба писала журнал руками со временем в конце).
RF=$(ls "$TMP/state"/rework-fired-s1*.jsonl 2>/dev/null | head -1)
if [ -n "$RF" ] && grep -qE '^\{"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z","path":"/repo/test_x\.sh","cycles":[0-9]+\}$' "$RF" \
   && ! grep -vqE '^\{"ts":"[^"]+","path":"[^"]+","cycles":[0-9]+\}$' "$RF"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T1f]: строка журнала переработки не в форме {ts,path,cycles}: $(head -2 "${RF:-/dev/null}")"; fi

# === T2: три правки ПОДРЯД без прогонов — обычное дописывание, не переработка ===
OUT=$(edit s2 /repo/doc.md); assert_empty "$OUT" "T2a: первая → тишина"
OUT=$(edit s2 /repo/doc.md); assert_empty "$OUT" "T2b: вторая подряд → тишина"
OUT=$(edit s2 /repo/doc.md)
assert_empty "$OUT" "T2c: третья подряд без прогонов → тишина (не переработка)"

# === T3: правки РАЗНЫХ файлов с прогонами — не цепочка ===
edit s3 /repo/a.sh >/dev/null; run s3 >/dev/null
edit s3 /repo/b.sh >/dev/null; run s3 >/dev/null
OUT=$(edit s3 /repo/c.sh)
assert_empty "$OUT" "T3: разные файлы → тишина"

# === T4: новый цикл переделки того же файла говорит снова; повтор без прогона — молчит ===
# Троттл — по (файл, число циклов), а не по файлу: первый прогон замера detection-share
# (30 августа 2026) показал, что после первого напоминания файл переделывался дальше, а страж
# молчал — «повтор уплывает» (поправка владельца 27 августа). Правки без прогона между ними
# число циклов не меняют — та же подпись, тишина.
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T4a: четвёртый цикл того же файла — новое событие, страж говорит"
OUT=$(edit s1 /repo/test_x.sh)
assert_empty "$OUT" "T4b: правка без прогона — та же подпись, тишина (throttle)"

# === T5: другая сессия считается независимо ===
edit s5 /repo/test_x.sh >/dev/null; run s5 >/dev/null
edit s5 /repo/test_x.sh >/dev/null; run s5 >/dev/null
OUT=$(edit s5 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T5: новая сессия — свой счёт"

# === T6: порог настраивается ===
OUT=$(jq -cn '{session_id:"s6", tool_name:"Edit", tool_input:{file_path:"/repo/z.sh"}}' \
    | env STATE_DIR="$TMP/state" REWORK_THRESHOLD=1 bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "Переработка" "T6: порог 1 → горит с первой правки"

# === T8: файлы-хроники исключены (калибровка D18) ===
edit s8 /repo/CHANGELOG.md >/dev/null; run s8 >/dev/null
edit s8 /repo/CHANGELOG.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/CHANGELOG.md)
assert_empty "$OUT" "T8: CHANGELOG.md — хроника, детектор молчит"
edit s8 /repo/sub/SESSION.md >/dev/null; run s8 >/dev/null
edit s8 /repo/sub/SESSION.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/sub/SESSION.md)
assert_empty "$OUT" "T8b: SESSION.md во вложенной папке — тоже хроника"
# T8c (D358, 13 сентября 2026): производные файлы учёта и документы — индекс зависимостей, README,
# карта корней, docs/, доки модулей — правятся каждой задачей по устройству; детектор молчит.
# Положительный контроль рядом: код в hooks/ считается как прежде.
for _bk in /repo/.claude-docs/dep-index.tsv /repo/README.ru.md /repo/ROOTS.md /repo/docs/architecture.md /repo/.claude-docs/modules/x.md; do
    edit s8c "$_bk" >/dev/null; run s8c >/dev/null; edit s8c "$_bk" >/dev/null; run s8c >/dev/null
    OUT=$(edit s8c "$_bk")
    assert_empty "$OUT" "T8c: $_bk — файл учёта, детектор молчит"
done
edit s8d /repo/hooks/x.sh >/dev/null; run s8d >/dev/null; edit s8d /repo/hooks/x.sh >/dev/null; run s8d >/dev/null
OUT=$(edit s8d /repo/hooks/x.sh)
assert_contains "$OUT" "Переработка" "T8d: код в hooks/ по-прежнему считается (положительный контроль сужения)"
assert_contains "$OUT" "x.sh" "T8d: назван файл (детектор печатает имя без каталога, как в T1d)"
OUT=$(jq -cn '{session_id:"s8", tool_name:"Edit", tool_input:{file_path:"/repo/BACKLOG-archive.md"}}' \
    | env STATE_DIR="$TMP/state" REWORK_THRESHOLD=1 bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T8c: BACKLOG-archive.md исключён даже при пороге 1"
# Разметка выборки D23 (2026-08-11): документы состояния попали в сигнал как шум —
# CLAUDE.md дважды, META.md один раз. Повторная правка в них — норма жанра, как append
# в хронике: картина уточняется по ходу сессии.
edit s8 /repo/CLAUDE.md >/dev/null; run s8 >/dev/null
edit s8 /repo/CLAUDE.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/CLAUDE.md)
assert_empty "$OUT" "T8d: CLAUDE.md — документ состояния, детектор молчит"
# Отрицательный контроль к T8d: рядом стоящий .md БЕЗ роли документа состояния обязан
# сигналить, иначе исключение расширилось до «любой markdown» и сигнала не осталось.
edit s8 /repo/case-2026-08-11-x.md >/dev/null; run s8 >/dev/null
edit s8 /repo/case-2026-08-11-x.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/case-2026-08-11-x.md)
assert_contains "$OUT" "Переработка" "T8e: обычный .md по-прежнему сигналит (иначе исключение съело сигнал)"

# === T7: мусор на входе не роняет хук ===
OUT=$(printf 'not-json' | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null); RC=$?
assert_empty "$OUT" "T7a: мусор → тишина"
if [ "$RC" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [T7b]: rc=$RC"; fi

# === D91: правка через оболочку — такая же правка ===
# До 27 августа 2026 ветка Bash писала только «прогон», и в сессии, где файлы правят
# через heredoc и sed, цепочка не набирала ни шага: замер по живой сессии — 156 записей
# в логе, из них 16 правок, все от субагентов через Write, а переписанный больше десяти
# раз через оболочку hook-input-lib.sh отсутствовал полностью.
# Цель — во временном каталоге С ФОРМОЙ `*/tmp/*` на любой платформе (D1268): детектор судит временный каталог по
# корню сессии — внутри каталога сессии это файл проекта. Прежде фикстура жила в настоящем HOME, потому что детектор
# отбрасывал `*/tmp/*` по форме пути (CI 30 августа 2026, case-2026-08-29-fixture-easier-than-world-hides-the-defect), и
# снятый по сроку прогон оставлял её там. Каталог сессии подаётся полем `cwd`.
BASH_DIR="$TMP/tmp/proj"; mkdir -p "$BASH_DIR"
BASH_TARGET="$BASH_DIR/target_file.sh"
printf '#!/usr/bin/env bash\necho x\n' > "$BASH_TARGET"

sh_edit() { # sid, команда [каталог сессии]
    jq -cn --arg s "$1" --arg c "$2" --arg d "${3-$BASH_DIR}" \
        '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# затравка: цепочка создаётся только если в сессии уже была правка
edit s9 /repo/seed.sh >/dev/null

OUT=$(sh_edit s9 "cat > $BASH_TARGET <<'EOF'
one
EOF"); assert_empty "$OUT" "D91a: первая правка через оболочку → тишина"
run s9 "$BASH_DIR" >/dev/null
OUT=$(sh_edit s9 "sed -i '' 's/one/two/' $BASH_TARGET"); assert_contains "$OUT" "Второй заход" "D91b: вторая через оболочку → короткий вопрос"
# D1268: та же цель во временном каталоге, а каталог сессии — другой: черновик, цепочки нет.
edit s9n /repo/seed.sh >/dev/null
sh_edit s9n "cat > $BASH_TARGET <<'EOF'
one
EOF" /repo >/dev/null
run s9n /repo >/dev/null
OUT=$(sh_edit s9n "sed -i '' 's/one/two/' $BASH_TARGET" /repo); assert_empty "$OUT" "D1268: цель во временном каталоге вне каталога сессии — черновик, тишина"
# D1268 (скептик opus по 53d7a871, M): каталог сессии — соседний префикс цели (`…/tmp/pro` при `…/tmp/proj/…`) — не
# корень цели: черновик. Мутант без `/` после каталога сессии считал бы её файлом проекта.
edit s9p /repo/seed.sh >/dev/null
sh_edit s9p "cat > $BASH_TARGET <<'EOF'
one
EOF" "${BASH_DIR%j}" >/dev/null
run s9p "${BASH_DIR%j}" >/dev/null
OUT=$(sh_edit s9p "sed -i '' 's/one/two/' $BASH_TARGET" "${BASH_DIR%j}"); assert_empty "$OUT" "D1268p: каталог сессии — соседний префикс цели, черновик"
# D1268e: та же граница у файлового инструмента — правка во временном каталоге вне каталога сессии не считается.
ew() { jq -cn --arg s "$1" --arg p "$2" --arg d "$3" '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p}, cwd:$d}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }
ew s9e /repo/seed.sh /repo >/dev/null; ew s9e "$BASH_TARGET" /repo >/dev/null; run s9e /repo >/dev/null
OUT=$(ew s9e "$BASH_TARGET" /repo); assert_empty "$OUT" "D1268e: Edit во временном каталоге вне каталога сессии — черновик"
ew s9f /repo/seed.sh "$BASH_DIR" >/dev/null; ew s9f "$BASH_TARGET" "$BASH_DIR" >/dev/null; run s9f "$BASH_DIR" >/dev/null
OUT=$(ew s9f "$BASH_TARGET" "$BASH_DIR"); assert_contains "$OUT" "Второй заход" "D1268f: Edit во временном каталоге внутри каталога сессии — файл проекта"
run s9 "$BASH_DIR" >/dev/null
OUT=$(sh_edit s9 "python3 - <<'PY'
import io
p='$BASH_TARGET'
io.open(p,'w').write('three')
PY")
assert_contains "$OUT" "Переработка" "D91c: третья правка через оболочку → горит"
assert_contains "$OUT" "target_file.sh" "D91d: назван файл, правленный через оболочку"

# === D277 (3 сентября 2026): относительный путь достраивается каталогом СЕССИИ ===
# Прежде список корней начинался с $CLAUDE_PROJECT_DIR и $PWD, а `.cwd` payload не
# разбиралось ни разу. Процесс хука не обязан стоять в каталоге сессии — Claude Code
# запускает его из своего cwd, — и при запуске из чужого каталога ни один относительный
# путь не находился: цепочка не набирала ни шага, страж молчал при любом числе заходов.
# Фикстура уводит ПРОЦЕСС в `/` и подаёт каталог только полем `cwd`, как это делает
# Claude Code. Цель — в каталоге сессии `$BASH_DIR`, как у D91 выше (D1268).
REL_TARGET="rel_target.sh"
printf '#!/usr/bin/env bash\necho x\n' > "$BASH_DIR/$REL_TARGET"

rel_call() { # sid, команда, cwd (пустой — поля .cwd в payload нет)
    if [ -n "$3" ]; then
        jq -cn --arg s "$1" --arg c "$2" --arg d "$3" \
            '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:$c}}'
    else
        jq -cn --arg s "$1" --arg c "$2" \
            '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}}'
    fi | (cd / && env STATE_DIR="$TMP/state" CLAUDE_PROJECT_DIR= bash "$HOOK" 2>/dev/null)
}

edit s11 /repo/seed.sh >/dev/null   # затравка: цепочка живёт только при непустом логе
OUT=$(rel_call s11 "printf x >> $REL_TARGET" "$BASH_DIR")
assert_empty "$OUT" "D277a: первая правка относительным путём → тишина"
rel_call s11 "bash -n $REL_TARGET" "$BASH_DIR" >/dev/null
OUT=$(rel_call s11 "printf x >> $REL_TARGET" "$BASH_DIR")
assert_contains "$OUT" "Второй заход" "D277b: вторая относительным путём → короткий вопрос"
rel_call s11 "bash -n $REL_TARGET" "$BASH_DIR" >/dev/null
OUT=$(rel_call s11 "printf x >> $REL_TARGET" "$BASH_DIR")
assert_contains "$OUT" "Переработка" "D277c: третья правка относительным путём из чужого каталога процесса → горит"
assert_contains "$OUT" "$REL_TARGET" "D277d: назван файл, найденный по каталогу сессии"

# Отрицательный контроль: тот же сценарий БЕЗ поля `.cwd` — достраивать нечем, тишина.
# Без него D277c зеленел бы и у версии, которая находит файл каким-то другим способом.
edit s12 /repo/seed.sh >/dev/null
rel_call s12 "printf x >> $REL_TARGET" "" >/dev/null
rel_call s12 "bash -n $REL_TARGET" "" >/dev/null
rel_call s12 "printf x >> $REL_TARGET" "" >/dev/null
rel_call s12 "bash -n $REL_TARGET" "" >/dev/null
OUT=$(rel_call s12 "printf x >> $REL_TARGET" "")
assert_empty "$OUT" "D277e: без .cwd в payload и вне каталога — цепочка не строится (тишина)"

# Запуск файла — не правка: адресат записи другой
edit s10 /repo/seed.sh >/dev/null
OUT=$(sh_edit s10 "bash $BASH_TARGET > $TMP/out.log 2>&1"); assert_empty "$OUT" "D91e: запуск с редиректом в лог → тишина"
run s10 "$BASH_DIR" >/dev/null
OUT=$(sh_edit s10 "bash $BASH_TARGET > $TMP/out.log 2>&1"); assert_empty "$OUT" "D91f: второй запуск → тишина"
run s10 "$BASH_DIR" >/dev/null
OUT=$(sh_edit s10 "bash $BASH_TARGET > $TMP/out.log 2>&1")
assert_empty "$OUT" "D91g: третий запуск не считается переработкой"

# === D449: снимок мира принадлежит АКТОРУ, и актор берётся из поля `agent_id` ===
# Прежде актор различался префиксом `agent-` в ИМЕНИ расшифровки — формой, которой харнесс
# не производит: в `transcript_path` он кладёт путь РОДИТЕЛЯ и субагенту тоже (замер
# 17 сентября 2026). Снимков с суффиксом в живом состоянии было 0 при 3330 расшифровках
# субагентов, то есть правки субагента приписывались родителю.
# Мир ног — `$WORLD` (выше), поле `cwd` у каждого вызова (D1287).
edit_as() { # sid, agent_id, путь — правка файловым инструментом от имени актора
    jq -cn --arg s "$1" --arg a "$2" --arg f "$3" --arg d "$WORLD" \
        '{session_id:$s, tool_name:"Edit", cwd:$d, tool_input:{file_path:$f}}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
run_as() { # sid, agent_id
    jq -cn --arg s "$1" --arg a "$2" --arg d "$WORLD" \
        '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:"bash test.sh"}}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
# Журнал у КАЖДОГО актора свой (D453), поэтому свой заводит и субагент — снимок мира
# появляется первым прогоном ПОСЛЕ первой правки, одинаково у обоих. 18 сентября 2026 здесь
# стоял только `edit` родителя: субагент проходил ветку Bash за счёт ЧУЖОГО журнала, и это
# была форма прежнего мира, где журнал общий. Попытка сохранить прежнюю форму веткой
# «журнала нет — завести снимок» стоила субагенту сигнала переработки целиком (снята в тот
# же день адверсариальной проверкой), поэтому фикстура приведена к устройству, а не наоборот.
edit_as d449 "" /repo/actor_x.sh >/dev/null  # журнал РОДИТЕЛЯ
edit_as d449 abc123 /repo/actor_y.sh >/dev/null  # журнал СУБАГЕНТА
run_as d449 "" >/dev/null                 # вызов родителя
run_as d449 abc123 >/dev/null             # вызов субагента той же сессии
if [ -f "$TMP/state/rework-world-d449.txt" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [D449a]: снимок родителя не создан"; fi
if [ -f "$TMP/state/rework-world-d449.agent-abc123.txt" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [D449b]: снимок субагента не отделён — правки акторов в одном файле"; fi
# Положительный контроль: ИМЯ расшифровки актором больше не считается.
run_as d449b "" >/dev/null
edit_as d449b "" /repo/actor_y.sh >/dev/null
jq -cn --arg d "$WORLD" '{session_id:"d449b", tool_name:"Bash", cwd:$d, transcript_path:"/x/agent-looks-like-one.jsonl", tool_input:{command:"bash t.sh"}}' \
    | env STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
if [ -f "$TMP/state/rework-world-d449b.txt" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [D449c]: имя agent-*.jsonl без поля увело снимок в чужой файл"; fi

# === D1291: снимок прежнего вида (ключ — время файла) после переноса правкой не засчитывается ===
# Ключ строки снимка стал хешем содержимого; снимок, написанный прежним детектором, считается отсутствующим — иначе первый
# вызов после переноса засчитал бы правкой каждый изменённый файл. Положительный контроль: дозапись после — правка.
W2="$TMP/world1291"; mkdir -p "$W2"
( cd "$W2" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=t -c user.email=t@t commit -qm 0 \
    && printf 'b\n' >> f.sh ) || { echo "подготовка мира D1291 не удалась" >&2; exit 1; }
printf '%s\tf.sh\t1700000000\n%s\t\t\n' "$W2" "$W2" > "$TMP/state/rework-world-d1291.txt"
: > "$TMP/state/rework-d1291.jsonl"
run d1291 "$W2" >/dev/null
if ! grep -q '"kind":"edit"' "$TMP/state/rework-d1291.jsonl"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [D1291a]: снимок прежнего вида засчитал изменённый файл правкой"; fi
printf 'c\n' >> "$W2/f.sh"; run d1291 "$W2" >/dev/null
if grep -q '"kind":"edit".*f\.sh' "$TMP/state/rework-d1291.jsonl"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [D1291b]: дозапись после снимка прежнего вида не засчитана"; fi
# D1291c (скептик opus по a3566bff, M1): строка прежнего вида файла, ушедшего из статуса, памятью с числом не становится —
# иначе снимок вершины навсегда «прежнего вида», и ветка мира молчит на настоящих правках.
W3="$TMP/world1291c"; mkdir -p "$W3"
( cd "$W3" && git init -q && printf 'a\n' > f.sh && printf 'a\n' > g.sh && git add f.sh g.sh \
    && git -c user.name=t -c user.email=t@t commit -qm 0 && printf 'b\n' >> f.sh ) || { echo "подготовка мира D1291c не удалась" >&2; exit 1; }
printf '%s\tf.sh\t1700000000\n%s\tg.sh\t1700000001\n%s\t\t\n' "$W3" "$W3" "$W3" > "$TMP/state/rework-world-d1291c.txt"
: > "$TMP/state/rework-d1291c.jsonl"
run d1291c "$W3" >/dev/null
printf 'c\n' >> "$W3/f.sh"; run d1291c "$W3" >/dev/null
if grep -q '"kind":"edit".*f\.sh' "$TMP/state/rework-d1291c.jsonl"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [D1291c]: память прежнего вида осталась в снимке — правка после перехода не засчитана"; fi

# --- ЦЕЛЬ ПРАВКИ УЗНАЁТСЯ И В ЧУЖОМ СТЕКЕ (25 сентября 2026, D483) --------------------------
# Перечень целей стоял `sh|py|md|json|yml|yaml|tsv` в ЧЕТЫРЁХ местах — стек ClaudSoul, и правка
# `.tsx`, `.prisma`, `.sql` соседнего проекта переработкой не считалась. Перечень ОСТАВЛЕН
# намеренно: замер по 19 867 вызовам Bash показал, что структурный признак добавляет 1397
# целей, почти всё — временные выводы и не-файлы (`console.log`, `Math.abs`). Роль перечня
# двойная: отсечь мусор И назвать код. Расширен владельцем `token_code_ext_re`.
# Судится ступень ИЗВЛЕЧЕНИЯ, а не весь детектор: ниже стоит фильтр существования файла, и на
# выдуманных путях он гасит всё — на этом сбилась первая моя проба.
_RWT_PL="$HOOKS_DIR/portable-lib.sh"
if [ ! -f "$_RWT_PL" ]; then
    echo "SKIP: нет portable-lib.sh — перечень расширений спросить не у кого"
else
    # shellcheck source=/dev/null
    . "$_RWT_PL" 2>/dev/null
    _rwt_ext="($(token_code_ext_re)|md|json|yml|yaml|tsv|tmpl|toml)"
    # Ступень извлечения — та же пара, что в детекторе (D1330): пути называет владелец разбора, расширение отсекает
    # перечень. Прежде здесь стояла КОПИЯ образца детектора, и нога судила её, а не прибор.
    # shellcheck source=/dev/null
    . "$HOOKS_DIR/command-scope-lib.sh" 2>/dev/null
    _rwt() { executable_content_targets "$1" | grep -E "\\.$_rwt_ext\$" 2>/dev/null; }
    _rwt_miss=""
    for _c in "cat > web/components/Card.tsx|web/components/Card.tsx" \
              "cat > prisma/schema.prisma|prisma/schema.prisma" \
              "cat > db/migrate.sql|db/migrate.sql" \
              "echo x > docs/reference.md|docs/reference.md"; do
        _cmd="${_c%%|*}"; _want="${_c##*|}"
        [ "$(_rwt "$_cmd")" = "$_want" ] || _rwt_miss="$_rwt_miss [$_cmd -> $(_rwt "$_cmd")]"
    done
    if [ -z "$_rwt_miss" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [цели чужого стека]:$_rwt_miss"; fi
    # ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: временный вывод целью не считается, иначе детектор захлебнётся.
    if [ -z "$(_rwt 'echo y > /tmp/t.out')" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [временный вывод засчитан целью]"; fi
    # Имя берётся ЦЕЛИКОМ: узкий перечень обрезал `templates/ROOTS.md.tmpl` до `.md`.
    if [ "$(_rwt 'cat > templates/ROOTS.md.tmpl')" = "templates/ROOTS.md.tmpl" ]; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo "FAIL [имя обрезано]: $(_rwt 'cat > templates/ROOTS.md.tmpl')"; fi
fi

# === D1330: «прогон ли это» и «что команда записала» — у владельца разбора команд, а не у образцов по тексту ===
# Образцы читали прогоном и записью текст в кавычках, один файл знали под тремя именами, а «прогоном» была всякая
# команда без цели записи. У каждой ноги молчания рядом контроль, где детектор обязан сказать.
W13="$TMP/w1330"; mkdir -p "$W13"
( cd "$W13" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=t -c user.email=t@t commit -qm 0 ) \
    || { echo "подготовка мира не удалась (репозиторий ног D1330)" >&2; exit 1; }
shw() { # sid, команда — вызов оболочки в репозитории ног D1330
    jq -cn --arg s "$1" --arg c "$2" --arg d "$W13" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
editw() { # sid, путь — правка файловым инструментом в том же репозитории
    jq -cn --arg s "$1" --arg p "$2" --arg d "$W13" '{session_id:$s, tool_name:"Edit", cwd:$d, tool_input:{file_path:$p}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
# (а) Читающая по роду команда между правками — не прогон. Контроль — T1b: с прогоном между правками заход назван.
_n=0
for _c in 'ls hooks' 'git diff f.sh' 'grep -n a f.sh | head -3; git status --short' 'chmod +x f.sh && touch f.sh'; do
    _n=$((_n + 1))
    editw "d1330a$_n" "$W13/f.sh" >/dev/null; shw "d1330a$_n" "$_c" >/dev/null
    OUT=$(editw "d1330a$_n" "$W13/f.sh"); assert_empty "$OUT" "D1330a: «${_c}» между правками — не прогон"
done
editw d1330a0 "$W13/f.sh" >/dev/null; shw d1330a0 'ls hooks; make test' >/dev/null
OUT=$(editw d1330a0 "$W13/f.sh"); assert_contains "$OUT" "Второй заход" "D1330a-ctrl: незнакомая программа рядом с читающей — прогон, как прежде"
# (б) Текст формы записи в кавычках и смена режима файла — не запись; та же форма в позиции команды — запись.
editw d1330b "$W13/f.sh" >/dev/null; shw d1330b 'bash test.sh' >/dev/null
OUT=$(shw d1330b 'grep -n "sed -i" f.sh'); assert_empty "$OUT" "D1330b: поиск строки «sed -i» в файле — не правка файла"
OUT=$(shw d1330b "grep -rn 'printf x > f.sh' ."); assert_empty "$OUT" "D1330b: перенаправление внутри кавычек — не запись"
OUT=$(shw d1330b 'chmod +x f.sh && touch f.sh'); assert_empty "$OUT" "D1330b: смена режима и времени файла — не правка содержимого"
_e=$(grep -c '"kind":"edit"' "$TMP/state/rework-d1330b.jsonl" 2>/dev/null)
if [ "${_e:-0}" = 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [D1330b: журнал]: правок f.sh в журнале ${_e:-0} при одной настоящей"; fi
OUT=$(shw d1330b "sed -i.bak 's/a/b/' f.sh"); assert_contains "$OUT" "Второй заход" "D1330b-ctrl: sed -i в позиции команды — правка"
# (в) Запись из python в репозитории называет мир — по содержимому, а не по литералу пути в тексте команды.
PYREAD=$(printf "python3 - <<'PY'\ns = open('f.sh').read()\nopen('out.md', 'w').write(s)\nPY")
editw d1330c "$W13/f.sh" >/dev/null; shw d1330c 'bash test.sh' >/dev/null
OUT=$(shw d1330c "$PYREAD"); assert_empty "$OUT" "D1330c: питон читает f.sh и пишет другой файл — f.sh не правлен"
printf 'b\n' >> "$W13/f.sh"
OUT=$(shw d1330c "$PYREAD"); assert_contains "$OUT" "Второй заход" "D1330c-ctrl: содержимое f.sh изменилось — правку называет мир"
# (г) Один файл — одно имя: `~/`, `\$HOME/` и `./` приводятся к виду, в котором путь кладёт файловый инструмент.
HM="$TMP/home"; mkdir -p "$HM/.claude/hooks"; printf 'a\n' > "$HM/.claude/hooks/x.sh"
hcall() { # sid, инструмент, путь|команда — HOME и каталог сессии — песочница
    if [ "$2" = Bash ]; then jq -cn --arg s "$1" --arg c "$3" --arg d "$HM" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:$c}}'
    else jq -cn --arg s "$1" --arg p "$3" --arg d "$HM" '{session_id:$s, tool_name:"Edit", cwd:$d, tool_input:{file_path:$p}}'; fi \
        | env HOME="$HM" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
_n=0
for _c in "printf c >> ~/.claude/hooks/x.sh" 'sed -i.bak "s/a/d/" "$HOME/.claude/hooks/x.sh"' "sed -i.bak 's/a/b/' ./.claude/hooks/x.sh" \
          "sed -i.bak 's/a/b/' .claude/hooks/x.sh"; do
    _n=$((_n + 1))
    hcall "d1330d$_n" Edit "$HM/.claude/hooks/x.sh" >/dev/null; hcall "d1330d$_n" Bash 'bash test.sh' >/dev/null
    OUT=$(hcall "d1330d$_n" Bash "$_c"); assert_contains "$OUT" "Второй заход на x.sh" "D1330d: «${_c}» — тот же файл, что правил инструмент"
done
# (е) Приёмник копии — не авторская правка (скептик D1330, L3): `cp`/`mv` целью записи по тексту не становятся, копию
# в репозитории называет мир. Контроль — D1330b-ctrl: правка на месте той же позиции названа.
editw d1330f "$W13/f.sh" >/dev/null; shw d1330f 'bash test.sh' >/dev/null
OUT=$(shw d1330f 'cp seed.sh f.sh; mv seed2.sh f.sh'); assert_empty "$OUT" "D1330е: приёмник cp и mv по тексту правкой не назван"
# (ж) Разбора нет — цели берутся прежними образцами по тексту (скептик D1330, M1): вне git пустой перечень терял запись
# оболочкой молча. Разборщик-заглушка без ответа `--content`; каталог сессии — песочница без git.
printf 'print("устаревший разбор")\n' > "$TMP/stale_wt.py"
scall() { # sid, инструмент, путь|команда — как hcall, но с устаревшим разборщиком
    if [ "$2" = Bash ]; then jq -cn --arg s "$1" --arg c "$3" --arg d "$HM" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:$c}}'
    else jq -cn --arg s "$1" --arg p "$3" --arg d "$HM" '{session_id:$s, tool_name:"Edit", cwd:$d, tool_input:{file_path:$p}}'; fi \
        | env HOME="$HM" STATE_DIR="$TMP/state" WRITE_TARGETS_PY="$TMP/stale_wt.py" bash "$HOOK" 2>/dev/null
}
scall d1330g Edit "$HM/.claude/hooks/x.sh" >/dev/null; scall d1330g Bash 'bash test.sh' >/dev/null
OUT=$(scall d1330g Bash "printf c >> $HM/.claude/hooks/x.sh"); assert_contains "$OUT" "Второй заход на x.sh" "D1330ж: без разбора запись оболочкой названа прежним образцом"
# (з) Разбор зовётся ОДИН раз на вызов хука (скептик D1330, M2): обёртка считает запуски и отдаёт ответ настоящего.
cat > "$TMP/count_wt.py" <<PYW
# режимы обёртки: --content --heads
import os, runpy, sys
open(os.environ["WT_COUNT"], "a").write("x\\n")
sys.argv[0] = "$HOOKS_DIR/lib/write_targets.py"
runpy.run_path(sys.argv[0], run_name="__main__")
PYW
editw d1330h "$W13/f.sh" >/dev/null
: > "$TMP/wt.count"
jq -cn --arg d "$W13" '{session_id:"d1330h", tool_name:"Bash", cwd:$d, tool_input:{command:"ls hooks; bash hooks/tests/test_x.sh"}}' \
    | env STATE_DIR="$TMP/state" WRITE_TARGETS_PY="$TMP/count_wt.py" WT_COUNT="$TMP/wt.count" bash "$HOOK" >/dev/null 2>&1
_wc=$(grep -c x "$TMP/wt.count" 2>/dev/null)
if [ "${_wc:-0}" = 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [D1330з]: разбор запущен ${_wc:-0} раз(а) на один вызов хука, ждали 1"; fi
grep -q '"kind":"run"' "$TMP/state/rework-d1330h.jsonl" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [D1330з-ctrl]: через обёртку прогон не записан — обёртка не отдаёт ответ разбора"; }
# (д) Договор ответа владельца, на котором стоят ноги выше: простые команды по строке, слова через табуляцию; у git —
# подкоманда вторым словом без глобальных ключей; обёртки сняты; тело `bash -c` раскрыто; строка в кавычках — одно слово.
_hd() { executable_heads "$1" | tr '\t' '~' | paste -sd'|' -; }
_hd_miss=""
for _c in 'git -C "/a b" --no-pager log -3@git~log~-3' \
          "FOO=1 timeout 60 bash tests/x.sh | tail -3@bash~tests/x.sh|tail~-3" \
          "grep -rn 'bash tests/x.sh' docs@grep~-rn~bash tests/x.sh~docs" \
          'bash -c "ls; make"@ls|make|bash~-c~ls; make' \
          'if [ -f a ]; then make test; fi@[~-f~a~]|make~test'; do
    _cmd="${_c%@*}"; _want="${_c##*@}"
    [ "$(_hd "$_cmd")" = "$_want" ] || _hd_miss="$_hd_miss [$_cmd -> $(_hd "$_cmd")]"
done
if [ -z "$_hd_miss" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [D1330д: ответ «какие программы зовёт команда»]:$_hd_miss"; fi

echo ""
echo "=================================="
echo "rework-detector: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
