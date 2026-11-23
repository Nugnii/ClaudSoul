#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# test_root_cause_lib.sh — ключ хода один на продюсера и потребителя, и живёт в библиотеке.
#
# Результат: five-whys-gate и declared-problem-recorded считают ключ хода ОДНОЙ функцией
#            rc_turn_key; исчезновение библиотеки глушит обоих, а не ломает
# Проверка результата: bash hooks/tests/test_root_cause_lib.sh даёт 0
#
# Повод, 29 августа 2026: формула ключа хода жила ДВУМЯ копиями (five-whys-gate.sh и
# declared-problem-recorded.sh), и комментарий у читателя признавал: «расходятся молча —
# и связь порвётся без единого падения». Тот же класс сутки молчал у трёх стражей бэклога
# 28 августа (повод backlog-lib.sh).
#
# КОНТРПРИМЕРЫ, оба проверяются ниже:
#   · библиотека недоступна → оба хука выходят тихо (0, пустой вывод), не падают;
#   · ход, чьей метки нет в журнале, у сверщика молчит — ключ читается, а не игнорируется.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS/root-cause-lib.sh"
GATE="$HOOKS/five-whys-gate.sh"
DPR="$HOOKS/declared-problem-recorded.sh"
for f in "$LIB" "$GATE" "$DPR"; do
    [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SID="rclib-test"
STATE="$TMP/state"; mkdir -p "$STATE"

USER_TEXT="почини вот это"
NOW=$(date -u +%s)
T_TURN_START=$((NOW - 3600))
T_OLD=$((NOW - 7200))
TURN_ISO=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$T_TURN_START")
set_mtime() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }

TRANSCRIPT="$TMP/t.jsonl"
{
  printf '{"type":"user","message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"оказалось тут дыра"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TRANSCRIPT"

# --- T1: rc_turn_key совпадает с независимо посчитанным cksum последней реплики ---
# `%s\n`, не `%s`: jq -r печатает строку С переводом, и он входит в cksum (так же в
# test_declared_problem_per_turn.sh — первая редакция этого теста промахнулась без \n).
# shellcheck source=/dev/null
. "$LIB"
EXPECTED=$(printf '%s\n' "$USER_TEXT" | cksum | awk '{print $1}')
GOT=$(rc_turn_key "$TRANSCRIPT")
if [ "$GOT" = "$EXPECTED" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: rc_turn_key='$GOT', ожидалось '$EXPECTED'"; fi

# --- T2: rc_why_count считает только ПОСЛЕ последней реплики собеседника ---
TR2="$TMP/t2.jsonl"
{
  printf '{"message":{"role":"assistant","content":"почему почему почему — прошлый ход"}}\n'
  printf '{"type":"user","message":{"role":"user","content":"дальше"}}\n'
  printf '{"message":{"role":"assistant","content":"здесь почему один и почему два"}}\n'
} > "$TR2"
N=$(rc_why_count "$TR2")
if [ "$N" = "2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: rc_why_count='$N', ожидалось 2 (прошлый ход не считается)"; fi

# --- T3: E2E продюсер→потребитель через ОДНУ функцию ---
# Гейт (сигнал discovery в последнем блоке речи) пишет в журнал ключ этого хода...
printf '' > "$STATE/five-whys-${SID}.seen" 2>/dev/null || true
printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$SID" "$TRANSCRIPT" \
    | STATE_DIR="$STATE" bash "$GATE" >/dev/null 2>"$STATE/gate-err"
_rc=$?; [ "$_rc" -eq 0 ] || { FAIL=$((FAIL+1)); echo "FAIL [T3rc]: гейт умер rc=$_rc: $(tail -c 200 "$STATE/gate-err" 2>/dev/null)"; }
if grep -q "^turn:${EXPECTED}|" "$STATE/five-whys-${SID}.seen" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3a]: гейт не подписал журнал ключом библиотеки: $(cat "$STATE/five-whys-${SID}.seen" 2>/dev/null)"; fi
# ...а сверщик тем же ключом находит срабатывание и требует исход.
# Носитель сверщика — бэклог проекта (`DPR_LOCAL_BACKLOG` либо корень по `cwd`); базу знаний он по mtime не читает
# (D1241: до 8 ноября 2026 тест задавал `DPR_BACKLOG` и `DPR_LESSONS`, которых хук с b07fb76e не читает).
BACKLOG="$TMP/BACKLOG.md"; printf '# долг\n' > "$BACKLOG"; set_mtime "$BACKLOG" "$T_OLD"
# Канал — файл напоминаний stop-signals-<sid> (D1044, D1047; systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний. Очередь и дроссель сверщика чистятся перед вызовом.
run_dpr() { # $1 транскрипт, $2 хвост JSON-полей (необязательно, с ведущей запятой)
    : > "$STATE/stop-signals-${SID}.txt" 2>/dev/null || true
    rm -f "$STATE"/declared-problem-fired-*.jsonl 2>/dev/null || true
    # С полем `cwd` носитель — бэклог корня этого каталога, как в жизни: переменная у сверщика главнее `cwd` (T6).
    local _lb="$BACKLOG"; case "${2:-}" in *'"cwd"'*) _lb="" ;; esac
    STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$_lb" bash "$DPR" >/dev/null 2>&1 <<PAYLOAD || { echo "подготовка мира не удалась: hooks/tests/test_root_cause_lib.sh:$LINENO" >&2; exit 1; }
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$1"${2:-}}
PAYLOAD
    cat "$STATE/stop-signals-${SID}.txt" 2>/dev/null
}
OUT=$(run_dpr "$TRANSCRIPT")
if grep -q 'В ЭТОМ ходе' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3b]: сверщик не нашёл срабатывание по ключу библиотеки: '$OUT'"; fi
# T3c (D1241): носитель, тронутый в ходе, сверщик видит — требование исхода гаснет. Без неё T3b зеленела бы и у сверщика,
# который бэклога не видит вовсе (так и было, пока тест задавал переменную, которой хук не читает).
set_mtime "$BACKLOG" "$NOW"
OUT3c=$(run_dpr "$TRANSCRIPT")
if ! grep -q 'В ЭТОМ ходе' <<< "$OUT3c"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3c]: бэклог тронут в ходе, а сверщик требует исход — носителя не видит: '${OUT3c}'"; fi
set_mtime "$BACKLOG" "$T_OLD"

