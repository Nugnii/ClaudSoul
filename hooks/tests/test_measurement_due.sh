#!/usr/bin/env bash
# СУДИТ: scripts/measurement-due.sh hooks/session-collector.sh
# test_measurement_due.sh — у замера есть срок, и просроченный виден.
#
# Повод, сформулированный собеседником: «ну и толку что ты мерил, а пока я не сказал — не
# мерил? А если бы вообще не вспомнил? Всё что меряют должно дедлайн иметь».
#
# Случай конкретный: замер «становится ли знание инструментом» дал 1,4% — но случился
# только потому, что о нём спросили. Ни владельца, ни срока у измерения не было, и его
# отсутствие ничем не обнаруживалось. Замер, держащийся на чьей-то памяти, — намерение,
# а не механизм.
#
# Проверяются обе стороны: просроченное называется и выполняется, свежее не трогается,
# сломанная команда отличается от выполненной. Плюс отрицательный контроль на сам реестр.

set -uo pipefail
# Рамка теста не наследует корень вызывающего (D1074): «Проверку» пункта и зелёную сторону гоняют с экспортированной
# CLAUDSOUL_REPO, а ноги T9/T9b и зонд требуют её отсутствия (`rc_env_is_real` глушит запись повода). Кому корень
# нужен (`run`, `run10`), задают его явно.
unset CLAUDSOUL_REPO

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/measurement-due.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/repo/scripts"
# Нонс уходит замерам через окружение, в реестре лежит только имя переменной: строка
# «ran:<нонс>» может появиться в файле ТОЛЬКО как результат исполнения замера — ни текст
# команды, ни реестр, ни дамп окружения её не содержат (D281: подделки, зеленившие
# проверку литералом из фикстуры).
PROBE="d281-$RANDOM$RANDOM"
mkdir -p "$TMP/probe"
printf 'ran:%s\n' "$PROBE" > "$TMP/probe/out"
printf 'err:%s\n' "$PROBE" > "$TMP/probe/err"
cp "$SCRIPT" "$TMP/repo/scripts/"

# Реестр-фикстура: свежий, просроченный, сломанный, событийный.
printf '# id\tдней\tкоманда\tчто\n' > "$TMP/repo/scripts/measurements.tsv"
{
  printf 'fresh\t7\ttrue\tсвежий замер\n'
  printf 'stale\t7\ttrue\tпросроченный замер\n'
  printf 'found\t7\tsh -c "cat $D281_OUT; exit 1"\tзамер отработал и НАШЁЛ проблему\n'
  printf 'broken\t7\tsh -c "cat $D281_ERR >&2; exit 2"\tзамер НЕ СМОГ отработать\n'
  printf 'evented\t0\ttrue\tпо событию, не по календарю\n'
} >> "$TMP/repo/scripts/measurements.tsv"

mkdir -p "$TMP/state/measurement-runs"
date +%s > "$TMP/state/measurement-runs/fresh"                       # прогонялся только что
printf '%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$TMP/state/measurement-runs/stale"
printf '%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$TMP/state/measurement-runs/broken"
printf '%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$TMP/state/measurement-runs/found"

# СРОК МЕРИТСЯ РАБОТОЙ, А НЕ КАЛЕНДАРЁМ (D1074; слово владельца: «могу полгода к компу не подходить, а могу за день
# 500000 строк кода выдать»). Прибор считает возраст отметки в днях опыта — сессиях реестра после отметки, делённых на
# темп (`hooks/fsrs-lib.sh`). Рамка теста объявляет СВОЙ реестр и библиотеку из репозитория: без этого прибор брал
# установленную библиотеку и живой реестр машины, и вердикт ног зависел от числа сессий владельца. 300 сессий вчерашним
# днём — 10 дней опыта: 40-дневная отметка просрочена, сегодняшняя — нет.
mkreg() {  # mkreg <файл> <число сессий> <дней назад>
    python3 -c 'import datetime, json, sys
d = (datetime.date.today() - datetime.timedelta(days=int(sys.argv[3]))).isoformat()
with open(sys.argv[1], "a") as f:
    for i in range(int(sys.argv[2])):
        f.write(json.dumps({"session_id": "s%s-%d" % (sys.argv[3], i), "started_at": d + "T10:00:00Z"}) + "\n")' "$@"
}
mkreg "$TMP/registry.jsonl" 300 1
run() { D281_OUT="$TMP/probe/out" D281_ERR="$TMP/probe/err" CLAUDSOUL_REPO="$TMP/repo" STATE_DIR="$TMP/state" \
        FSRS_LIB="$REPO/hooks/fsrs-lib.sh" FSRS_SESSION_REGISTRY="${REG:-$TMP/registry.jsonl}" \
        bash "$TMP/repo/scripts/measurement-due.sh" "${1:-run}" 2>&1; }
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- T1: режим check называет просроченные и не трогает свежие ---
OUT=$(run check)
grep -q 'просрочен: stale' <<< "$OUT"  && ok || bad "T1a" "просроченный не назван"
grep -q 'просрочен: broken' <<< "$OUT" && ok || bad "T1b" "сломанный не назван"
grep -q 'просрочен: fresh' <<< "$OUT"  && bad "T1c" "свежий назван просроченным" || ok
grep -q 'просрочен: evented' <<< "$OUT" && bad "T1d" "событийный попал в просрочку" || ok
grep -q 'по событию: 1' <<< "$OUT"     && ok || bad "T1e" "событийные не посчитаны"

