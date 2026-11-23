#!/usr/bin/env bash
# СУДИТ: hooks/disagreement-lib.sh
# test_harvest_failures.sh — жнец провалов кладёт pending-кандидата и уважает окно и дедуп.
# en: failure harvester writes pending candidates and honours window, dedup and sources.
#
# Проверяется: инжект + серия провалов в окне → кандидат class=failure_after_injection;
# провал ВНЕ окна — нет; повторный прогон — без дублей; внешнее событие (ci-red) — тоже
# источник; ранги 4-6 (injected=false) кандидатов не порождают.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/disagreement-lib.sh"
# shellcheck source=/dev/null
source "$LIB"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PEND="$TMP/disagreement-pending-s1.jsonl"

cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-01T10:00:00Z","file":"pattern-a.md","confidence":4,"injected":true,"session_id":"s1","rank":1}
{"date":"2026-09-01T10:00:00Z","file":"pattern-ctl.md","confidence":4,"injected":false,"session_id":"s1","rank":5}
{"date":"2026-09-01T08:00:00Z","file":"pattern-old.md","confidence":4,"injected":true,"session_id":"s1","rank":2}
EOF
cat > "$TMP/error-streak-log-s1.jsonl" << 'EOF'
{"ts":"2026-09-01T10:10:00Z","attempts":2}
EOF

