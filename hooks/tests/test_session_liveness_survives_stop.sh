#!/usr/bin/env bash
# СУДИТ: hooks/session-registry-lib.sh
# test_session_liveness_survives_stop.sh — живая сессия видна соседней ПОСЛЕ границы хода.
#
# Повод (D298, 3 сентября 2026). Живость сессии читалась по наличию `active/<sid>.json`,
# а `sr_finalize_session` удаляет этот файл на КАЖДОМ Stop — Stop есть конец ХОДА, не
# сессии (`session-collector.sh:239`). Значит после первого же хода живая параллельная
# сессия исчезала из вида: `sr_detect_parallel` печатал `[]`, стартовый контекст —
# «Параллельных сессий нет». Корень: у признака живости не было своего носителя, он был
# совмещён с накопителем записи хода, а тот обязан сбрасываться каждый ход (D270).
#
# Предмет проверки — СОСТОЯНИЕ МИРА («соседняя сессия видит живую»), а не форма кода:
# проба гоняет две сессии отдельными процессами через общий каталог реестра и читает
# вывод `sr_detect_parallel`. Позеленить правкой комментария нельзя.
#
# T3/T4 держат границы починки: накопитель хода по-прежнему уносится на Stop (иначе
# ломается T0 в test_knowledge_delta_reaches_registry) и запись реестра остаётся одна на
# ход (иначе объём реестра растёт молча). T5 — срок: сессия без признака жизни живой не
# считается, иначе метка каждой завершённой сессии вечно числилась бы параллельной.
# T6 — отрицательный контроль: на копии библиотеки без записи метки T1 обязан покраснеть.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен — реестр без него не пишется"; exit 0; }
# Отказ чтения ответа пробы НЕ равен «сессия не видна»: длина списка не прочитана — это
# нечитаемость, а не замер. Различение берётся единым источником (род дефекта B), а не
# пишется здесь заново; ниже T5/T7 держат ту же границу маркером `x`.
. "$HOOKS_DIR/lib/unread-lib.sh"

PASS=0
FAIL=0
assert_eq() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: получено '$got', ожидалось '$want'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/libs-real" "$TMP/libs-old" "$TMP/projA"
printf '# fixture\n' > "$TMP/projA/CLAUDE.md"
for lib in session-registry-lib.sh portable-lib.sh state-lock-lib.sh; do
    [ -f "$HOOKS_DIR/$lib" ] && cp "$HOOKS_DIR/$lib" "$TMP/libs-real/"
done

# Копия БЕЗ записи метки живости: вызовы `_sr_mark_live …` заменены пустой командой.
cp "$TMP/libs-real/"*.sh "$TMP/libs-old/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_session_liveness_survives_stop.sh:$LINENO" >&2; exit 1; }
sed 's/^\([[:space:]]*\)_sr_mark_live .*$/\1:/' "$HOOKS_DIR/session-registry-lib.sh" \
    > "$TMP/libs-old/session-registry-lib.sh"

# Проба сессии: подключает библиотеку в отдельном процессе и исполняет поданный код.
# `set -u` в пробе НЕ ставится намеренно: в библиотеке три цикла вида `for f in
# "${files[@]}"`, и на пустом каталоге под bash 3.2 (умолчание macOS) это «unbound
# variable» — дефект отдельного рода, не предмет D298. С `set -u` проба мерила бы его.
cat > "$TMP/sess.sh" <<'SESS'
set -o pipefail
LIB="$1"; CODE="$2"
# shellcheck source=/dev/null
source "$LIB/session-registry-lib.sh"
eval "$CODE"
SESS

sess() { # $1=libdir $2=root $3=sid $4=код
    env HOME="$2/h" SR_SESSIONS_DIR="$2/sessions" SR_OVERRIDE_SESSION_ID="$3" \
        bash "$TMP/sess.sh" "$1" "$4" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_session_liveness_survives_stop.sh:$LINENO" >&2; exit 1; }
}