# --- T2: check ничего не запускает — отметка о прогоне не двигается ---
_before=$(cat "$TMP/state/measurement-runs/stale")
run check >/dev/null
[ "$(cat "$TMP/state/measurement-runs/stale")" = "$_before" ] && ok || bad "T2" "режим check изменил отметку о прогоне"

# --- T3: run выполняет просроченные и двигает отметку ---
# Код возврата различает ТРИ вещи: 0 — отработал без находок, 1 — отработал и НАШЁЛ
# проблему, ≥2 — не смог отработать. Прежняя версия считала ошибкой любой ненулевой код,
# поэтому замер, чья задача — краснеть на находке, отметки не получал НИКОГДА и висел
# вечно просроченным. Обнаружено на живом `escalation-age`: заявке 99 дней, он честно
# вернул 1, и это прочиталось как «команда сломалась».
# У каждой отметки — СВОЁ значение до прогона (D1257): раскладка пишет их отдельными вызовами `date +%s`, и под нагрузкой
# секунда меняется между ними — сравнение с отметкой ДРУГОГО замера краснило T4a и зеленило T4b без всякого сдвига.
_broken_before=$(cat "$TMP/state/measurement-runs/broken")
_found_before=$(cat "$TMP/state/measurement-runs/found")
OUT=$(run run)
[ "$(cat "$TMP/state/measurement-runs/stale")" != "$_before" ] && ok || bad "T3a" "отметка не обновилась после выполнения"
grep -q 'НЕ ВЫПОЛНЕН' <<< "$OUT" && ok || bad "T3b" "отказ (код 2) не отличён от выполнения"
grep -q 'ЕСТЬ НАХОДКИ' <<< "$OUT" && ok || bad "T3c" "находка (код 1) не отличена от отсутствия находок"

# --- T4: не сумевший отработать замер не получает отметку — иначе он «протухнет» тихо ---
[ "$(cat "$TMP/state/measurement-runs/broken")" = "$_broken_before" ] && ok || bad "T4a" "у не выполнившегося замера обновилась отметка"

# --- T4b: замер С НАХОДКОЙ отметку получает: он выполнен, просто нашёл проблему ---
[ "$(cat "$TMP/state/measurement-runs/found")" != "$_found_before" ] && ok \
    || bad "T4b" "замер с находкой не отмечен — будет висеть вечно просроченным"

# --- T8: находка замера ДОХОДИТ до читателя — вывод сохранён рядом с отметкой, путь назван ---
# До D281 :104 уводил stdout/stderr замера в /dev/null, а :112 писал «смотри вывод замера»:
# недельный state-prune вернул 1 с текстом «за окном 51 файл», и текст не увидел никто.
_p=$(grep 'ЕСТЬ НАХОДКИ' <<< "$OUT" | grep -oE '/[^[:space:]]+' | head -1)
case "$_p" in
    "$TMP/state/measurement-runs/"*)
        grep -qx "ran:$PROBE" "$_p" 2>/dev/null && ok || bad "T8a" "названный файл без вывода замера: $_p" ;;
    *) bad "T8a" "строка «ЕСТЬ НАХОДКИ» не называет файл под measurement-runs/ (получено: '${_p}')" ;;