# --- T4: ОБРЫВ СВЯЗИ — новый ход (другая реплика) → журнал прошлого хода не считается ---
TR3="$TMP/t3.jsonl"
{
  printf '{"type":"user","message":{"role":"user","content":"совсем другая реплика"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"ответ без находки"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR3"
OUT4=$(run_dpr "$TR3")
if ! grep -q 'В ЭТОМ ходе' <<< "$OUT4"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: чужой ход прочитал журнал прошлого: '$OUT4'"; fi

# --- T5: КОНТРПРИМЕР — библиотеки нет → оба хука тихо выходят (0, пустой вывод) ---
# Глушатся ОБЕ ступени поиска: `RC_LIB` (рядом с хуком) и `$HOME/.claude/hooks/` (установка).
# Первая редакция этого теста подменяла только RC_LIB и была зелёной ровно до тех пор, пока
# библиотека не появилась в установленной копии — тогда fallback находил её, хук работал, и
# «контрпример на тишину» проверял не то, что утверждал. Тот же род, что повод backlog-lib:
# проверка, выраженная через одну ступень реализации, наследует её слепое пятно.
NOHOME="$TMP/nohome"; mkdir -p "$NOHOME"
OUT5g=$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$SID" "$TRANSCRIPT" \
    | HOME="$NOHOME" STATE_DIR="$STATE" RC_LIB="$TMP/no-such-lib.sh" bash "$GATE" 2>&1); RC5g=$?
if [ "$RC5g" -eq 0 ] && [ -z "$OUT5g" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5a]: гейт без библиотеки: rc=$RC5g out='$OUT5g'"; fi
OUT5d=$(HOME="$NOHOME" STATE_DIR="$STATE" RC_LIB="$TMP/no-such-lib.sh" DPR_LOCAL_BACKLOG="$BACKLOG" bash "$DPR" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TRANSCRIPT"}
PAYLOAD
); RC5d=$?
if [ "$RC5d" -eq 0 ] && [ -z "$OUT5d" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5b]: сверщик без библиотеки: rc=$RC5d out='$OUT5d'"; fi

# --- T6: локальный носитель чужого проекта гасит сверщик ---
PROJ="$TMP/proj"; mkdir -p "$PROJ"
printf '# CLAUDE\n' > "$PROJ/CLAUDE.md"
printf '# долг проекта\n' > "$PROJ/BACKLOG.md"   # свежий mtime = менялся В ходе
# Журнал состояния — старше носителя: сверка сессионной ветки строгая («>»), и файлы,
# созданные в одну секунду, дают ложное «не менялся». В жизни состояние сессии всегда
# старше записи исхода; в фикстуре это задаётся явно.
set_mtime "$STATE/five-whys-${SID}.seen" "$T_OLD"
OUT6=$(run_dpr "$TRANSCRIPT" ",\"cwd\":\"$PROJ\"")
if [ -z "$OUT6" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: запись в локальный BACKLOG чужого проекта не гасит: '$OUT6'"; fi

# ── След разбора (D211): формы доктрины, а не одно слово ──────────────────────
# Повод: ADR-016 добавил реестр мест с дробью и входы узла, а машинный признак разбора был
# один — счёт слова «почему»; связный разбор без него был неотличим от отсутствия разбора
# (7 цепочек на 371 повод), и из трёх живых отказов гейта один пришёлся на текст с
# разделами «Вширь…/Вглубь…» и спуском «←» без единого «почему». Формы выбраны реплеем.
mk_tr() {   # <файл> <текст агента> — транскрипт из одной реплики и одного ответа
    printf '{"type":"user","message":{"role":"user","content":"чини"}}\n{"message":{"role":"assistant","content":%s}}\n' \
        "$(printf '%s' "$2" | jq -Rs '.')" > "$1"
}
tr_field() { printf '%s' "$1" | jq -r ".$2"; }

# --- T7: заголовки шаблона без слова «почему» — цепочка ---
TR7="$TMP/t7.jsonl"
mk_tr "$TR7" "Вширь по проявлениям: hooks/a.sh:10 и scripts/b.py:5. Вглубь: звено ← звено ← причина."
J7=$(rc_trace "$TR7")
[ "$(tr_field "$J7" heads)" = "2" ] && [ "$(tr_field "$J7" why)" = "0" ] && [ "$(tr_field "$J7" arrows)" = "2" ] \
    && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7]: след неверен: $J7"; }
rc_chain_spoken "$J7" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7b]: два заголовка шаблона не признаны цепочкой: $J7"; }

