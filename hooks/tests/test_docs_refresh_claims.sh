#!/usr/bin/env bash
# test_docs_refresh_claims.sh — число в документе подставляется из реестра и сверяется с ним.
#
# Результат: `run` подставляет значение команды в место, названное регулярным выражением;
#            `--check` называет расхождение кодом 1, свежий документ — кодом 0; ключ без
#            источника пропускается и называется, а не считается нулём; выражение без места
#            в тексте — находка, не тишина
# Проверка результата: bash hooks/tests/test_docs_refresh_claims.sh даёт 0
#
# Повод (30 августа 2026): README ушёл наружу в v1.31.0 со 176 находками при 185 и «пятью
# хуками» при девяти — числа жили прозой, стражи проверяли форму. Механизм тот же, что у
# показаний бэклога (D210): число объявляет команду.
#
# КОНТРПРИМЕРЫ, все проверяются ниже: свежее число — тишина и код 0; ключ n/a — пропуск,
# код 0; выражение без места — код 1; --check не правит файл.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/docs-refresh-claims.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 250)"; fi
}
assert_empty() {
    if [ -z "${1//[[:space:]]/}" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина: $(printf '%s' "$1" | head -c 200)"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/scripts"
cat > "$TMP/figures.sh" <<'FIG'
#!/usr/bin/env bash
case "$1" in
    hooks) echo 54 ;;
    ratio) echo 0.16 ;;
    big)   echo 13117 ;;
    gone)  echo n/a ;;
    *) exit 2 ;;
esac
FIG
printf '# Док\n\n52 hooks on events, ratio **0.11** per session, 12,267 injections, 7 ghosts.\n' > "$TMP/repo/DOC.md"
printf 'DOC.md\t(\\d+) hooks on events\thooks\t\tхуки\nDOC.md\t\\*\\*([\\d.]+)\\*\\* per session\tratio\t\tдоля\nDOC.md\t([\\d,]+) injections\tbig\tthousands_comma\tинжекции\nDOC.md\t(\\d+) ghosts\tgone\t\tпризраки\n' > "$TMP/claims.tsv"
run() { CLAUDSOUL_REPO="$TMP/repo" DOC_CLAIMS_FILE="$TMP/claims.tsv" DOC_FIGURES="$TMP/figures.sh" bash "$SCRIPT" "$@" 2>&1; }

# --- T1: --check называет расхождения и не правит файл ---
BEFORE=$(cat "$TMP/repo/DOC.md")
OUT=$(run --check); RC=$?
assert_contains "$OUT" "в документе 52, в мире 54" "T1: расхождение названо парой «в документе / в мире»"
[ "$RC" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1b]: --check не сообщил кодом: $RC"; }
[ "$(cat "$TMP/repo/DOC.md")" = "$BEFORE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1c]: --check изменил файл"; }
# КОНТРПРИМЕР: ключ без источника пропущен и назван, не приравнен к нулю
assert_contains "$OUT" "источник gone недоступен" "T1d: ключ n/a пропущен и назван"
grep -q "7 ghosts" "$TMP/repo/DOC.md" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1e]: n/a затёр число"; }

# --- T2: run подставляет, включая формат тысяч ---
OUT2=$(run run); RC2=$?
assert_contains "$(cat "$TMP/repo/DOC.md")" "54 hooks on events" "T2: число подставлено"
assert_contains "$(cat "$TMP/repo/DOC.md")" "**0.16** per session" "T2b: доля подставлена в группу, разметка сохранена"
assert_contains "$(cat "$TMP/repo/DOC.md")" "13,117 injections" "T2c: формат тысяч"
[ "$RC2" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2d]: run вернул $RC2"; }

# --- T3: свежий документ — --check 0, run «обновлять нечего» ---
OUT3=$(run --check); RC3=$?
[ "$RC3" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T3]: свежий документ дал $RC3: $OUT3"; }
assert_empty "$(printf '%s' "$OUT3" | grep '^  · ' | grep -v 'недоступен')" "T3b: расхождений не названо"

