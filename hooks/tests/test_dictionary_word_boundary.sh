#!/usr/bin/env bash
# test_dictionary_word_boundary.sh — характеризующий тест рода D (D245).
# Держит ровно то, на чём споткнулись два стража 1 сентября 2026: русский корень в словаре
# свободной прозы без границы слова совпадает ВНУТРИ другого слова.
#   five-whys-gate:     «замер ПОКАЗАЛ» ⊃ «оказал»  → отказ на записи
#   user-correction-guard: «ОСНОВАНИЕ», «ОБОСНОВАНО» ⊃ «снова»; «УСУГУБЛЯЕТСЯ» ⊃ «бля»
#                                                  → вопрос собеседнику
# Ловушка теста: проверять надо ОБЕ стороны. Граница, поставленная слишком жадно, убивает
# настоящие срабатывания — поэтому у каждого ложного случая рядом стоит истинный.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Словарь достаётся ИЗ ФАЙЛА, а не переписывается сюда: копия словаря в тесте разошлась бы
# с оригиналом молча, и тест продолжал бы зеленеть на устаревшем наборе.
DISCOVERY=$(grep -m1 '^DISCOVERY_RE=' "$REPO/hooks/five-whys-gate.sh" \
    | sed 's/^DISCOVERY_RE="${FIVE_WHYS_DISCOVERY_RE:-//; s/}"$//')
CORRECTION=$(grep -m1 "^CORRECTION_REGEX=" "$REPO/hooks/user-correction-guard.sh" \
    | sed "s/^CORRECTION_REGEX='//; s/'$//")
[ -n "$DISCOVERY" ]  || { echo "FAIL: DISCOVERY_RE не извлечён"; exit 1; }
[ -n "$CORRECTION" ] || { echo "FAIL: CORRECTION_REGEX не извлечён"; exit 1; }

# Рамка складывает регистр ТЕМ ЖЕ инструментом, что и потребители словаря: `grep -i` в
# наследованной локали (LC_CTYPE=C) кириллицу не складывает, и рамка мерила бы не то, что
# делает страж. T5 («Оказалось, что файл пустой») краснела по этой причине, а не по словарю.
PORT_LIB="$REPO/hooks/portable-lib.sh"
# shellcheck source=/dev/null
[ -f "$PORT_LIB" ] && . "$PORT_LIB"
fold() { if command -v to_lower >/dev/null 2>&1; then to_lower "${1:-}"; else printf '%s' "${1:-}"; fi; }
silent() { grep -qiE "$1" <<< "$(fold "$2")" && bad "$3" "ложное совпадение: «$2»" || ok; }
fires()  { grep -qiE "$1" <<< "$(fold "$2")" && ok || bad "$3" "пропуск настоящего: «$2»"; }

# --- five-whys-gate: находка по ходу работы -------------------------------------------
silent "$DISCOVERY" "Замер показал эффект правки"      T1
silent "$DISCOVERY" "Тест показал 28 из 28"            T2
silent "$DISCOVERY" "Прибор доказал обратное"          T3
silent "$DISCOVERY" "Указал путь к файлу"              T4
fires  "$DISCOVERY" "Оказалось, что файл пустой"       T5
fires  "$DISCOVERY" "оказался пустым"                  T6
fires  "$DISCOVERY" "решение за владельцем"            T7

# --- user-correction-guard: коррекция собеседника -------------------------------------
silent "$CORRECTION" "какое у этого основание"         T8
silent "$CORRECTION" "это обосновано замером"          T9
silent "$CORRECTION" "усугубляется тем что"            T10
fires  "$CORRECTION" "снова то же самое"               T11
fires  "$CORRECTION" "опять двадцать пять"             T12
fires  "$CORRECTION" "нихера не работает"              T13

# --- род D в реестре носителей пуст ----------------------------------------------------
# ОТКАЗ ПРИБОРА ОТЛИЧЁН ОТ НАХОДКИ (корень R6). Прежняя редакция читала ПУСТУЮ строку как
# «род непуст»: под нагрузкой полного набора реестр родов (107 с CPU) не успевал ответить,
# и набор краснел не по своей причине — 14 сентября 2026, прогон 514/515 при зелёном
# одиночном. Три состояния теперь названы раздельно.
D_LINE=$(python3 "$REPO/scripts/defect-class-carriers.py" 2>/dev/null | grep "РОД D")
if [ -z "$D_LINE" ]; then
    bad T14 "реестр родов не ответил — вердикта о роде D нет (это НЕ «род пуст»)"
else
    case "$D_LINE" in
        *"носителей: 0"*) ok ;;
        *) bad T14 "род D непуст: $D_LINE" ;;
    esac
fi

echo "$PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