# --- T8: спуск стрелками (три «←») — цепочка; две — нет ---
# Фикстура несёт АДРЕС: с 9 сентября 2026 он обязателен во всех ветвях критерия. Спуск
# стрелками без единого адреса разбором не считается — доктрина требует «каждое место с
# адресом», а цитата доктрины давала why=4, heads=4, addr=0 и снимала отказ (D323).
TR8="$TMP/t8.jsonl"; mk_tr "$TR8" "страж падает (hooks/skill-name-ascii-guard.sh:42) ← голое имя перед не-ASCII ← чинились только подсвеченные строки ← мутация не применилась"
rc_chain_spoken "$(rc_trace "$TR8")" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8]: три стрелки не признаны цепочкой"; }
TR8b="$TMP/t8b.jsonl"; mk_tr "$TR8b" "a ← b ← c"
rc_chain_spoken "$(rc_trace "$TR8b")" && { FAIL=$((FAIL+1)); echo "FAIL [T8b]: две стрелки сочтены цепочкой"; } || PASS=$((PASS+1))

# --- T8c: РЕЧЬ БЕЗ АДРЕСА цепочкой не считается (9 сентября 2026) ---
# Прежде критерий был чистой дизъюнкцией, и три её ветви — «почему», заголовки, стрелки —
# проходились при нуле адресов. Замер по 976 следам в живых журналах: старый критерий
# проходили 163, требование `addr>=1` оставляет 135, отсекая 28 (17%) — ровно те, где
# адресов нет вовсе. Порог ОДИН, а не два: доктрина признаёт разбор с единственным
# проявлением законным.
TR8c="$TMP/t8c.jsonl"; mk_tr "$TR8c" "Почему упало — не тот файл. Почему не тот — путь собрали иначе. Почему иначе — правили соседнюю ветку."
rc_chain_spoken "$(rc_trace "$TR8c")" && { FAIL=$((FAIL+1)); echo "FAIL [T8c]: три «почему» без единого адреса сочтены цепочкой"; } || PASS=$((PASS+1))
TR8d="$TMP/t8d.jsonl"; mk_tr "$TR8d" "Почему упало — не тот файл (hooks/paths-lib.sh:67). Почему не тот — путь собрали иначе. Почему иначе — правили соседнюю ветку."
rc_chain_spoken "$(rc_trace "$TR8d")" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8d]: та же цепочка С адресом не признана"; }

