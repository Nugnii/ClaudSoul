#!/usr/bin/env bash
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
  printf '{"message":{"role":"user","content":"%s"},"timestamp":"%s"}\n' "$USER_TEXT" "$TURN_ISO"
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
  printf '{"message":{"role":"user","content":"дальше"}}\n'
  printf '{"message":{"role":"assistant","content":"здесь почему один и почему два"}}\n'
} > "$TR2"
N=$(rc_why_count "$TR2")
if [ "$N" = "2" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: rc_why_count='$N', ожидалось 2 (прошлый ход не считается)"; fi

# --- T3: E2E продюсер→потребитель через ОДНУ функцию ---
# Гейт (сигнал discovery в последнем блоке речи) пишет в журнал ключ этого хода...
printf '' > "$STATE/five-whys-${SID}.seen" 2>/dev/null || true
printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/x"},"transcript_path":"%s"}' "$SID" "$TRANSCRIPT" \
    | STATE_DIR="$STATE" bash "$GATE" >/dev/null 2>&1
if grep -q "^turn:${EXPECTED}|" "$STATE/five-whys-${SID}.seen" 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3a]: гейт не подписал журнал ключом библиотеки: $(cat "$STATE/five-whys-${SID}.seen" 2>/dev/null)"; fi
# ...а сверщик тем же ключом находит срабатывание и требует исход.
BACKLOG="$TMP/BACKLOG.md"; printf '# долг\n' > "$BACKLOG"; set_mtime "$BACKLOG" "$T_OLD"
LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"
OUT=$(STATE_DIR="$STATE" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TRANSCRIPT"}
PAYLOAD
)
if grep -q 'В ЭТОМ ходе' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3b]: сверщик не нашёл срабатывание по ключу библиотеки: '$OUT'"; fi

# --- T4: ОБРЫВ СВЯЗИ — новый ход (другая реплика) → журнал прошлого хода не считается ---
TR3="$TMP/t3.jsonl"
{
  printf '{"message":{"role":"user","content":"совсем другая реплика"},"timestamp":"%s"}\n' "$TURN_ISO"
  printf '{"message":{"role":"assistant","content":"ответ без находки"},"timestamp":"%s"}\n' "$TURN_ISO"
} > "$TR3"
OUT4=$(STATE_DIR="$STATE" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TR3"}
PAYLOAD
)
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
OUT5d=$(HOME="$NOHOME" STATE_DIR="$STATE" RC_LIB="$TMP/no-such-lib.sh" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD
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
OUT6=$(STATE_DIR="$STATE" DPR_BACKLOG="$BACKLOG" DPR_LESSONS="$LESSONS" bash "$DPR" <<PAYLOAD
{"session_id":"$SID","hook_event_name":"Stop","transcript_path":"$TRANSCRIPT","cwd":"$PROJ"}
PAYLOAD
)
if [ -z "$OUT6" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: запись в локальный BACKLOG чужого проекта не гасит: '$OUT6'"; fi

# ── След разбора (D211): формы доктрины, а не одно слово ──────────────────────
# Повод: ADR-016 добавил реестр мест с дробью и входы узла, а машинный признак разбора был
# один — счёт слова «почему»; связный разбор без него был неотличим от отсутствия разбора
# (7 цепочек на 371 повод), и из трёх живых отказов гейта один пришёлся на текст с
# разделами «Вширь…/Вглубь…» и спуском «←» без единого «почему». Формы выбраны реплеем.
mk_tr() {   # <файл> <текст агента> — транскрипт из одной реплики и одного ответа
    printf '{"message":{"role":"user","content":"чини"}}\n{"message":{"role":"assistant","content":%s}}\n' \
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
TR8="$TMP/t8.jsonl"; mk_tr "$TR8" "страж падает ← голое имя перед не-ASCII ← чинились только подсвеченные строки ← мутация не применилась"
rc_chain_spoken "$(rc_trace "$TR8")" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8]: три стрелки не признаны цепочкой"; }
TR8b="$TMP/t8b.jsonl"; mk_tr "$TR8b" "a ← b ← c"
rc_chain_spoken "$(rc_trace "$TR8b")" && { FAIL=$((FAIL+1)); echo "FAIL [T8b]: две стрелки сочтены цепочкой"; } || PASS=$((PASS+1))

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

echo "root-cause lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