esac
# T8b: повторный прогон ПЕРЕЗАПИСЫВАЕТ вывод, а не дописывает — иначе файл растёт с каждой неделей
printf '%s\n' "$_before" > "$TMP/state/measurement-runs/found"
run run >/dev/null
[ -n "$_p" ] && [ "$(grep -cx "ran:$PROBE" "$_p" 2>/dev/null)" = "1" ] && ok \
    || bad "T8b" "вывод дописывается, а не перезаписывается"
# T8c: у не сумевшего отработать сохранён stderr — причина отказа читается без повторного запуска
grep -qx "err:$PROBE" "$TMP/state/measurement-runs/broken.out" 2>/dev/null && ok \
    || bad "T8c" "stderr не выполнившегося замера не сохранён"

# --- T5: после выполнения просроченным остаётся только тот, что не смог отработать ---
OUT=$(run check)
_n=$(printf '%s' "$OUT" | grep -c '^  просрочен:' || true)
[ "${_n:-0}" -eq 1 ] && ok || bad "T5" "ожидался ровно один просроченный (отказавший), получено ${_n}"

# --- T6: отрицательный контроль — проверка обязана уметь найти просрочку ---
# Без него зелёный T5 не отличим от «скрипт ничего не смотрит».
printf '%s\n' "$(( $(date +%s) - 999 * 86400 ))" > "$TMP/state/measurement-runs/fresh"
grep -q 'просрочен: fresh' <<< "$(run check)" && ok \
    || bad "T6" "состаренный замер не распознан — проверка ничего не измеряет"

# --- T7: реальный реестр проекта разбирается и содержит замер о знаниях ---
REAL="$REPO/scripts/measurements.tsv"
if [ -f "$REAL" ]; then
    grep -q '^knowledge-instrument' "$REAL" && ok || bad "T7a" "в реестре нет замера knowledge-instrument"
    _bad=$(awk -F'\t' '!/^#/ && NF>0 && NF<4 {print NR}' "$REAL" | head -1)
    [ -z "$_bad" ] && ok || bad "T7b" "строка $_bad реестра не имеет четырёх колонок"
else
    bad "T7" "нет реального реестра $REAL"
fi

# --- T8: сообщение о просрочке не обещает того, чего механизм не делает ---
# Повод, 7 сентября 2026. session-collector зовёт бегуна режимом `check` (в нём команды НЕ
# исполняются), а его алерт обещал «Называет и ЗАПУСКАЕТ их». Замеры числились просроченными
# с 30 августа — обещание не исполнилось ни разу за восемь дней. Запускать их на границе хода
# и нельзя: это повод шторма из 2225 процессов (D321).
# Нога сверяет ДВА утверждения ОДНОГО файла между собой — режим вызова и текст обещания.
# Путь коллектора переопределяется РАДИ МУТАЦИИ: зелень ноги не доказывает ничего, пока она
# не покраснела на прежней редакции. Образец — test_drift_check.sh.
SC="${SESSION_COLLECTOR:-$(cd "$(dirname "$0")/.." && pwd)/session-collector.sh}"
if [ -f "$SC" ]; then
    _mode_check=$(grep -c 'MEASURE_DUE_SH" check' "$SC" 2>/dev/null) || _mode_check=0
    # Признак смотрит на СТРОКУ АЛЕРТА, а не на весь файл: первая редакция ноги грепала
    # текст где угодно и ловила собственный пояснительный комментарий, который этот текст
    # ЦИТИРУЕТ. Ровно то, о чём предупреждает carrier-growth-check: предмет, названный
    # буквально, попадает в поле зрения прибора.
    _promises_run=$(grep -c '^[[:space:]]*ALERTS=.*ЗАПУСКАЕТ их' "$SC" 2>/dev/null) || _promises_run=0
    if [ "${_mode_check:-0}" -gt 0 ] && [ "${_promises_run:-0}" -gt 0 ]; then
        FAIL=$((FAIL + 1))
        echo "FAIL [T8]: бегун зовётся режимом check (команды не исполняются), а алерт обещает «ЗАПУСКАЕТ их»"
    else
        PASS=$((PASS + 1))
    fi
    # T8b: и наоборот — если режим сменят на run, обещание станет правдой, но появится
    # исполнение произвольных команд на Stop. Тогда нога обязана напомнить про D321.
    _mode_run=$(grep -c 'MEASURE_DUE_SH" run' "$SC" 2>/dev/null) || _mode_run=0
    if [ "${_mode_run:-0}" -gt 0 ]; then
        FAIL=$((FAIL + 1))
        echo "FAIL [T8b]: на границе хода бегун зовётся режимом run — это исполнение произвольных команд, запрещённое D321"
    else
        PASS=$((PASS + 1))
    fi