# --- T4: КОНТРПРИМЕР — выражение без места в тексте есть находка, не тишина ---
printf 'DOC.md\t(\\d+) unicorns\thooks\t\tединороги\n' >> "$TMP/claims.tsv"
OUT4=$(run --check); RC4=$?
assert_contains "$OUT4" "не нашло места в тексте" "T4: мёртвая строка реестра названа"
# Код 3, а не 1 (D377): устаревший реестр — не расхождение чисел, у него свой код.
[ "$RC4" -eq 3 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4b]: мёртвая строка обязана давать код 3 (реестр устарел), получен: $RC4"; }
# --- T8: расхождение чисел ВМЕСТЕ с мёртвой строкой — код 1: работа с числами первая ---
sed -i.bak 's/54 hooks on events/50 hooks on events/' "$TMP/repo/DOC.md" && rm -f "$TMP/repo/DOC.md.bak"
OUT8=$(run --check); RC8=$?
[ "$RC8" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8]: расхождение рядом с мёртвой строкой обязано давать 1, получен $RC8: $OUT8"; }
assert_contains "$OUT8" "не нашло места в тексте" "T8b: мёртвая строка при этом всё равно названа"
sed -i.bak 's/50 hooks on events/54 hooks on events/' "$TMP/repo/DOC.md" && rm -f "$TMP/repo/DOC.md.bak"
# --- T9: --keys сужает сверку до названных ключей ---
OUT9=$(run --check --keys ratio,big); RC9=$?
[ "$RC9" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T9]: --keys ratio,big не отсёк мёртвую строку с ключом hooks: $RC9 $OUT9"; }
OUT9b=$(run --check --keys hooks); RC9b=$?
[ "$RC9b" -eq 3 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T9b]: --keys hooks обязан видеть мёртвую строку кодом 3: $RC9b"; }
# --- T10: источник есть, а числа не дал — код 2 (сломан прибор, не реестр и не документ) ---
printf '#!/usr/bin/env bash\ncase "$1" in boom) echo err ;; *) echo 5 ;; esac\n' > "$TMP/figures2.sh"
printf 'DOC.md\t(\\d+) hooks on events\tboom\t\tбум\n' > "$TMP/claims2.tsv"
OUT10=$(CLAUDSOUL_REPO="$TMP/repo" DOC_CLAIMS_FILE="$TMP/claims2.tsv" DOC_FIGURES="$TMP/figures2.sh" bash "$SCRIPT" --check 2>&1); RC10=$?
[ "$RC10" -eq 2 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T10]: источник без числа обязан давать код 2, получен $RC10: $OUT10"; }
assert_contains "$OUT10" "числа не дал" "T10b: сломанный источник назван"

# --- T6: строка не из пяти полей (лишний таб сдвинул ключ) — «сломана», а не «источник недоступен» ---
printf 'DOC.md\t(\\d+) ghosts\t\tn_a_key\t\tпризраки-с-лишним-табом\n' > "$TMP/claims.tsv"
OUT6=$(run --check); RC6=$?
assert_contains "$OUT6" "сломанных строк реестра" "T6: строка с лишним табом названа сломанной"
[ "$RC6" -eq 3 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6b]: сломанная строка реестра обязана давать код 3 (реестр негоден), получен: $RC6"; }
grep -q "источник .* недоступен" <<< "$OUT6" && { FAIL=$((FAIL+1)); echo "FAIL [T6c]: сломанная строка прошла как «недоступен»"; } || PASS=$((PASS+1))

# --- T5: у живого реестра каждая строка находит своё место; ЧИСЛА судит замер, не тест ---
# Числа здесь судить нельзя, и это свойство реестра, а не решение вкуса. Из 168 строк
# `scripts/doc-claims.tsv` 100 держат величины, которые растит РАБОТА системы, а не коммит
# (sessions_unique, blocker_markers, trust_guard_firings, ki_*), а у сведения
# (`docs-refresh-claims.sh run`) нет ни одного автоматического вызывающего — ни хука, ни
# launchd, ни cron; автоматически зовётся только `--check` (страж бампа и гейт публикации).
# Расхождение между ручными прогонами `run` поэтому НОРМА: 2 сентября 2026 разошлись
# строки про сессии (346→347) и реестр (396→397), все из подвижной сотни, из 68
# коммит-обусловленных — ни одной. Тест, требовавший rc=0, был красен ПО ПОСТРОЕНИЮ и
# красил весь набор (D268). Числа держит замер `doc-claims` (период 7,
# `scripts/measurements.tsv`), который читает тот же код возврата как ОТЧЁТ, а не вердикт.
# Тесту осталась целостность: мёртвых строк нет, сломанных нет — это меняется коммитом.
# Маркер вложенности снимает ИСПОЛНЕНИЕ источников, которое этой ноге не нужно: предмет —
# целостность РЕЕСТРА (мёртвых строк нет, сломанных нет), а не значения чисел. Среди ~100
# ключей есть такие, что сами запускают прогоны (tests_*, drift_check_pairs), и без маркера
# нога стоила 31 с из 32 всего теста; с ним — 5 с. Предмет проверен положительным контролем
# 11 сентября 2026: заведомо мёртвая строка реестра ловится и с маркером.
OUT5=$(BACKLOG_CHECKS_NESTED=1 bash "$SCRIPT" --check 2>&1)
grep -q "не нашло места в тексте" <<< "$OUT5" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T5]: в живом реестре мёртвая строка — $(printf '%s' "$OUT5" | grep -A1 'не нашло места в тексте' | head -2)"; } \
    || PASS=$((PASS+1))
grep -q "сломанных строк реестра" <<< "$OUT5" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T5b]: в живом реестре строка не из пяти полей"; } \
    || PASS=$((PASS+1))

