#!/usr/bin/env bash
# test_lib_shell_parity.sh — библиотека обязана давать один и тот же вывод в bash и в zsh.
#
# Повод. `dis_scan_open` под zsh печатала три строки `sid=<значение>` вместо записей
# `sid|key|date|conf|tool`, и три мусорные строки были прочитаны как три открытые записи
# контура опровержения. `dis_stats` под zsh давала 13 строк вместо одной.
#
# Причина: в zsh повторное объявление `local x` для уже существующей переменной ПЕЧАТАЕТ
# `x=значение` в stdout, в bash молчит. Объявление стояло в теле цикла, то есть выполнялось
# на каждой итерации.
#
# Почему тест, а не правило. Этот класс уже чинили один раз: в `dis_stats` заменили
# `read -r a b c <<EOF` на позиционный разбор и оставили комментарий про zsh. Лечили
# конструкцию, а не причину — и она вернулась другим путём, через `local` в цикле.
# Комментарий в коде не помешал повторению; проверка помешает.
#
# Почему это не косметика. Хуки объявлены с `#!/usr/bin/env bash`, но скиллы зовут те же
# функции через Bash-инструмент Claude Code, а он на macOS — zsh (`pattern-shell-portability`,
# уверенность 5). `/learn` Step 4e прямо предписывает брать SID «из первой колонки
# `dis_scan_open`» — то есть разбирать выдачу, засорённую под zsh.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v zsh >/dev/null 2>&1 || { echo "SKIP: zsh недоступен — паритет проверить не с чем"; exit 0; }

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

# Состояние минимум из ТРЁХ элементов: течёт повторное объявление, на одной итерации
# расхождения не будет и тест пройдёт вхолостую.
for s in aaa bbb ccc; do
    printf '{"date":"2026-07-01T10:00:00Z","key":"pattern-x-%s","outcome":"pending","confidence":4,"tool":"Bash"}\n' "$s" \
        > "$TMP/state/disagreement-pending-$s.jsonl"
done

parity() { # $1=библиотека $2=вызов $3=имя случая
    _ob=$(bash -c "STATE_DIR='$TMP/state' source '$HOOKS_DIR/$1' 2>/dev/null; $2" 2>/dev/null)
    _oz=$(zsh  -c "STATE_DIR='$TMP/state' source '$HOOKS_DIR/$1' 2>/dev/null; $2" 2>/dev/null)
    if [ "$_ob" = "$_oz" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$3]: вывод расходится (bash $(printf '%s' "$_ob" | grep -c .) строк, zsh $(printf '%s' "$_oz" | grep -c .) строк)"
        diff <(printf '%s\n' "$_ob") <(printf '%s\n' "$_oz") | head -4 | sed 's/^/        /'
    fi
}

parity disagreement-lib.sh 'dis_scan_open'      "T1 dis_scan_open"
parity disagreement-lib.sh 'dis_stats'          "T2 dis_stats"
parity disagreement-lib.sh 'dis_expire_old 3650' "T3 dis_expire_old"

# session-registry-lib: тот же класс, найден отдельно (D32). Здесь было ДВА дефекта сразу —
# `compgen` (встроенная команда bash, в zsh её нет: перечисление файлов молча пустело) и
# `local` в теле цикла. Итог под zsh: `[]` вместо списка сессий, то есть детектор параллельных
# сессий сообщал «их нет» — тихий ложноотрицательный.
mkdir -p "$TMP/sessions/active"
for s in pa pb pc; do
    printf '{"session_id":"%s","started_at":"2026-07-01T10:00:00Z","cwd":"/tmp","status":"active","project_name":"p"}\n' "$s" \
        > "$TMP/sessions/active/$s.json"
done
# $3=strict — требовать непустой вывод. Ставится только там, где есть ЗАМЕР непустого
# результата до починки: у `sr_detect_parallel` bash выдавал 7 строк, а zsh — `[]`, и
# именно поэтому пустой ответ здесь означал бы возврат дефекта. Для остальных функций
# такого замера нет, и требовать непустоты значило бы закрепить собственное допущение
# вместо наблюдения.
parity_sr() { # $1=вызов $2=имя $3=strict|loose
    # SR_SESSIONS_DIR задаётся ДО подключения библиотеки. Первая версия ставила только
    # SR_ACTIVE_DIR, и функции продолжали читать живой ~/.claude/sessions — он менялся между
    # прогоном в bash и прогоном в zsh, и тест «расхождение оболочек» на деле измерял
    # изменение состояния во времени. Проверка была нестабильной по построению.
    # Оба каталога задаются ПОСЛЕ подключения: библиотека присваивает SR_SESSIONS_DIR жёстко,
    # без `:=`, поэтому значение из окружения она игнорирует. Первая версия стенда ставила
    # только SR_ACTIVE_DIR, и функции продолжали читать живой ~/.claude/sessions, который
    # менялся между прогоном в bash и в zsh — тест «расхождение оболочек» на деле измерял
    # изменение состояния во времени и был нестабилен по построению.
    _sr_pre="source '$HOOKS_DIR/session-registry-lib.sh' 2>/dev/null; SR_SESSIONS_DIR='$TMP/sessions'; SR_ACTIVE_DIR='$TMP/sessions/active';"
    _ob=$(bash -c "$_sr_pre $1" 2>/dev/null)
    _oz=$(zsh  -c "$_sr_pre $1" 2>/dev/null)
    _ok=1
    [ "$_ob" = "$_oz" ] || _ok=0
    if [ "${3:-loose}" = "strict" ]; then
        [ -n "$_ob" ] && [ "$_ob" != "[]" ] || _ok=0
    fi
    if [ "$_ok" = "1" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$2]: bash=«$(printf '%s' "$_ob" | head -c 40)» zsh=«$(printf '%s' "$_oz" | head -c 40)»"
    fi
}
parity_sr 'sr_detect_parallel'    "T4 sr_detect_parallel — совпадает и НЕ пуст" strict

# `sr_detect_interrupted` сюда НЕ добавлен намеренно. Он сверяется с живым деревом процессов
# (`_sr_process_ancestors`), а у подоболочек bash и zsh оно разное — сравнение выводов для
# него некорректно по построению, и тест был бы нестабилен не из-за продукта. Проверено:
# состояние функция не мутирует (файлы на месте до и после), при одинаковом дереве процессов
# выводы совпадают побайтово. Класс «zsh печатает объявления» для этого файла закрывает T4.

# Отрицательный контроль: проверка обязана уметь ловить этот класс.
# Ставим функцию с тем самым приёмом и требуем, чтобы паритет НЕ сошёлся. Без этого
# зелёный результат выше не означает, что проверка вообще на что-то реагирует.
cat > "$TMP/leaky-lib.sh" <<'LEAK'
leaky_fn() {
    local i
    for i in 1 2 3; do
        local tmp
        tmp="значение-$i"
        printf 'строка-%s\n' "$i"
    done
}
LEAK
_nb=$(bash -c "source '$TMP/leaky-lib.sh'; leaky_fn" 2>/dev/null)
_nz=$(zsh  -c "source '$TMP/leaky-lib.sh'; leaky_fn" 2>/dev/null)
if [ "$_nb" != "$_nz" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [T4 отрицательный контроль]: заведомо текущая функция не дала расхождения — проверка ничего не измеряет"
fi

echo ""
echo "lib shell parity tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