else
    PASS=$((PASS + 2))
fi

# --- T8c: дверь вложенности бегуна (D321) ---
# T8/T8b держат ОДИН инвариант — «на Stop зовут режимом check». Он держится одним словом
# в одной строке чужого файла. T8c держит второй, независимый: даже позванный `run` изнутри
# собственной команды, бегун ничего не исполняет. Проверяется ПОВЕДЕНИЕМ, а не наличием
# имени переменной в тексте: 9 сентября 2026 показание пункта D321 сдвинулось с 2 на 1 от
# одного КОММЕНТАРИЯ, упомянувшего маркер, — форма зеленеет от прозы.
_t8c="$TMP/t8c"; mkdir -p "$_t8c/state"
printf 'zond\t1\techo ЗАПУЩЕН; exit 1\tзонд\n' > "$_t8c/m.tsv"
_run_zond() {   # <значение маркера>
    # Каталог состояния зовётся STATE_DIR (`measurement-due.sh:30`). Первая редакция ноги
    # подала CLAUDE_HOOKS_STATE — имя, которого скрипт не читает, — и прогон зонда ушёл
    # в БОЕВОЙ каталог: рамка проверки разошлась с миром ровно там, где её задавали.
    env MEASUREMENT_REGISTRY="$_t8c/m.tsv" STATE_DIR="$_t8c/state" \
        MEASURE_DUE_NESTED="$1" bash "$SCRIPT" run 2>&1
}
# Маркер несёт реестр (D1218): дверь закрыта для вложенного прогона ТОГО ЖЕ реестра, путь — после `pwd -P`.
_t8c_id="$(cd "$_t8c" && pwd -P)/m.tsv"
_o_nested=$(_run_zond "$_t8c_id")
case "$_o_nested" in
    *"Вложенный прогон"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL [T8c-a]: вложенный прогон не назван: $_o_nested" ;;
esac
case "$_o_nested" in
    *ЗАПУЩЕН*) FAIL=$((FAIL + 1)); echo "FAIL [T8c-b]: под маркером команда замера ВСЁ РАВНО исполнена" ;;
    *) PASS=$((PASS + 1)) ;;
esac
# отрицательный контроль: без маркера тот же зонд исполняется — значит ноги выше про дверь,
# а не про негодную заготовку реестра
_o_plain=$(_run_zond 0)
case "$_o_plain" in
    *"ЕСТЬ НАХОДКИ"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL [T8c-c]: без маркера зонд не исполнился: $_o_plain" ;;
esac
# Маркер ДРУГОГО реестра — не дверь: тест бегуна на своей фикстуре под командой замера `suite-world-locale` судит
# бегуна, а не его дверь (D1218; прежде маркер `1` закрывал любой реестр).
rm -rf "$_t8c/state"; mkdir -p "$_t8c/state"
_o_other=$(_run_zond "$REPO/scripts/measurements.tsv")
case "$_o_other" in
    *"ЕСТЬ НАХОДКИ"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL [T8c-e]: маркер чужого реестра закрыл дверь: $_o_other" ;;
esac
# и маркер доходит ДО команды: иначе дверь закрыта только на первом уровне
printf 'zond2\t1\techo "МАРКЕР=${MEASURE_DUE_NESTED:-НЕТ}"; exit 1\tзонд\n' > "$_t8c/m.tsv"
rm -rf "$_t8c/state"; mkdir -p "$_t8c/state"
_run_zond 0 >/dev/null 2>&1
_seen=$(cat "$_t8c/state/measurement-runs/zond2.out" 2>/dev/null || true)
case "$_seen" in
    *"МАРКЕР=$_t8c_id"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL [T8c-d]: маркер не дошёл до команды замера: $_seen" ;;
esac

