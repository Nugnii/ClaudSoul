#!/usr/bin/env bash
# test_docs_duplicates.sh — «Проверка результата» docs-duplicates.sh меряет объявленный им результат.
#
# Результат: команда из шапки scripts/docs-duplicates.sh красна на дереве, где содержательная
#            строка повторяется в двух документах состояния одного языка, и называет пару;
#            зелена, когда повтор живёт в хронике, в автоотчёте, вне корня и docs/, короче порога
#            или в документах разных языков; при универсуме меньше порога отвечает отказом, а не
#            зелёным отчётом.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Единственный кандидат в свидетели — `test_docs_match_tree.sh`
# — исполняет инструмент и судит по коду 0: заглушка `exit 0` неотличима от прогона, роль
# выведена из формы (`pattern-marker-matches-form-not-role`). Здесь роль устанавливается
# исполнением на подложенном дереве. Команда БЕРЁТСЯ из шапки инструмента, как в
# test_split_provenance_log.sh.
#
# Порог универсума у инструмента — 20 документов (иначе отказ, род F), поэтому фикстура несёт
# двадцать русских документов с различными длинными строками; повтор подкладывается поверх.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/docs-duplicates.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *docs-duplicates.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
F="$TMP/f"
DUP='Этот факт записан дважды в двух документах состояния и потому обязан быть найден сверщиком.'
EN='This particular sentence is long enough to take part in the duplicate check across documents.'

# Чистое дерево: N русских документов в docs/, у каждого своя длинная строка.
mk_fixture() {
    local n="${1:-20}" i
    rm -rf "$F"; mkdir -p "$F/docs"
    i=1
    while [ "$i" -le "$n" ]; do
        printf '# Документ %02d\n\nСтрока номер %02d этого документа достаточно длинна, чтобы участвовать в сверке дублей.\n' "$i" "$i" > "$F/docs/d$(printf '%02d' "$i").md"
        i=$((i + 1))
    done
    ( cd "$F" && git init -q && git add -A ) || { echo "FAIL: фикстура не собралась"; exit 1; }
}
track() { ( cd "$F" && git add -A ); }
run_tool() {
    OUT=$(cd "$REPO" && CLAUDSOUL_REPO="$F" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: дублей нет — зелено, группа и универсум названы числом --------------------------------
mk_fixture; run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "чистое дерево: rc=$RC — $OUT"
has T1 'ГРУППА «русские»: документов 20, дублей 0'
has T1 'ВНЕ СВЕРКИ 0 из 20:'
has T1 'дублей нет'

# --- T2: одна строка в двух документах одного языка — красно, пара названа --------------------
mk_fixture; printf '%s\n' "$DUP" >> "$F/docs/d01.md"; printf '%s\n' "$DUP" >> "$F/docs/d02.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T2 "дубль не найден: rc=$RC — $OUT"
has T2 'дублей всего: 1'
has T2 '· docs/d01.md + docs/d02.md'

# --- T3: переводные пары сравниваются раздельно — та же латинская строка в русском и английском
mk_fixture; printf '# Doc\n\n%s\n' "$EN" > "$F/docs/en.md"
printf '%s\nЕщё одна русская строка, чтобы перевес букв остался за русской группой документа.\nИ третья русская строка того же назначения, чтобы перевес был бесспорным.\n' "$EN" >> "$F/docs/d03.md"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "перевод засчитан дублем: rc=$RC — $OUT"
has T3 'ГРУППА «английские»: документов 1, дублей 0'

# --- T4: хроника вне сверки и названа пофайлово --------------------------------------------
mk_fixture; printf '# Changelog\n\n%s\n' "$DUP" > "$F/CHANGELOG.md"; printf '%s\n' "$DUP" >> "$F/docs/d01.md"
printf '# Отчёт\n\n%s\n' "$DUP" > "$F/docs/report-2026-09-12.md"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T4 "хроника попала в сверку: rc=$RC — $OUT"
has T4 '· CHANGELOG.md — хроника'
has T4 '· docs/report-2026-09-12.md — хроника'

# --- T5: автоотчёт вне сверки --------------------------------------------------------------
mk_fixture; printf 'Автоматический отчёт генератора\n\n%s\n' "$DUP" > "$F/docs/auto.md"; printf '%s\n' "$DUP" >> "$F/docs/d01.md"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T5 "автоотчёт попал в сверку: rc=$RC — $OUT"
has T5 '· docs/auto.md — автоотчёт'

# --- T6: документ вне корня и docs/ в универсум не входит ------------------------------------
mk_fixture; mkdir -p "$F/bridges"; printf '# Мост\n\n%s\n' "$DUP" > "$F/bridges/x.md"; printf '%s\n' "$DUP" >> "$F/docs/d01.md"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T6 "документ вне универсума засчитан: rc=$RC — $OUT"

# --- T7: строка короче порога — повтор законен ----------------------------------------------
mk_fixture; printf 'Короткая строка повторяется.\n' >> "$F/docs/d01.md"; printf 'Короткая строка повторяется.\n' >> "$F/docs/d02.md"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T7 "короткий повтор засчитан: rc=$RC — $OUT"

# --- T8: универсум меньше порога — отказ, а не зелёный отчёт --------------------------------
mk_fixture 5; run_tool
[ "$RC" -eq 2 ] && ok || bad T8 "малый универсум не отвергнут: rc=$RC — $OUT"
has T8 'универсум не выведен'

echo ""
echo "docs-duplicates tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
