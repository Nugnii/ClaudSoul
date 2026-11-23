#!/usr/bin/env bash
# test_disagreement_revocation_check.sh — «Проверка результата» disagreement-revocation-check.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/disagreement-revocation-check.sh зелена на журнале, где все
#            строки компактны, набор полей известен и каждый отзыв имеет ровно один более ранний
#            оригинал; красна и называет класс на строке в чужом формате (пробел после двоеточия),
#            на неизвестном наборе полей, на отзыве без оригинала и на битой строке; без журнала —
#            0 «журнала ещё нет»; неизвестный режим — 2.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного. Журнал
# подкладывается через STATE_DIR. Команда БЕРЁТСЯ из шапки инструмента, как в
# test_split_provenance_log.sh.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/disagreement-revocation-check.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *disagreement-revocation-check.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
S="$TMP/state"; J="$S/disagreement-outcomes.jsonl"
ORIG='{"date":"2026-09-01","session":"s1","knowledge":"pattern-x","confidence":4,"outcome":"confirmed","case":"c1"}'
REVO='{"date":"2026-09-02","session":"s1","knowledge":"pattern-x","confidence":4,"outcome":"revoked","case":"c1","supersedes":"confirmed","note":"n"}'
fresh() { rm -rf "$S"; mkdir -p "$S"; }
run_tool() {
    OUT=$(cd "$REPO" && STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: журнала нет — 0 и сказано -------------------------------------------------------------
fresh; run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'журнала ещё нет'

# --- T2: компактный журнал, отзыв сопоставлен — 0 ----------------------------------------------
fresh; printf '%s\n%s\n' "$ORIG" "$REVO" > "$J"; run_tool
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'журнал контура: 2 строк, отзывов 1'
has T2 'формат един, отзывы сопоставлены'

# --- T3: строка в чужом формате (пробел после двоеточия) — 1 ----------------------------------
fresh; printf '%s\n{"date": "2026-09-01","session":"s1","knowledge":"pattern-y","confidence":4,"outcome":"confirmed","case":"c1"}\n' "$ORIG" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'строк в ЧУЖОМ формате (пробел после двоеточия): 1'

# --- T4: неизвестный набор полей — 1 ------------------------------------------------------------
fresh; printf '%s\n{"date":"2026-09-01","session":"s1","knowledge":"pattern-y","confidence":4,"outcome":"confirmed","case":"c1","foo":1}\n' "$ORIG" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'строк с неизвестным набором полей: 1'

# --- T5: отзыв без оригинала — 1 ----------------------------------------------------------------
fresh; printf '%s\n' "$REVO" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T5 "rc=$RC — $OUT"
has T5 'отзывов без сопоставимого оригинала: 1'

# --- T6: битая строка — 1 -------------------------------------------------------------------
fresh; printf '%s\nне json\n' "$ORIG" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T6 "rc=$RC — $OUT"
has T6 'битых строк JSON: 1'

# --- T7: неизвестный режим — 2, не умолчание ------------------------------------------------
fresh; OUT=$(cd "$REPO" && STATE_DIR="$S" bash "$TOOL" bogus 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T7 "rc=$RC — $OUT"
has T7 'применение'

# --- T8: python3 нет в PATH, журнал в чужом формате — 2, не 0 «формат един» -----------------------
fresh; printf '{"date": "2026-09-01","session":"s1","knowledge":"pattern-y","confidence":4,"outcome":"confirmed","case":"c1"}\n' > "$J"
BIN="$TMP/bin"; mkdir -p "$BIN"; ln -s "$(command -v bash)" "$BIN/bash"
OUT=$(cd "$REPO" && PATH="$BIN" STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T8 "без python3 rc=$RC — $OUT"
has T8 'нужен python3'

# --- T9–T11: у предиката сопоставления четыре условия, по ноге на каждое (мутант, снимающий одно,
# обязан краснить): та же сессия; оригинал РАНЬШЕ отзыва; оригинал гасится РОВНО ОДНИМ отзывом --------
REVO_S2=${REVO/\"session\":\"s1\"/\"session\":\"s2\"}
fresh; printf '%s\n%s\n' "$ORIG" "$REVO_S2" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T9 "отзыв из другой сессии сопоставлен: rc=$RC — $OUT"
has T9 'отзывов без сопоставимого оригинала: 1'
ORIG_LATE=${ORIG/\"date\":\"2026-09-01\"/\"date\":\"2026-09-03\"}
fresh; printf '%s\n%s\n' "$ORIG_LATE" "$REVO" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T10 "оригинал позже отзыва сопоставлен: rc=$RC — $OUT"
has T10 'отзывов без сопоставимого оригинала: 1'
REVO_B=${REVO/\"date\":\"2026-09-02\"/\"date\":\"2026-09-04\"}
fresh; printf '%s\n%s\n%s\n' "$ORIG" "$REVO" "$REVO_B" > "$J"; run_tool
[ "$RC" -eq 1 ] && ok || bad T11 "второй отзыв на тот же оригинал сопоставлен: rc=$RC — $OUT"
has T11 'отзывов без сопоставимого оригинала: 1'

echo ""
echo "disagreement-revocation-check tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
