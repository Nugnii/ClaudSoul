#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh hooks/completion-gate.sh scripts/backlog-return-check.sh
# test_adv2_cmdring_depth_max_nonnumeric.sh — нечисловой предел глубины ограды кольца (BACKLOG_CMD_DEPTH_MAX, D503) не немит completion-gate и не снимает предел у оболочечных исполнителей.
#
# Атака (противник ограды кольца, раунд 2, 1 октября 2026). Предел — объявленная ручка
# (`BACKLOG_CMD_DEPTH_MAX="${BACKLOG_CMD_DEPTH_MAX:-2}"`), значение берётся из окружения как есть и
# нигде не сверяется. Два читателя одного значения расходятся на нечисловом:
#   · питоновские исполнители считают `int(...)` прямо в цикле «Проверок» — ValueError роняет разбор
#     completion-gate на первой же команде, гейт читает пустой вывод без «#CG_STATUS» и МОЛЧИТ: красное
#     ☑ не названо никем (тот же род, что «краш питона читался чистым», прожарка 31.08);
#   · оболочечные (`[ "$n" -ge "$BACKLOG_CMD_DEPTH_MAX" ]`) получают ошибку `test` = «ложь», то есть
#     предела нет вовсе, и дерево вызовов снова растёт как e·K! (вход закрытого класса 2).
#
# Рамка: (G) ☑ D9100 с красной «Проверкой» под гейтом; (R) K=4 открытых пункта, условие возврата
# каждого зовёт стража возврата на том же бэклоге (как нога R3 test_backlog_cmd_ring.sh), счётчик с
# предохранителем 200. Контроль у обеих — тот же вход без ручки.
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

# --- (G) completion-gate
G="$T/g"; mkdir -p "$G/c" "$G/s"
printf -- '- ☑ **D9100** закрытие с красной «Проверкой»\n  **Результат.** проба\n  **Проверка.** `false` → 0\n' > "$G/BACKLOG.md"
printf '{"session_id":"adv2-depth-nan-c","cwd":"/"}' | env CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$G/c" \
    bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_cmdring_depth_max_nonnumeric.sh:$LINENO" >&2; exit 1; }
AC=$(alerts_of "$G/c" || true)
grep -q 'D9100' <<< "$AC" && ok || bad TC-G "контроль: без ручки гейт не назвал красное ☑ D9100 — рамка не собралась: «${AC}»"
printf '{"session_id":"adv2-depth-nan","cwd":"/"}' | env BACKLOG_CMD_DEPTH_MAX=abc CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$G/s" \
    bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_cmdring_depth_max_nonnumeric.sh:$LINENO" >&2; exit 1; }
AG=$(alerts_of "$G/s" || true)
grep -q 'D9100' <<< "$AG" && ok \
    || bad T-G "при BACKLOG_CMD_DEPTH_MAX=abc completion-gate промолчал о красном ☑ D9100: разбор упал на int() предела, а пустой вывод без статуса гейт не называет никак; очередь: «${AG}»"

# --- (R) страж возврата: предел глубины у оболочечного исполнителя
K=4
leg() {  # <каталог> [значение ручки] → число исполнений условий возврата
    local d="$1" i=1
    mkdir -p "$d" || { echo "подготовка мира не удалась: hooks/tests/test_adv2_cmdring_depth_max_nonnumeric.sh:$LINENO" >&2; exit 1; }
    git -C "$d" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv2_cmdring_depth_max_nonnumeric.sh:$LINENO" >&2; exit 1; }
    cat > "$d/again.sh" <<EOF
echo "\$1" >> "$d/cnt"
[ "\$(wc -l < "$d/cnt")" -ge 200 ] && exit 1
cd "$d" && bash "$REPO/scripts/backlog-return-check.sh" >/dev/null 2>&1
exit 1
EOF
    : > "$d/BACKLOG.md"
    while [ "$i" -le "$K" ]; do
        printf -- '- ☐ **D930%s** проба дерева\n  **Проверка.** `false` → 0\n  **Проверка возврата:** `bash %s/again.sh D930%s`\n\n' "$i" "$d" "$i" >> "$d/BACKLOG.md"
        i=$((i + 1))
    done
    if [ -n "${2:-}" ]; then
        ( cd "$d" && BACKLOG_CMD_DEPTH_MAX="$2" bash "$REPO/scripts/backlog-return-check.sh" ) >/dev/null 2>&1  || true  # предмет свидетеля: код ненулевой при сроке и кольце штатен, итог читают строки ниже (D1262)
    else
        ( cd "$d" && bash "$REPO/scripts/backlog-return-check.sh" ) >/dev/null 2>&1  || true  # предмет свидетеля: код ненулевой при сроке и кольце штатен, итог читают строки ниже (D1262)
    fi
    if [ -f "$d/cnt" ]; then wc -l < "$d/cnt" | tr -d ' '; else echo 0; fi
}
NC=$(leg "$T/r0")
{ [ "$NC" -gt 0 ] && [ "$NC" -le $((K * K)) ]; } && ok || bad TC-R "контроль: без ручки страж возврата исполнил условия $NC раз (ожидалось от 1 до K²=$((K * K)))"
NR=$(leg "$T/r1" abc)
[ "$NR" -le $((K * K)) ] && ok \
    || bad T-R "при BACKLOG_CMD_DEPTH_MAX=abc страж возврата исполнил условия $NR раз при K=$K (потолок K²=$((K * K)), без ручки — $NC): ошибка \`test\` читается «не глубже», предела нет"

echo "adv2 cmdring depth max non-numeric: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
