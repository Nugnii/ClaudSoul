#!/usr/bin/env bash
# test_adv6_fsrs_stale_index_backwards_mtime.sh — days-index не пересобирается, когда
# реестр переписан С БОЛЕЕ СТАРЫМ mtime.
#
# АТАКА. Кэш индекса валиден, если он НОВЕЕ реестра:
#     if [ -f "$idx" ] && [ "$idx" -nt "$reg" ]; then echo "$idx"; return 0; fi
# Инвалидация «по mtime» держится на допущении «реестр только дописывается, mtime
# растёт». Но mtime реестра может уйти НАЗАД: восстановление из бэкапа, git checkout,
# cp -p / rsync --times, распаковка архива. Тогда idx -nt reg остаётся истинным, и
# СТАРЫЙ индекс отдаётся при изменившемся содержимом реестра.
#
# ВХОД. Реестр с 1 сессией (день A) → индекс собран. Затем реестр переписан: те же +5
#       новых сессий на день A+1, но mtime выставлен в прошлое (touch -t).
# ОЖИДАНИЕ. fsrs_experience_days_since A видит 5 новых сессий → при темпе 1/день = 5.
# ФАКТ.     Отдаётся кэш со счётом 0 → «опыта не прошло» → знание кажется свежее, чем
#           есть; FSRS-штраф/статус и ранжирование в knowledge-activator считаются по
#           заниженному опыту.
set -u
LIB="$(cd "$(dirname "$0")/.." && pwd)/fsrs-lib.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REG="$TMP/registry.jsonl"
export FSRS_SESSION_REGISTRY="$REG"
export FSRS_SESSIONS_PER_DAY=1

# shellcheck source=/dev/null
source "$LIB"

# 1) Реестр: одна сессия в день якоря → первый вызов строит индекс.
printf '{"session_id":"a","started_at":"2000-01-01T10:00:00Z"}\n' > "$REG"
base=$(fsrs_experience_days_since 2000-01-01)   # 0: сессия того же дня не считается
[ -f "$REG.days-index" ] || { echo "SKIP: индекс не построился (нет jq?)"; exit 0; }

# 2) Реестр переписан: +5 сессий на СЛЕДУЮЩИЙ день, но mtime уведён в прошлое.
{
  printf '{"session_id":"a","started_at":"2000-01-01T10:00:00Z"}\n'
  for s in b c d e f; do
    printf '{"session_id":"%s","started_at":"2000-01-02T10:00:00Z"}\n' "$s"
  done
} > "$REG"
touch -t 199001010000 "$REG"   # реестр «старше» уже существующего индекса

got=$(fsrs_experience_days_since 2000-01-01)
want=5   # 5 сессий строго после дня A, темп 1/день, округление → 5

if [ "$got" != "$want" ]; then
    echo "FAIL (attack succeeds): реестр переписан 5 новыми сессиями с более старым"
    echo "  mtime → индекс не пересобран. days_since=$got, ожидалось $want (base был $base)."
    echo "  Опыт занижен: знание кажется свежее, FSRS-decay/ранжирование искажены."
    exit 1
fi

echo "PASS: индекс пересобран, days_since=$got"
exit 0
