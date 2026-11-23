#!/usr/bin/env bash
# СУДИТ: hooks/docs-derived-lib.sh scripts/count-stats.sh scripts/docs-derived-check.sh scripts/docs-refresh-claims.sh
# test_docs_derived.sh — производный документ узнаётся по шапке, отставание считается ХЕШЕМ, а не присутствием шапки.
#
# Результат: библиотека и прибор различают none/fresh/stale/broken, называют отставшего поимённо
#            с командой пересборки; шапка с чужим хешем — отставание (положительный контроль:
#            сравнивается хеш, а не форма); без библиотеки прибор говорит и даёт 2, а не молчит нулём
# Проверка результата: bash hooks/tests/test_docs_derived.sh даёт 0
#
# Песочница — свой git-репозиторий через git -C, свой корень (CLAUDSOUL_REPO, DOCS_DERIVED_ROOT);
# живой ~/.claude не читается — тест остаётся в параллельной фазе.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/docs-derived-lib.sh"
CHK="$ROOT/scripts/docs-derived-check.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
[ -f "$CHK" ] || { echo "FAIL: нет $CHK"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=0; F=0
ok()  { P=$((P+1)); printf '  ✅ %s\n' "$1"; }
bad() { F=$((F+1)); printf '  ❌ %s\n' "$1"; }

R="$TMP/repo"; mkdir -p "$R/docs" "$R/hooks" "$R/scripts"
cp "$LIB" "$R/hooks/"; cp "$CHK" "$R/scripts/"
git -C "$R" init -q 2>/dev/null || { echo "SKIP: нет git"; exit 0; }
printf '# Источник\n\nтекст один\n' > "$R/docs/x.ru.md"
printf '# Source\n\ntext one\n' > "$R/docs/x.md"
printf '# Просто документ\n' > "$R/docs/plain.md"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_docs_derived.sh:$LINENO" >&2; exit 1; }
git -C "$R" -c user.email=t@example.com -c user.name=t commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_docs_derived.sh:$LINENO" >&2; exit 1; }

run() { CLAUDSOUL_REPO="$R" bash "$R/scripts/docs-derived-check.sh" "$@"; }
# shellcheck source=../docs-derived-lib.sh
. "$LIB"; export DOCS_DERIVED_ROOT="$R"

# --- T1: без шапки — none/0; прибор при нуле производных говорит об этом и даёт 0 ---
st=$(docs_derived_state "$R/docs/plain.md"); rc=$?
[ "$st" = none ] && [ "$rc" = 0 ] && ok "T1 без шапки → none/0" || bad "T1: $st/$rc"
out=$(run); rc=$?
[ "$rc" = 0 ] && grep -q "производных документов нет" <<< "$out" && ok "T1b производных нет → 0 и сказано" || bad "T1b: код $rc: $out"

# --- T2: stamp ставит шапку первой строкой; состояние fresh; прибор считает ---
out=$(run stamp docs/x.md); rc=$?
_h1=$(head -1 "$R/docs/x.md")
if [ "$rc" = 0 ] && grep -qE '^<!-- derived-from: docs/x\.ru\.md@[0-9a-f]{12} -->$' <<< "$_h1"; then
    ok "T2 stamp пишет шапку первой строкой"
else bad "T2: код $rc, первая строка: $(head -1 "$R/docs/x.md")"; fi
st=$(docs_derived_state "$R/docs/x.md")
[ "$st" = fresh ] && ok "T2b после stamp → fresh" || bad "T2b: $st"
out=$(run); rc=$?
[ "$rc" = 0 ] && grep -q "свежих 1" <<< "$out" && ok "T2c прибор: свежих 1, код 0" || bad "T2c: код $rc: $out"

# --- T3: источник ушёл вперёд — stale/1; прибор называет файл и команду ---
printf 'текст два\n' >> "$R/docs/x.ru.md"
st=$(docs_derived_state "$R/docs/x.md"); rc=$?
[ "$st" = stale ] && [ "$rc" = 1 ] && ok "T3 источник изменён → stale/1" || bad "T3: $st/$rc"
out=$(run); rc=$?
if [ "$rc" = 1 ] && grep -q "отстал: docs/x.md" <<< "$out" && grep -q "stamp docs/x.md" <<< "$out"; then
    ok "T3b прибор: код 1, назван файл и команда пересборки"
else bad "T3b: код $rc: $out"; fi
out=$(run stale); [ "$out" = "docs/x.md" ] && ok "T3c режим stale печатает только имя" || bad "T3c: '$out'"

# --- T4: повторный stamp — fresh, шапка одна, не дублируется ---
run stamp docs/x.md >/dev/null
st=$(docs_derived_state "$R/docs/x.md")
n=$(grep -c '^<!-- derived-from:' "$R/docs/x.md")
[ "$st" = fresh ] && [ "$n" = 1 ] && ok "T4 повторный stamp: fresh, шапка одна" || bad "T4: $st, шапок $n"

# --- T5: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — шапка с чужим хешем есть отставание. Без этой ноги «fresh»
#         неотличим от «шапка присутствует»: прибор, сравнивающий только форму, прошёл бы T2-T4 ---
sed -i.bak -E '1s/@[0-9a-f]{12}/@000000000000/' "$R/docs/x.md" && rm -f "$R/docs/x.md.bak"
st=$(docs_derived_state "$R/docs/x.md")
[ "$st" = stale ] && ok "T5 чужой хеш в шапке → stale (сравнивается хеш, не форма)" || bad "T5: $st"
run stamp docs/x.md >/dev/null

# --- T6: источника нет — broken/2; прибор даёт 2 и имя ---
mv "$R/docs/x.ru.md" "$R/docs/x.ru.md.away"
st=$(docs_derived_state "$R/docs/x.md"); rc=$?
[ "$st" = broken ] && [ "$rc" = 2 ] && ok "T6 источник пропал → broken/2" || bad "T6: $st/$rc"
out=$(run); rc=$?
[ "$rc" = 2 ] && grep -q "сломан: docs/x.md" <<< "$out" && ok "T6b прибор: код 2 и имя" || bad "T6b: код $rc: $out"
mv "$R/docs/x.ru.md.away" "$R/docs/x.ru.md"

# --- T7: stamp без названного источника берёт <файл>.ru.md рядом; нет рядом — отказ 2 ---
printf '# Y\n' > "$R/docs/y.md"; printf '# Й\n' > "$R/docs/y.ru.md"; git -C "$R" add -A >/dev/null 2>&1
out=$(run stamp docs/y.md); rc=$?
[ "$rc" = 0 ] && grep -q "docs/y.ru.md" <<< "$out" && ok "T7 источник по умолчанию — .ru.md рядом" || bad "T7: код $rc: $out"
printf '# Z\n' > "$R/docs/z.md"
out=$(run stamp docs/z.md 2>&1); rc=$?
[ "$rc" = 2 ] && ok "T7b без источника рядом — отказ 2" || bad "T7b: код $rc: $out"

# --- T8: библиотеки нет — прибор говорит «НЕ ИЗМЕРЕНО» и даёт 2, а не молчит нулём ---
mv "$R/hooks/docs-derived-lib.sh" "$R/hooks/away"
out=$(run 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "НЕ ИЗМЕРЕНО" <<< "$out" && ok "T8 без библиотеки — 2 и сказано" || bad "T8: код $rc: $out"
mv "$R/hooks/away" "$R/hooks/docs-derived-lib.sh"


# --- T9: снимок «свежих ДО правки» — защита от маскировки. Генератор чисел правит ОБЕ
#         языковые версии синхронно и переставляет штамп тем, кто был свеж; отставший по
#         ПРОЗЕ в снимок не попадает и остаётся отставшим. Без этой ноги автоштамп
#         превратил бы непереведённую правку источника в «свежо» ---
printf '# A\n' > "$R/docs/a.ru.md"; printf '# A en\n' > "$R/docs/a.md"
printf '# B\n' > "$R/docs/b.ru.md"; printf '# B en\n' > "$R/docs/b.md"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_docs_derived.sh:$LINENO" >&2; exit 1; }
run stamp docs/a.md >/dev/null; run stamp docs/b.md >/dev/null
printf 'непереведённая проза\n' >> "$R/docs/b.ru.md"      # b отстал ДО «прогона генератора»
SNAP=$(run fresh | tr '\n' ' ')
case " $SNAP " in
    *" docs/a.md "*) case " $SNAP " in *" docs/b.md "*) bad "T9: отставший b попал в снимок свежих" ;;
                                    *) ok "T9 снимок свежих: a есть, отставший b — нет" ;; esac ;;
    *) bad "T9: свежий a в снимок не попал ($SNAP)" ;;