# === T1-T4: сессия A прошла границу хода и продолжает жить; сессия B её ищет ===
R1="$TMP/r1"; mkdir -p "$R1/h"
sess "$TMP/libs-real" "$R1" advA \
    "sr_register_session '$TMP/projA'; sr_finalize_session 'ход 1'" >/dev/null
SEEN=$(sess "$TMP/libs-real" "$R1" advB 'sr_detect_parallel' | jq -r 'length' 2>/dev/null)
unread_or SEEN "НЕ ПРОЧИТАНО" "длина списка параллельных сессий (T1)" || true
assert_eq "$SEEN" "1" "T1: живая сессия видна соседней после границы хода"

NAME=$(sess "$TMP/libs-real" "$R1" advB 'sr_detect_parallel' | jq -r '.[0].session_id' 2>/dev/null)
assert_eq "$NAME" "advA" "T2: названа именно та сессия, а не любая запись"

assert_eq "$([ -f "$R1/sessions/active/advA.json" ] && echo yes || echo no)" "no" \
    "T3: накопитель хода по-прежнему уносится на Stop"

assert_eq "$(wc -l < "$R1/sessions/registry.jsonl" 2>/dev/null | tr -d ' ')" "1" \
    "T4: запись реестра одна на ход — объём не вырос"

# === T5: без признака жизни сессия живой не считается ===
# Стареет весь каталог сессии, а не конкретный файл: проверка о состоянии мира, а не о
# том, в каком файле починка держит метку.
find "$R1/sessions" -type f -exec touch -t 202601010000 {} + 2>/dev/null
STALE=$(sess "$TMP/libs-real" "$R1" advB 'sr_detect_parallel' | jq -r 'length' 2>/dev/null)
assert_eq "${STALE:-x}" "0" "T5: сессия без признака жизни (старше срока) параллельной не числится"

# === T6: сессия видна и ДО первой границы хода — прежнее поведение не потеряно ===
R2="$TMP/r2"; mkdir -p "$R2/h"
sess "$TMP/libs-real" "$R2" advA "sr_register_session '$TMP/projA'" >/dev/null
FIRST=$(sess "$TMP/libs-real" "$R2" advB 'sr_detect_parallel' | jq -r 'length' 2>/dev/null)
unread_or FIRST "НЕ ПРОЧИТАНО" "длина списка параллельных сессий (T6)" || true
assert_eq "$FIRST" "1" "T6: сессия до первого Stop видна (и ровно один раз)"

# === T7: отрицательный контроль — без записи метки живая сессия снова невидима ===
# Подмена обязана состояться И иметь что подменять: пустой счёт в ОБОИХ копиях значит,
# что контроль гоняет ту же библиотеку, что и T1, и «краснеет» не от подмены.
SUBST=$(grep -c '_sr_mark_live ' "$TMP/libs-old/session-registry-lib.sh" 2>/dev/null | tr -d ' ')
ORIG=$(grep -c '_sr_mark_live ' "$TMP/libs-real/session-registry-lib.sh" 2>/dev/null | tr -d ' ')
if [ "${SUBST:-1}" != "0" ] || [ "${ORIG:-0}" -lt 2 ]; then
    FAIL=$((FAIL + 1)); echo "FAIL [T7-подмена]: вызовов в оригинале $ORIG, в копии $SUBST — контроль мерил бы ту же библиотеку"
else
    R3="$TMP/r3"; mkdir -p "$R3/h"
    sess "$TMP/libs-old" "$R3" advA \
        "sr_register_session '$TMP/projA'; sr_finalize_session 'ход 1'" >/dev/null
    OLD=$(sess "$TMP/libs-old" "$R3" advB 'sr_detect_parallel' | jq -r 'length' 2>/dev/null)
    assert_eq "${OLD:-x}" "0" "T7: без метки живости соседняя сессия невидима (дефект D298)"
fi

echo ""
echo "session liveness tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
