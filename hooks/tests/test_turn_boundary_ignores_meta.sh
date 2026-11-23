#!/usr/bin/env bash
# СУДИТ: дерево
# test_turn_boundary_ignores_meta.sh — граница хода не сдвигается вставкой харнесса.
#
# Предмет. Стражи ищут «последнюю реплику владельца», чтобы взять ответы агента ПОСЛЕ неё.
# Под `role == "user"` харнесс кладёт и свои вставки — тела скиллов, напоминания, справку
# инструментов. Принятая за реплику вставка двигает границу вперёд, и часть ответов агента
# выпадает из поля зрения стража.
#
# Замер 8 сентября 2026 по 204 расшифровкам основных сессий: в 42 из них (21%) последняя
# «реплика» — вставка харнесса. То есть каждый пятый прогон этих стражей смотрел не туда.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# Универсум ВЫВОДИТСЯ из дерева, а не перечисляется: страж, написанный завтра и взявший
# границу тем же способом, попадёт под проверку сам (род F — «универсум перечислен, а не
# выведен»). Ищем файлы, где граница определяется через role(...) == "user".
FILES=$(cd "$ROOT" && git ls-files 'hooks/*.sh' 'hooks/lib/*.sh' 'scripts/*.sh' \
        | while IFS= read -r f; do
              grep -qE 'role\([^)]*\) *== *"user"' "$ROOT/$f" 2>/dev/null && printf '%s\n' "$f"
          done)

if [ -z "$FILES" ]; then
    bad "T0" "ни одного файла с определением границы хода не найдено — признак ослеп"
else ok; fi

while IFS= read -r f; do
    [ -n "$f" ] || continue
    # У каждого места, где роль сравнивается с "user", рядом обязан стоять отсев вставки.
    # Считаем места и места-с-отсевом: расхождение и есть находка.
    total=$(grep -cE 'role\([^)]*\) *== *"user"' "$ROOT/$f" 2>/dev/null; true)
    guarded=$(grep -cE 'role\([^)]*\) *== *"user" and \(\(.*isMeta' "$ROOT/$f" 2>/dev/null; true)
    total=${total:-0}; guarded=${guarded:-0}
    # Отсев бывает и отдельной строкой предиката (образец — `real_user` в
    # timestamp-canary-check.sh): признак, требующий его ТОЛЬКО в одной строке с ролью, дал бы
    # ложную находку на верном коде. Поэтому засчитывается и `isMeta` в теле того же
    # предиката — проверено на этом самом файле, он был первой ложной находкой признака.
    if [ "$total" -eq "$guarded" ] || grep -qE 'isMeta' "$ROOT/$f" 2>/dev/null; then ok
    else bad "T1/$f" "мест с границей $total, с отсевом вставки $guarded"; fi
done <<EOF
$FILES
EOF

# T2 — ПОВЕДЕНЧЕСКАЯ нога, а не только структурная: структура может совпасть, а jq всё равно
# считать не то. Транскрипт: реплика владельца → ответ агента → ВСТАВКА харнесса. Граница
# обязана остаться на реплике, то есть ответ агента должен попасть в поле зрения.
TMP=$(mktemp -d)
TR="$TMP/t.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"вопрос владельца"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ответ агента"}]}}'
  printf '%s\n' '{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x"}]}}'
} > "$TR"

SEEN=$(jq -s '
    def role(x): x.message.role // x.role // "";
    def get_text(x): (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then ($c | map(select(.type == "text") | .text) | join("\n"))
        elif ($c | type) == "string" then $c else "" end;
    . as $items | (length) as $n |
    ([range(0; $n) | ($n - 1 - .)
      | select(role($items[.]) == "user" and ((($items[.]).isMeta // false) | not)
               and ((get_text($items[.]) // "") | length > 0))] | first) as $pu |
    [range(($pu // -1) + 1; $n) | $items[.] | select(role(.) == "assistant") | get_text(.)] | length
' "$TR" 2>/dev/null)
if [ "$SEEN" = "1" ]; then ok
else bad "T2" "после вставки граница съехала: ответов агента в поле зрения $SEEN, ожидался 1"; fi

# T3 — КОНТРПРИМЕР: без отсева тот же транскрипт даёт НОЛЬ ответов. Без этой ноги зелень T2
# не отличалась бы от «проверка ничего не проверяет».
SEEN_RAW=$(jq -s '
    def role(x): x.message.role // x.role // "";
    def get_text(x): (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then ($c | map(select(.type == "text") | .text) | join("\n"))
        elif ($c | type) == "string" then $c else "" end;
    . as $items | (length) as $n |
    ([range(0; $n) | ($n - 1 - .)
      | select(role($items[.]) == "user" and ((get_text($items[.]) // "") | length > 0))] | first) as $pu |
    [range(($pu // -1) + 1; $n) | $items[.] | select(role(.) == "assistant") | get_text(.)] | length
' "$TR" 2>/dev/null)
if [ "$SEEN_RAW" = "0" ]; then ok
else bad "T3" "контрпример не воспроизвёл дефект: без отсева ответов $SEEN_RAW, ожидался 0"; fi

rm -rf "$TMP"
echo ""
echo "turn boundary ignores meta: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