esac
# «Генератор» меняет число в обоих источниках и штампует ТОЛЬКО тех, кто был свеж
printf 'число 2\n' >> "$R/docs/a.ru.md"; printf 'число 2\n' >> "$R/docs/b.ru.md"
for d in $SNAP; do run stamp "$d" >/dev/null; done
[ "$(docs_derived_state "$R/docs/a.md")" = fresh ] && ok "T9b свежий до прогона остался свежим" \
    || bad "T9b: a стал $(docs_derived_state "$R/docs/a.md")"
[ "$(docs_derived_state "$R/docs/b.md")" = stale ] && ok "T9c отставший по прозе НЕ замаскирован" \
    || bad "T9c: b стал $(docs_derived_state "$R/docs/b.md") — автоштамп скрыл непереведённое"

# --- T10: генераторы чисел зовут снимок и штамп (проверка ВЫЗОВА, не формы: мутант без
#          вызова оставил бы производный отставшим — это и ловит T9c выше на логике) ---
for g in scripts/count-stats.sh scripts/docs-refresh-claims.sh; do
    if grep -q 'docs-derived-check.sh" fresh\|docs-derived-check.sh fresh\|\$_DERIVED_CHK" fresh' "$ROOT/$g" \
       && grep -q 'stamp' "$ROOT/$g"; then ok "T10 $g берёт снимок свежих и штампует"
    else bad "T10 $g: нет снимка свежих или штампа — производный будет отставать после каждого прогона"; fi
done

echo "passed=$P failed=$F"
exit $(( F != 0 ))
