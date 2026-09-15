#!/usr/bin/env bash
# test_knowledge_delta_reaches_registry.sh — дельта знаний доходит до реестра сессий
# независимо от того, на каком ходу она записана.
#
# Повод (D270, 2 сентября 2026). Носитель `active/<sid>.json` заводится один раз
# (`sr_register_session` на старте), а уносится в реестр на КАЖДОЙ границе хода:
# `session-collector.sh` зовёт `sr_finalize_session` на Stop, а Stop — конец ХОДА, не
# сессии. После первой границы активного файла нет, и `sr_update_knowledge` выходил
# нулём по `[ -f "$active_file" ] || return 0`. Замер: сессия d5116580-… имеет в
# `registry.jsonl` две записи и ни одной строки о знании, записанном между ними.
#
# Предмет проверки — СОСТОЯНИЕ МИРА («дельта в реестре»), а не форма кода: тест не ищет
# строк в библиотеке, он прогоняет запись после границы хода и читает реестр. Поэтому
# позеленить его правкой комментария нельзя.
#
# T3 — отрицательный контроль: на копии библиотеки со СТАРОЙ строкой (`|| return 0`)
# та же проба обязана дать «дельта потеряна». Без него T1-T2 не доказывают, что здесь
# вообще что-то измеряется: они зеленели бы и на библиотеке, пишущей дельту куда угодно.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен — реестр без него не пишется"; exit 0; }

PASS=0
FAIL=0
assert_eq() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: получено '$got', ожидалось '$want'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/libs-real" "$TMP/libs-old"
cp "$HOOKS_DIR/session-registry-lib.sh" "$TMP/libs-real/"
# Библиотека замка (род H, 4 сентября 2026) — обязательный сосед: session-registry-lib
# зовёт `atomic_filter` из неё. Фикстура, забывшая её скопировать, даёт ТИХУЮ потерю
# записи, а не отказ: функции нет, ветка `if [ -f ... ]` молча пропускает подключение.
# Ровно тот гочи, что записан в docs/development.md про фиксированные списки фикстур.
cp "$HOOKS_DIR/portable-lib.sh" "$TMP/libs-real/" 2>/dev/null || true
cp "$HOOKS_DIR/state-lock-lib.sh" "$TMP/libs-real/" 2>/dev/null || true
cp "$HOOKS_DIR/portable-lib.sh" "$TMP/libs-old/" 2>/dev/null || true
cp "$HOOKS_DIR/state-lock-lib.sh" "$TMP/libs-old/" 2>/dev/null || true

# Копия с поведением ДО починки: пересоздание носителя снято, остаётся тихий выход.
# Правится ровно одна строка — та, что и была корнем.
sed 's#^    \[ -f "$active_file" \] || sr_register_session$#    :#' \
    "$HOOKS_DIR/session-registry-lib.sh" > "$TMP/libs-old/session-registry-lib.sh"
# Подмена обязана состояться: молчаливый промах sed дал бы копию, равную исправленной,
# и T3 «доказал» бы отсутствие дефекта на том же коде, что и T2.
grep -q 'sr_register_session$' "$TMP/libs-old/session-registry-lib.sh" && {
    if grep -q '^    \[ -f "$active_file" \] || sr_register_session$' "$TMP/libs-old/session-registry-lib.sh"; then
        echo "FAIL: подмена библиотеки не состоялась — T3 мерил бы исправленный код"; exit 1
    fi
}

# Проба: старт → знание (носитель жив) → граница хода → знание (носителя нет) → граница.
# Печатает, сколько записей реестра несут каждое из двух знаний.
cat > "$TMP/probe.sh" <<'PROBE'
set -uo pipefail
LIBDIR="$1"
export HOME="$2"
# Каталог реестра выводится ИЗ HOME намеренно — предмет пробы именно умолчание.
# Раннер даёт каждому тесту свой SR_SESSIONS_DIR (D271), и унаследованная переменная
# перебила бы выведение, сделав отрицательный контроль ложным.
unset SR_SESSIONS_DIR
mkdir -p "$HOME/.claude/sessions/active"
export SR_OVERRIDE_SESSION_ID="probe-sid"
# shellcheck source=/dev/null
source "$LIBDIR/session-registry-lib.sh"

sr_register_session
sr_update_knowledge created "pattern-first-turn.md"
sr_finalize_session "ход 1" 2>/dev/null

# Граница хода прошла: активного файла больше нет — это и есть условие дефекта.
echo "active_after_turn1=$([ -f "$SR_ACTIVE_DIR/probe-sid.json" ] && echo да || echo нет)"

sr_update_knowledge created "pattern-second-turn.md"
sr_finalize_session "ход 2" 2>/dev/null

echo "first=$(grep -c 'pattern-first-turn.md' "$SR_REGISTRY" 2>/dev/null || echo 0)"
echo "second=$(grep -c 'pattern-second-turn.md' "$SR_REGISTRY" 2>/dev/null || echo 0)"
PROBE

OUT_REAL=$(bash "$TMP/probe.sh" "$TMP/libs-real" "$TMP/home-real" 2>/dev/null)
OUT_OLD=$(bash "$TMP/probe.sh" "$TMP/libs-old" "$TMP/home-old" 2>/dev/null)

get() { printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2; }

# Условие дефекта воспроизведено: после первой границы хода носителя нет.
assert_eq "$(get "$OUT_REAL" active_after_turn1)" "нет" "T0: граница хода уносит носитель"

# T1: знание, записанное ДО первой границы, доходит — прежний путь не сломан.
assert_eq "$(get "$OUT_REAL" first)"  "1" "T1: дельта первого хода в реестре"

# T2: знание, записанное ПОСЛЕ границы хода, доходит тоже — предмет пункта D270.
assert_eq "$(get "$OUT_REAL" second)" "1" "T2: дельта после границы хода в реестре"

# T3: отрицательный контроль — со старой строкой дельта второго хода теряется.
assert_eq "$(get "$OUT_OLD" second)"  "0" "T3: без пересоздания носителя дельта терялась"

echo "knowledge delta reaches registry: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
