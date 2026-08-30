#!/usr/bin/env bash
# test_adv5_escaped_dollar_erases_bomb.sh — гашение экранированного доллара стирает
# настоящую бомбу вместе с данными.
#
# test_multibyte_var_boundary.sh:42 перед поиском выполняет
#     sed 's/\\\$//g' "$1"
# с комментарием «`\$` — экранированный доллар: подстановки нет, это данные».
# Подстановка `s///g` не смотрит, что стоит ЛЕВЕЕ обратного слеша. В последовательности
# из двух слешей и доллара — `\\$v` — правая пара `\$` подходит под образец и вырезается,
# от строки остаётся `\v`, доллара в ней больше нет, и поиск проходит по пустому месту.
#
# Между тем `"\\$v»"` для bash — литеральный обратный слеш ПЛЮС обычная подстановка `$v`  # mb-ok: строка демонстрирует дефект
# вплотную к «»», то есть ровно то нарушение, которое обход ищет. Проверено на
# /bin/bash 3.2.57: «unbound variable», выход посреди работы (проверка ниже в тесте).
#
# Форма законная и обычная: так пишут литеральный слеш перед значением — в json,
# в sed/awk-скриптах, в markdown-экранировании. Обход её не увидит никогда.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_multibyte_var_boundary.sh"
RAQUO=$(printf '\302\273')
rc_test=0

T="$(mktemp -d)"
mkdir -p "$T/hooks/tests" "$T/scripts"
cp "$GUARD" "$T/hooks/tests/"

# echo "\\$v»"  — литеральный слеш + подстановка вплотную к закрывающей ёлочке  # mb-ok: строка демонстрирует дефект
{
    printf '#!/bin/bash\nset -u\nv=x\n'
    printf 'echo "\\\\$v%s"\necho AFTER\n' "$RAQUO"
} > "$T/hooks/escaped_bomb.sh"

echo "исследуемая строка: $(awk 'NR==4' "$T/hooks/escaped_bomb.sh")"

# --- 1. Доказать, что это бомба ---
err="$(/bin/bash "$T/hooks/escaped_bomb.sh" 2>&1 >/dev/null)"
case "$err" in
    *"unbound variable"*) echo "предпосылка: bash 3.2 упал — [$err]" ;;
    *)
        echo "SKIP: на этом bash форма не ломается — [$err]"
        exit 0 ;;
esac

# --- 2. Обход обязан её увидеть ---
guard_out="$(bash "$T/hooks/tests/$(basename "$GUARD")" 2>&1)"; guard_rc=$?
if [ "$guard_rc" -eq 0 ]; then
    echo "FAIL [A3]: обход зелен на файле с настоящей бомбой:"
    echo "  файл: $T/hooks/escaped_bomb.sh"
    echo "  после sed 's/\\\\\\\$//g' строка выглядит так: $(sed 's/\\\$//g' "$T/hooks/escaped_bomb.sh" | awk 'NR==4')"
    printf '%s\n' "$guard_out" | sed 's|^|    |'
    rc_test=1
else
    echo "PASS [A3]: обход назвал нарушение (rc=$guard_rc)"
fi

echo ""
if [ "$rc_test" -ne 0 ]; then
    echo "adv5 escaped-dollar-erases-bomb: КРАСНЫЙ — гашение данных гасит и предмет поиска."
fi
exit "$rc_test"