# --- T9: находка замера становится ПОВОДОМ разбора, а не строкой в выводе ---
# Разбор 10 сентября 2026: все десять сродов повода ждут СОБЫТИЯ, и ни один не имеет
# предметом ОТСУТСТВИЕ. Отсутствие не происходит — значит сигнала не рождает, и приборы
# полноты (docs-inventory, docs-concepts-check, docs-staleness) говорили только тому, кто
# сам их запустил: их находка умирала в файле вывода. Здесь она превращается в событие мира.
# Повод: карта корней построена 9 сентября и к утру 10-го не упоминалась ни в одном
# документе состояния — нашёл это собеседник чтением, механизм молчал.
_t9="$TMP/t9"; mkdir -p "$_t9/scripts" "$_t9/state"
cp "$REPO/scripts/measurement-due.sh" "$_t9/scripts/"
cp -R "$REPO/hooks" "$_t9/hooks"
printf '#!/usr/bin/env bash\necho "проба: понятие пропало"\nexit 1\n' > "$_t9/scripts/fake.sh"
chmod +x "$_t9/scripts/fake.sh"
printf 'зонд-находка\t1\tbash scripts/fake.sh\tзонд\n' > "$_t9/scripts/m.tsv"
# CLAUDSOUL_REPO НЕ выставляется: `rc_env_is_real` намеренно глушит запись, когда он есть,
# — предохранитель «не писать боевое состояние из теста». Первая проверка этой ноги так и
# вышла негодной: повод не писался, и это выглядело как поломка починки.
( cd "$_t9" && MEASUREMENT_REGISTRY="$_t9/scripts/m.tsv" STATE_DIR="$_t9/state" \
    bash "$_t9/scripts/measurement-due.sh" run >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_measurement_due.sh:$LINENO" >&2; exit 1; }
_ev=$(jq -r 'select(.status=="open") | .kind' "$_t9/state/pending-events.jsonl" 2>/dev/null | head -1)
if [ "$_ev" = "measure-found" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T9]: находка замера не завела повод (kind=[$_ev], ожидался measure-found)"; fi

# --- T9c (D1350): повод несёт адрес РЕПОЗИТОРИЯ скрипта, а не каталога процесса ---
# launchd запускает задание из «/»: писатель повода брал проект у каталога процесса, и находка ложилась с адресом
# «/» — читатель отдаёт сессии только поводы её проекта, такие не доходили никому (108 из 148 на 21 ноября 2026).
# Та же песочница, что у T9, своё состояние; T9 выше шёл ИЗ песочницы и адрес получал верный по совпадению каталогов.
mkdir -p "$_t9/state_c"
( cd / && env -u CLAUDSOUL_REPO -u RC_EVENT_PROJECT MEASUREMENT_REGISTRY="$_t9/scripts/m.tsv" STATE_DIR="$_t9/state_c" \
    bash "$_t9/scripts/measurement-due.sh" run >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_measurement_due.sh:$LINENO" >&2; exit 1; }
_evp=$(jq -r 'select(.kind=="measure-found") | .project' "$_t9/state_c/pending-events.jsonl" 2>/dev/null | head -1)
[ -n "$_evp" ] && [ "$_evp" = "$(cd "$_t9" && pwd -P)" ] && ok \
    || bad "T9c" "находка задания из каталога «/» записана с адресом «${_evp}», а не репозитория скрипта"

# --- T9b: ЧИСТЫЙ замер повода НЕ заводит. Без этой ноги повод завёлся бы всегда ---
_t9b="$TMP/t9b"; mkdir -p "$_t9b/scripts" "$_t9b/state"
cp "$REPO/scripts/measurement-due.sh" "$_t9b/scripts/"; cp -R "$REPO/hooks" "$_t9b/hooks"
printf '#!/usr/bin/env bash\necho "чисто"\nexit 0\n' > "$_t9b/scripts/fake.sh"; chmod +x "$_t9b/scripts/fake.sh"
printf 'зонд-чистый\t1\tbash scripts/fake.sh\tзонд\n' > "$_t9b/scripts/m.tsv"
( cd "$_t9b" && MEASUREMENT_REGISTRY="$_t9b/scripts/m.tsv" STATE_DIR="$_t9b/state" \
    bash "$_t9b/scripts/measurement-due.sh" run >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_measurement_due.sh:$LINENO" >&2; exit 1; }
_n9b=$(grep -c . "$_t9b/state/pending-events.jsonl" 2>/dev/null || true)
if [ "${_n9b:-0}" -eq 0 ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T9b]: чистый замер завёл повод ($_n9b записей) — повод перестал что-либо значить"; fi

# --- T10: единица «Nc» — коммиты с последнего прогона, а не дни ---
G="$TMP/grepo"; mkdir -p "$G/scripts"; cp "$SCRIPT" "$G/scripts/"
gc() { git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$1" 2>/dev/null; }
git -C "$G" init -q 2>/dev/null && gc one
printf 'bycommit\t2c\ttrue\tпо коммитам\n' > "$G/scripts/measurements.tsv"
S10="$TMP/state10"; mkdir -p "$S10/measurement-runs"
run10() { CLAUDSOUL_REPO="$G" STATE_DIR="$S10" bash "$G/scripts/measurement-due.sh" "${1:-check}" 2>&1; }
OUT=$(run10 check); grep -q 'просрочен: bycommit' <<< "$OUT" && ok || bad "T10a" "без отметки коммита замер не назван просроченным: $OUT"
run10 run >/dev/null 2>&1
[ -s "$S10/measurement-runs/bycommit.sha" ] && ok || bad "T10b" "прогон не записал коммит"
gc two
OUT=$(run10 check); grep -q 'просрочен: bycommit' <<< "$OUT" && bad "T10c" "один коммит при пороге 2 назван просрочкой" || ok
gc three
OUT=$(run10 check); grep -q 'просрочен: bycommit.*коммитов' <<< "$OUT" && ok || bad "T10d" "два коммита при пороге 2 не названы: $OUT"

# --- T11/T12: срок — работа, а не календарь (D1074, слово владельца 25 октября 2026) ---
# T11: полгода тишины — после отметки ни одной сессии: замер НЕ просрочен, хотя календарь говорит «180 дней».
mkreg "$TMP/reg-quiet.jsonl" 5 200
printf '%s\n' "$(( $(date +%s) - 180 * 86400 ))" > "$TMP/state/measurement-runs/fresh"
grep -q 'просрочен: fresh' <<< "$(REG="$TMP/reg-quiet.jsonl" run check)" \
    && bad "T11" "полгода без сессий объявлены просрочкой — срок мерится календарём" || ok
# T12: отметка позавчерашняя, а после неё 300 сессий — 10 дней опыта при периоде 7: замер ПРОСРОЧЕН.
printf '%s\n' "$(( $(date +%s) - 2 * 86400 ))" > "$TMP/state/measurement-runs/fresh"
grep -q 'просрочен: fresh' <<< "$(run check)" && ok \
    || bad "T12" "300 сессий после отметки не состарили замер — работа не считается"

# --- T13 (D1347): задание без единой настройки языка даёт командам замеров UTF-8 ---
# launchd запускает `/bin/bash measurement-due.sh run` с одним PATH. Команда замера — дочерняя оболочка, считающая
# длину двухбайтовой буквы: 1 — знаки, 2 — байты. T13b — контроль рамки и граница признака: язык, названный вызывающим
# (`LC_ALL=C`), не трогается, и та же команда отвечает 2 — нога умеет отличить одно от другого.
_t13="$TMP/t13"; mkdir -p "$_t13/state" "$_t13/state2"
_len_cmd() { printf 'zond-lang\t1\tbash -c '"'"'x=$(printf "\\321\\217"); printf %%s "${#x}"'"'"' > %s\tзонд\n' "$1"; }
_len_cmd "$_t13/out"  > "$_t13/m.tsv"
_len_cmd "$_t13/out2" > "$_t13/m2.tsv"
env -i PATH="$PATH" HOME="$HOME" MEASUREMENT_REGISTRY="$_t13/m.tsv" STATE_DIR="$_t13/state" \
    /bin/bash "$SCRIPT" run >/dev/null 2>&1
[ "$(cat "$_t13/out" 2>/dev/null)" = 1 ] && ok \
    || bad "T13" "без настроек языка команда замера считает байты: длина буквы «$(cat "$_t13/out" 2>/dev/null)», ожидалась 1"
env -i PATH="$PATH" HOME="$HOME" LC_ALL=C MEASUREMENT_REGISTRY="$_t13/m2.tsv" STATE_DIR="$_t13/state2" \
    /bin/bash "$SCRIPT" run >/dev/null 2>&1
[ "$(cat "$_t13/out2" 2>/dev/null)" = 2 ] && ok \
    || bad "T13b" "язык, названный вызывающим (LC_ALL=C), заменён: длина буквы «$(cat "$_t13/out2" 2>/dev/null)», ожидалась 2"

echo ""
echo "measurement due tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
