#!/usr/bin/env bash
# test_knowledge_fields.sh — поля знания: заявка на эскалацию, направление причинности,
# второй контур (D46, D47, D48).
#
# Три случая одного класса: поле или контур существует, но ничто не делает его видимым.
#
#   D46 — заявка на эскалацию. Единственным меняющимся числом был `confirmed_count`, то
#         есть мерилось, насколько знание ПОДКРЕПИЛОСЬ, а не насколько долго по нему не
#         действуют. Строка эскалации стояла дословно одинаковой в 13 дайджестах подряд
#         (W19…W31), и растущее число читалось как «всё под контролем».
#   D47 — `preceded_artifact` отсутствовал во ВСЕХ трёх шаблонах. Пока поля нет в шаблоне,
#         следующая запись создастся без него независимо от любого замера.
#   D48 — FSRS отбирает `case|pattern|principle`, поэтому 104 записи второго контура вне
#         распада по конструкции: `last_confirmed` — 0 записей, `valid_until` — 69 и у всех
#         значение `null`.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -qF -- "$1" <<< "$2"; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

# ============================================================================
# D47 — поле есть во всех трёх шаблонах
# ============================================================================
for f in templates/knowledge.md.tmpl \
         skills/learn/references/case-template.md \
         skills/retro/references/case-template.md; do
    grep -q '^preceded_artifact:' "$REPO/$f" && ok || bad "T1:$f" "нет preceded_artifact — запись создастся без него"
done
# Не спутано с origin: это разные оси, и обе должны быть в шаблоне.
grep -q '^origin:' "$REPO/templates/knowledge.md.tmpl" && ok || bad "T2" "origin пропал из шаблона"

# ============================================================================
# D46 — возраст заявки, а не счётчик подтверждений
# ============================================================================
SCRIPT="$REPO/scripts/escalation-age.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
L="$TMP/lessons"; mkdir -p "$L"

mkknow() { # $1=имя $2=confirmed $3=threshold $4=opened(или пусто)
    { printf -- '---\nname: %s\ntype: pattern\nblocker: true\nconfirmed_count: %s\nescalation_threshold: %s\n' "$1" "$2" "$3"
      [ -n "${4:-}" ] && printf 'escalation_opened: %s\n' "$4"
      printf -- '---\nтело\n'; } > "$L/pattern-$1.md"
}
run() { LESSONS_DIR="$L" ESCALATION_MAX_DAYS="${1:-60}" bash "$SCRIPT" 2>&1; }

# T3: заявки нет — молчит и возвращает 0
mkknow quiet 3 15
OUT=$(run); RC=$?
has "открытых нет" "$OUT" && ok || bad "T3a" "ниже порога — заявка не должна быть открыта: $OUT"
[ "$RC" -eq 0 ] && ok || bad "T3b" "здоровое состояние вернуло $RC"

# T4: свежая заявка открыта, но не просрочена
mkknow fresh 20 15 "$(date +%Y-%m-%d)"
OUT=$(run); RC=$?
has "Заявок открыто: 1" "$OUT" && ok || bad "T4a" "открытая заявка не посчитана: $OUT"
[ "$RC" -eq 0 ] && ok || bad "T4b" "свежая заявка уронила проверку"

# T5: старая заявка роняет проверку и называет ВОЗРАСТ, а не только подтверждения
mkknow stale 20 15 2026-01-01
OUT=$(run); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T5a" "просроченная заявка не уронила проверку"
grep -qE 'открыта [0-9]+ дн' <<< "$OUT" && ok || bad "T5b" "возраст не назван: $OUT"

# T6: отрицательный контроль — с огромным порогом та же заявка проходит.
# Без него зелёный T4b не отличим от «проверка никогда не краснеет».
[ -n "$(run 99999)" ] && OUT=$(run 99999); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T6 отрицательный контроль" "порог не учитывается — краснеет всегда"

# T7: дайджест ставит escalation_opened механически, если его нет
DIG="$REPO/hooks/knowledge-audit-digest.sh"
grep -q 'escalation_opened' "$DIG" && ok || bad "T7" "дайджест не знает про дату открытия заявки"

# T8: поля эскалации задокументированы в META — иначе схема расходится с практикой
for field in escalation_threshold escalation_opened escalation_hint; do
    grep -q "^${field}:" "$REPO/knowledge/META.md" && ok || bad "T8:$field" "поле не описано в META"
done

# ============================================================================
# D48 — второй контур мерится своей мерой, а не FSRS
# ============================================================================
SC="$REPO/scripts/second-contour-freshness.sh"
[ -f "$SC" ] || { echo "FAIL: нет $SC"; exit 1; }
L2="$TMP/lessons2"; mkdir -p "$L2"
# Обе формы записи даты: в кавычках и без. Первая версия разбора требовала голую дату
# и нашла 2 записи из 102 — цифра выглядела бы как «поле почти никто не заполняет».
printf -- "---\nname: e1\ntype: entity\nlast_updated: '2026-04-21'\n---\n" > "$L2/entity-e1.md"
printf -- "---\nname: e2\ntype: entity\nlast_updated: 2026-04-20\n---\n"   > "$L2/entity-e2.md"
printf -- "---\nname: f1\ntype: fact\nvalid_until: null\n---\n"            > "$L2/fact-f1.md"

OUT=$(LESSONS_DIR="$L2" SECOND_CONTOUR_MAX_DAYS=99999 bash "$SC" 2>&1); RC=$?
has "Второй контур: 3 записей" "$OUT" && ok || bad "T9a" "неверный счёт записей: $OUT"
has "с датой обновления 2"     "$OUT" && ok || bad "T9b" "обе формы записи даты не разобраны: $OUT"
has 'null` (активные): 1'                 "$OUT" && ok || bad "T9c" "valid_until: null не посчитан"
[ "$RC" -eq 0 ] && ok || bad "T9d" "при огромном пороге проверка всё равно упала"

# T10: отрицательный контроль — с малым порогом те же записи просрочены
OUT=$(LESSONS_DIR="$L2" SECOND_CONTOUR_MAX_DAYS=1 bash "$SC" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T10 отрицательный контроль" "устаревшие записи не роняют проверку"

# T11: у обоих замеров есть срок в реестре
for id in escalation-age second-contour; do
    grep -q "^${id}" "$REPO/scripts/measurements.tsv" && ok || bad "T11:$id" "замера нет в реестре"
done

echo ""
echo "knowledge fields tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
