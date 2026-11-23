#!/usr/bin/env bash
# test_adversary_openfind_silent_zero.sh — АТАКА 3: правдоподобный ноль вместо отказа.
#
# Библиотека объявляет: «ТРИ СОСТОЯНИЯ, А НЕ ДВА. Источник недоступен — это ПОЛОМКА, и она
# называется словом BROKEN, а не выдаёт ноль: ноль читается как "незакрытого нет", то есть
# отказ прибора становится неотличим от чистого мира (род B)» (open-findings-lib.sh:34-36).
#
# Правило объявлено для ОДНОГО источника (виды сигнала) и не применено к трём остальным.
# Каждое плечо ниже — мир, где незакрытое ЕСТЬ, а прибор отвечает «0 0» с кодом 0:
#   C1  нет python3            — hooks/lib/open-findings-lib.sh:49 печатает «0 0» и уходит
#   C2  метасимвол в пути      — строка 77 склеивает `os.path.join(sd,"outcome-*.jsonl")`,
#                                и `[`/`*`/`?` в имени каталога состояния читаются glob'ом
#                                как ЧАСТЬ ШАБЛОНА: файлы не находятся
#   C3  журнал не читается     — строки 79-81 глотают OSError через `continue`
#   C4  каталог не читается    — glob возвращает пусто, отказ не отличим от пустоты
#
# Ожидание: BROKEN (либо верное число), код 2.
# Факт: «0 0» и код 0 — потребитель молчит, незакрытое исчезает из виду.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/open-findings-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)   # ничего не удаляем
# shellcheck source=/dev/null
. "$LIB"

REC1='{"ts":"2026-09-01T10:00:00Z","key":"k1","signal":"discovery","outcome":"deferred","ref":""}'
REC2='{"ts":"2026-09-02T10:00:00Z","key":"k2","signal":"rework","outcome":"deferred","ref":""}'

# C1. python3 недоступен. Виды сигнала при этом ЗАДАНЫ — проверяется именно ветка 49,
#     а не ветка отсутствия источника видов.
mkdir -p "$TMP/c1"; printf '%s\n' "$REC1" > "$TMP/c1/outcome-a.jsonl"
OUT=$(PATH="$TMP/пусто" OF_RC_LIB=/dev/null RC_KINDS_RE='discovery:|rework:' of_open_counts "$TMP/c1" 2>/dev/null); RC=$?
case "${OUT}" in
    BROKEN*) [ "$RC" -eq 2 ] && ok || bad C1rc "сказал BROKEN, но код $RC" ;;
    *)       bad C1 "прибора нет (нет python3), а ответ «${OUT}» с кодом $RC — отказ неотличим от чистого мира" ;;
esac

# C2. Метасимвол в имени каталога состояния. Каталог настоящий, журнал настоящий, запись
#     настоящая — а прибор её не видит, потому что путь ушёл в шаблон без экранирования.
mkdir -p "$TMP/state[1]"; printf '%s\n' "$REC1" > "$TMP/state[1]/outcome-a.jsonl"
OUT=$(of_open_counts "$TMP/state[1]" 2>/dev/null); RC=$?
[ "$(printf '%s' "${OUT}" | awk '{print $1}')" = "1" ] \
    && ok || bad C2 "каталог с «[» в имени: ждали 1 отложенное, ответ «${OUT}» (код $RC)"

# C3. Журнал не читается. Под root проверка бессмысленна — права его не держат.
if [ "$(id -u)" != "0" ]; then
    mkdir -p "$TMP/c3"
    printf '%s\n' "$REC1" > "$TMP/c3/outcome-a.jsonl"
    printf '%s\n' "$REC2" > "$TMP/c3/outcome-b.jsonl"
    chmod 000 "$TMP/c3/outcome-b.jsonl"
    OUT=$(of_open_counts "$TMP/c3" 2>/dev/null); RC=$?
    chmod 644 "$TMP/c3/outcome-b.jsonl" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_openfind_silent_zero.sh:$LINENO" >&2; exit 1; }
    case "${OUT}" in
        BROKEN*) ok ;;
        *) [ "$(printf '%s' "${OUT}" | awk '{print $1}')" = "2" ] \
               && ok || bad C3 "нечитаемый журнал молча пропущен: ответ «${OUT}» вместо 2 или BROKEN — неудача чтения выдана за чистоту (род B)" ;;
    esac

    # C4. Каталог состояния не читается целиком.
    mkdir -p "$TMP/c4"; printf '%s\n' "$REC1" > "$TMP/c4/outcome-a.jsonl"
    chmod 000 "$TMP/c4"
    OUT=$(of_open_counts "$TMP/c4" 2>/dev/null); RC=$?
    chmod 755 "$TMP/c4" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_openfind_silent_zero.sh:$LINENO" >&2; exit 1; }
    case "${OUT}" in
        BROKEN*) ok ;;
        *) bad C4 "каталог состояния нечитаем, а ответ «${OUT}» с кодом $RC — «незакрытого нет»" ;;
    esac
else
    echo "SKIP C3/C4: запуск под root, права не проверяются"
fi

echo "adversary openfind silent-zero: $PASS passed, $FAIL failed (песочница: $TMP)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
