#!/bin/bash
# throttle-lib.sh — v1.0.0
# Единый per-session механизм подавления повторов для хуков ClaudSoul.
#
# До v1.0.0 логика throttle была скопирована в 6 хуков с расходящимися именами
# поля ключа ("key" в blocker-tier-check, "hash" в docs-family/enrich/
# quality-gate/skill-review) и флаг-файлом без ключа в decompose-detector.
# Копипаст уже посеял рассинхрон (см. docs/health-audit-2026-06-20.md, F1).
# Эта библиотека — единый источник. Каноническое имя поля — "key".
#
# Throttle-файлы эфемерны: имя содержит SESSION_ID, читаются только в своей
# сессии тем же кодом — смена имени поля ничего исторического не ломает.
#
# Эфемерность до v1.16.1 была ОБЪЯВЛЕНА и не исполнялась (D44): библиотека не удаляла
# свои файлы никогда, а поимённый список уборки в `session-collector.sh:278` разошёлся с
# реальностью на 20+ семейств. Замер: `blocker-fired-*` 122 файла, `trust-guard-fired-*`
# 72, `docs-family-fired-*` 61, `decompose-fired-*` 32, и дальше по списку. Документация
# описывала свойство, которого нет, — ровно тот класс, что разбирался в D38.
#
# Теперь уборка стоит ЗДЕСЬ, в единственном месте, где схема имён известна: любой новый
# страж получает её автоматически, а поимённый список не нужен и не может разойтись.
#
# Provides:
#   throttle_file <state_dir> <name> <sid>   → путь к jsonl по единой схеме
#                                               <state_dir>/<name>-fired-<sid>.jsonl
#   throttle_seen <file> <key>               → код 0 если <key> уже зафиксирован,
#                                               иначе код 1 (в т.ч. если файла нет)
#   throttle_mark <file> <key> [extra_json]  → дописать запись о <key>;
#                                               extra_json — опц. сырой фрагмент
#                                               доп. полей, напр. '"marker":"v1.0"'
#
# Паттерн использования (проверка и запись разнесены — как в существующих хуках):
#   F=$(throttle_file "$STATE_DIR" docs-family "$SESSION_ID")
#   if throttle_seen "$F" "$key"; then exit 0; fi   # уже было в этой сессии
#   ... хук делает работу / инжектит маркер ...
#   throttle_mark "$F" "$key"                        # отметить, что сработал
#
# Fail silently — источается из хуков, где ошибка не должна ронять процесс.

# Семейства, у которых есть МЕЖСЕССИОННЫЙ читатель — файл переживает свою сессию и
# служит выборкой. Уборке они не подлежат, сколько бы ни было объявлено в шапке.
#
# Список выведен проверкой, а не предположением: `grep -l '<семья>-fired-\*'` по всем
# хукам и скриптам — то есть ищется читатель, обходящий ВСЕ файлы семейства, а не свой.
#   blocker-fired-*  ← backfill-compliance.sh:143, эталон round-trip гейта
#   rework-fired-*   ← metrics-collector.sh:434, накопительная выборка для порога D18
#
# Цена ошибки измерена на себе: первая версия этой уборки снесла 122 файла
# `blocker-fired-*`, и выборка гейта «round-trip по 26 сессиям» ужалась до 2. Данные
# писал живой хук и пересобрать их нечем. Заявление шапки об эфемерности было ЛОЖНЫМ
# для двух семейств из двенадцати, и уборка это заявление исполнила буквально.
THROTTLE_KEEP_FAMILIES="${THROTTLE_KEEP_FAMILIES:-blocker rework}"

throttle_file() {
    local state_dir="$1"
    # Уборка по возрасту — только для семейств без межсессионного читателя.
    # Порог с запасом: сессия живёт часы, но `throttle_seen` обязан находить свой ключ
    # всю сессию целиком, включая долгие.
    local _keep_expr=""
    local _fam
    for _fam in $THROTTLE_KEEP_FAMILIES; do
        _keep_expr="$_keep_expr ! -name ${_fam}-fired-*"
    done
    # shellcheck disable=SC2086
    find "$state_dir" -maxdepth 1 -name '*-fired-*' $_keep_expr \
        -mtime "+${THROTTLE_TTL_DAYS:-3}" -delete 2>/dev/null || true
    printf '%s/%s-fired-%s.jsonl' "$state_dir" "$2" "$3"
}

throttle_seen() {
    local file="$1" key="$2"
    [ -f "$file" ] && grep -Fq "\"key\":\"$key\"" "$file" 2>/dev/null
}

throttle_mark() {
    local file="$1" key="$2" extra="${3:-}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [ -n "$extra" ]; then
        printf '{"date":"%s","key":"%s",%s}\n' "$now" "$key" "$extra" >> "$file"
    else
        printf '{"date":"%s","key":"%s"}\n' "$now" "$key" >> "$file"
    fi
}
