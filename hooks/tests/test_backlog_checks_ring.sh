#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backlog_item_shape.sh
# test_backlog_checks_ring.sh — свидетель формы пунктов, позванный из «Проверки», не зовёт исполнителя «Проверок» на живом бэклоге (D502).
#
# Результат: во вложенном прогоне (маркер BACKLOG_CHECKS_NESTED=1 унаследован от исполнителя
#            «Проверок») свидетель формы не зовёт ни архиватор, ни страж возврата и называет
#            пропуск ноги T6; в прямом прогоне зовёт обоих — положительный контроль рамки.
# Проверка результата: bash hooks/tests/test_backlog_checks_ring.sh даёт 0
#
# Повод (1 октября 2026). «Проверка» закрытого D499 звала свидетеля формы, а его нога T6 —
# архиватор `check` на ЖИВОМ бэклоге, сняв перед этим маркер вложенности (D334). Архиватор
# исполнял «Проверку» D499 снова: кольцо «архиватор → D499 → свидетель → архиватор» без дна.
# Тайм-ауты убивали прямого потомка, внуки продолжали сиротами: 298 процессов, нагрузка 41–69.
#
# Песочница: копия свидетеля и библиотеки, архиватор и страж возврата — заглушки, пишущие свой
# вызов в журнал. Вердикт самого свидетеля здесь не предмет: бэклог песочницы минимален.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJ="$REPO/hooks/tests/test_backlog_item_shape.sh"
[ -f "$SUBJ" ] || { echo "FAIL: нет $SUBJ"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hooks/tests" "$T/hooks/lib" "$T/scripts"
cp "$SUBJ" "$T/hooks/tests/"
cp "$REPO/hooks/backlog-lib.sh" "$T/hooks/"
cp "$REPO/hooks/lib/universe-lib.sh" "$T/hooks/lib/" 2>/dev/null || true
for s in backlog-archive.sh backlog-return-check.sh; do
    printf '#!/usr/bin/env bash\necho "%s" >> "%s/calls"\necho "В BACKLOG.md выполненных пунктов: 0 (открытых: 1)"\n' "$s" "$T" > "$T/scripts/$s"
done
printf -- '- ☐ **D9001** проба\n  **Проверка.** `false` → 0\n' > "$T/BACKLOG.md"

# T1: вложенный прогон — заглушки молчат, пропуск T6 назван.
rm -f "$T/calls"
OUT=$(BACKLOG_CHECKS_NESTED=1 bash "$T/hooks/tests/test_backlog_item_shape.sh" 2>&1)
[ ! -s "$T/calls" ] && ok || bad T1 "во вложенном прогоне позваны: $(tr '\n' ' ' < "$T/calls") — кольцо через живой бэклог открыто"
case "$OUT" in *"SKIP [T6]"*) ok ;; *) bad T1b "пропуск ноги T6 не назван — молчаливый пропуск неотличим от «проверено»" ;; esac

# T2: прямой прогон — заглушки позваны. Без этого T1 зеленел бы и от рамки, не дошедшей до T6.
rm -f "$T/calls"
env -u BACKLOG_CHECKS_NESTED bash "$T/hooks/tests/test_backlog_item_shape.sh" >/dev/null 2>&1 || true  # вложенный свидетель с заглушками краснеет — предмет: вызовы заглушек читают строки ниже (D1261)
grep -q 'backlog-archive.sh' "$T/calls" 2>/dev/null && ok || bad T2 "в прямом прогоне архиватор не позван — рамка песочницы не дошла до ноги T6"
grep -q 'backlog-return-check.sh' "$T/calls" 2>/dev/null && ok || bad T2b "в прямом прогоне страж возврата не позван"

echo "backlog checks ring: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
