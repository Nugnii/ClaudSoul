#!/usr/bin/env bash
# test_adv_snapshot_marker_root.sh — АТАКА на признак «дерево неполно по построению».
#
# Предмет: признак судит ОБЪЯВЛЕННЫЙ корень, а не текущий каталог. Маркер, оказавшийся рядом
#          с местом запуска, не должен выключать проверки — иначе любой фикстурный файл с
#          таким именем разом снимает ноги живых предметов.
# Проверка результата: bash hooks/tests/test_adv_snapshot_marker_root.sh даёт 0.
#
# Повод. Признак заведён 15 сентября 2026 с умолчанием `${UNIVERSE_ROOT:-.}`. Раунд критика
# в тот же час предъявил рабочую подделку: каталог с файлом `.public-snapshot`, из которого
# зовут признак без корня, — «неполное дерево» объявлялось на пустом месте.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/universe-lib.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/podlog" "$TMP/nastoyashchij" "$TMP/roditel/vnutri"
printf 'подложка\n' > "$TMP/podlog/.public-snapshot"
printf 'снимок\n'   > "$TMP/nastoyashchij/.public-snapshot"
printf 'снимок\n'   > "$TMP/roditel/.public-snapshot"

# A1 — АТАКА: корень не объявлен, маркер лежит рядом с местом запуска.
OUT=$(cd "$TMP/podlog" && bash -c '. "'"$LIB"'"; unset UNIVERSE_ROOT; universe_partial_tree' 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad A1 "маркер из текущего каталога выключил проверки при незаданном корне"
grep -q 'UNIVERSE_ROOT не задан' <<< "$OUT" && ok || bad A1b "ошибка зовущего не названа — молчание неотличимо от решения"

# A2 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: объявленный корень с маркером признаётся. Без этой ноги A1
# зеленела бы на признаке, который не срабатывает никогда.
(cd / && bash -c '. "'"$LIB"'"; UNIVERSE_ROOT="'"$TMP/nastoyashchij"'"; universe_partial_tree') && ok \
    || bad A2 "объявленный корень со снимком не признан неполным"

# A3 — маркер У РОДИТЕЛЯ корнем не считается: признак судит ровно объявленное место.
(bash -c '. "'"$LIB"'"; UNIVERSE_ROOT="'"$TMP/roditel/vnutri"'"; universe_partial_tree') \
    && bad A3 "маркер родительского каталога засчитан корню" || ok

# A4 — пустой корень (объявлен, но пуст) — та же ошибка зовущего, тот же безопасный ответ.
(bash -c '. "'"$LIB"'"; UNIVERSE_ROOT=""; universe_partial_tree' 2>/dev/null) \
    && bad A4 "пустой корень принят за объявленный" || ok

echo "adv snapshot marker root: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
