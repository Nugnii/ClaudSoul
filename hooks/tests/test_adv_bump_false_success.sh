#!/usr/bin/env bash
# test_adv_bump_false_success.sh — АТАКА: «✅ confirmed_count++» и код возврата 0 печатаются
# независимо от того, изменилось ли хоть что-нибудь.
#
# Между записью и отчётом нет ни одной проверки. `cat "$TMP_OUT" > "$FILE"` (строка 289)
# не проверяется вовсе; awk, не нашедший frontmatter, молча ничего не меняет, а запасная
# вставка поля (строка 282) ищет ВТОРОЙ разделитель `---` и без него не срабатывает.
# Дальше идёт `dis_close_outcome` — durable-запись `confirmed_knowledge` и гашение pending, —
# затем безусловный `echo "✅ …"`. Скрипт заканчивается на echo, поэтому код возврата 0.
#
# Итог: счётчик не двинулся, а система считает встречу разобранной — очередь погашена,
# журнал утверждает «знание подтвердилось». Ровно та асимметрия, против которой написана
# шапка скрипта (строки 70-78): «кто положился на скрипт — тот инкрементировал счётчик,
# но в журнал не попадал». Здесь наоборот, и это хуже: журнал пишется без счётчика.
#
# Проба 1 — знание без frontmatter. Достижимость низкая: в боевой базе такой файл один
# (META.md, знанием не является). Ценность пробы в том, что она показывает механизм без
# трюков с правами.
# Проба 2 — файл, недоступный для записи. Достижимость: любой отказ записи (права, ENOSPC,
# квота) идёт этим же путём, поскольку результат `cat >` не проверяется никогда.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"
rc=0

# --- Проба 1: файл без frontmatter ---
printf 'заготовка знания без frontmatter\nconfirmed_count: 5\n' > "$LESSONS_DIR/pattern-nofm.md"
before=$(cat "$LESSONS_DIR/pattern-nofm.md")
out1=$(bash "$SCRIPT" pattern-nofm confirmed "подтвердилось" case-x.md 2>&1); rc1=$?
after=$(cat "$LESSONS_DIR/pattern-nofm.md")
echo "проба 1: rc=$rc1, вывод: $out1"
if [ "$before" = "$after" ]; then
    if [ "$rc1" -eq 0 ]; then
        echo "FAIL [1]: файл не изменён ни на байт, а скрипт вернул 0 и отчитался успехом"
        rc=1
    fi
    if grep -q '"outcome":"confirmed_knowledge"' "$STATE_DIR/disagreement-outcomes.jsonl" 2>/dev/null; then
        echo "FAIL [1]: в durable-журнал записано confirmed_knowledge при неизменённом знании"
        rc=1
    fi
fi

# --- Проба 2: файл недоступен для записи ---
cat > "$LESSONS_DIR/pattern-ro.md" <<'KN'
---
name: проба
confidence: 4
confirmed_count: 2
contradicted_count: 0
provenance_log: []
---
тело
KN
chmod 444 "$LESSONS_DIR/pattern-ro.md"
if : > "$LESSONS_DIR/pattern-ro.md" 2>/dev/null; then
    echo "SKIP [2]: запись в файл 0444 не отбивается (вероятно root) — проба неприменима"
else
    out2=$(bash "$SCRIPT" pattern-ro confirmed "подтвердилось" 2>&1); rc2=$?
    cnt=$(grep '^confirmed_count:' "$LESSONS_DIR/pattern-ro.md")
    echo "проба 2: rc=$rc2, счётчик в файле: $cnt"
    if [ "$cnt" = "confirmed_count: 2" ]; then
        if [ "$rc2" -eq 0 ]; then
            echo "FAIL [2]: запись отбита, счётчик остался 2, а скрипт вернул 0. Вывод:"
            printf '%s\n' "$out2" | sed 's|^|        |'
            rc=1
        fi
        if grep -q '"knowledge":"pattern-ro.md","confidence":[0-9]*,"outcome":"confirmed_knowledge"' \
             "$STATE_DIR/disagreement-outcomes.jsonl" 2>/dev/null; then
            echo "FAIL [2]: журнал утверждает confirmed_knowledge для знания, которое не тронуто"
            rc=1
        fi
    fi
fi
chmod 644 "$LESSONS_DIR/pattern-ro.md" 2>/dev/null || true

# --- Проба 3: недоступен для записи ЖУРНАЛ, а не знание ---
# Пробы 1-2 бьют по записи файла знания, и она проверяется с 26 августа 2026. Запись
# СУЖДЕНИЯ в долговременный журнал не проверялась до 1 сентября 2026: неотмеченный `>>`,
# скрипт без `set -e`, и веер гашения очереди шёл следом. Прогон давал «✅ … погашено
# записей: 1» и код 0 при нуле строк в журнале — то есть запись очереди закрывалась БЕЗ
# парного суждения. Это тот самый класс, который разбор D247 сперва объявил историческим.
cat > "$LESSONS_DIR/pattern-jr.md" <<'KN'
---
name: проба журнала
confidence: 3
confirmed_count: 1
contradicted_count: 0
---
тело
KN
printf '{"date":"2026-09-01T00:00:00Z","key":"pattern-jr","outcome":"pending","confidence":3,"tool":"probe"}\n' \
    > "$STATE_DIR/disagreement-pending-JRPROBE.jsonl"
: > "$STATE_DIR/disagreement-outcomes.jsonl"
chmod 444 "$STATE_DIR/disagreement-outcomes.jsonl"
if printf 'x' >> "$STATE_DIR/disagreement-outcomes.jsonl" 2>/dev/null; then
    echo "SKIP [3]: дозапись в файл 0444 не отбивается (вероятно root) — проба неприменима"
else
    out3=$(DIS_SESSION=JRPROBE bash "$SCRIPT" pattern-jr not_applicable "проба" 2>&1); rc3=$?
    jr_lines=$(wc -l < "$STATE_DIR/disagreement-outcomes.jsonl" | tr -d ' ')
    pend_lines=$(wc -l < "$STATE_DIR/disagreement-pending-JRPROBE.jsonl" | tr -d ' ')
    echo "проба 3: rc=$rc3, строк в журнале: $jr_lines, строк в очереди: $pend_lines"
    if [ "$jr_lines" -eq 0 ]; then
        if [ "$rc3" -eq 0 ]; then
            echo "FAIL [3]: суждение не записано, а скрипт вернул 0. Вывод:"
            printf '%s\n' "$out3" | sed 's|^|        |'
            rc=1
        fi
        if [ "$pend_lines" -ne 1 ]; then
            echo "FAIL [3]: очередь погашена ($pend_lines строк) при незаписанном суждении —"
            echo "          гашение без парного суждения, ровно класс D247"
            rc=1
        fi
    fi
fi
chmod 644 "$STATE_DIR/disagreement-outcomes.jsonl" 2>/dev/null || true

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: успех отчитывается только после проверенной записи; иначе ненулевой код"
    echo "          и отсутствие записи об исходе."
    echo "Факт:     журнал и гашение очереди опережают проверку, которой нет:"
    sed 's|^|    |' "$STATE_DIR/disagreement-outcomes.jsonl" 2>/dev/null
    echo "adv bump false-success: КРАСНЫЙ"
else
    echo "adv bump false-success: passed"
fi
exit "$rc"
