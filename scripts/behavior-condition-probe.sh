#!/usr/bin/env bash
# behavior-condition-probe.sh — у свидетеля-атаки условие явления СОЗДАЁТСЯ, а не предполагается.
# en: probes adversarial witnesses by gutting their subject; an honest leg must redden.
#
# Результат: у каждого свидетеля-атаки (hooks/tests/test_adv*.sh) предмет назван так, что
#            разрешим механически, и прогон против ВЫХОЛОЩЕННОГО предмета краснеет;
#            ложно-зелёных ноль, неразрешимых ноль.
# Проверка результата: bash hooks/tests/test_behavior_condition_probe.sh даёт 0 — прибор
#            краснеет на подложенном ложно-зелёном свидетеле и молчит на честном.
#
# Зачем (D342). Восемь заходов искали ТЕКСТОВЫЙ признак «условие не создаётся», и все восемь
# отвергнуты числом: полнота и точность ниже порога реестра, а у одного устройства признак
# невозможен по построению — расхождение лежит СНАРУЖИ ноги. Девятый заход поведенческий:
# предмет выхолащивается, и честная нога обязана покраснеть. Прежняя проверка пункта судила
# ИМЯ ФАЙЛА (перечисление hooks по шаблону имени) — заглушка с таким именем её зеленила, что
# пункт и признавал меткой о суждении по форме.
#
# УСЛОВИЕ СОЗДАЁТСЯ ПО РОЛИ ПРЕДМЕТА, и это не мелочь, а тот самый класс. Источаемую
# библиотеку выхолащивает ПУСТОЙ файл: заглушка с немедленным выходом внутри source убивает
# вызывающего, и тест выходит нулём, не дойдя до своей итоговой строки — ложно-зелёный,
# порождённый самим зондом. Замер 14 сентября 2026: заглушка без различения роли дала три
# ложно-зелёных из восьми, все три — артефакт зонда; с различением роли — ноль из восьми.
#
# НАЗВАННЫЙ ПРЕДЕЛ: предмет разрешим у 8 свидетелей из 204 — тех, кто зовёт механизм дерева
# через переменную корня либо объявляет его переменной с суффиксом SRC. Остальные 196 предмет
# не называют, и для них зонд неисполним: это и есть нынешняя открытая часть D342, а не дефект
# прибора. Положительный контроль устройства измерен отдельно: четыре свидетеля, названные в
# пункте поимённо, краснеют на выхолощенном предмете — 4 из 4.
# Условие снятия: свидетель-атака объявляет свой предмет так же, как это делают восемь
# разрешимых (вызов через переменную корня либо переменная с суффиксом SRC) — тогда зонд
# станет исполним на всём универсуме, и предел исчезнет сам.
#
# Код возврата: 0 — ложно-зелёных нет И неразрешимых нет; 1 — есть те или другие;
#               2 — прибор сломан (нет свидетелей, снимок дерева не собрался).
set -uo pipefail

_self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
REPO="${CLAUDSOUL_REPO:-$(cd -- "$_self/.." 2>/dev/null && pwd -P)}"
cd "$REPO" 2>/dev/null || { echo "BROKEN: корень не разрешён"; exit 2; }

PAIRS=$(python3 - "$REPO" <<'PY'
import re, glob, os, sys
os.chdir(sys.argv[1])
total = 0
for f in sorted(glob.glob("hooks/tests/test_adv*.sh")):
    total += 1
    text = open(f, encoding="utf-8", errors="ignore").read()
    code = "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))
    # Класс записан без обратного слеша внутри скобок намеренно: признак
    # non_ascii_adjacent_to_shell_syntax ловит POSIX-класс с перловым escape и не отличает
    # питоновский heredoc от оболочки — ложное срабатывание 14 сентября 2026, обход дешевле спора.
    call = r'(?:bash|source|\.)[ \t]+"?\$\{?(?:REPO|HOOKS|HOOK_DIR|CLAUDSOUL_REPO)\}?[^" \t]*?/'
    unit = r'((?:hooks|scripts)/[A-Za-z0-9_.-]+\.(?:sh|py))'
    c = set(re.findall(call + unit, code))
    c |= set(re.findall(r'_SRC="\$\{?REPO\}?/' + unit, code))
    if len(c) == 1:
        print(f + "\t" + list(c)[0])
print("#TOTAL\t%d" % total)
PY
) || { echo "BROKEN: разбор свидетелей не удался"; exit 2; }

TOTAL=$(printf '%s\n' "$PAIRS" | sed -n 's/^#TOTAL\t//p')
PAIRS=$(printf '%s\n' "$PAIRS" | grep -v '^#TOTAL')
[ -n "${TOTAL:-}" ] && [ "$TOTAL" -gt 0 ] || { echo "BROKEN: свидетелей-атак не найдено"; exit 2; }

SNAP=$(mktemp -d) || { echo "BROKEN: нет временного каталога"; exit 2; }
trap 'rm -rf "$SNAP"' EXIT
git archive HEAD 2>/dev/null | tar -x -C "$SNAP" 2>/dev/null \
    || { echo "BROKEN: снимок дерева не собрался"; exit 2; }

RESOLVED=0
VACUOUS=0
NAMES=""
while IFS=$'\t' read -r t subj; do
    [ -n "${t:-}" ] && [ -n "${subj:-}" ] || continue
    RESOLVED=$((RESOLVED + 1))
    (
        cd "$SNAP" || exit 9
        cp "$subj" "$subj.keep" 2>/dev/null || exit 9
        base=$(basename "$subj")
        if grep -qE '^[[:space:]]*(\.|source) .*'"$base" "$t" 2>/dev/null; then
            : > "$subj"
        else
            printf '#!/usr/bin/env bash\nexit 0\n' > "$subj"
        fi
        bash "$t" >/dev/null 2>&1
        rc=$?
        mv "$subj.keep" "$subj" 2>/dev/null
        exit "$rc"
    )
    rc=$?
    if [ "$rc" -eq 9 ]; then
        echo "BROKEN: предмет $subj недоступен в снимке"
        exit 2
    elif [ "$rc" -eq 0 ]; then
        VACUOUS=$((VACUOUS + 1))
        NAMES="${NAMES}${NAMES:+ }$(basename "$t")"
    fi
done <<< "$PAIRS"

UNRESOLVED=$((TOTAL - RESOLVED))
echo "свидетелей-атак: $TOTAL; предмет разрешим: $RESOLVED; ложно-зелёных: $VACUOUS; предмет не назван: $UNRESOLVED"
[ "$VACUOUS" -eq 0 ] || echo "  ложно-зелёные: $NAMES"
[ "$VACUOUS" -eq 0 ] && [ "$UNRESOLVED" -eq 0 ]
