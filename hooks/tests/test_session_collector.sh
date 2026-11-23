#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh
# test_session_collector.sh — характеризующий тест Stop-финализатора.
# Хук центральный (финализация сессии, напоминания /learn, pending-alerts, silence debt),
# но был без своего теста (F8). Полный прогон зависит от реестра/activity-flush, поэтому
# тест проверяет безопасный инвариант: на пустых transcript/cwd хук завершает Stop без
# падения (rc=0) и при наличии/отсутствии session_id. Изоляция STATE_DIR.

set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
# РАМКУ ЗАДАЁТ ТЕСТ (D334, D1179): дверь вложенности вызывающего снимается — ключ кольца BACKLOG_CMD_RUNNING остаётся (D503).
unset BACKLOG_CHECKS_NESTED

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-collector.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_rc0() { if [ "$1" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

run() {  # $1=session_id — пустые transcript/cwd → activity_flush пропускается
    # Бэклог песочницы (D1179, M1): без него сборщик берёт BACKLOG.md корня по указателю — живой — и уносит его ☑ в архив.
    printf '{"session_id":"%s","transcript_path":"","cwd":""}' "$1" \
        | STATE_DIR="$TMP/state" CLAUDSOUL_BACKLOG="$TMP/none.md" bash "$HOOK" >/dev/null 2>&1
}

# Stop с session_id (fresh, без накопленных алертов) → завершает без падения
run "stop-sid-fresh"; assert_rc0 "$?" "T1 Stop with SID → rc=0"

# Stop без session_id → завершает без падения
run ""; assert_rc0 "$?" "T2 Stop without SID → rc=0"

# повторный Stop той же сессии → без падения (idempotent finalize)
run "stop-sid-fresh"; assert_rc0 "$?" "T3 repeat Stop → rc=0"

# === T4-T6: долг проекта всплывает из BACKLOG.md (v1.14.0) ===
#
# Зачем. За одну сессию накопилось 30 незакрытых пунктов, и при сборке списка выяснилось:
# большинство были названы вслух в тот же момент, когда пропущены. `BACKLOG.md` существовал,
# но его не читал ни один хук — только скилл упоминал текстом. Отложенное испарялось не
# потому, что его не записывали, а потому что записанное некому было поднять.
#
# Обе стороны обязательны: есть открытые → видно; нет открытых или нет файла → тишина.
#
# Путь к BACKLOG.md — абсолютный, а не от каталога сессии (v1.15.1). До этого хук читал
# `${PAYLOAD_CWD}/BACKLOG.md`, и весь контур долга существовал только пока работа шла
# внутри самого ClaudSoul; из любого другого проекта долг молчал. Развёртка D38 назвала
# это тем же классом, что и всё остальное в ней: обязанность есть, а наступить не может.
# Поэтому фикстура подаётся через `CLAUDSOUL_BACKLOG`, а не через `cwd`, — прежний ввод
# и был дефектом.
assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 160)"; fi
}
assert_no() {
    if grep -qF -- "$2" <<< "$1"; then FAIL=$((FAIL + 1)); echo "FAIL [$3]: неожиданно найдено '$2'"
    else PASS=$((PASS + 1)); fi
}
# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний. Очередь и дроссель свода чистятся перед вызовом.
_sc_reset() {
    alerts_clear "$TMP/state" || true
    rm -f "$TMP/state"/session-persist-fired-*.jsonl 2>/dev/null || true
}
_sc_queue() { alerts_of "$TMP/state"; }
_backlog_run() { # содержимое BACKLOG.md (пусто = файла нет)
    local proj="$TMP/proj-$RANDOM"
    mkdir -p "$proj"
    [ -n "$1" ] && printf '%s\n' "$1" > "$proj/BACKLOG.md"
    # cwd подаётся ЧУЖОЙ (пустой каталог) — так проверяется, что долг виден из любого
    # проекта, а не только из ClaudSoul. Замер идёт по несуществующему пути, чтобы
    # строка о просроченных не смешивалась со строкой о долге.
    _sc_reset
    jq -cn --arg s "bl$RANDOM" '{session_id:$s, cwd:"/nonexistent-project"}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_BACKLOG="$proj/BACKLOG.md" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
          bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_session_collector.sh:$LINENO" >&2; exit 1; }
    _sc_queue
}
OUT=$(_backlog_run '- ☐ **D1** раз
- ☐ **D2** два
- ☑ **D0** сделано')
assert_contains "$OUT" "2 открытых пункт" "T4: два открытых пункта → показаны, закрытый не считается"
assert_contains "$OUT" "BACKLOG.md" "T4b: назван источник"

OUT=$(_backlog_run '- ☑ **D1** сделано')
assert_no "$OUT" "открытых пункт" "T5: всё закрыто → про долг молчит"

# --- Просроченные замеры: алерт обязан НАЗЫВАТЬ их, а не только считать ---
# Живой случай (2026-08-25): «8 просроченных замеров» висело шесть ходов подряд, пока шла
# правка BACKLOG.md, а просрочен был среди прочего backlog-archive — тот самый, что этот
# файл и убирает. Число не совпадает ни с чем, чем занят читатель; имя совпадает.
_measure_run() { # $1 = сколько просроченных подделать
    local n="$1" fake="$TMP/fake-measure-$1.sh" proj="$TMP/mproj-$RANDOM" i=1
    mkdir -p "$proj"
    # Файл собирается дописыванием, а не группой `{ } > файл`: внутри группы с
    # перенаправлением объявление `local` теряет видимость переменной цикла, и под
    # `set -u` подделка обрывается на первой строке — тест при этом краснеет так,
    # будто дефект в хуке.
    printf '#!/usr/bin/env bash\n' > "$fake"
    while [ "$i" -le "$n" ]; do
        printf 'echo "  просрочен: measure-%s   (период 7 дн.)"\n' "$i" >> "$fake"
        i=$((i + 1))
    done
    chmod +x "$fake"
    _sc_reset
    jq -cn --arg s "ms$RANDOM" '{session_id:$s, cwd:"/nonexistent-project"}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_BACKLOG="$proj/none.md" \
          CLAUDSOUL_MEASURE_DUE="$fake" \
          bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_session_collector.sh:$LINENO" >&2; exit 1; }
    _sc_queue
}

OUT=$(_measure_run 2)
assert_contains "$OUT" "measure-1" "T5c: имя первого просроченного названо"
assert_contains "$OUT" "measure-2" "T5d: имя второго просроченного названо"

# --- Уборка закрытых: отметка пункта влечёт перенос, а не ждёт недельного срока ---
# Правило собеседника (2026-08-25): отметил → по завершении уехало. Прежде это был
# отдельный замер с периодом 7 дней, и он дважды просрочивался ровно тогда, когда
# BACKLOG.md активно правили.
_archive_run() { # $1 = содержимое BACKLOG.md
    local proj="$TMP/aproj-$RANDOM"
    mkdir -p "$proj"
    printf '%s\n' "$1" > "$proj/BACKLOG.md"
    printf '# Архив\n' > "$proj/BACKLOG-archive.md"
    _sc_reset
    jq -cn --arg s "ar$RANDOM" '{session_id:$s, cwd:"/nonexistent-project"}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_BACKLOG="$proj/BACKLOG.md" \
          CLAUDSOUL_BACKLOG_ARCHIVE="$proj/BACKLOG-archive.md" \
          CLAUDSOUL_BACKLOG_ARCHIVER="$(cd "$(dirname "$0")/../.." && pwd)/scripts/backlog-archive.sh" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
          bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_session_collector.sh:$LINENO" >&2; exit 1; }
    _sc_queue
    ARCH_PROJ="$proj"
}

OUT=$(_archive_run '- ☐ **D1** открытый
- ☑ **D2** закрытый
- ☑ **D3** тоже закрытый')
assert_contains "$OUT" "унесено в BACKLOG-archive.md: 2" "T5h: закрытые унесены и число названо"
assert_contains "$OUT" "добавь в коммит" "T5i: сказано, что файлы изменены"

# ОТКАЗ АРХИВАТОРА ГОВОРИТ, а не гасится вместе с «переносить нечего» (19 сентября 2026).
# Повод — слова владельца «в бэклоге висят закрытые пункты»: D445 и D448 провисели полдня,
# архиватор отказывал по красной «Проверке», а свод считал этот исход известным и молчал.
# Два разных состояния мира («уносить нечего» и «есть что унести, но отказано») шли одним
# каналом — молчанием. Контроль ниже держит ОБА конца: отказ обязан быть назван с причиной,
# а законная пустота обязана остаться немой, иначе отказ утонет в шуме.
OUT=$(_archive_run '- ☑ **D902** закрытый, а «Проверка» красная.
  **Результат.** мир стал таким.
  **Проверка.** `false` → 0')
assert_contains "$OUT" "Архиватор ОТКАЗАЛСЯ уносить закрытые пункты" "T5j: отказ архиватора назван"
assert_contains "$OUT" "D902" "T5k: назван ПУНКТ, на котором отказано"

OUT=$(_archive_run '- ☐ **D1** открытый и только')
if grep -q "Архиватор ОТКАЗАЛСЯ" <<< "$OUT"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T5l: без закрытых пунктов отказ не выдумывается]"
else PASS=$((PASS + 1)); fi

# Перенос настоящий, а не только на словах: свидетельство закрытия обязано уцелеть.
_archive_run '- ☐ **D1** открытый
- ☑ **D2** закрытый' >/dev/null
assert_contains "$(cat "$ARCH_PROJ/BACKLOG-archive.md" 2>/dev/null)" "D2" \
    "T5j: закрытый пункт лёг в архив, а не пропал"
assert_contains "$(cat "$ARCH_PROJ/BACKLOG.md" 2>/dev/null)" "D1" \
    "T5k: открытый остался в рабочем файле"
assert_no "$(cat "$ARCH_PROJ/BACKLOG.md" 2>/dev/null)" "D2" \
    "T5m: закрытый из рабочего файла ушёл"

# Нечего убирать — про уборку молчит, лишней строки в отчёте нет.
OUT=$(_archive_run '- ☐ **D1** открытый')
assert_no "$OUT" "унесено в BACKLOG-archive" "T5l: без закрытых пунктов про уборку молчит"

OUT=$(_measure_run 6)
assert_contains "$OUT" "measure-4" "T5e: до четырёх имён показываются"
assert_contains "$OUT" "и ещё 2" "T5f: остаток назван числом, а не потерян"
assert_no "$OUT" "measure-5" "T5g: пятое имя не печатается — строка не растёт без границы"

OUT=$(_backlog_run "")
assert_no "$OUT" "открытых пункт" "T6: BACKLOG.md нет (чужой проект) → молчит"

# T7: пункт «в работе» (◐) считается открытым. По легенде BACKLOG.md обе метки означают
# «не сделано», но хук считал только ☐ — и перевод пункта в работу ГАСИЛ алерт. Долг
# умолкал ровно тогда, когда за него взялись и остановились: худший момент для тишины.
OUT=$(_backlog_run '- ☐ **D1** раз
- ◐ **D2** взят в работу
- ☑ **D0** сделано')
assert_contains "$OUT" "2 открытых пункт" "T7: ◐ считается наравне с ☐"

# T8: отрицательный контроль на сам счёт — пункт в работе БЕЗ открытых всё равно виден.
# Без этого случая T7 проходил бы и при подсчёте одного лишь ☐.
OUT=$(_backlog_run '- ◐ **D2** только в работе
- ☑ **D0** сделано')
assert_contains "$OUT" "1 открытых пункт" "T8: один только ◐ — долг не молчит"

# === T9-T12: долг инициированного проекта (локальный BACKLOG.md по cwd, 2026-08-07)
# и архивная секция (правка параллельной сессии — здесь получает тест).
_backlog_run2() { # $1 ClaudSoul-BACKLOG, $2 локальный BACKLOG, $3 cwd_mode(local|claudsoul)
    local cs="$TMP/cs-$RANDOM" loc="$TMP/loc-$RANDOM" cwd
    mkdir -p "$cs" "$loc"
    [ -n "$1" ] && printf '%s\n' "$1" > "$cs/BACKLOG.md"
    [ -n "$2" ] && printf '%s\n' "$2" > "$loc/BACKLOG.md"
    case "$3" in claudsoul) cwd="$cs" ;; *) cwd="$loc" ;; esac
    _sc_reset
    jq -cn --arg s "bl$RANDOM" --arg c "$cwd" '{session_id:$s, cwd:$c}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_ROOT="$cs" \
          CLAUDSOUL_BACKLOG="$cs/BACKLOG.md" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
          bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_session_collector.sh:$LINENO" >&2; exit 1; }
    _sc_queue
}

# T9: оба долга видны одновременно — кросс-проектный И локальный.
OUT=$(_backlog_run2 '- ☐ **D1** системный' '- ☐ **L1** локальный
- ☐ **L2** локальный два' local)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md — долг проекта" "T9a: ClaudSoul-долг виден из чужого проекта"
assert_contains "$OUT" "2 открытых пункт(ов) в BACKLOG.md этого проекта" "T9b: локальный долг проекта виден"

# T10: сессия в самом ClaudSoul → локальный не дублирует системный.
OUT=$(_backlog_run2 '- ☐ **D1** системный' '' claudsoul)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md — долг проекта" "T10a: системный долг есть"
assert_no "$OUT" "этого проекта" "T10b: двойного счёта в ClaudSoul нет"

# T11: у локального проекта нет BACKLOG.md → локальной строки нет (не инициирован).
OUT=$(_backlog_run2 '- ☐ **D1** системный' '' local)
assert_no "$OUT" "этого проекта" "T11: без BACKLOG.md локальный контур молчит"

# T12: архивная секция не считается — в обоих файлах (тест правки параллельной сессии).
OUT=$(_backlog_run2 '- ☐ **D1** открыт
## Архив
- ☐ **D9** лежит в архиве' '- ☐ **L1** открыт
## Archive
- ◐ **L9** в архиве' local)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md — долг проекта" "T12a: архив ClaudSoul не считается"
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md этого проекта" "T12b: архив локального не считается"

# T12c–T12e (D1334): строку пункта называет владелец формы — пункт-заголовок (`### B40 … ◐`) считается наравне со
# списочным. Своя копия признака у сборщика знала одну вёрстку, и у проекта с пунктами-заголовками строка о долге не
# звучала вовсе (blalb: владелец называл 9 открытых, сборщик 0). Закрытый заголовок и образец в заборе кода не считаются.
OUT=$(_backlog_run2 '- ☐ **D1** системный' '### B40 — пункт заголовком — ◐
### B41 — второй заголовком — ☐
- ☐ **L1** списком
### B42 — закрытый — ☑
```
### B43 — образец разметки в заборе — ☐
```' local)
assert_contains "$OUT" "3 открытых пункт(ов) в BACKLOG.md этого проекта" "T12c: пункты-заголовки считаются вместе со списочным, закрытый и образец в заборе — нет"
OUT=$(_backlog_run2 '- ☐ **D1** системный' '### B40 — единственный пункт заголовком — ☐' local)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md этого проекта" "T12d: бэклог из одних заголовков не молчит"
OUT=$(_backlog_run2 '- ☐ **D1** системный' '### B40 — открытый — ☐
## Архив
### B41 — в архиве — ☐' local)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md этого проекта" "T12e: граница архива держится и для заголовков"

# T13: подсказка про устаревший свод — если в ClaudSoul-бэклоге след project-health.
OUT=$(_backlog_run2 '- ☐ **D1** раз (см. docs/project-health-2026-06-21.md)' '' local)
assert_contains "$OUT" "Свод мог устареть" "T13: подсказка ре-аудита при маркере project-health"

# T14: работа и ожидание порознь, следующий к взятию — по строке «Очередь.» (12 сентября
# 2026). D1 — ожидание (команда возврата), D2 — работа с очередью 3 и корнем, D3 — без
# очереди: следующим назван D2, число ждущих — 1, в работе — 2.
OUT=$(_backlog_run '- ☐ **D1** ждёт события
  **Проверка возврата:** `true`
- ☐ **D2** работа
  **Очередь.** 3
  **Корень.** R3 — роль решается перечнем форм
  **Проверка возврата:** решение
- ☐ **D3** без очереди
  **Проверка возврата:** решение')
assert_contains "$OUT" "3 открытых пункт(ов) в BACKLOG.md — долг проекта: 2 в работе, 1 ждут условия" "T14: работа и ожидание сосчитаны порознь"
assert_contains "$OUT" "следующий к взятию: D2 (очередь 3, корень R3)" "T14b: следующий назван по наименьшей очереди, ожидание не кандидат"

# T15: взятый пункт (◐) печатается как «в работе», «следующий» при нём не называется.
OUT=$(_backlog_run '- ◐ **D1** взят
  **Проверка возврата:** решение
- ☐ **D2** ждёт своей очереди
  **Очередь.** 1
  **Проверка возврата:** решение')
assert_contains "$OUT" "в работе: D1" "T15: взятый назван в работе"
case "$OUT" in
    *"следующий к взятию"*) FAIL=$((FAIL + 1)); echo "FAIL [T15b]: при живом ◐ назван «следующий»: $OUT" ;;
    *) PASS=$((PASS + 1)) ;;
esac

# === T-RACE: уборка состояния хода не трогает файлы новее старта прогона (D1000) ===
# Сборщик зарегистрирован фоном, и следующий ход пишет эти файлы, пока прогон ещё идёт.
# «Следующий ход» моделируется временем изменения в будущем; старый файл обязан уйти, как прежде.
# Корень проекта и реестр сессий — пустые каталоги: живой бэклог и реестр не трогаются.
RACE="$TMP/race"; mkdir -p "$RACE/state" "$RACE/sessions"
OLDF="$RACE/state/knowledge_injected_sc-race"; NEWF="$RACE/state/last_keywords_sc-race"
: > "$OLDF"; : > "$NEWF"
touch -t 202001010000 "$OLDF"
_fut=$(date -v+1H +%Y%m%d%H%M 2>/dev/null || date -d '+1 hour' +%Y%m%d%H%M)
touch -t "$_fut" "$NEWF"
printf '{"session_id":"sc-race","transcript_path":"","cwd":""}' \
    | CLAUDE_CODE_SESSION_ID=sc-race STATE_DIR="$RACE/state" CLAUDSOUL_ROOT="$RACE" \
      SR_SESSIONS_DIR="$RACE/sessions" bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_session_collector.sh:$LINENO" >&2; exit 1; }
if [ ! -e "$OLDF" ] && [ -e "$NEWF" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T-RACE]: старый $( [ -e "$OLDF" ] && echo остался || echo снят ), новый $( [ -e "$NEWF" ] && echo остался || echo СТЁРТ )"; fi

# T-ITR (D1335): файлы состояния сессий сборщик не убирает — срок держит один хозяин, общая уборка каталога
# (`scripts/state-prune.sh`). Прежде здесь стоял вызов «тридцать дней опыта»: вторая копия срока в другой единице.
# Блок интрузивности идёт только при файле состояния СВОЕЙ сессии — его заводит трекер первой репликой.
printf '{"session_id":"itr-own","prompt":"реплика"}' | STATE_DIR="$TMP/state" bash "$HOOKS_DIR/intrusiveness-tracker.sh" >/dev/null 2>&1
ITR_OLD="$TMP/state/intrusiveness-itr-foreign.json"
printf '{"session_id":"itr-foreign","created_at":"2024-01-01T00:00:00Z","budget":{"gentle_used":2}}\n' > "$ITR_OLD"
# Положительный контроль рамки: файл своей сессии заведён — иначе блок не исполнялся бы, и нога зеленела бы вслепую.
if [ -f "$TMP/state/intrusiveness-itr-own.json" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T-ITR-ctrl]: трекер не завёл состояние своей сессии — рамка не собралась"; fi
run "itr-own"
if [ -f "$ITR_OLD" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T-ITR]: сборщик снял состояние чужой сессии — срок жизни держит не он"; fi

echo ""
echo "session-collector tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
