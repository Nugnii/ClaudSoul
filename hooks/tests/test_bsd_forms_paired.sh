#!/usr/bin/env bash
# test_bsd_forms_paired.sh — BSD-форма в коде хука стоит только в паре с GNU-формой на той же строке.
#
# Результат: ни в одном исполняемом файле hooks/*.sh и scripts/*.sh нет строки кода, где
#            BSD-only форма (`stat -f`, `date -j`, `tail -r`) стоит без своей GNU-пары
#            (`stat -c`, `date -d`, `tac`) на той же строке или в трёх строках кода выше
# Проверка результата: bash hooks/tests/test_bsd_forms_paired.sh даёт 0
#
# Повод (D213, 30 августа 2026). Инвариант держал сигнал `bsd_only_command_in_hook` в
# `pattern-shell-portability` — отказ на Edit/Write в hooks|scripts с BSD-формой в тексте.
# Первый прогон `dead-sensor`: ноль срабатываний за 40 сессий. Реплей по 33 расшифровкам:
# 14 правок с такими формами прошли мимо отказа, ещё 39 шли через Bash (heredoc, python,
# sed -i), куда сигнал не смотрит, — то есть он был мёртв по построению. И хуже: в дереве
# 10 файлов несут BSD-формы ПАРОЙ с GNU (`stat -c … || stat -f …`), и сработавший сигнал
# отказал бы на переносимом коде — тот же класс, что 40 отказов / 32 ложных у первой редакции.
# Проверка по ДЕРЕВУ видит результат любой правки, каким бы инструментом её ни сделали.
#
# КОНТРПРИМЕРЫ, проверяются ниже:
#   · пара на одной строке — не нарушение (это и есть переносимость);
#   · комментарий с формой — не нарушение (строка не исполняется);
#   · фикстура с формой без пары — нарушение, тест краснеет (мутация).
# Названный предел: `#` внутри строки-литерала считается началом комментария не будет —
# проверяется только первый непробельный символ строки; `compgen -G` в перечень не входит,
# это встроенная bash, а не различие BSD/GNU (в коде дерева не используется, только в комментариях).
# Условие снятия: появится разбор строки оболочки (кавычки, heredoc — как в command-scope-lib),
# и проверка сможет отличать литерал от кода; тогда правило «первый непробельный символ» уйдёт.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

# check_tree <каталог...> → печатает нарушения «файл:строка», код 1 при наличии
check_tree() {
    _bad=0
    for f in "$@"; do
        [ -f "$f" ] || continue
        # Строки кода: первый непробельный символ не `#`.
        # Пара ищется на той же строке ЛИБО в трёх предыдущих строках кода: так устроены
        # цепочки запасных ветвей в дереве (`stat -c … && return` строкой выше `stat -f`).
        awk -v F="$f" '
            /^[[:space:]]*#/ { next }
            {
                line = $0
                win = p1 "\n" p2 "\n" p3 "\n" line
                if (line ~ /stat -f / && win !~ /stat -c/) { print F ":" NR ": stat -f без stat -c"; bad = 1 }
                if (line ~ /date (-u )?-j/ && win !~ /date (-u )?-d/) { print F ":" NR ": date -j без date -d"; bad = 1 }
                if (line ~ /tail -r/ && win !~ /(^|[^a-z])tac([^a-z]|$)/) { print F ":" NR ": tail -r без tac"; bad = 1 }
                p3 = p2; p2 = p1; p1 = line
            }
            END { exit bad }
        ' "$f" || _bad=1
    done
    return $_bad
}

# --- T1: дерево чистое ---
OUT=$(check_tree "$ROOT"/hooks/*.sh "$ROOT"/scripts/*.sh 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: BSD-формы без GNU-пары:"; printf '%s\n' "$OUT"; fi

# --- T2: КОНТРПРИМЕР — пара на одной строке и комментарий не считаются ---
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ok.sh" <<'SH'
#!/usr/bin/env bash
# здесь stat -f упомянут в комментарии
m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
e=$(date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || echo 0)
r=$(tac "$1" 2>/dev/null || tail -r "$1" 2>/dev/null || true)
SH
check_tree "$TMP/ok.sh" >/dev/null 2>&1 && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2]: пара на одной строке принята за нарушение"; }

# --- T3: мутация — форма без пары краснеет ---
cat > "$TMP/bad.sh" <<'SH'
#!/usr/bin/env bash
m=$(stat -f %m "$1")
SH
if ! check_tree "$TMP/bad.sh" >/dev/null 2>&1; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: stat -f без пары не замечен — тест ничего не держит"; fi

echo "bsd forms paired: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
