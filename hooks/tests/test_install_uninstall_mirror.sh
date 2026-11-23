#!/usr/bin/env bash
# СУДИТ: install.sh uninstall.sh
# test_install_uninstall_mirror.sh — сниматель снимает ровно то, что ставит установщик.
#
# Результат: множество источников копирования в install.sh и множество источников сверки
#            в uninstall.sh совпадают, кроме явно названных исключений
# Проверка результата: bash hooks/tests/test_install_uninstall_mirror.sh даёт 0
#
# Повод (род F, 6 сентября 2026). Оба файла держат СВОЙ перечень путей, и разойтись они
# могут молча: ни один страж их не сверял — `drift-check` знает 9 пар «репозиторий ↔
# установленное», а пары «установщик ↔ сниматель» среди них нет, uninstall в нём лишь
# упомянут комментарием. Первый же прогон этой сверки нашёл расхождение: install ставит
# `templates/*.tmpl`, uninstall снимал `templates/*` — то есть шире, чем ставили. Не-.tmpl
# файлов в templates/ сейчас 0, поэтому дефект был латентным и ждал первого такого файла.
#
# ОБЛАСТЬ: только источники в `"$CLAUDSOUL_DIR"/…`. Пути назначения (`$CLAUDE_HOME/…`) не
# сверяются: у снимателя они те же по построению, а у установщика есть шаги без пары
# (слияние настроек, правка проектного CLAUDE.md) — их отсутствие у снимателя законно.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# ИСКЛЮЧЕНИЕ, названное с основанием: база знаний не удаляется НИКОГДА (правило проекта,
# оно же в drift-check.sh:235). Установщик её ставит, сниматель обязан не трогать.
EXCEPT='knowledge/'

sources() {  # $1 — файл; печатает пути-источники, по одному на строку
    grep -oE '"\$CLAUDSOUL_DIR"/[a-zA-Z0-9_/.-]+\*?[a-zA-Z0-9_.]*' "$1" \
        | sed 's|"\$CLAUDSOUL_DIR"/||' | sort -u
}

INS=$(sources "$ROOT/install.sh")
UNI=$(sources "$ROOT/uninstall.sh")

# Положительный контроль: без него пустой вывод grep дал бы зелень на обоих пустых
# множествах — «сверено 0 путей» неотличимо от «расхождений нет» (род B).
if [ "$(printf '%s\n' "$INS" | grep -c .)" -ge 3 ] && [ "$(printf '%s\n' "$UNI" | grep -c .)" -ge 3 ]; then
    ok
else
    bad "T0" "перечни не извлеклись: install $(printf '%s\n' "$INS" | grep -c .), uninstall $(printf '%s\n' "$UNI" | grep -c .)"
    echo "install/uninstall mirror: $PASS passed, $FAIL failed"
    exit $(( FAIL != 0 ))
fi

# T1: всё, что ставит установщик, снимается — кроме названного исключения.
MISSING=""
while IFS= read -r src; do
    [ -n "$src" ] || continue
    case "$src" in $EXCEPT*) continue ;; esac
    grep -qxF "$src" <<< "$UNI" || MISSING="$MISSING $src"
done <<< "$INS"
[ -z "$MISSING" ] && ok || bad "T1" "установщик ставит, а сниматель не снимает:$MISSING"

# T2: сниматель не шире установщика — иначе снимаем то, чего не ставили.
EXTRA=""
while IFS= read -r src; do
    [ -n "$src" ] || continue
    grep -qxF "$src" <<< "$INS" || EXTRA="$EXTRA $src"
done <<< "$UNI"
[ -z "$EXTRA" ] && ok || bad "T2" "сниматель снимает то, чего установщик не ставит:$EXTRA"

# T3: исключение действительно исключение — база знаний у снимателя отсутствует.
grep -q "^$EXCEPT" <<< "$UNI" \
    && bad "T3" "база знаний попала в перечень снимателя — она не удаляется никогда" || ok

echo "install/uninstall mirror: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
