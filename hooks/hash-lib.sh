#!/bin/bash
# hash-lib.sh — v1.0.0
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
