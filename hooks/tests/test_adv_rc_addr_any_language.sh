#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# АТАКА: выражение адресов узнаёт файл по ЗАКРЫТОМУ ПЕРЕЧНЮ РАСШИРЕНИЙ, собранному по стеку
# самого ClaudSoul. Хуки стоят глобально и читают ходы ЛЮБОГО проекта: `src/app/page.tsx:42`
# и `prisma/schema.prisma:10` — такие же адреса, как `hooks/x.sh:12`. Перечень их не видит,
# страж считает, что адресов в разборе нет, и отказывает в записи по делу названной находке.
# Повод: сообщение владельца из соседнего проекта — три ложных отказа подряд (24.09.2026).
#
# Ожидание: адрес узнаётся по УСТРОЙСТВУ (путь.расширение:номер), а не по списку языков.
# Различение: перечень обязан провалить эту ногу — он и проваливал, 2 адреса из 9.
# Конвейер в `grep -q` под pipefail даёт 141 на УСПЕХЕ (SIGPIPE производителю), и
# успешная проверка читается как провал. Везде here-string.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/root-cause-lib.sh"
[ -f "$LIB" ] || { echo "SKIP: нет $LIB"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# shellcheck source=/dev/null
# Файл на месте — дальше предпосылку даёт сам предмет: не загрузился или не объявил признак — красный (D1222, H1).
. "$LIB" 2>/dev/null || { echo "FAIL: библиотека не загрузилась"; exit 1; }
[ -n "${RC_TRACE_ADDR_RE:-}" ] || { echo "FAIL: RC_TRACE_ADDR_RE не объявлен"; exit 1; }

# --- A1: адреса ЧУЖИХ стеков узнаются --------------------------------------------------
_miss=""
for a in "src/app/page.tsx:42" "prisma/schema.prisma:10" "components/Card.jsx:3" \
         "db/migrate.sql:12" "app/models/user.rb:9" "src/Main.vue:20" "pkg/main.go:5" \
         "lib/hooks-merge.jq:14" "src/Main.kt:77" "styles/app.scss:4"; do
    grep -qE "$RC_TRACE_ADDR_RE" <<< "$a" || _miss="$_miss $a"
done
[ -z "$_miss" ] && ok || bad A1 "адреса чужих стеков не узнаны:$_miss"

# --- A2: СВОИ адреса не потеряны (правка обязана быть надмножеством) --------------------
_miss=""
for a in "hooks/root-cause-lib.sh:693" "scripts/count-stats.sh:139" "docs/reference.md:8" \
         "mcp-server/server.py:12" "scripts/measurements.tsv:112" "D408" \
         "case-2026-09-24-stale-derived-doc-deadlock"; do
    grep -qE "$RC_TRACE_ADDR_RE" <<< "$a" || _miss="$_miss $a"
done
[ -z "$_miss" ] && ok || bad A2 "прежние адреса потеряны:$_miss"

# --- A3: НЕ адрес остаётся не адресом ----------------------------------------------------
# Расширение обязано начинаться с буквы: иначе версия `1.2:3` пошла бы в адреса. Последствие
# такой ошибки обратное — гейт стал бы мягче, а не строже.
_false=""
for a in "1.2:3" "12:30" "0.9:1"; do
    grep -qE "$RC_TRACE_ADDR_RE" <<< "$a" && _false="$_false $a"
done
[ -z "$_false" ] && ok || bad A3 "не-адрес засчитан адресом:$_false"

# --- A4: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — прежний перечень эту ногу проваливает ------------------
# Без него нога зелена на любой редакции, лишь бы та что-то ловила.
_OLD='[A-Za-z0-9_./-]+\.(sh|py|md|js|ts|json|tsv|yml|yaml|toml|txt):[0-9]+'
_seen=0
for a in "src/app/page.tsx:42" "prisma/schema.prisma:10"; do
    grep -qE "$_OLD" <<< "$a" && _seen=$((_seen+1))
done
[ "$_seen" -eq 0 ] && ok || bad A4 "прежний перечень видит $_seen из 2 — контроль не различает"

echo "rc addr any language: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
