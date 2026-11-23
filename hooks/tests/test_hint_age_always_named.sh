#!/usr/bin/env bash
# test_hint_age_always_named.sh — возраст снимка называется при ЛЮБОМ его возрасте.
#
# Результат: читатель подсказки видит, когда она собрана, и не принимает старое за нынешнее
# Проверка результата: bash hooks/tests/test_hint_age_always_named.sh даёт 0
#
# Повод (6 сентября 2026). Порог `HINT_AGE -ge 1` считал возраст в ДНЯХ, поэтому снимок
# двухчасовой давности подавался молча — как нынешнее состояние. Замер того же дня:
# подсказка возрастом 2,6 ч несла два утверждения, из них ОДНО устарело («1 инвариант
# закрытых пунктов перестал держаться» при прогоне backlog-recheck.sh, дающем 0), второе
# осталось верным (три просроченных замера). Ход начался с работы по несуществующему поводу.
#
# Класс уже разбирался как D84 — тогда снимок был трёхдневным, и порог в сутках его ловил.
# Щель осталась ровно шириной в рабочий день, а состояние активной сессии меняется за минуты:
# единица измерения возраста обязана быть соразмерна ТЕМПУ предмета
# (pattern-calendar-window-lies-under-bursty-work-rhythm).
#
# ОБЛАСТЬ: только наличие строки возраста. Точность формулировки не проверяется — важно,
# что читатель не может принять снимок за нынешний, а не то, сказано «3 ч» или «180 мин».
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/../session-start.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# Каталог сессии — тоже песочница (D1353). Хук пишет не только в STATE_DIR: сводку сквозной линии он кладёт в
# `<cwd>/.claude-docs/narrative.md`, а реестр сессий в песочнице пуст, и сводка собирается на каждом вызове. С `$PWD`
# здесь тест дописал 2541 запись-пробу в рабочий файл ClaudSoul. Предмет теста от каталога не зависит: подсказка
# читается из STATE_DIR.
PROJ="$TMP/proj"; mkdir -p "$PROJ"

probe() {   # probe <возраст в секундах> → строка возраста или пусто
    printf 'подсказка-образец\n' > "$TMP/audit-hint.txt"
    python3 -c "import os,time; t=time.time()-$1; os.utime('$TMP/audit-hint.txt',(t,t))"
    find "$TMP" -maxdepth 1 -name 'startup-signals-*.txt' -delete 2>/dev/null
    printf '{"session_id":"probe-%s","cwd":"%s"}' "$1" "$PROJ" \
        | STATE_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
    local f
    f=$(find "$TMP" -maxdepth 1 -name 'startup-signals-*.txt' | head -1)
    [ -n "$f" ] && grep -oE '📅[^\n]{0,40}' "$f" 2>/dev/null | head -1
}

# T1-T3: возраст назван при любом возрасте — минуты, часы, дни.
for AGE in 0 10800 259200; do
    OUT=$(probe "$AGE")
    if [ -n "$OUT" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [T:${AGE}с]: возраст снимка НЕ назван — читатель примет его за нынешний"; fi
done

# T4: КОНТРПРИМЕР — без подсказки строки возраста нет. Иначе нога зеленела бы на пустоте.
find "$TMP" -maxdepth 1 -name 'audit-hint.txt' -delete 2>/dev/null
find "$TMP" -maxdepth 1 -name 'bridge-hint.txt' -delete 2>/dev/null
find "$TMP" -maxdepth 1 -name 'startup-signals-*.txt' -delete 2>/dev/null
printf '{"session_id":"probe-none","cwd":"%s"}' "$PROJ" | STATE_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
F=$(find "$TMP" -maxdepth 1 -name 'startup-signals-*.txt' | head -1)
if [ -z "$F" ] || ! grep -q '📅 Снимок ниже' "$F" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: возраст назван при ОТСУТСТВИИ подсказки — строка не о предмете"; fi

echo "hint age always named: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