# --- T5c: у чисел назван свой держатель. Без этой строки предыдущая проверка означала бы
# не «числа судит замер», а «числа не судит никто».
MEAS="$(cd "$(dirname "$0")/../.." && pwd)/scripts/measurements.tsv"
awk -F'\t' '$1 == "doc-claims" && $2 + 0 > 0 { found = 1 } END { exit !found }' "$MEAS" \
    && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T5c]: замера doc-claims со сроком нет в реестре — числа документов не судит никто"; }

# --- T7: число берётся ТОЛЬКО из зелёного прогона теста ---
# Красный тест печатает МЕНЬШЕЕ «N passed», и без проверки исхода оно молча становилось
# характеристикой теста в документе. Случай 1 сентября 2026: test_backlog_item_shape читает
# боевой BACKLOG.md (сверяет трёх его читателей), архиватор в тот момент переписывал файл,
# тест дал «8 passed, 1 failed» — и модуль получил «8 проверок» вместо девяти. Падение не
# отразилось нигде.
FIG="$(cd "$(dirname "$0")/../.." && pwd)/scripts/doc-figures.sh"
# Фикстуры ложатся в БОЕВОЙ каталог тестов: `doc-figures` ищет тест ровно там и подменить
# каталог нечем. Значит уборка закладывается ДО первого запуска, а не после последней
# проверки — падение между созданием и удалением оставило бы мусор в дереве
# (`pattern-external-test-write-teardown`; тот же класс сегодня уронил фикстуру в боевой
# BACKLOG-archive.md). Прежний trap сохраняется — снимаем оба каталога.
_zz="$(cd "$(dirname "$0")" && pwd)"
trap 'rm -rf "$TMP" "$_zz"/test_zz_probe_*.sh' EXIT
printf '#!/usr/bin/env bash\necho "zz: 8 passed, 1 failed"\nexit 1\n' > "$_zz/test_zz_probe_red.sh"
printf '#!/usr/bin/env bash\necho "zz: 12 passed, 0 failed"\n'        > "$_zz/test_zz_probe_green.sh"
printf '#!/usr/bin/env bash\necho "zz: 5 passed, 2 failed"\nexit 0\n' > "$_zz/test_zz_probe_lie.sh"
[ "$(bash "$FIG" tests_test_zz_probe_red)" = "err" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T7]: число взято из КРАСНОГО прогона"; }
[ "$(bash "$FIG" tests_test_zz_probe_green)" = "12" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T7b]: зелёный прогон не дал числа"; }
# КОНТРПРИМЕР: тест вернул 0 и всё же сообщил о провалах — число тоже не берётся
[ "$(bash "$FIG" tests_test_zz_probe_lie)" = "err" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T7c]: rc=0 при failed>0 принят за зелёный"; }
rm -f "$_zz/test_zz_probe_red.sh" "$_zz/test_zz_probe_green.sh" "$_zz/test_zz_probe_lie.sh"

# --- T8: СТРОКОВОЕ утверждение — поимённый список — сверяется и подставляется как число (D378) ---
# Число «8 отказывают» реестр держал с 30 августа, а пять имён в скобках — никто: состав
# разошёлся с миром на три хука при верном числе. Ключ печатает канонический список, регулярка
# захватывает скобку, формат пустой — сравнение дословное.
cat > "$TMP/figures8.sh" <<'FIG'
#!/usr/bin/env bash
case "$1" in
    names) printf '%s\n' '`alpha`, `beta`, `gamma`' ;;
    *) exit 2 ;;
esac
FIG
printf '# Док\n\n3 guards refuse (`alpha`, `gamma`).\n' > "$TMP/repo/LIST.md"
printf 'LIST.md\trefuse \\(([^)]*)\\)\tnames\t\tсписок отказывающих\n' > "$TMP/claims8.tsv"
run8() { CLAUDSOUL_REPO="$TMP/repo" DOC_CLAIMS_FILE="$TMP/claims8.tsv" DOC_FIGURES="$TMP/figures8.sh" bash "$SCRIPT" "$@" 2>&1; }
OUT8=$(run8 --check); RC8=$?
assert_contains "$OUT8" 'в документе `alpha`, `gamma`, в мире `alpha`, `beta`, `gamma`' "T8: расхождение СОСТАВА названо парой «в документе / в мире»"
[ "$RC8" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8b]: --check не сообщил кодом о расхождении списка: $RC8"; }
run8 run >/dev/null 2>&1
grep -qF '3 guards refuse (`alpha`, `beta`, `gamma`).' "$TMP/repo/LIST.md" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T8c]: run не подставил список: $(cat "$TMP/repo/LIST.md")"; }
OUT8b=$(run8 --check); [ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8d]: после run список всё ещё расходится: $OUT8b"; }

echo "docs refresh claims: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
