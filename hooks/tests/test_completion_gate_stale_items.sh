#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh hooks/completion-gate.sh
# test_completion_gate_stale_items.sh — пункт, ПЕРЕЖИВШИЙ свою сессию, не лежит вечно:
# гейт на Stop называет самый старый открытый ☐ В СВОЁМ ФАЙЛЕ, когда ни свежих, ни взятых
# в этой сессии ◐ там не осталось.
#
# Результат: запас долга получает владельца — очередь из одного пункта НА ФАЙЛ, а не простыня
# Проверка результата: bash hooks/tests/test_completion_gate_stale_items.sh даёт 0
#
# Повод (18 сентября 2026): страж свежих закрыл ПРИТОК долга, запас не закрыт ничем.
# Замер: из 21 открытого пункта 18 заведены раньше текущей сессии и невидимы по построению.
#
# ЕДИНИЦА ВОЗРАСТА — порядковый номер ВНУТРИ СВОЕГО ФАЙЛА (`BACKLOG_ID_SEQ_RE`). Каждая
# отвергнутая мера закреплена ногой, чтобы возврат к ней был виден сменой знака:
#   T1  — не алфавит:            «D400» лексикографически МЕНЬШЕ «D99», численно наоборот;
#   T8  — не D-нумерация:        `B1`..`B30` живого проекта владельца обязаны называться;
#   T9  — не одна шкала на два файла: чужой `D1` не «старше» своего `D307`;
#   T11 — не голый ID в дросселе: одинаковый номер в двух файлах — два РАЗНЫХ пункта.
#
# РАМКА ЗАДАЁТСЯ, А НЕ НАСЛЕДУЕТСЯ (D461). Гейт прогоняет «Проверку» пункта с
# BACKLOG_CHECKS_NESTED=1 (защита от кольца процессов), а предмет этого теста — сам гейт:
# под маркером он выходит молча, и тест краснел бы В РАМКЕ СВОЕГО ЖЕ ПУНКТА при зелёном
# прямом прогоне. Снимается здесь, а не у каждого вызова: вызовов в файле больше одного.
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
unset BACKLOG_CHECKS_NESTED

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/completion-gate.sh"
LIB="$HOOKS_DIR/backlog-lib.sh"
[ -f "$HOOK" ] || { echo "SKIP: нет $HOOK"; exit 0; }
[ -f "$LIB" ]  || { echo "SKIP: нет $LIB"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"
command -v backlog_snapshot >/dev/null 2>&1 || { echo "FAIL: в библиотеке нет backlog_snapshot"; exit 1; }
[ -n "${BACKLOG_ID_SEQ_RE:-}" ] || { echo "FAIL: в библиотеке нет BACKLOG_ID_SEQ_RE"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"

item() { # $1 метка $2 id $3 хвост (необязательно)
    printf -- '- %s **%s** пункт %s\n  **Проверка.** `false` → 0\n%s' "$1" "$2" "$2" "${3:+  $3
}"
}
run() { # $1 главный бэклог $2 sid [$3 локальный] → очередь, добавленная этим вызовом
    alerts_clear "$STATE"
    printf '{"session_id":"%s","cwd":"/"}' "$2" \
      | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$1" CG_LOCAL_BACKLOG="${3:-}" \
            STATE_DIR="$STATE" bash "$HOOK" >"$TMP/stdout" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_completion_gate_stale_items.sh:$LINENO" >&2; exit 1; }
    alerts_of "$STATE"
}
# Счёт «страж говорил» ведётся ФАЙЛОМ, а не переменной: функция зовётся из подстановки
# команд `$(...)`, то есть в подпроцессе, и `SPOKE=$((SPOKE+1))` до родителя не доходит.
# Первая редакция этого контроля дала «говорил 1 раз» при девяти настоящих срабатываниях —
# прибор нёс дефект того же рода, что искал (pattern-new-instrument-carries-its-own-defect).
: > "$TMP/spoke"
stale_line() { _l=$(grep 'Залежавшийся пункт ждёт очереди' <<< "$1" | head -1); [ -n "$_l" ] && printf 'x\n' >> "$TMP/spoke"; printf '%s' "$_l"; }
fresh_line() { grep 'ждут взятия' <<< "$1" | head -1; }

# --- T1: самый старый ПО НОМЕРУ, а не по алфавиту -------------------------------------
B="$TMP/m1.md"; { item ☐ D400; item ☐ D99; } > "$B"
backlog_snapshot "$STATE" st1 "$B" >/dev/null
OUT=$(run "$B" st1)
case "$(stale_line "$OUT")" in
    *"очереди: m1.md:D99 "*) ok ;;
    *"m1.md:D400"*) bad T1 "взят алфавитный минимум D400 вместо числового D99: $OUT" ;;
    *) bad T1 "залежавшийся не назван: $OUT" ;;
esac

