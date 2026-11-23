#!/usr/bin/env bash
# path-without.sh (тесты) — каталог ссылок на команды машины БЕЗ названных: путь поиска, где команды нет.
#
# Зачем (D1302, скептик opus M2, 16 ноября 2026). Ноги «отказ, когда команды нет» включались условием
# `command -v timeout`, и после обновления macOS 27.2.1, поставившего `/usr/bin/timeout`, молча проверяли только
# тишину — ногу выбирало состояние машины. Каталог без команды делает обе стороны судимыми на любой машине. Владелец
# построения один: свидетели зовут эту функцию, а не держат свою копию цикла.
#
# path_without <каталог> <команда>... — заполняет каталог ссылками на всё из системных каталогов и каталога jq, кроме
# названных команд; код 1 и строка в stderr, если подготовка не удалась или команда всё равно находится.
path_without() {
    local dest="$1" d f b skip c; shift
    mkdir -p "$dest" || { echo "подготовка мира не удалась: mkdir $dest" >&2; return 1; }
    for d in /usr/bin /bin /usr/sbin /sbin "$(dirname "$(command -v jq 2>/dev/null || echo /usr/bin/jq)")"; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            b="${f##*/}"; skip=""
            for c in "$@"; do [ "$b" = "$c" ] && skip=1; done
            [ -n "$skip" ] && continue
            [ -e "$dest/$b" ] || [ -L "$dest/$b" ] || ln -s "$f" "$dest/$b" \
                || { echo "подготовка мира не удалась: ln -s $f" >&2; return 1; }
        done
    done
    for c in "$@"; do
        PATH="$dest" /bin/bash -c 'command -v "$1"' _ "$c" >/dev/null 2>&1 && { echo "подготовка мира не удалась: $c нашёлся в $dest" >&2; return 1; }
    done
    return 0
}
