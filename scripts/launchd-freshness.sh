#!/usr/bin/env bash
# launchd-freshness.sh — расписание есть, а проверки что оно сработало — нет.
# Результат: задания по расписанию живы и их артефакты свежее периода
# Проверка результата: bash scripts/launchd-freshness.sh даёт 0
#
#
# Повод. `scripts/measurements.tsv` перечисляет три замера с периодом 0 — «по событию,
# по расписанию launchd». `measurement-due.sh:46-49` делает `continue` ДО сравнения
# возраста, то есть период 0 означает буквальное освобождение от проверки. Владелец
# у обязанности назван (launchd), но никто не смотрит, жив ли он.
#
# Два независимых способа отказа, оба проверяются здесь:
#   1. задание выгружено (plist удалён, launchctl не знает имени) — обязанность исчезла;
#   2. задание загружено, но артефакт не обновляется (машина спала, команда падает) —
#      обязанность есть и не выполняется.
# Первое без второго: сканер оставался «загруженным» и пропустил два четырёхчасовых
# срока подряд, пока машина спала. Второе без первого: задание можно выгрузить руками
# при отладке и забыть вернуть — артефакт останется лежать свежим ещё сутки.
#
# Допуски не выводятся из plist намеренно. `StartInterval` и `StartCalendarInterval` —
# две разные формы, разбор обеих дороже пользы, а календарное задание всё равно требует
# запаса на пропущенный запуск. Допуск = период плюс запас на один пропуск.
#
# Код возврата: 0 — все задания живы и свежи; 1 — есть выгруженные или протухшие.

set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
BRIDGES_HISTORY="${BRIDGES_HISTORY_DIR:-$HOME/.claude/bridges-history}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"

STALE=0
GONE=0
CHECKED=0

# Список заданий снимается ОДИН раз в переменную, а не конвейером на каждую проверку.
# Первая версия делала `launchctl list | grep -q "$name"` внутри цикла и объявила
# выгруженными два живых задания: `grep -q` выходит по первому совпадению, `launchctl`
# получает SIGPIPE, под `set -o pipefail` статус конвейера ненулевой. Совпадало только
# то задание, что стоит последним в выводе, — там grep дочитывает поток до конца.
# Тот же механизм уже ломал `test_case_folding_portable.sh` (2026-07-29).
# Подстановка через env — чтобы ветка «выгружено» была проверяема: на машине, где
# задания загружены, её иначе не воспроизвести, и она осталась бы недоказанной.
LAUNCHD_LIST="${CLAUDSOUL_LAUNCHD_LIST-$(launchctl list 2>/dev/null || true)}"

_newest_mtime() { # каталог или файл → epoch последнего изменения, 0 если нет
    local target="$1" newest=0 m
    if [ -d "$target" ]; then
        for f in "$target"/*.md; do
            [ -f "$f" ] || continue
            m=$(_mtime "$f")
            [ "$m" -gt "$newest" ] && newest="$m"
        done
    elif [ -f "$target" ]; then
        newest=$(_mtime "$target")
    fi
    printf '%s' "$newest"
}

_mtime() { # переносимо: GNU stat, затем BSD stat (hooks/portable-lib.sh, тот же приём)
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

_check() {
    local name="$1" artifact="$2" max_hours="$3" what="$4"
    CHECKED=$((CHECKED + 1))

    if ! printf '%s\n' "$LAUNCHD_LIST" | grep -q "[[:space:]]${name}\$"; then
        GONE=$((GONE + 1))
        printf '  выгружено: %-32s — %s\n' "$name" "$what"
        return
    fi

    local m age_h
    m=$(_newest_mtime "$artifact")
    if [ "${m:-0}" -eq 0 ]; then
        STALE=$((STALE + 1))
        printf '  без следа:  %-32s — артефакт не найден (%s)\n' "$name" "$artifact"
        return
    fi
    age_h=$(( ( $(date +%s) - m ) / 3600 ))
    if [ "$age_h" -gt "$max_hours" ]; then
        STALE=$((STALE + 1))
        printf '  протухло:   %-32s — %s ч назад при допуске %s ч (%s)\n' \
            "$name" "$age_h" "$max_hours" "$what"
    fi
}

# Допуски: период + запас на один пропущенный запуск.
_check com.claudsoul.scanner        "$STATE/last-scan-timestamp"     12   "обход проектов, раз в 4 ч"
_check com.claudsoul.knowledge-audit "$LESSONS/_audit-history"       336  "ревизия знаний, еженедельно"
_check com.claudsoul.bridge-health   "$BRIDGES_HISTORY"              1512 "дайджест мостов, ежемесячно"

if [ "$((STALE + GONE))" -eq 0 ]; then
    echo "Задания по расписанию: ${CHECKED} проверено, все живы и свежи."
else
    echo "Задания по расписанию: выгружено ${GONE}, протухло ${STALE} из ${CHECKED}."
fi

[ "$((STALE + GONE))" -eq 0 ]