# --- T2: взятый в ЭТОЙ сессии ◐ того же файла глушит ----------------------------------
B="$TMP/m2.md"; { item ☐ D400; item ☐ D99; } > "$B"
backlog_snapshot "$STATE" st2 "$B" >/dev/null
{ item ◐ D400; item ☐ D99; } > "$B"
OUT=$(run "$B" st2)
[ -z "$(stale_line "$OUT")" ] && ok || bad T2 "при взятом в сессии ◐ страж заговорил: $OUT"
# T2b: то же под ru_RU.UTF-8 (D1158, пятый круг): метки снимка сравнивались сортировкой локали, «☐» == «◐», и ◐,
# взятый в сессии, новым не бывал. Пустые LC_ALL и LC_COLLATE — снять внешнюю рамку. Нога судит только при живой локали
# (awk сворачивает метки), иначе молчание ничего не доказывает и нога называет себя (D1171, M3 скептика).
ru_live() { env -u LC_ALL -u LC_COLLATE LANG=ru_RU.UTF-8 awk 'BEGIN { exit !("☐" == "◐") }'; }
if ru_live; then
    B="$TMP/m2b.md"; { item ☐ D400; item ☐ D99; } > "$B"
    backlog_snapshot "$STATE" st2b "$B" >/dev/null
    { item ◐ D400; item ☐ D99; } > "$B"
    OUT=$(LC_ALL= LC_COLLATE= LANG=ru_RU.UTF-8 run "$B" st2b)
    [ -z "$(stale_line "$OUT")" ] && ok || bad T2b "под ru_RU.UTF-8 при взятом в сессии ◐ страж заговорил: $OUT"
else
    echo "T2b не судит: локаль ru_RU.UTF-8 здесь не сворачивает метки в awk"
fi

# --- T3: свежий ☐ не глушит старейший — очередь по возрасту (решение владельца 29.10.2026) ---
B="$TMP/m3.md"; { item ☐ D99; } > "$B"
backlog_snapshot "$STATE" st3 "$B" >/dev/null
{ item ☐ D99; item ☐ D401; } > "$B"
OUT=$(run "$B" st3)
[ -n "$(fresh_line "$OUT")" ] && ok || bad T3a "свежий D401 не назван: $OUT"
case "$(stale_line "$OUT")" in
    *"m3.md:D99"*) ok ;;
    *) bad T3b "при свежем D401 старейший D99 не назван: $OUT" ;;
esac
case "$(fresh_line "$OUT")" in
    *"КОНЕЦ очереди"*) ok ;;
    *) bad T3c "свежий не отправлен в конец очереди: $(fresh_line "$OUT")" ;;
esac

# --- T4: дроссель и сдвиг очереди ------------------------------------------------------
B="$TMP/m4.md"; { item ☐ D99; item ☐ D400; } > "$B"
backlog_snapshot "$STATE" st4 "$B" >/dev/null
OUT1=$(run "$B" st4); OUT2=$(run "$B" st4)
[ -n "$(stale_line "$OUT1")" ] && ok || bad T4a "первый вызов промолчал: $OUT1"
[ -z "$(stale_line "$OUT2")" ] && ok || bad T4b "повтор того же состава прозвучал снова: $OUT2"
{ item ☑ D99; item ☐ D400; } > "$B"
OUT3=$(run "$B" st4)
case "$(stale_line "$OUT3")" in
    *"m4.md:D400"*) ok ;;
    *) bad T4c "после ухода D99 следующий D400 не назван: $OUT3" ;;
esac

# --- T5: пункт-ОЖИДАНИЕ залежавшимся не считается --------------------------------------
B="$TMP/m5.md"; { item ☐ D99 '**Проверка возврата:** `false`'; } > "$B"
backlog_snapshot "$STATE" st5 "$B" >/dev/null
OUT=$(run "$B" st5)
[ -z "$(stale_line "$OUT")" ] && ok || bad T5 "ожидание с командой возврата названо залежавшимся: $OUT"

# --- T6: stdout ПУСТ — непустой additionalContext на Stop перезапускал бы ход ----------
[ -s "$TMP/stdout" ] && bad T6 "stdout не пуст: $(head -c 120 "$TMP/stdout")" || ok

# --- T8 (прожарка F2): НЕ-D нумерация — живой проект владельца идёт на B1..B30 ---------
B="$TMP/m8.md"; { item ☐ B30; item ☐ B1; item ☐ B10; } > "$B"
backlog_snapshot "$STATE" st8 "$B" >/dev/null
OUT=$(run "$B" st8)
case "$(stale_line "$OUT")" in
    *"m8.md:B1 "*) ok ;;
    *) bad T8 "не-D нумерация невидима (BACKLOG_ID_NUM_RE вместо SEQ?): $OUT" ;;
esac

