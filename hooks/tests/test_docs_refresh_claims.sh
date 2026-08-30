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
[ "$RC4" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4b]: мёртвая строка не сообщена кодом: $RC4"; }

# --- T6: строка не из пяти полей (лишний таб сдвинул ключ) — «сломана», а не «источник недоступен» ---
printf 'DOC.md\t(\\d+) ghosts\t\tn_a_key\t\tпризраки-с-лишним-табом\n' > "$TMP/claims.tsv"
OUT6=$(run --check); RC6=$?
assert_contains "$OUT6" "сломанных строк реестра" "T6: строка с лишним табом названа сломанной"
[ "$RC6" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6b]: сломанная строка не сообщена кодом: $RC6"; }
grep -q "источник .* недоступен" <<< "$OUT6" && { FAIL=$((FAIL+1)); echo "FAIL [T6c]: сломанная строка прошла как «недоступен»"; } || PASS=$((PASS+1))

# --- T5: живой реестр проекта совпадает с деревом (то, что должен видеть гейт) ---
OUT5=$(bash "$SCRIPT" --check 2>&1); RC5=$?
[ "$RC5" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5]: живые документы разошлись с миром — bash scripts/docs-refresh-claims.sh run: $(printf '%s' "$OUT5" | grep '^  · ' | head -3)"; }

echo "docs refresh claims: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
