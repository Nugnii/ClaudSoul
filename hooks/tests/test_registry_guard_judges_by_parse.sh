#!/usr/bin/env bash
# test_registry_guard_judges_by_parse.sh — страж полей реестра судит по РАЗБОРУ
# jq-программы, а не по совпадению текста строки (D297, 6 сентября 2026).
#
# ПОВОД. Адверсариальный прогон 3 сентября 2026 нашёл у
# `test_registry_fields_have_writers.sh` три ложно-зелёных и одну форму, роняющую его на
# здоровом коде. Замер до починки — 1 верный исход из 6:
#   поле `phantom_empty: []` на финализации  → rc=0, поле не названо (D273 повторился бы);
#   два поля на одной строке, второе литерал → rc=0, второе поле вне универсума;
#   многострочное вычисляемое значение       → rc=1 на ЗДОРОВОМ коде (разбор упал);
#   пустой объект в heredoc                  → rc=0, поле исчезло из универсума;
#   литерал в скобках на финализации         → rc=0, названо вычисляемым;
#   здоровая библиотека                      → rc=0 (единственный верный исход).
# Корень: единицей разбора была СТРОКА ТЕКСТА, а не элемент jq-объекта, и правило
# «созданное пустым требует писателя» существовало двумя копиями — в ветке heredoc оно
# было, в ветке финализации его не было.
#
# ЧЕМ ЭТОТ ТЕСТ ОТЛИЧАЕТСЯ ОТ ВНУТРЕННИХ КОНТРОЛЕЙ СТРАЖА. Те доказывают, что страж
# СПОСОБЕН покраснеть, и живут внутри него. Этот проверяет ВЕРДИКТ на форме: подсаживает
# в копию библиотеки известную форму и требует названного исхода — и красного там, где
# поле не имеет второго значения, и ЗЕЛЁНОГО там, где код здоров. Без второй половины
# страж чинится загрублением: «краснеть всегда» проходит любой набор одних красных.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$HOOKS_DIR/tests/test_registry_fields_have_writers.sh"
LIB="$HOOKS_DIR/session-registry-lib.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Подмена подаётся стражу через REGISTRY_LIB_OVERRIDE: копировать всё дерево на каждую
# форму незачем, а писателей (`knowledge-counter-bump.sh` и прочие) страж обязан искать
# в НАСТОЯЩЕМ дереве — иначе `knowledge_delta` осталась бы без писателя во всех формах и
# любая из них краснела бы по чужой причине.
run_form() { # $1=имя $2=файл-библиотека → печатает "rc|названные поля"
    local out rc
    out=$(REGISTRY_LIB_OVERRIDE="$2" bash "$GUARD" 2>&1)
    rc=$?
    printf '%s|%s' "$rc" "$(printf '%s\n' "$out" | awk '/^  FAIL /{printf "%s ", $2}')"
}

check() { # $1=метка $2=ожидание(rc) $3=ожидаемое поле или "-" $4=результат
    local got_rc="${4%%|*}" got_f="${4#*|}"
    if [ "$got_rc" != "$2" ]; then
        FAIL=$((FAIL + 1)); echo "FAIL [$1]: rc=$got_rc, ожидался $2 (названы: ${got_f:--})"; return
    fi
    if [ "$3" != "-" ]; then
        case " $got_f" in
            *" $3 "*) ;;
            *) FAIL=$((FAIL + 1)); echo "FAIL [$1]: поле $3 не названо (названы: ${got_f:--})"; return ;;
        esac
    fi
    PASS=$((PASS + 1))
}

