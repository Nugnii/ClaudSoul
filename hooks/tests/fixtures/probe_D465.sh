#!/usr/bin/env bash
# probe_D465.sh — проба пункта D465: в свидетелях есть подготовительные вызовы, чей отказ
#                 не говорит ничем — код не читается, вывод выброшен, — и свидетель
#                 продолжает работу на несобранной фикстуре.
# Результат: реестр `scripts/setup-call-guard.py` не называет ни одного носителя в дереве.
# Проверка результата: bash hooks/tests/fixtures/probe_D465.sh даёт 0
#
# Коды: 0 — носителей нет; 1 — носители есть (дефект); 2 — рамка не собралась.
#
# СУДИТСЯ МИР, А НЕ ФОРМА ОТЧЁТА, и различающая способность реестра доказывается ЗДЕСЬ, до
# суда: в песочнице строятся два свидетеля — у одного подготовительный вызов без стража,
# у другого тот же вызов со стражем. Реестр обязан назвать первого и не назвать второго.
# Без этих двух контролей «носителей 0» на живом дереве было бы неотличимо от выпотрошенного
# реестра (тот же класс, что пункт и описывает).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
TOOL="$MECH/scripts/setup-call-guard.py"
[ -f "$TOOL" ] || { echo "probe_D465: нет $TOOL" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D465: нет python3" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D465: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bad/hooks/tests" "$T/good/hooks/tests" || { echo "probe_D465: песочница не собралась" >&2; exit 2; }
# Носитель: вызов строит мир проверки, код не читается, вывод выброшен.
printf '#!/usr/bin/env bash\nd=$(mktemp -d)\ncp /etc/hosts "$d/x" 2>/dev/null\necho ok\n' > "$T/bad/hooks/tests/test_x.sh"
# Не носитель: тот же вызов, но отказ читается и говорит.
printf '#!/usr/bin/env bash\nd=$(mktemp -d)\ncp /etc/hosts "$d/x" 2>/dev/null || { echo "подготовка не удалась" >&2; exit 1; }\necho ok\n' > "$T/good/hooks/tests/test_x.sh"

N_BAD=$(python3 "$TOOL" --root "$T/bad" --count 2>/dev/null); RC_BAD=$?
N_GOOD=$(python3 "$TOOL" --root "$T/good" --count 2>/dev/null); RC_GOOD=$?
[ "$N_BAD" = 1 ] && [ "$RC_BAD" = 1 ] \
    || { echo "probe_D465: контроль — реестр не назвал заведомого носителя (носителей $N_BAD, rc=$RC_BAD)" >&2; exit 2; }
[ "$N_GOOD" = 0 ] && [ "$RC_GOOD" = 0 ] \
    || { echo "probe_D465: контроль — реестр назвал носителем вызов СО стражем (носителей $N_GOOD, rc=$RC_GOOD)" >&2; exit 2; }

# КОНТРОЛЬ 3 — ПОВЕДЕНИЕ СТРАЖА, а не его наличие. Реестр судит форму вызова; сама по себе
# форма ничего не доказывала бы, поэтому здесь проверяется, что она РАБОТАЕТ: свидетель с
# упавшей подготовкой обязан покраснеть со стражем и остаться зелёным без него. Без этого
# «носителей 0» говорило бы лишь «слово стоит», и закрытие пункта было бы слепым.
mkdir -p "$T/beh" || { echo "probe_D465: песочница поведения не собралась" >&2; exit 2; }
printf '#!/usr/bin/env bash\nfalse 2>/dev/null\necho ok\n' > "$T/beh/silent.sh"
printf '#!/usr/bin/env bash\nfalse 2>/dev/null || { echo "подготовка мира не удалась" >&2; exit 1; }\necho ok\n' > "$T/beh/loud.sh"
bash "$T/beh/silent.sh" >/dev/null 2>&1; RC_SILENT=$?
bash "$T/beh/loud.sh" >/dev/null 2>&1; RC_LOUD=$?
[ "$RC_SILENT" = 0 ] || { echo "probe_D465: контроль — свидетель БЕЗ стража должен был промолчать (rc=$RC_SILENT)" >&2; exit 2; }
[ "$RC_LOUD" != 0 ] || { echo "probe_D465: контроль — страж не сделал отказ слышимым: свидетель зелен (rc=$RC_LOUD)" >&2; exit 2; }

# Суд: живое дерево механизма.
OUT=$(python3 "$TOOL" --root "$MECH" 2>"$T/err"); RC=$?
if [ "$RC" = 2 ]; then
    echo "probe_D465: рамка — реестр не смог судить дерево: $(head -1 "$T/err")" >&2; exit 2
fi
N=$(python3 "$TOOL" --root "$MECH" --count 2>/dev/null)
if [ "$RC" != 0 ]; then
    echo "probe_D465: дефект — подготовительных вызовов без стража: $N; первый: $(head -1 <<< "$OUT")" >&2
    exit 1
fi
exit 0
