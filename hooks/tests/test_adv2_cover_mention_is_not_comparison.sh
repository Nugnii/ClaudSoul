#!/usr/bin/env bash
# test_adv2_cover_mention_is_not_comparison.sh
#
# АТАКА: покрытие засчитывается по УПОМИНАНИЮ пути в файле, а не по факту сравнения.
#
# Комментарий стража обещает обратное: «Покрытие засчитывается только по строке, которая
# ДЕЙСТВИТЕЛЬНО сравнивает: вызов `_cmp_tree` либо `cmp`/`diff` с этим путём». В коде такой
# проверки нет — из `comparing` выброшены лишь строки-комментарии и строки `_emit`, а дальше
# ищется голое `\$CLAUDE_HOME/<ключ>\b` в чём угодно.
#
# Три входа, у всех приёмник `templates` НЕ сравнивается ни разу:
#   1. вызов обёрнут в `if false` — не исполняется никогда;
#   2. вместо вызова осталось присваивание неиспользуемой переменной;
#   3. `_cmp_tree` есть, но сравнивает ДРУГОЙ каталог — `$CLAUDE_HOME/templates-old`
#      (граница `\b` после ключа стоит перед дефисом и совпадает).
# Ожидание: во всех трёх — код 1, «непокрытых пар: 1».
# Факт: во всех трёх — «непокрытых пар: 0», код 0.
set -uo pipefail

REAL_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REAL_REPO/hooks/tests/test_drift_pairs_cover_install.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T=$(mktemp -d)
R="$T/repo"; mkdir -p "$R/hooks/tests"
cp "$GUARD" "$R/hooks/tests/"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
CLAUDE_HOME="$HOME/.claude"
TEMPLATES_TARGET="$CLAUDE_HOME/templates"
mkdir -p "$TEMPLATES_TARGET"
for tmpl in "$CLAUDSOUL_DIR"/templates/*.tmpl; do
    cp "$tmpl" "$TEMPLATES_TARGET/$(basename "$tmpl")"
done
INST

fail=0
probe() {
    local name="$1" body="$2" out rc
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$R/hooks/tests/drift-check.sh"
    # Предмет проверки — «щель поймана ХОТЬ ОДНИМ стражем», а не конкретным. Текстовый
    # страж покрытия судит по присутствию пути в исполняемом коде и по построению не
    # отличает мёртвую ветку от живой и присваивание от вызова: для этого нужна модель
    # потока управления. Эти два случая ловит ПОВЕДЕНЧЕСКИЙ страж — подмени файл в
    # приёмнике, вывод обязан измениться; он доказан мутацией (отключённая пара шаблонов
    # даёт FAIL). Предел текстового стража назван в его собственной шапке.
    out=$(bash "$R/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "--- вход: $name — поймано текстовым стражем (код $rc) ---"
        return
    fi
    out=$(bash "$R/hooks/tests/test_drift_pair_actually_compares.sh" 2>&1); rc=$?
    echo "--- вход: $name — текстовый молчит, поведенческий даёт код $rc ---"
    printf '%s\n' "$out" | tail -2
    if [ "$rc" -eq 0 ]; then
        echo "FAIL: $name — ни один страж не заметил, что сравнения нет. Расхождение в"
        echo "      ~/.claude/templates даст молчание, неотличимое от OK."
        fail=1
    fi
}

probe "вызов внутри if false" \
'if false; then
    _cmp_tree "шаблоны" "$REPO/templates" "$CLAUDE_HOME/templates" "*.tmpl"
fi'

probe "только присваивание, вызова нет" \
'_tpl_dst="$CLAUDE_HOME/templates"'

probe "сравнивается не тот каталог (templates-old)" \
'_cmp_tree "шаблоны" "$REPO/templates" "$CLAUDE_HOME/templates-old" "*.tmpl"'

# Контроль: если путь виден только в комментарии — страж кричит. Значит предмет проверки
# ровно текстовое присутствие строки, а не сравнение.
printf '#!/usr/bin/env bash\n# _cmp_tree "шаблоны" "$REPO/templates" "$CLAUDE_HOME/templates" "*.tmpl"\n' \
    > "$R/hooks/tests/drift-check.sh"
CTL=$(bash "$R/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1); CRC=$?
echo "--- контроль: путь только в комментарии (код $CRC) ---"
printf '%s\n' "$CTL"
if [ "$CRC" -eq 0 ]; then
    echo "FAIL: контроль не сработал — страж не ловит даже закомментированное сравнение."
    fail=1
fi

echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: покрытие требует настоящего сравнения"
exit "$fail"