# --- T1: инжект за 10 минут до провала → один кандидат нужного класса ---
MADE=$(dis_harvest_failures "s1" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-a"' "$PEND" 2>/dev/null \
   && grep -q '"class":"failure_after_injection"' "$PEND"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: made=$MADE $(cat "$PEND" 2>/dev/null)"; fi

# --- T2: pattern-old (2 часа до провала) вне окна 30 мин — кандидата нет ---
grep -q '"key":"pattern-old"' "$PEND" 2>/dev/null \
    && { FAIL=$((FAIL+1)); echo "FAIL [T2]: вне окна попал"; } || PASS=$((PASS+1))

# --- T3: контрольный ранг (injected=false) кандидата не порождает ---
grep -q '"key":"pattern-ctl"' "$PEND" 2>/dev/null \
    && { FAIL=$((FAIL+1)); echo "FAIL [T3]: контроль попал"; } || PASS=$((PASS+1))

# --- T4: повторный прогон — дедуп, счёт 0 ---
MADE=$(dis_harvest_failures "s1" "$TMP" 30 3)
[ "$MADE" = "0" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4]: дубль made=$MADE"; }

# --- T5: внешнее событие (ci-red) — второй источник времени провала ---
cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-02T12:00:00Z","file":"pattern-b.md","confidence":3,"injected":true,"session_id":"s2","rank":1}
EOF
printf '{"ts":"2026-09-02T12:05:00Z","kind":"ci-red","detail":"прогон 1 для x: failure","status":"open"}\n' > "$TMP/pending-events.jsonl"
MADE=$(dis_harvest_failures "s2" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-b"' "$TMP/disagreement-pending-s2.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: made=$MADE"; fi

# --- T6: без источников провала — ноль, не падение ---
MADE=$(dis_harvest_failures "s3" "$TMP" 30 3)
[ "$MADE" = "0" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6]: made=$MADE"; }

# --- T7: hotfix-repeat и resurrected — тоже негативные события мира ---
# Диагностика 2026-08-31: в живом pending-events.jsonl 26 строк, из них 21 hotfix-repeat
# и 1 resurrected — селектор жнеца знал только revert|ci-red и был слеп к 22 из 26.
# Самый частый вид негативного события не жнётся вовсе.
cat > "$TMP/injection-log.jsonl" << 'EOF'
{"date":"2026-09-03T09:00:00Z","file":"pattern-hf.md","confidence":3,"injected":true,"session_id":"s4","rank":1}
{"date":"2026-09-03T09:00:00Z","file":"pattern-rz.md","confidence":3,"injected":true,"session_id":"s5","rank":1}
EOF
cat > "$TMP/pending-events.jsonl" << 'EOF'
{"ts":"2026-09-03T09:07:00Z","kind":"hotfix-repeat","detail":"второй fix того же файла","status":"open"}
{"ts":"2026-09-03T09:08:00Z","kind":"resurrected","detail":"закрытый пункт ожил","status":"open"}
EOF
MADE=$(dis_harvest_failures "s4" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-hf"' "$TMP/disagreement-pending-s4.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7a]: hotfix-repeat не пожат, made=$MADE"; fi
MADE=$(dis_harvest_failures "s5" "$TMP" 30 3)
if [ "$MADE" = "1" ] && grep -q '"key":"pattern-rz"' "$TMP/disagreement-pending-s5.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7b]: resurrected не пожат, made=$MADE"; fi

# =============================================================================================
# Ноги T8-T14 — D1000 (17 октября 2026). Жнец перебирал пары «провал × показ» процессами: на живых
# данных сессии 19c775dd 909 провалов × 239 показов = 217 251 пара, по два-три процесса на пару, и это
# 257 с из 267 с границы хода. Теперь пары перебирает один awk (`_dis_join_pairs`), а семантика прежнего
# цикла обязана остаться ДОСЛОВНОЙ: порядок перебора (внешний — провалы в порядке источника, внутренний —
# показы в порядке журнала), порядок проверок, граница окна, потолок, пустая дата показа. Прежняя
# редакция снята с HEAD и сличена с нынешней на 1900 с лишним прогонах (случайные и целевые фикстуры,
# живые данные двух сессий) — расхождений ноль; эти ноги закрепляют то, что сличение показало, чтобы
# следующая правка не вернула процессы на пару и не сдвинула границу на секунду.
# =============================================================================================
newdir() { mktemp -d "$TMP/d.XXXXXX"; }
# inj <sid> <дата> <файл> <уверенность> — строка журнала показов; frow <метка> — серия провалов.
inj()  { printf '{"date":"%s","file":"%s","confidence":%s,"injected":true,"session_id":"%s","rank":1}\n' "$2" "$3" "$4" "$1"; }
frow() { printf '{"ts":"%s","attempts":2}\n' "$1"; }
# keys <pending-файл> — ключи записей в порядке файла через пробел (с хвостовым пробелом).
keys() { grep -o '"key":"[^"]*"' "$1" 2>/dev/null | sed 's/"key":"//; s/"$//' | tr '\n' ' '; }
ck() {  # <имя> <получено> <ожидалось>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$1]: получено [$2], ожидалось [$3]"; fi
}
has() { if [ -s "$1" ]; then echo есть; else echo нет; fi; }

# --- T8: граница окна. Провал в 12:30:00, окно 30 мин = 1800 с: ровно окно входит, окно + 1 с — нет;
# показ в ту же секунду входит, на секунду позже провала — нет (инжект обязан ПРЕДШЕСТВОВАТЬ провалу).
bcase() {  # <имя> <окно_мин> <метка_показа> <метка_провала> <ожидаемое_число>
    local d m; d=$(newdir)
    inj sb "$3" pattern-edge.md 2 > "$d/injection-log.jsonl"
    frow "$4" > "$d/error-streak-log-sb.jsonl"
    m=$(dis_harvest_failures sb "$d" "$2" 3)
    ck "T8 $1" "$m" "$5"
}
F=2026-09-04T12:30:00Z
bcase "ровно окно"                       30 2026-09-04T12:00:00Z "$F" 1
bcase "окно минус секунда"               30 2026-09-04T12:00:01Z "$F" 1
bcase "окно плюс секунда"                30 2026-09-04T11:59:59Z "$F" 0
bcase "в ту же секунду"                  30 2026-09-04T12:30:00Z "$F" 1
bcase "показ на секунду позже провала"   30 2026-09-04T12:30:01Z "$F" 0
bcase "окно 1 мин, ровно"                 1 2026-09-04T12:29:00Z "$F" 1
bcase "окно 1 мин, плюс секунда"          1 2026-09-04T12:28:59Z "$F" 0
bcase "окно 0, та же секунда"             0 2026-09-04T12:30:00Z "$F" 1
bcase "окно 0, секунда назад"             0 2026-09-04T12:29:59Z "$F" 0
# Огромное окно (100 млн минут — 190 лет): показ с эпохой <= 0 отсекает проверка эпохи, а не окно.
bcase "огромное окно, годный показ"      100000000 2026-09-04T12:00:00Z "$F" 1
bcase "огромное окно, мусор вместо даты" 100000000 garbage "$F" 0
bcase "огромное окно, ноль эпохи"        100000000 1970-01-01T00:00:00Z "$F" 0
bcase "огромное окно, до 1970 года"      100000000 1969-12-31T23:59:59Z "$F" 0

# --- T9: потолок кандидатов. Отсекает на N по порядку журнала показов, повторный прогон добирает
# остаток (взятые ключи уже в pending), потолок 0 не пишет ничего, нечисловой — не падение, а ноль.
cap5() {  # <каталог> — пять разных знаний в окне одного провала, в порядке журнала
    { inj sc 2026-09-07T09:50:00Z pattern-a.md 1; inj sc 2026-09-07T09:51:00Z pattern-b.md 2
      inj sc 2026-09-07T09:52:00Z pattern-c.md 3; inj sc 2026-09-07T09:53:00Z pattern-d.md 4
      inj sc 2026-09-07T09:54:00Z pattern-e.md 5; } > "$1/injection-log.jsonl"
    frow 2026-09-07T10:00:00Z > "$1/error-streak-log-sc.jsonl"
}
D=$(newdir); cap5 "$D"; PD="$D/disagreement-pending-sc.jsonl"
M=$(dis_harvest_failures sc "$D" 30 2); ck "T9a потолок 2" "$M|$(keys "$PD")" "2|pattern-a pattern-b "
M=$(dis_harvest_failures sc "$D" 30 2); ck "T9b повтор добирает" "$M|$(keys "$PD")" "2|pattern-a pattern-b pattern-c pattern-d "
M=$(dis_harvest_failures sc "$D" 30 2); ck "T9c остаток" "$M|$(keys "$PD")" "1|pattern-a pattern-b pattern-c pattern-d pattern-e "
M=$(dis_harvest_failures sc "$D" 30 2); ck "T9d всё взято" "$M" "0"
D=$(newdir); cap5 "$D"
M=$(dis_harvest_failures sc "$D" 30 0); ck "T9e потолок 0" "$M|$(has "$D/disagreement-pending-sc.jsonl")" "0|нет"
D=$(newdir); cap5 "$D"
M=$(dis_harvest_failures sc "$D" 30 100); ck "T9f потолок выше числа ключей" "$M" "5"
for cap in abc -1 3x 1e1 0x10; do
    D=$(newdir); cap5 "$D"
    M=$(dis_harvest_failures sc "$D" 30 "$cap" 2>/dev/null); ck "T9g потолок '$cap'" "$M|$(has "$D/disagreement-pending-sc.jsonl")" "0|нет"
done
# Потолок действует на ВЕСЬ перебор, а не на один провал: два провала, потолок 1 — один кандидат.
D=$(newdir); cap5 "$D"; { frow 2026-09-07T10:00:00Z; frow 2026-09-07T10:01:00Z; } > "$D/error-streak-log-sc.jsonl"
M=$(dis_harvest_failures sc "$D" 30 1); ck "T9h потолок на весь перебор" "$M|$(keys "$D/disagreement-pending-sc.jsonl")" "1|pattern-a "
# Порядок перебора: внешний — провалы в порядке ИСТОЧНИКА (не по времени), внутренний — показы в порядке
# журнала. Показ s1 годен только для провала 10:20, показ s2 — для обоих; потолок 1 выдаёт, кто пошёл первым.
D=$(newdir)
{ inj so 2026-09-08T10:10:00Z pattern-s1.md 1; inj so 2026-09-08T09:50:00Z pattern-s2.md 2; } > "$D/injection-log.jsonl"
{ frow 2026-09-08T10:00:00Z; frow 2026-09-08T10:20:00Z; } > "$D/error-streak-log-so.jsonl"
M=$(dis_harvest_failures so "$D" 30 1); ck "T9i порядок: провал 10:00 первым" "$M|$(keys "$D/disagreement-pending-so.jsonl")" "1|pattern-s2 "
D=$(newdir)
{ inj so 2026-09-08T10:10:00Z pattern-s1.md 1; inj so 2026-09-08T09:50:00Z pattern-s2.md 2; } > "$D/injection-log.jsonl"
{ frow 2026-09-08T10:20:00Z; frow 2026-09-08T10:00:00Z; } > "$D/error-streak-log-so.jsonl"
M=$(dis_harvest_failures so "$D" 30 1); ck "T9j порядок: провал 10:20 первым" "$M|$(keys "$D/disagreement-pending-so.jsonl")" "1|pattern-s1 "

# --- T10: ключ уже в pending-файле ЭТОЙ сессии — пропуск, даже когда показ в окне. Точное совпадение
# `"key":"…"`: префикс ключа (pattern-ab при записи pattern-a) не считается; запись любого исхода
# (закрытая тоже) считается; файл чужой сессии не мешает; тот же ключ дважды за прогон — одна запись.
D=$(newdir)
{ inj sp 2026-09-09T09:50:00Z pattern-a.md 1; inj sp 2026-09-09T09:51:00Z pattern-ab.md 2
  inj sp 2026-09-09T09:52:00Z pattern-x.md 3; inj sp 2026-09-09T09:53:00Z pattern-xy.md 4
  inj sp 2026-09-09T09:54:00Z pattern-b.md 5; inj sp 2026-09-09T09:55:00Z pattern-c.md 6
  inj sp 2026-09-09T09:56:00Z pattern-a.md 7; inj sp 2026-09-09T09:57:00Z pattern-d.md 8; } > "$D/injection-log.jsonl"
frow 2026-09-09T10:00:00Z > "$D/error-streak-log-sp.jsonl"
printf '%s\n' '{"date":"2026-09-01T00:00:00Z","key":"pattern-a","outcome":"pending","confidence":3,"tool":"failure"}' \
    '{"date":"2026-09-01T00:00:00Z","key":"pattern-xy","outcome":"pending","confidence":3,"tool":"failure"}' \
    '{"date":"2026-09-01T00:00:00Z","key":"pattern-d","outcome":"confirmed_knowledge"}' > "$D/disagreement-pending-sp.jsonl"
printf '%s\n' '{"date":"2026-09-01T00:00:00Z","key":"pattern-c","outcome":"pending","confidence":3,"tool":"failure"}' > "$D/disagreement-pending-other.jsonl"
M=$(dis_harvest_failures sp "$D" 30 9)
ck "T10a ключ в pending" "$M|$(keys "$D/disagreement-pending-sp.jsonl")" "4|pattern-a pattern-xy pattern-d pattern-ab pattern-x pattern-b pattern-c "
D=$(newdir)
{ inj sd 2026-09-09T09:50:00Z pattern-a.md 1; inj sd 2026-09-09T09:51:00Z pattern-a 2; inj sd 2026-09-09T09:52:00Z pattern-a.md 3; } > "$D/injection-log.jsonl"
frow 2026-09-09T10:00:00Z > "$D/error-streak-log-sd.jsonl"
M=$(dis_harvest_failures sd "$D" 30 9); ck "T10b тот же ключ трижды" "$M|$(keys "$D/disagreement-pending-sd.jsonl")" "1|pattern-a "

# --- T11: пустая дата показа. TSV показа читается `IFS=$'\t' read`, где табуляция — пробельный разделитель:
# пустое поле СДВИГАЕТ остальные (файл становится датой, уверенность — файлом). Такой показ кандидата не
# даёт (его «дата» не метка) и соседей не сдвигает; ключом-уверенностью («3») запись тоже не появляется.
D=$(newdir)
{ printf '%s\n' '{"date":"","file":"pattern-e1.md","confidence":3,"injected":true,"session_id":"se","rank":1}' \
    '{"file":"pattern-e2.md","confidence":3,"injected":true,"session_id":"se","rank":1}' \
    '{"date":null,"file":"pattern-e3.md","confidence":3,"injected":true,"session_id":"se","rank":1}' \
    '{"date":"","file":"pattern-e4.md","confidence":"","injected":true,"session_id":"se","rank":1}'
  inj se 2026-09-10T09:55:00Z pattern-ok.md 4; } > "$D/injection-log.jsonl"
frow 2026-09-10T10:00:00Z > "$D/error-streak-log-se.jsonl"
M=$(dis_harvest_failures se "$D" 30 9)
ck "T11a пустая дата" "$M|$(keys "$D/disagreement-pending-se.jsonl")" "1|pattern-ok "
ck "T11b сосед не сдвинут" "$(grep -c '"key":"pattern-ok","outcome":"pending","confidence":4,' "$D/disagreement-pending-se.jsonl")" "1"

# --- T12: метки разных форм сличаются так, как ответил бы iso_epoch на каждую: доли, смещение (внутри и вне
# окна), местное время без зоны (под TZ=UTC), несуществующий день и мусор. Провал — каноническая UTC-метка.
forms_dir() {  # свежий каталог со сценарием T12; печатает путь
    local d; d=$(newdir)
    { inj sf 2026-09-11T10:05:00.750Z pattern-frac.md 1; inj sf 2026-09-11T13:00:00+03:00 pattern-offin.md 2
      inj sf 2026-09-11T10:00:00+03:00 pattern-offout.md 3; inj sf 2026-09-11T10:02:00 pattern-local.md 4
      inj sf 2026-02-30T10:00:00Z pattern-noday.md 5; inj sf garbage pattern-junk.md 1; } > "$d/injection-log.jsonl"
    frow 2026-09-11T10:10:00Z > "$d/error-streak-log-sf.jsonl"
    printf '%s' "$d"
}
D=$(forms_dir)
M=$(TZ=UTC dis_harvest_failures sf "$D" 30 9)
ck "T12 формы меток" "$M|$(keys "$D/disagreement-pending-sf.jsonl")" "3|pattern-frac pattern-offin pattern-local "

# --- T13: цена. 300 показов × 1000 внешних событий = 300 000 пар — в 10 с. Прежний цикл платил процессами на
# пару: на живых данных 217 251 пара стоили 257 с, а здесь он простоял бы около часа, поэтому прогон идёт под
# сторожем 60 с и под строгими флагами хука (set -euo pipefail), а не голым вызовом. Форма данных самая дорогая:
# 999 событий лежат за сутки до всех показов, ни одна пара не отсекается рано и кандидатов нет; лишь последнее
# событие даёт три — порядок журнала и потолок заодно проверены на большом вводе.
# shellcheck source=/dev/null
source "$(dirname "$LIB")/timeout-lib.sh"
PB=$(newdir)
awk 'BEGIN { for (i = 0; i < 300; i++) printf "{\"date\":\"2026-09-06T10:%02d:%02dZ\",\"file\":\"pattern-k%03d.md\",\"confidence\":%d,\"injected\":true,\"session_id\":\"sbig\",\"rank\":1}\n", int(i / 60), i % 60, i, i % 5 + 1 }' > "$PB/injection-log.jsonl"
awk 'BEGIN { for (i = 0; i < 999; i++) { t = i * 60; printf "{\"ts\":\"2026-09-05T%02d:%02d:%02dZ\",\"kind\":\"hotfix-repeat\",\"detail\":\"x\",\"status\":\"open\"}\n", int(t / 3600), int((t % 3600) / 60), t % 60 } print "{\"ts\":\"2026-09-06T10:05:10Z\",\"kind\":\"ci-red\",\"detail\":\"x\",\"status\":\"open\"}" }' > "$PB/pending-events.jsonl"
T0=$SECONDS
OUT=$(run_with_timeout 60 bash -c 'set -euo pipefail; source "$1"; dis_harvest_failures sbig "$2" 30 3' _ "$LIB" "$PB"); RC=$?
DT=$((SECONDS - T0))
ck "T13a цена: код и число" "$RC|$OUT" "0|3"
ck "T13b цена: порядок журнала" "$(keys "$PB/disagreement-pending-sbig.jsonl")" "pattern-k000 pattern-k001 pattern-k002 "
if [ "$DT" -le 10 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T13c]: 300 показов × 1000 событий — $DT с (порог 10 с)"; fi
# То же для соседа: жнец поправок делит с жнецом провалов соединение пар. Его кандидат несёт snippet СВОЕЙ
# строки поправки (тысячной), доставаемой по номеру.
PC=$(newdir); cp "$PB/injection-log.jsonl" "$PC/injection-log.jsonl"
awk 'BEGIN { for (i = 0; i < 999; i++) { t = i * 60; printf "{\"date\":\"2026-09-05T%02d:%02d:%02dZ\",\"hash\":\"h%d\",\"snippet\":\"старая %d\"}\n", int(t / 3600), int((t % 3600) / 60), t % 60, i, i } print "{\"date\":\"2026-09-06T10:05:10Z\",\"hash\":\"hz\",\"snippet\":\"поправка в окне\"}" }' > "$PC/correction-fired-sbig.jsonl"
T0=$SECONDS
OUT=$(run_with_timeout 60 bash -c 'set -euo pipefail; source "$1"; dis_harvest_corrections sbig "$2" 30 3' _ "$LIB" "$PC"); RC=$?
DT=$((SECONDS - T0))
ck "T13d цена поправок: код и число" "$RC|$OUT" "0|3"
ck "T13e цена поправок: ключи и snippet" "$(keys "$PC/disagreement-pending-sbig.jsonl")|$(jq -r '.snippet' "$PC/disagreement-pending-sbig.jsonl" | sort -u)" "pattern-k000 pattern-k001 pattern-k002 |поправка в окне"
if [ "$DT" -le 10 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T13f]: 300 показов × 1000 поправок — $DT с (порог 10 с)"; fi

# --- T14: поправка достаёт СВОЮ строку по номеру: строки без даты (пустая, null, ключа нет) номер не сдвигают
# и соседняя строка с другой датой не подменяет свою; при двух строках с одной датой побеждает первая — как и
# раньше (`sed -n 1p`).
D=$(newdir)
inj sg 2026-09-12T09:55:00Z pattern-g.md 2 > "$D/injection-log.jsonl"
printf '%s\n' '{"date":"","hash":"a","snippet":"пустая дата"}' '{"hash":"b","snippet":"даты нет вовсе"}' \
    '{"date":null,"hash":"b2","snippet":"дата null"}' '{"date":"2026-09-12T10:00:00Z","hash":"c","snippet":"нужная строка"}' \
    '{"date":"2026-09-12T10:01:00Z","hash":"d","snippet":"следующая строка"}' > "$D/correction-fired-sg.jsonl"
M=$(dis_harvest_corrections sg "$D" 30 1)
ck "T14a номер строки поправки" "$M|$(jq -r '.snippet' "$D/disagreement-pending-sg.jsonl")" "1|нужная строка"
D=$(newdir)
inj sg 2026-09-12T09:55:00Z pattern-g.md 2 > "$D/injection-log.jsonl"
printf '%s\n' '{"date":"2026-09-12T10:00:00Z","hash":"c","snippet":"первая с этой датой"}' \
    '{"date":"2026-09-12T10:00:00Z","hash":"d","snippet":"вторая с той же датой"}' > "$D/correction-fired-sg.jsonl"
M=$(dis_harvest_corrections sg "$D" 30 3)
ck "T14b две строки с одной датой" "$M|$(jq -r '.snippet' "$D/disagreement-pending-sg.jsonl")" "1|первая с этой датой"

# --- T13g: цена по ДЛИНЕ ЖУРНАЛА ПОКАЗОВ. Показы копятся к концу сессии, и всё, что соединение делает в оболочке
# над их списком, растёт вместе с ним: накопление строки в цикле (`x="${x}…"`) на bash 3.2 КВАДРАТИЧНО (замер
# 17 октября 2026: 5000 строк — 3,6 с, 10 000 — 13,6 с), а срез `${t#*перевод}` в цикле — тоже. 6000 показов × 3 провала
# должны уложиться в 10 с; провал 11:41:00 берёт три первых годных показа (11:11:00 — ровно окно).
PL=$(newdir)
awk 'BEGIN { for (i = 0; i < 6000; i++) { t = 36000 + i; printf "{\"date\":\"2026-09-14T%02d:%02d:%02dZ\",\"file\":\"pattern-s%05d.md\",\"confidence\":%d,\"injected\":true,\"session_id\":\"slong\",\"rank\":1}\n", int(t / 3600), int((t % 3600) / 60), t % 60, i, i % 5 + 1 } }' > "$PL/injection-log.jsonl"
{ frow 2026-09-14T09:00:00Z; frow 2026-09-14T09:30:00Z; frow 2026-09-14T11:41:00Z; } > "$PL/error-streak-log-slong.jsonl"
T0=$SECONDS
OUT=$(run_with_timeout 60 bash -c 'set -euo pipefail; source "$1"; dis_harvest_failures slong "$2" 30 3' _ "$LIB" "$PL"); RC=$?
DT=$((SECONDS - T0))
ck "T13g длинный журнал: код, число, ключи" "$RC|$OUT|$(keys "$PL/disagreement-pending-slong.jsonl")" "0|3|pattern-s04260 pattern-s04261 pattern-s04262 "
if [ "$DT" -le 10 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T13h]: 6000 показов × 3 провала — $DT с (порог 10 с)"; fi

# --- T15: установлена СТАРАЯ portable-lib без iso_epoch_lines (установка идёт файл за файлом, и библиотеки
# расходятся по возрасту). Жнец зовёт функцию по имени, а под `set -u` недостающее имя убивает Stop-хук на первом
# вызове: запасное определение в disagreement-lib.sh обязано подхватить, и ответ — тот же. Заглушка — настоящая
# portable-lib без функции; сверка, что её там и правда нет, стоит первой, иначе нога была бы пустой.
OLDP="$TMP/portable-lib-old.sh"
awk '/^iso_epoch_lines\(\) \{/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0 }' "$(dirname "$LIB")/portable-lib.sh" > "$OLDP"
ck "T15a заглушка без iso_epoch_lines" "$(grep -c '^iso_epoch_lines' "$OLDP")|$(grep -c '^iso_epoch()' "$OLDP")" "0|1"
D=$(forms_dir)
OUT=$(PORTABLE_LIB="$OLDP" TZ=UTC bash -c 'set -euo pipefail; source "$1"; type -t iso_epoch_lines; dis_harvest_failures sf "$2" 30 9' _ "$LIB" "$D" | tr '\n' ' ')
ck "T15b запасной iso_epoch_lines" "$OUT|$(keys "$D/disagreement-pending-sf.jsonl")" "function 3 |pattern-frac pattern-offin pattern-local "

echo "harvest-failures: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
