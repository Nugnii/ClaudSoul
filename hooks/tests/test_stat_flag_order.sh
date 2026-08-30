#!/usr/bin/env bash
# test_stat_flag_order.sh — GNU-форма `stat -c` обязана стоять ПЕРЕД BSD-формой `stat -f`.
#
# Асимметрия, из-за которой порядок не безразличен. На macOS `stat -c` не существует и
# честно падает с ненулевым кодом — фоллбек наступает. На Linux `stat -f %m FILE` не падает:
# `-f` там означает «сведения о файловой системе», `%m` читается как имя файла, и команда
# печатает в stdout справку вида «File: "..." ID: ... Type: overlayfs», возвращая КОД 0.
# Оператор `||` не срабатывает, потому что провала не было, и в переменную уезжает
# многострочный текст. Дальше он раскрывается как имя переменной и роняет вызывающего
# под `set -u`.
#
# Повод (2026-08-26). Ровно так `timestamp-canary-check.sh` падал в CI пять дней:
# «line 114: File: unbound variable», 10 тестов из 20 красные. На машине автора дефект
# невидим по построению — там первая форма отрабатывает и до второй дело не доходит.
# Второе вхождение нашлось тем же обходом в `scripts/ab-authorization-replay.sh`.
#
# Канон — `file_mtime` в `hooks/portable-lib.sh`, где порядок правильный. Этот тест
# сторожит не сам канон, а то, что его нигде не переизобрели наоборот.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(basename "$0")"
PASS=0
FAIL=0

# Ищем строки, где BSD-форма встречается РАНЬШЕ GNU-формы в одном выражении.
scan() {
    LC_ALL=C grep -nE 'stat -f [^|]*\|\|[^|]*stat -c' "$1" 2>/dev/null | sed "s|^|$1:|"
}

HITS=""
while IFS= read -r f; do
    case "$(basename "$f")" in "$SELF") continue ;; esac
    found="$(scan "$f")"
    [ -n "$found" ] && HITS="$HITS$found
"
done <<EOF
$(find "$REPO" -name '*.sh' -not -path '*/.git/*' -not -path '*/.venv/*' | sort)
EOF

if [ -n "$(printf '%s' "$HITS" | tr -d '[:space:]')" ]; then
    echo "FAIL [T1]: BSD-форма stat стоит перед GNU-формой —"
    echo "  на Linux первая вернёт код 0 со справкой о ФС, и фоллбек не наступит."
    printf '%s' "$HITS" | sed 's|^|  |'
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

# Правило обязано краснеть на заведомом нарушении.
TMPD="$(mktemp -d)"
printf '#!/bin/bash\nm=$(stat -f %%m "$1" 2>/dev/null || stat -c %%Y "$1" 2>/dev/null)\n' > "$TMPD/bad.sh"
if [ -n "$(scan "$TMPD/bad.sh")" ]; then PASS=$((PASS + 1))
else echo "FAIL [T2]: правило не увидело обратный порядок — проверка вхолостую"; FAIL=$((FAIL + 1)); fi

# И молчать на верном.
printf '#!/bin/bash\nm=$(stat -c %%Y "$1" 2>/dev/null || stat -f %%m "$1" 2>/dev/null)\n' > "$TMPD/good.sh"
if [ -z "$(scan "$TMPD/good.sh")" ]; then PASS=$((PASS + 1))
else echo "FAIL [T3]: ложная тревога на верном порядке"; FAIL=$((FAIL + 1)); fi

echo ""
echo "stat flag order: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
