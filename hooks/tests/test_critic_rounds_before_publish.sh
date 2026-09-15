#!/usr/bin/env bash
# test_critic_rounds_before_publish.sh — «Проверка результата» critic-rounds-before-publish.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/critic-rounds-before-publish.sh на подложенном журнале публикаций
#            считает публикации с раундом свежего критика и без него, называет каждую без раунда (в том
#            числе записанный пропуск и нулевое свидетельство), отличает битую строку от «без раунда»,
#            отвечает 0 при полном покрытии, 1 при находках и 2 без журнала или без jq.
# Проверка результата: этот тест.
#
# Повод (D331, 13 сентября 2026). Замер заведён вместе с исполнителем правила (гейт публикации);
# журнал подкладывается через STATE_DIR. Команда БЕРЁТСЯ из шапки инструмента.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/critic-rounds-before-publish.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *critic-rounds-before-publish.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }
hasnt() { grep -Fq -- "$2" <<< "$OUT" && bad "$1" "лишняя строка «$2»" || ok; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
S="$TMP/state"; J="$S/publications.jsonl"
line() {   # tag critic evidence ts-хвост
    printf '{"ts":"2026-09-%s","session":"s","sha":"%040d","tag":"%s","critic":"%s","evidence":%s,"since":"x..HEAD"}\n' "$4" 0 "$1" "$2" "$3"
}
run_tool() {
    OUT=$(cd "$REPO" && STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: журнала нет — 2 «ПРЕДМЕТА НЕТ», не зелёное -------------------------------------------
rm -rf "$S"; mkdir -p "$S"; run_tool
[ "$RC" -eq 2 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'ПРЕДМЕТА НЕТ'

# --- T2: три публикации — две с раундом, одна с записанным пропуском — 1, пропуск назван ------------
rm -rf "$S"; mkdir -p "$S"; { line v1.0.0 rounds 7 "01T10:00:00Z"; line v1.1.0 skipped 0 "05T10:00:00Z"; line v1.2.0 rounds 5 "09T10:00:00Z"; } > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'публикаций в журнале: 3; с раундом свежего критика: 2 (66%); без раунда: 1'
has T2 '· v1.1.0 · skipped · 0'
hasnt T2 '· v1.0.0 ·'

# --- T3: у каждой публикации раунд — 0 ------------------------------------------------------------
rm -rf "$S"; mkdir -p "$S"; { line v1.0.0 rounds 7 "01T10:00:00Z"; line v1.2.0 rounds 5 "09T10:00:00Z"; } > "$J"; run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'с раундом свежего критика: 2 (100%); без раунда: 0'

# --- T4: критик «rounds», но свидетельство 0 — это без раунда -----------------------------------------
rm -rf "$S"; mkdir -p "$S"; { line v1.0.0 rounds 0 "01T10:00:00Z"; } > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 '· v1.0.0 · rounds · 0'

# --- T5: битая строка журнала — названа битой, не «без раунда» ---------------------------------------
rm -rf "$S"; mkdir -p "$S"; { line v1.0.0 rounds 7 "01T10:00:00Z"; echo 'не json'; } > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T5 "rc=$RC — $OUT"
has T5 'битых строк журнала: 1'
has T5 'без раунда: 0'

# --- T6: без jq — 2, не 0 -------------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"; ln -s "$(command -v bash)" "$BIN/bash"; ln -s "$(command -v grep)" "$BIN/grep"
rm -rf "$S"; mkdir -p "$S"; line v1.0.0 rounds 7 "01T10:00:00Z" > "$J"
OUT=$(cd "$REPO" && PATH="$BIN" STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T6 "без jq rc=$RC — $OUT"
has T6 'нужен jq'

# --- T7: поле `suite` ЧИТАЕТСЯ, и три его состояния различены ------------------------------------
# Поле завелось 15 сентября 2026 вместе с прогоном набора по снимку, и прибор родов сразу назвал
# его носителем рода G — «запись без читателя». Читатель здесь; ноги доказывают, что он именно
# РАЗЛИЧАЕТ, а не печатает одно и то же: «поля не было» (публикации до правила) и «пропущен
# осознанно» — разные вещи, свалить их в одно значило бы завести род G заново.
rm -rf "$S"; mkdir -p "$S"; { line v1.0.0 rounds 7 "01T10:00:00Z"; } | sed 's/}$/,"suite":"run"}/' > "$J"; run_tool
has T7 'набор по снимку: прогнан 1; пропущен осознанно 0; поля не было 0'
rm -rf "$S"; mkdir -p "$S"; { line v1.0.0 rounds 7 "01T10:00:00Z"; } | sed 's/}$/,"suite":"skipped"}/' > "$J"; run_tool
has T7b 'набор по снимку: прогнан 0; пропущен осознанно 1; поля не было 0'
rm -rf "$S"; mkdir -p "$S"; line v1.0.0 rounds 7 "01T10:00:00Z" > "$J"; run_tool
has T7c 'набор по снимку: прогнан 0; пропущен осознанно 0; поля не было 1'

echo ""
echo "critic-rounds-before-publish tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