# --- T9: реестр мест — два адреса, дробь N<M и корень — цепочка ---
TR9="$TMP/t9.jsonl"; mk_tr "$TR9" "Реестр: hooks/x.sh:12, hooks/y.sh:40 — симптом у 1 из 2. Корень — общий признак пункта."
J9=$(rc_trace "$TR9")
[ "$(tr_field "$J9" addr)" = "2" ] && [ "$(tr_field "$J9" frac)" = "1" ] && [ "$(tr_field "$J9" roots)" = "1" ] \
    && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T9]: реестр не распознан: $J9"; }
rc_chain_spoken "$J9" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T9b]: реестр с корнем не признан цепочкой: $J9"; }

# --- T10: КОНТРПРИМЕРЫ — отчёт о прогонах, дата, дробь без адресов, тот же адрес дважды ---
TR10="$TMP/t10.jsonl"
mk_tr "$TR10" "Прогнал: hooks/x.sh:12 и x.sh:12 зелёные, 121 из 121 прошли, 30/08 подчистил. Корень не искал."
J10=$(rc_trace "$TR10")
[ "$(tr_field "$J10" frac)" = "0" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T10a]: «121 из 121» сочтена дробью: $J10"; }
[ "$(tr_field "$J10" addr)" = "1" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T10b]: один адрес в двух написаниях посчитан дважды: $J10"; }
rc_chain_spoken "$J10" && { FAIL=$((FAIL+1)); echo "FAIL [T10c]: отчёт о прогоне сочтён цепочкой: $J10"; } || PASS=$((PASS+1))
TR10d="$TMP/t10d.jsonl"; mk_tr "$TR10d" "оказалось: 3 из 7 файлов покрыты — корень где-то рядом"
rc_chain_spoken "$(rc_trace "$TR10d")" && { FAIL=$((FAIL+1)); echo "FAIL [T10d]: дробь без адресов сочтена реестром"; } || PASS=$((PASS+1))

# --- T11: пустой/нечитаемый вход — нули и код 0; rc_why_count равен полю why ---
J11=$(rc_trace "$TMP/no-such-transcript.jsonl"); RC11=$?
[ "$RC11" -eq 0 ] && [ "$(tr_field "$J11" why)" = "0" ] && [ "$(tr_field "$J11" heads)" = "0" ] \
    && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T11]: нечитаемый вход: rc=$RC11 $J11"; }
[ "$(rc_why_count "$TR2")" = "$(tr_field "$(rc_trace "$TR2")" why)" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T11b]: rc_why_count и поле why следа разошлись"; }
# «проверено» — не вход: граница слова у «верен»
TR11="$TMP/t11.jsonl"; mk_tr "$TR11" "вход проверено вживую; второй вход был неверен"
[ "$(tr_field "$(rc_trace "$TR11")" inputs)" = "1" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T11c]: «проверено» посчитано входом: $(rc_trace "$TR11")"; }

