#!/usr/bin/env bash
# probe_D1319 — сверка «строка есть в снимке» (`_rc_has_line`) отвечает и на тексте больше 128 КБ в рамке Linux.
# СУДИТ: hooks/root-cause-lib.sh
#
# Повод (18 ноября 2026, разбор D1315). `_rc_has_line` передаёт текст снимка awk строкой окружения, а у Linux одна
# строка окружения не длиннее 128 КБ (MAX_ARG_STRLEN). Перечень знаний в снимке — 66 КБ (1 253 имени) и растёт
# около 13 КБ в месяц; за пределом awk не запускается, сверка отвечает «не сверить», и исход «знание» отбивается.
# Положительный контроль — малый текст в той же рамке обязан дать «есть»: иначе рамка не умеет ответить «да» (код 2).
#
# Код: 0 — строка найдена и в большом тексте; 1 — в большом не сверена; 2 — не измерено (нет docker или tar, рамка сломана).
R="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$R" 2>/dev/null || exit 2
[ -f hooks/root-cause-lib.sh ] || exit 1
command -v tar >/dev/null 2>&1 && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || exit 2
# $1 — сколько имён в тексте; ищется предпоследнее.
# Библиотека едет в контейнер ПОТОКОМ на вход `docker run -i`, а не монтированием (D1361, рецепт D1355 из
# scripts/measure-linux-parity.sh): docker, направленный на другую машину (`ssh://server`), смонтировал бы там пустой
# каталог с путём этой машины. Распаковка в контейнере первой; код `run` — код контейнера, последнего звена трубы.
run() {
    COPYFILE_DISABLE=1 tar --no-xattrs -cf - hooks/root-cause-lib.sh \
      | docker run --rm -i -e N="$1" debian:stable-slim bash -c '
        mkdir -p /repo && tar -xf - -C /repo 2>/dev/null || exit 3
        . /repo/hooks/root-cause-lib.sh >/dev/null 2>&1
        command -v _rc_has_line >/dev/null 2>&1 || exit 3
        t=$(seq -f "pattern-%07g-knowledge-record-name" 1 "$N")
        _rc_has_line "$t" "$(printf "pattern-%07d-knowledge-record-name" $((N - 1)))"' >/dev/null 2>&1
}
run 100; [ $? -eq 0 ] || exit 2
run 4500   # около 180 КБ
case $? in 0) exit 0 ;; 1|2) exit 1 ;; *) exit 2 ;; esac
