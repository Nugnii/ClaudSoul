#!/usr/bin/env bash
# test_adv5_heredoc_comment_shape.sh — обход слеп к бомбе внутри heredoc, потому что
# строка тела heredoc выглядит как комментарий.
#
# test_multibyte_var_boundary.sh:44 гасит находку фильтром
#     grep -vE '^[0-9]+:[[:space:]]*#'
# с обоснованием в шапке: «строки комментариев (там подстановки не происходит)».
# Признак — «первый непробельный символ строки есть #». Внутри НЕэкранированного
# heredoc это неверно: подстановка там происходит, а `#` — обычный текст. В корпусе
# такие строки есть буквально: hooks/error-tracker.sh:128 пишет в черновик кейса
#     # Case ${TODAY} — auto-draft
# — заголовок markdown внутри `cat > "$DRAFT_FILE" <<DRAFT`. Скобки там стоят, поэтому
# бомба не взведена; убери их — и обход промолчит.
#
# Последствие хуже падения. Проверено на /bin/bash 3.2.57 (см. ниже в тесте):
# при подстановке вплотную к «»» heredoc НЕ выдаёт ничего, `cat > файл` создаёт
# ПУСТОЙ файл, сообщение «unbound variable» уходит в stderr, а код возврата остаётся 0
# и скрипт продолжает работу. То есть данные теряются молча — ровно тот исход, ради
# которого обход написан, и ровно тот, который он не видит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_multibyte_var_boundary.sh"
LAQUO=$(printf '\302\253'); RAQUO=$(printf '\302\273')
rc_test=0

T="$(mktemp -d)"
mkdir -p "$T/hooks/tests" "$T/scripts"
cp "$GUARD" "$T/hooks/tests/"

# Бомба: тело heredoc, строка начинается с «#», подстановка вплотную к «»».
{
    printf '#!/bin/bash\nset -u\nTODAY=2026-08-25\ncat > "$1" <<DRAFT\n'
    printf '# Case %s$TODAY%s — auto-draft\n' "$LAQUO" "$RAQUO"
    printf 'DRAFT\necho AFTER\n'
} > "$T/hooks/heredoc_bomb.sh"

# --- 1. Доказать, что это настоящая бомба, а не выдумка теста ---
OUT_FILE="$T/out.md"
bomb_err="$(/bin/bash "$T/hooks/heredoc_bomb.sh" "$OUT_FILE" 2>&1 >/dev/null)"
bomb_size=$(wc -c < "$OUT_FILE" | tr -d ' ')
case "$bomb_err" in
    *"unbound variable"*) ;;
    *)
        echo "SKIP: на этом bash подстановка вплотную к не-ASCII не ломается — вывод: [$bomb_err]"
        echo "  (тест рассчитан на системный /bin/bash 3.2 macOS)"
        exit 0 ;;
esac
if [ "$bomb_size" -ne 0 ]; then
    echo "SKIP: heredoc всё же что-то записал ($bomb_size байт) — предпосылка теста не выполнена"
    exit 0
fi
echo "предпосылка: bash 3.2 молча записал ПУСТОЙ файл, stderr = [$bomb_err]"

# --- 2. Обход обязан назвать эту строку нарушением ---
guard_out="$(bash "$T/hooks/tests/$(basename "$GUARD")" 2>&1)"; guard_rc=$?
if [ "$guard_rc" -eq 0 ]; then
    echo "FAIL [A1]: обход зелен на файле с настоящей бомбой в теле heredoc."
    echo "  файл:    $T/hooks/heredoc_bomb.sh"
    echo "  строка:  # Case ${LAQUO}\$TODAY${RAQUO} — auto-draft   (внутри <<DRAFT, не комментарий)"
    echo "  вердикт обхода:"
    printf '%s\n' "$guard_out" | sed 's|^|    |'
    rc_test=1
else
    echo "PASS [A1]: обход назвал нарушение (rc=$guard_rc)"
fi

echo ""
if [ "$rc_test" -ne 0 ]; then
    echo "adv5 heredoc-comment-shape: КРАСНЫЙ — фильтр комментариев гасит подстановку,"
    echo "  которая на самом деле исполняется, и теряет содержимое файла молча."
fi
exit "$rc_test"