# ── Знаменатель стражей считает ПОДПИСИ, а не вызовы (D205, поправка 30 августа 2026) ──
# Первый прогон detection-share дал «сказал 14%»: одна реплика пересчитывалась на каждом
# вызове инструмента, и каждый пересчёт ложился «промолчал». Объём работы вместо частоты предмета.
S12="$TMP/state12"; mkdir -p "$S12"
rc_note_detection "$S12" "d1" "guard-x" "said" "sig-A"
rc_note_detection "$S12" "d1" "guard-x" "muted" "sig-A"
rc_note_detection "$S12" "d1" "guard-x" "muted" "sig-A"
rc_note_detection "$S12" "d1" "guard-x" "muted" "sig-B"
rc_note_detection "$S12" "d1" "guard-y" "muted"          # без подписи — по-старому
[ "$(jq -r 'select(.sig=="sig-A") | .act' "$S12/detection-d1.jsonl" | wc -l | tr -d ' ')" = "3" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T12]: подпись не записана: $(cat "$S12/detection-d1.jsonl")"; }
OUT12=$(STATE_DIR="$S12" DETECTION_SHARE_MIN_N=2 bash "$HOOKS/../scripts/detection-share.sh" 2>&1)
if grep -q 'guard-x: подписей 2 (совпадений 4), сказал 50%' <<< "$OUT12"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T12b]: замер считает вызовы, а не подписи: '$OUT12'"; fi
if grep -q 'guard-y: подписей 1 (совпадений 1), сказал 0%' <<< "$OUT12"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T12c]: запись без подписи считается не по-старому: '$OUT12'"; fi

# T13 — четвёртое значение словаря `satisfied` (D372).
#
# Словарь предписывает: «Заводя четвёртое значение — проверь обоих [читателей]». Проверка
# здесь механическая, а не на слово: значение пишется, и ОБА читателя его не считают —
# иначе доля «сказал» у всех стражей поехала бы от чужого исхода.
S13="$TMP/s13"; mkdir -p "$S13"
rc_note_detection "$S13" "d1" "guard-z" "said" "sig-A"
rc_note_detection "$S13" "d1" "guard-z" "satisfied" "sig-B"
rc_note_detection "$S13" "d1" "guard-z" "satisfied" "sig-C"

if grep -q '"act":"satisfied"' "$S13/detection-d1.jsonl" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T13a]: значение satisfied не записано"; fi

# detection-share: знаменатель обязан остаться 1 (одна подпись said), а не 3.
OUT13=$(STATE_DIR="$S13" DETECTION_SHARE_MIN_N=1 bash "$HOOKS/../scripts/detection-share.sh" 2>&1)
if grep -q 'guard-z: подписей 1 ' <<< "$OUT13"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T13b]: satisfied попал в знаменатель detection-share: '$OUT13'"; fi

# violation-class: второй читатель того же журнала обязан вести себя так же.
OUT13V=$(STATE_DIR="$S13" bash "$HOOKS/../scripts/violation-class.sh" 2>&1)
if grep -q 'satisfied' <<< "$OUT13V"; then FAIL=$((FAIL+1)); echo "FAIL [T13c]: violation-class считает satisfied: '$OUT13V'"
else PASS=$((PASS+1)); fi

# --- T14: АДРЕС — РОЛЬ, А НЕ ОДНА ФОРМА (10 сентября 2026) ---------------------
# Повод: разбор, чей предмет БЭКЛОГ, а не код, давал addr=0 и получал неснимаемый отказ —
# девять подряд. Адресами там были номера пунктов, а выражение знало только `файл:строка`.
TR14a="$TMP/t14a.jsonl"
mk_tr "$TR14a" "Почему пункт D379 копится — разбор кончался местом. Почему местом — у пункта нет поля корня. Почему нет поля — карта заведена позже, чем D306 и D310."
J14a=$(rc_trace "$TR14a")
[ "$(tr_field "$J14a" addr)" -ge 1 ] 2>/dev/null && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14a]: номер пункта долга не признан адресом: $J14a"; }
rc_chain_spoken "$J14a" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14b]: разбор с адресами-пунктами не признан цепочкой: $J14a"; }