# --- T9 (прожарка F1): ДВА ФАЙЛА — две шкалы, чужой D1 не «старше» своего D307 ---------
M="$TMP/m9.md"; L="$TMP/l9.md"
{ item ☐ D307; item ☐ D460; } > "$M"; { item ☐ D1; } > "$L"
backlog_snapshot "$STATE" st9 "$M" >/dev/null; backlog_snapshot "$STATE" st9 "$L" >/dev/null
OUT=$(run "$M" st9 "$L")
LINE=$(stale_line "$OUT")
case "$LINE" in *"m9.md:D307"*) ok ;; *) bad T9a "долг своего файла заглушён чужой шкалой: $OUT" ;; esac
case "$LINE" in *"l9.md:D1"*) ok ;; *) bad T9b "пункт второго файла не назван: $OUT" ;; esac

# --- T10 (прожарка F4): ◐ в ЧУЖОМ файле не глушит долг своего -------------------------
M="$TMP/m10.md"; L="$TMP/l10.md"
{ item ☐ D307; } > "$M"; { item ☐ B1; } > "$L"
backlog_snapshot "$STATE" s10 "$M" >/dev/null; backlog_snapshot "$STATE" s10 "$L" >/dev/null
{ item ◐ B1; } > "$L"                        # работа взята в ЧУЖОМ проекте
OUT=$(run "$M" s10 "$L")
case "$(stale_line "$OUT")" in
    *"m10.md:D307"*) ok ;;
    *) bad T10 "◐ чужого проекта заглушил долг этого файла: $OUT" ;;
esac

# --- T11 (прожарка F3): одинаковый номер в двух файлах — два РАЗНЫХ пункта ------------
M="$TMP/m11.md"; L="$TMP/l11.md"
{ item ☐ D307; item ☐ D500; } > "$M"; { item ☐ D307; } > "$L"
backlog_snapshot "$STATE" s11 "$M" >/dev/null; backlog_snapshot "$STATE" s11 "$L" >/dev/null
OUT1=$(run "$M" s11 "$L"); stale_line "$OUT1" >/dev/null
{ item ☑ D307; item ☐ D500; } > "$M"          # закрыт СВОЙ D307, чужой остался
OUT2=$(run "$M" s11 "$L")
case "$(stale_line "$OUT2")" in
    *"m11.md:D500"*) ok ;;
    *) bad T11 "чужой D307 держит ключ дросселя — свой D500 не назван: $OUT2" ;;
esac

# --- T7 (НАЗВАННЫЙ ПРЕДЕЛ): ◐, взятый до старта сессии, невидим ----------------------
# Условие снятия — поле «взят когда» у ◐; нога закрепляет предел сменой знака.
B="$TMP/m7.md"; { item ◐ D400; item ☐ D99; } > "$B"
backlog_snapshot "$STATE" st7 "$B" >/dev/null
OUT=$(run "$B" st7)
[ -n "$(stale_line "$OUT")" ] && ok || bad T7 "предел сменил знак: ◐ прошлых сессий стал видимым — сними ногу вместе с пределом"

# --- T13: метка сравнивается байтами, а не сортировкой локали (D1158, четвёртый круг) -----
# `/usr/bin/awk` macOS под `ru_RU.UTF-8` считает «☐» равной «◐»: залежавшимся ☐ назывался пункт в работе D5.
# Нет такой локали — нога не судит и называет себя (D1171, M3 скептика).
if ru_live; then
B="$TMP/m13.md"; { item ◐ D5; item ☐ D9; } > "$B"
backlog_snapshot "$STATE" st13 "$B" >/dev/null
alerts_clear "$STATE"
printf '{"session_id":"st13","cwd":"/"}' \
  | env -u BACKLOG_CHECKS_NESTED -u LC_ALL -u LC_COLLATE LANG=ru_RU.UTF-8 CG_BACKLOG="$B" STATE_DIR="$STATE" bash "$HOOK" >/dev/null 2>&1
OUT=$(alerts_of "$STATE")
case "$(stale_line "$OUT")" in
    *"очереди: m13.md:D9 "*) ok ;;
    *"m13.md:D5"*) bad T13 "под ru_RU.UTF-8 залежавшимся ☐ назван пункт в работе D5: $OUT" ;;
    *) bad T13 "залежавшийся не назван: $OUT" ;;
esac
else
    echo "T13 не судит: локаль ru_RU.UTF-8 здесь не сворачивает метки в awk"
fi

# --- T12: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — прибор вообще говорил ------------------------------
# Без него тишина зеленит T2, T3b, T5 и любой блок, вырезанный целиком: у них ожидаемый
# исход И ЕСТЬ молчание. Прожарка 18 сентября: 4 ноги из 10 проходили на пустом месте.
SPOKE=$(grep -c x "$TMP/spoke" 2>/dev/null || true)
[ "${SPOKE:-0}" -ge 5 ] && ok || bad T12 "страж заговорил лишь $SPOKE раз(а) — ноги молчания зеленеют от неработающего блока"

echo "completion-gate stale items: $PASS passed, $FAIL failed (страж говорил $SPOKE раз)"
exit $(( FAIL != 0 ))
