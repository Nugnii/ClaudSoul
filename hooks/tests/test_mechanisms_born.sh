#!/usr/bin/env bash
# test_mechanisms_born.sh — характеризующий тест метрики D96 (кандидат 3).
# Повод: фаза ablation main-1 закрылась с нулём завершённых троек, а вопрос «становится ли
# система лучше оттого, что учится» остался. Контрасты его не берут — их единица ЗАДАЧА;
# здесь единица ПЕРИОД. Тест держит три вещи: тесты механизмом не считаются, признак
# происхождения читается из сообщения коммита, пустое окно даёт вердикт кодом.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/scripts/mechanisms-born.sh"
[ -f "$S" ] || { echo "FAIL: $S not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
has() { grep -q -- "$2" <<< "$1" && ok || bad "$3" "не найдено '$2' в: $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p hooks scripts hooks/tests

add() { # add <путь> <сообщение>
    mkdir -p "$(dirname "$1")"; printf '#!/usr/bin/env bash\n' > "$1"
    git add -A && git commit -q -m "$2"
}

# Механизм со ссылкой на пункт долга, механизм со ссылкой на знание, механизм без ссылки,
# и тест — последний механизмом считаться не должен.
add hooks/with-debt.sh       "feat(hooks): страж по пункту D42"
add scripts/with-knowledge.py "feat(scripts): замер по case-2026-08-27-something"
add scripts/plain.sh          "feat(scripts): просто захотелось"
add hooks/tests/test_x.sh     "test: покрытие D42"

OUT=$(bash "$S" 365 2>&1)
has "$OUT" "новых механизмов      : 3" "тест механизмом не считается"
has "$OUT" "из них родились из знания : 2" "ссылка на долг и на знание опознаны"
has "$OUT" "with-debt.sh" "механизм по пункту долга назван"
has "$OUT" "with-knowledge.py" "механизм по знанию назван"
grep -q "plain.sh" <<< "$OUT" && bad "без ссылки" "механизм без повода попал в список: $OUT" || ok

# Окно, в котором ни один механизм не сослался на знание — вердикт кодом 1 и метка,
# чтобы error-tracker не счёл это сбоем (D95).
rm -rf "$TMP/.git" hooks scripts
git init -q . && git config user.email t@t && git config user.name t
mkdir -p scripts
add scripts/only-plain.sh "chore: без повода"
OUT=$(bash "$S" 365 2>&1); RC=$?
[ "$RC" = "1" ] && ok || bad "пустое окно" "ожидался код 1, получен $RC"
has "$OUT" "замер: находки, не сбой" "метка вердикта на месте"

echo ""
echo "mechanisms-born tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