# Имя знания — тоже адрес: оно разрешается в файл ~/.claude/global-lessons/.
TR14c="$TMP/t14c.jsonl"
mk_tr "$TR14c" "Почему признак промахнулся — pattern-marker-matches-form-not-role. Почему он — форма вместо роли. Почему не поймали — контрпримера не было."
[ "$(tr_field "$(rc_trace "$TR14c")" addr)" -ge 1 ] 2>/dev/null && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14c]: имя знания не признано адресом"; }

# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ, без него нога доказывает лишь широту выражения.
# Слово, похожее на имя знания формой, но им не являющееся, адресом быть не должно.
TR14d="$TMP/t14d.jsonl"
mk_tr "$TR14d" "Почему упало — не знаю. Почему не знаю — не смотрел. Почему не смотрел — торопился."
[ "$(tr_field "$(rc_trace "$TR14d")" addr)" = "0" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14d]: речь без единого адреса получила адрес"; }

# Число, похожее на пункт, но не пункт: год, размер, код возврата.
TR14e="$TMP/t14e.jsonl"
mk_tr "$TR14e" "Почему медленно — 2026 год, 4096 байт, код 137. Почему так — не мерил. Почему не мерил — некогда."
[ "$(tr_field "$(rc_trace "$TR14e")" addr)" = "0" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T14e]: голое число сочтено номером пункта: $(rc_trace "$TR14e")"; }

# --- T15: СТРЕЛКА — ОБЕ ФОРМЫ, А НЕ ТА, КОТОРОЙ ДОКТРИНА НЕ УЧИТ (11 сентября 2026) ---
# Счётчик `arrows` искал ТОЛЬКО «←», тогда как доктрина, которой учит сам гейт, печатает
# «→»: в rules/CLAUDE.md «←» встречается 0 раз против 27 «→», а в корпусе одной сессии
# агента — 11 против 303. То есть 96% произнесённых стрелок ветвь формулы не видела.
# Корень R1: символ собран литералом на каждом конце связи отдельно.
# Ноги держат ОБЕ формы: без T15b правка выглядела бы починкой, сломавшей прежнее.
TR15a="$TMP/t15a.jsonl"
mk_tr "$TR15a" "Вширь: hooks/a.sh:10 → вглубь: вход неверен → сверка сошлась"
[ "$(tr_field "$(rc_trace "$TR15a")" arrows)" = "2" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15a]: стрелка «→», которой учит доктрина, не сосчитана: $(rc_trace "$TR15a")"; }

TR15b="$TMP/t15b.jsonl"
mk_tr "$TR15b" "Вширь: hooks/a.sh:10 ← вглубь ← сверка"
[ "$(tr_field "$(rc_trace "$TR15b")" arrows)" = "2" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15b]: прежняя форма «←» перестала считаться: $(rc_trace "$TR15b")"; }

TR15c="$TMP/t15c.jsonl"
mk_tr "$TR15c" "Просто текст без разбора и без стрелок"
[ "$(tr_field "$(rc_trace "$TR15c")" arrows)" = "0" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T15c]: стрелки найдены там, где их нет"; }

# --- T16 (D1036): запись узнаётся у владельца — расширение записи, не документ поведения, не под rules/skills/templates ---
for p in docs/architecture.md .claude-docs/modules/x.md "$HOME/.claude/projects/p/memory/notes.md" notes.txt state/x.jsonl run.log out/test.out CHANGELOG.md \
         "$HOME/.claude/global-lessons/case-x.md" .claude/plans/p.md "$HOME/.claude/hooks/state/x.jsonl"; do
    rc_is_record_target "$p" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16a]: запись не узнана: $p"; }
done
for p in hooks/x.sh scripts/y.py web/app.ts settings.json config.yaml Info.plist scripts/measurements.tsv skills/x/SKILL.md CLAUDE.md sub/CLAUDE.md AGENTS.md rules/x.md .claude/rules/y.md templates/z.md docs/../hooks/x.md README \
         "$HOME/.claude/commands/wiki.md" "$HOME/.claude/commands/compile/references/p.md" "$HOME/.claude/agents/lean.md" .claude/agents/a.md \
         "$HOME/.claude/skills-catalog.md" "$HOME/.claude/hooks/notes.md" CLAUDE.local.md sub/CLAUDE.local.md; do   # D1329: каталог настроек и локальные правила
    rc_is_record_target "$p" && { FAIL=$((FAIL+1)); echo "FAIL [T16b]: механизм или документ поведения принят за запись: $p"; } || PASS=$((PASS+1))
