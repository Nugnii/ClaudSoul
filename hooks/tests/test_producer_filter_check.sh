#!/usr/bin/env bash
# test_producer_filter_check.sh — характеризующий тест проверки D88.
# Держит ровно то, на чём проверка спотыкалась при написании: словарь в ПЕРЕМЕННОЙ
# опознаётся так же, как встроенный в grep (первая версия пропустила user-correction-guard),
# и хук, читающий речь ради границы хода или ключа троттла, в улов НЕ попадает.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/scripts/producer-filter-check.sh"
[ -f "$S" ] || { echo "FAIL: $S not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
has() { grep -q -- "$2" <<< "$1" && ok || bad "$3" "не найдено '$2' в: $1"; }
no()  { grep -q -- "$2" <<< "$1" && bad "$3" "лишнее '$2' в: $1" || ok; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
H="$TMP/hooks"; mkdir -p "$H"
: > "$H/hook-input-lib.sh"

# Словарь в переменной, отсева нет — обязан попасть.
cat > "$H/var-dict.sh" <<'EOF'
LAST_USER_TEXT=$(jq -r '.' t)
CORRECTION_REGEX='не так|опять|забудь'
grep -qE -- "$CORRECTION_REGEX" <<< "$LAST_USER_TEXT"
EOF
# Словарь встроен в grep, отсев подключён — обязан числиться благополучным.
cat > "$H/inline-ok.sh" <<'EOF'
. "$HOOKS_DIR/hook-input-lib.sh"
LAST_USER_TEXTS=$(jq -r '.' t)
grep -qiE 'да|нет|может' <<< "$LAST_USER_TEXTS"
EOF
# Речь берётся ради границы хода, словарь к ней не применяется — в улов не должен.
cat > "$H/boundary-only.sh" <<'EOF'
LAST_USER_TEXT=$(jq -r '.' t)
ASSISTANT=$(jq -r '.a' t)
grep -oiE 'почему|зачем|отчего' <<< "$ASSISTANT"
EOF
# Смотрит только на свой вывод — не продюсер по речи собеседника.
cat > "$H/own-output.sh" <<'EOF'
LAST_ASSISTANT=$(jq -r '.a' t)
grep -qE 'один|два|три' <<< "$LAST_ASSISTANT"
EOF

OUT=$( cd "$TMP" && git init -q . 2>/dev/null; bash "$S" 2>&1 )
has "$OUT" "var-dict.sh"      "словарь в переменной опознан"
has "$OUT" "БЕЗ ОТСЕВА"       "раздел находок присутствует"
has "$OUT" "inline-ok.sh"     "хук с отсевом назван как благополучный"
grep -q "БЕЗ ОТСЕВА.*inline-ok" <<< "$OUT" && bad "ложная тревога" "хук с отсевом попал в находки" || ok
no  "$OUT" "boundary-only.sh" "речь ради границы хода находкой не считается"
no  "$OUT" "own-output.sh"    "чтение своего вывода находкой не считается"

RC=$( cd "$TMP" && bash "$S" >/dev/null 2>&1; echo $? )
[ "$RC" = "1" ] && ok || bad "код выхода" "ожидался 1 при находках, получен $RC"
has "$OUT" "замер: находки, не сбой" "метка вердикта на месте (D95)"

echo ""
echo "producer-filter-check tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
