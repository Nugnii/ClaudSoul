#!/usr/bin/env bash
# test_adv5_scan_coverage_gap.sh — обход не заглядывает в четыре каталога, где живут
# те же скрипты под тем же `set -u`.
#
# test_multibyte_var_boundary.sh:49 перечисляет предмет:
#     for f in "$REPO"/hooks/*.sh "$REPO"/hooks/tests/*.sh "$REPO"/scripts/*.sh
# Ни один из трёх образцов не рекурсивен. Мимо проходят (проверено на живом репозитории,
# все перечисленные файлы существуют и объявляют `set -u`):
#     hooks/lib/*.sh        — backfill-replay-one.sh, backfill-aggregate-digest.sh
#     scripts/ablation/*.sh — journal.sh, checker.sh, phase.sh, shadow-run.sh, snapshot.sh,
#                             pair.sh, env-diff.sh, freeze-policy.sh, dry-run-activator.sh
#     install.sh            — корень репозитория, `set -euo pipefail`
#     bin/*.sh, lib/*.sh    — resolve-claudsoul-repo.sh и прочее
# Итого девять файлов одной только ablation-запускалки, которые обход не открывал ни разу.
#
# Шапка обхода прямо говорит, что предмет — КЛАСС, а не «эти места»: «проверять его надо
# обходом по правилу, а не мутацией по точкам». Правило есть, обход по нему — неполный.
# Живых бомб в этих каталогах сейчас нет; проверка ловит не их, а то, что их появление
# никто не заметит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_multibyte_var_boundary.sh"
LAQUO=$(printf '\302\253'); RAQUO=$(printf '\302\273')
rc_test=0

T="$(mktemp -d)"
mkdir -p "$T/hooks/tests" "$T/hooks/lib" "$T/scripts/ablation" "$T/bin" "$T/lib"
cp "$GUARD" "$T/hooks/tests/"

bomb() {   # $1 — куда положить
    {
        printf '#!/bin/bash\nset -u\nv=x\n'
        printf 'echo "%s$v%s"\n' "$LAQUO" "$RAQUO"
    } > "$1"
}
bomb "$T/hooks/lib/backfill-replay-one.sh"
bomb "$T/scripts/ablation/journal.sh"
bomb "$T/install.sh"
bomb "$T/bin/resolve-claudsoul-repo.sh"
bomb "$T/lib/helper.sh"

# --- 1. Доказать, что заложенное — бомба ---
err="$(/bin/bash "$T/install.sh" 2>&1 >/dev/null)"
case "$err" in
    *"unbound variable"*) echo "предпосылка: bash 3.2 падает на такой строке — [$err]" ;;
    *) echo "SKIP: на этом bash форма не ломается — [$err]"; exit 0 ;;
esac

# --- 2. Обход обязан назвать все пять ---
guard_out="$(bash "$T/hooks/tests/$(basename "$GUARD")" 2>&1)"; guard_rc=$?
missed=""
for p in hooks/lib/backfill-replay-one.sh scripts/ablation/journal.sh install.sh \
         bin/resolve-claudsoul-repo.sh lib/helper.sh; do
    case "$guard_out" in
        *"$p"*) ;;
        *) missed="$missed $p" ;;
    esac
done

if [ -n "$missed" ]; then
    echo "FAIL [A4]: обход (rc=$guard_rc) не открыл файлы:$missed"
    echo "  вердикт обхода:"
    printf '%s\n' "$guard_out" | sed 's|^|    |'
    rc_test=1
else
    echo "PASS [A4]: обход назвал все пять"
fi

echo ""
if [ "$rc_test" -ne 0 ]; then
    echo "adv5 scan-coverage-gap: КРАСНЫЙ — правило обходит три образца из шести каталогов,"
    echo "  остальные скрипты под set -u не проверялись ни разу."
fi
exit "$rc_test"