done

# T17 — владелец перечня временных корней (D1013): системный путь живой, временный и без каталога — частные. Нога
# держит имя `rc_path_is_private` (его зовут четыре носителя) и направление «настоящий путь признан частным», которого
# не видят свидетели D1011 (финальный скептик D1013, находка 2). Живой путь — системный, а не путь дерева: снимок
# публикации и рабочие копии лежат во временных папках.
_t17=$(mktemp -d)
rc_path_is_private /usr/bin/env && { FAIL=$((FAIL+1)); echo "FAIL [T17]: системный путь признан частным"; } || PASS=$((PASS+1))
rc_path_is_private "$_t17/x" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17b]: путь под mktemp не признан частным"; }
rc_path_is_private "/нет/такого/каталога/x" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17c]: путь без каталога не признан частным"; }
# D1112: корни — у `wt_temp_roots`; /var/tmp прежде знал только страж записи. Без библиотеки корней путь частный
# (след фикстуры не уходит в живой каталог), а не «живой».
rc_path_is_private /var/tmp/x && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17d]: /var/tmp не признан частным"; }
( unset -f wt_temp_roots; _RC_WT_LIB=/нет/библиотеки; rc_path_is_private /usr/bin/env ) && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17e]: без библиотеки корней системный путь признан живым"; }
# $TMPDIR берёт только этот признак (фикстуры живут в mktemp), и глоб в нём не раскрывается (скептик D1112, L1).
( TMPDIR='/usr/*'; rc_path_is_private /usr/bin/env ) && { FAIL=$((FAIL+1)); echo "FAIL [T17f]: глоб в TMPDIR сделал системный путь частным"; } || PASS=$((PASS+1))
( TMPDIR=/usr; rc_path_is_private /usr/bin/env ) && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17g]: корень из TMPDIR не взят признаком частного пути"; }
# Рядом с библиотекой нет `lib/` (копия в пробном дереве) — перечень берётся из установки, а не «нет перечня → частный».
_t17h=$(mktemp -d); mkdir -p "$_t17h/home/.claude/hooks/lib" "$_t17h/tree"
cp "$HOOKS/lib/write-target-lib.sh" "$_t17h/home/.claude/hooks/lib/" && cp "$LIB" "$_t17h/tree/"
HOME="$_t17h/home" bash -c '. "$1" 2>/dev/null; rc_path_is_private /usr/bin/env' _ "$_t17h/tree/root-cause-lib.sh" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T17h]: без lib/ рядом перечень не взят из установки — системный путь частный"; } || PASS=$((PASS+1))
# Перевод строки в $TMPDIR не делит перечень (скептик D1112, второй круг, L1).
( TMPDIR=$'/nonexistent\n/usr'; rc_path_is_private /usr/bin/env ) && { FAIL=$((FAIL+1)); echo "FAIL [T17i]: перевод строки в TMPDIR сделал системный путь частным"; } || PASS=$((PASS+1))
# Чужой IFS вызывающего не склеивает перечень корней в одно слово (мутант i2 четвёртого круга D1112 выжил без этой ноги).
( IFS=:; rc_path_is_private /var/tmp/x ) && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17k]: при IFS=: вызывающего /var/tmp не частный"; }
# Закрытая на запись ФС (обход перечня без временных файлов): фикстура остаётся частной (M2). Только macOS.
if command -v sandbox-exec >/dev/null 2>&1; then
    sandbox-exec -p '(version 1)(allow default)(deny file-write* (subpath "/"))(allow file-write* (literal "/dev/null"))' \
        /bin/bash -c '. "$1" 2>/dev/null; rc_path_is_private "$2/x"' _ "$LIB" "$_t17" 2>/dev/null \
        && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T17j]: под закрытой ФС путь фикстуры признан живым"; }
else
    echo "SKIP [T17j]: нет sandbox-exec — закрытую ФС здесь не построить"
fi

echo "root-cause lib: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
