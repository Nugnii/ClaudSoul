#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_adv_dep_index_nonascii_paths.sh
# test_adv_nonascii_a4a_unread.sh — нога под починкой A4a: замер без чтения обязан
# краснеть, а не печатать вывод о состоянии дерева (род дефекта B).
#
# Что было. В test_adv_dep_index_nonascii_paths.sh число нечитаемых документов корпуса
# приходило из встроенного python3, а ветка выбиралась по `${NBAD:-0}`. Отказ python3
# (ошибка git, UnicodeDecodeError, сломанный интерпретатор) отдавал пустоту, подстановка
# делала из неё ноль, и тест печатал «под учётом нет ни одного пути с не-ASCII (проверено
# ls-files), поэтому живой носитель отсутствует» — утверждение о репозитории, сделанное
# без чтения репозитория, — и выходил с кодом 0.
#
# Что здесь проверяется. Мир ломается ровно в одном месте: python3 подменяется на
# заведомо падающий. T1 — при таком мире вердикт называет несостоявшийся замер. T2 —
# отрицательный контроль: в целом мире эта ветка молчит и тест зелёный, то есть страж
# не краснеет от собственной подозрительности.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$REPO/hooks/tests/test_adv_dep_index_nonascii_paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "SKIP: не git-репозиторий"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/shim"
printf '#!/bin/sh\nexit 1\n' > "$TMP/shim/python3"; chmod +x "$TMP/shim/python3"

# --- T1. Чтение отказало → замер назван несостоявшимся ------------------------------
OUT1=$(PATH="$TMP/shim:$PATH" bash "$TARGET" 2>&1)
if grep -qF 'замер не выполнен' <<< "$OUT1"; then
    ok "T1 отказ чтения назван"
else
    bad "T1" "python3 не отработал, а A4a не сказал этого. Вывод:
$(printf '%s\n' "$OUT1" | sed 's/^/      /')"
fi
if grep -qF 'живой носитель отсутствует' <<< "$OUT1"; then
    bad "T1-ложь" "при несостоявшемся замере напечатано утверждение о состоянии дерева
      («живой носитель отсутствует») — вывод сделан без чтения"
else
    ok "T1-ложь утверждения о дереве нет"
fi

# --- T2. Отрицательный контроль: целый мир → ветка молчит --------------------------
OUT2=$(bash "$TARGET" 2>&1); RC2=$?
if [ "$RC2" -eq 0 ] && ! grep -qF 'замер не выполнен' <<< "$OUT2"; then
    ok "T2 в целом мире ветка молчит"
else
    bad "T2" "чтение исправно, а вердикт rc=$RC2. Вывод:
$(printf '%s\n' "$OUT2" | sed 's/^/      /')"
fi

echo ""
echo "adv nonascii a4a unread: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
