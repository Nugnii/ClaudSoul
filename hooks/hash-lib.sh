#!/bin/bash
# hash-lib.sh — v1.0.0
#
# ПРЕФИКСЫ: hash_
# Объявление пространства имён (11 сентября 2026, D390). Функция этой библиотеки
# носит один из названных префиксов; имя с ведущим `_` считается внутренним и под
# правило не подпадает. Сверяет `hooks/lib-prefix-guard.sh` при записи файла.
# Список собран ИЗ ФАКТА, а не придуман: он фиксирует нынешнее состояние, чтобы
# разнобой не рос дальше — из 21 библиотеки с 3+ функциями лишь 10 держали 80%+
# имён под одним префиксом, а объявления не было ни у одной из 29.
# Единая переносимая хеш-функция для дедупликации в хуках ClaudSoul.
#
# До v1.0.0 эта функция была скопирована байт-в-байт в 5 хуков (docs-family-check,
# enrich-suggester, quality-gate-check, skill-review-check, trust-guard) плюс два
# по-другому оформленных варианта TURN_KEY (itr-event-detector, reformulation-tracker).
# Любой фикс переносимости (см. pattern-shell-portability) приходилось бы повторять
# в 7 местах; пропуск одного → разные хеши для одного входа → ломается дедуп.
#
# Provides:
#   hash_value <string>   → стабильный хеш строки (один токен, без пробелов)
#   hash_file  <path>     → тот же хеш для СОДЕРЖИМОГО файла (байт в байт, без чтения в строку)
#   hash_values           → hash_value каждой строки stdin, построчно, одним процессом
#
# Переносимость: предпочитает md5sum (Linux), затем md5 (BSD/macOS),
# затем cksum (последний рубеж). md5sum и md5 дают идентичный md5 — выбор тула
# не меняет значение хеша на платформах, где есть оба.
#
# Fail silently — источается из хуков, где ошибка не должна ронять процесс.

hash_value() {
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$1" | md5
    else
        printf '%s' "$1" | cksum | awk '{print $1}'
    fi
}

# hash_values — hash_value для каждой строки stdin, одним процессом (D488): тай-брейк
# активатора хешировал кандидатов по одному, а их больше двухсот — сотни fork+exec на
# вызов. Значение то же: где есть md5sum или md5, hash_value считает md5, и python3 даёт
# тот же md5 тех же байтов (строка без перевода строки). Нет python3 или нет md5 (тогда
# hash_value — это cksum) — построчно через hash_value.
hash_values() {
    if command -v python3 >/dev/null 2>&1 \
       && { command -v md5sum >/dev/null 2>&1 || command -v md5 >/dev/null 2>&1; }; then
        python3 -c 'import hashlib, sys
for line in sys.stdin.buffer:
    if line.endswith(b"\n"):
        line = line[:-1]
    sys.stdout.write(hashlib.md5(line).hexdigest() + "\n")'
        return
    fi
    local _l
    while IFS= read -r _l || [ -n "$_l" ]; do hash_value "$_l"; done
}

# hash_file — файл читается инструментом, а не подстановкой `$(cat …)`: подстановка
# срезает завершающие переводы строк и ломается на NUL, то есть два разных файла давали
# бы один хеш. Тот же выбор инструмента, что у hash_value, — значения сравнимы.
# Файл подаётся на stdin, а не именем (D1321): GNU и uutils `md5sum`/`cksum` при обратной косой или переводе строки в
# имени начинают строку с `\`, и первое поле становилось `\<хеш>`.
hash_file() {
    [ -f "$1" ] || return 1
    if command -v md5sum >/dev/null 2>&1; then
        md5sum < "$1" | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$1"
    else
        cksum < "$1" | awk '{print $1}'
    fi
}
