#!/usr/bin/env bash
# test_multibyte_var_boundary.sh — подстановка вплотную к не-ASCII обязана быть в скобках.
#
# bash 3.2 (системный на macOS) при разборе `"$var»"` включает первый байт кавычки-ёлочки
# (\xc2) в ИМЯ переменной и ищет `var\xc2`. Под `set -u` это не косметика: оболочка выходит
# с «unbound variable» посреди работы. Строка обычно лежит на редком пути — в ветке FAIL, —
# поэтому дефект спит, пока проверка зелёная, и просыпается ровно тогда, когда она должна
# назвать нарушение. Падение с ошибкой неотличимо от отсутствия проверки.
#
# ПРАВИЛО НАМЕРЕННО БЕЗУСЛОВНОЕ. Первая версия пыталась отличать код от не-кода: гасила
# строки, начатые с `#`, и вырезала экранированный доллар. Противник снял это за один
# заход с четырёх сторон — `#` внутри heredoc не комментарий (bash там подставляет и,
# найдя пустое имя, пишет пустой файл с кодом 0); комментарий в конце строки не в начале;
# `sed` по `\$` съедал правую пару в `"\$v»"` и стирал настоящую бомбу; а обход трёх
# нерекурсивных образцов не открывал ни install.sh, ни hooks/lib/, ни scripts/ablation/.
#
# Цепочка «почему» на этом сходится в третий раз к одному: предмет назывался «текст, в
# котором надо отличить комментарий от кода», а является СИНТАКСИСОМ ОБОЛОЧКИ, и разбирать
# его эвристиками — то же, что проверять парсер списком примеров. Верный ход не пятая
# эвристика, а снятие вопроса: `${var}` корректно ВЕЗДЕ — в коде, в комментарии, в heredoc.
# Правилу больше не нужно знать контекст, потому что починка от контекста не зависит.
#
# Единственное исключение — строка, которая дефект ДЕМОНСТРИРУЕТ (описание в шапке,
# фикстура теста). Она помечается автором явно: `mb-ok` в той же строке. Явная пометка
# вместо угадывания: список того, что автор считает данными, не выводится из текста.
#
# Обход идёт по ВСЕМУ дереву, а не по трём образцам: `install.sh`, `bin/`, `lib/`,
# `hooks/lib/`, `scripts/ablation/` объявляют `set -u` ровно так же.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(basename "$0")"
PASS=0
FAIL=0

# LC_ALL=C обязателен: только под ним `[^ -~]` означает БАЙТ, а не символ, и первый байт
# многобайтовой кавычки в класс попадает. `grep -P` в BSD grep отсутствует — только ERE.
scan() {
    LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$1" 2>/dev/null \
        | grep -v 'mb-ok' \
        | sed "s|^|$1:|"
}

HITS=""
while IFS= read -r f; do
    case "$(basename "$f")" in "$SELF") continue ;; esac
    found="$(scan "$f")"
    [ -n "$found" ] && HITS="$HITS$found
"
done <<EOF
$(find "$REPO" -name '*.sh' -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/__pycache__/*' | sort)
EOF

if [ -n "$(printf '%s' "$HITS" | tr -d '[:space:]')" ]; then
    echo "FAIL [T1]: подстановка вплотную к не-ASCII без фигурных скобок —"
    echo "  bash 3.2 включит первый байт символа в имя переменной и выйдет по set -u."
    echo "  Починка: \${имя}. Если строка ДЕМОНСТРИРУЕТ дефект — пометь её 'mb-ok'."
    printf '%s' "$HITS" | sed 's|^|  |'
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

# Правило обязано КРАСНЕТЬ — иначе зелёный ничего не значит. Три формы, которые прошлая
# версия пропускала: тело heredoc, комментарий в конце строки, экранированный доллар рядом.
TMPD="$(mktemp -d)"
{
    printf '#!/usr/bin/env bash\n'
    printf 'cat > /dev/null <<DRAFT\n# Case «$TODAY» — draft\nDRAFT\n'
} > "$TMPD/heredoc.sh"
printf '#!/usr/bin/env bash\nv=1\necho ok  # разбор «$v» тут\n' > "$TMPD/trailing.sh"
printf '#!/usr/bin/env bash\nv=1\necho "\\$v»"\n' > "$TMPD/escaped.sh"
MUT_FAIL=0
for m in heredoc trailing escaped; do
    if [ -z "$(scan "$TMPD/$m.sh")" ]; then
        echo "FAIL [T2/$m]: правило не увидело нарушение — проверка проходит вхолостую"
        MUT_FAIL=1
    fi
done
[ "$MUT_FAIL" -eq 0 ] && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# И обязано МОЛЧАТЬ на законном коде и на явно помеченной демонстрации.
printf '#!/usr/bin/env bash\nv=1\necho "видим «${v}» тут"\necho "«$v»"  # mb-ok: демонстрация\n' > "$TMPD/good.sh"
if [ -z "$(scan "$TMPD/good.sh")" ]; then
    PASS=$((PASS + 1))
else
    echo "FAIL [T3]: ложное срабатывание на законном коде:"
    scan "$TMPD/good.sh" | sed 's|^|  |'
    FAIL=$((FAIL + 1))
fi

# Покрытие: обход обязан открывать всё дерево, а не три образца.
COVER_MISS=""
for rel in install.sh bin/resolve-claudsoul-repo.sh lib/claude-md-merge.sh; do
    [ -f "$REPO/$rel" ] || continue
    # Без трубы: `printf | grep -q` под `set -o pipefail` даёт ненулевой статус из-за
    # SIGPIPE у printf, и проверка врёт (test_assert_no_sigpipe.sh сторожит этот приём).
    # Поймано на себе: T4 объявлял непокрытыми файлы, которые обход открывает.
    [ -n "$(find "$REPO" -path "$REPO/$rel" -name '*.sh')" ] \
        || COVER_MISS="$COVER_MISS $rel"
done
if [ -z "$COVER_MISS" ]; then
    PASS=$((PASS + 1))
else
    echo "FAIL [T4]: обход не покрывает:$COVER_MISS"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "multibyte var boundary: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