# Форма готовится питоном: подмена ОБЯЗАНА состояться, иначе форма мерила бы здоровый код.
# Пар подмены может быть две: форма L6 правит и объявление поля, и его писателя.
form() { # $1=имя $2=что_ищем $3=чем_заменяем [$4=что_ищем2 $5=чем_заменяем2]
    local dst="$TMP/$1.sh"
    FORM_SRC="$LIB" FORM_DST="$dst" FORM_OLD="$2" FORM_NEW="$3" \
    FORM_OLD2="${4:-}" FORM_NEW2="${5:-}" python3 - <<'FORMPY' || return 1
import os, sys
s = open(os.environ["FORM_SRC"], encoding="utf-8").read()
for a, b in (("FORM_OLD", "FORM_NEW"), ("FORM_OLD2", "FORM_NEW2")):
    old, new = os.environ.get(a, ""), os.environ.get(b, "")
    if not old:
        continue
    if s.count(old) != 1:
        sys.exit("подмена не применилась: якорь встречается %d раз" % s.count(old))
    s = s.replace(old, new)
open(os.environ["FORM_DST"], "w", encoding="utf-8").write(s)
FORMPY
    printf '%s' "$dst"
}

END_LINE='            ended_at: $ended,
'
DUR_LINE='            duration_min: $duration,
'
KD_LINE='  "knowledge_delta": {
'

# L0: здоровая библиотека — зелено. Без этой ноги любую красноту ниже даёт «краснеть всегда».
check "L0 здоровая библиотека" 0 "-" "$(run_form L0 "$LIB")"

# L1: поле создано ПУСТЫМ в конструкторе финализации. Ровно то, чем был `commits: []`:
# выглядит живым в каждой записи и всегда пусто.
F=$(form L1 "$END_LINE" "$END_LINE            phantom_empty: [],
") && check "L1 пустое поле на финализации" 1 phantom_empty "$(run_form L1 "$F")"

# L2: два поля на ОДНОЙ строке, второе — литерал. Разбор по строкам видел только первое,
# и `status: \"completed\"` (D273) прошёл бы здесь зелёным вторично.
F=$(form L2 "$DUR_LINE" '            duration_min: $duration, phantom_second: "only_value",
') && check "L2 второе поле на строке" 1 phantom_second "$(run_form L2 "$F")"

# L3: ЗДОРОВОЕ многострочное вычисляемое значение — страж обязан молчать, а не падать.
F=$(form L3 "$END_LINE" "$END_LINE            phantom_multi: (\$ended
                | ascii_upcase),
") && check "L3 многострочное вычисляемое" 0 "-" "$(run_form L3 "$F")"

# L4: пустой объект в heredoc. Обход схемы рекурсией терял его: у пустого словаря нет
# листьев, и поле исчезало из универсума целиком.
F=$(form L4 "$KD_LINE" '  "phantom_obj": {},
  "knowledge_delta": {
') && check "L4 пустой объект в heredoc" 1 phantom_obj "$(run_form L4 "$F")"

# L5: литерал в скобках. Значение одно, форма другая — вердикт обязан быть тем же.
F=$(form L5 "$END_LINE" "$END_LINE            phantom_paren: (\"only_value\"),
") && check "L5 литерал в скобках" 1 phantom_paren "$(run_form L5 "$F")"

# L6: поле создано пустым на финализации, но ПИСАТЕЛЬ у него есть (sr_update_knowledge,
# её зовёт knowledge-counter-bump.sh). Вторая половина того же правила: без этой ноги
# «пустое на финализации» проходит загрублением «пустое всегда красное», и разница между
# «писателя нет» и «писатель есть» стражем не измеряется.
KD_WRITE="            '.knowledge_delta[\$action] += [\$file] | .knowledge_delta[\$action] |= unique'"
F=$(form L6 "$END_LINE" "$END_LINE            phantom_delta: [],
" "$KD_WRITE" "            '.knowledge_delta[\$action] += [\$file] | .knowledge_delta[\$action] |= unique | .phantom_delta += [\$file]'") \
    && check "L6 пустое на финализации с писателем" 0 "-" "$(run_form L6 "$F")"

echo ""
echo "registry guard judges by parse: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
