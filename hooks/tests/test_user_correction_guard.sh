#!/usr/bin/env bash
# СУДИТ: hooks/user-correction-guard.sh
# test_user_correction_guard.sh — предметный признак сравнивает реплику с ходом агента
# ДО неё, а не со своим эхом.
#
# Результат: «Сигнал C» стража поправок считает пересечение слов реплики с последним
#   текстом агента, написанным ДО этой реплики; текст текущего хода в сравнение не входит
# Проверка результата: bash hooks/tests/test_user_correction_guard.sh даёт 0
#
# Повод, измеренный 13 сентября 2026. Шапка стража объявляет предмет так: «поправка
# говорит о том, что агент только что назвал сделанным». Код брал последний текст агента
# ВООБЩЕ (`select(.type=="assistant") | … | tail -1`), а на первом же вызове инструмента
# текущего хода последним оказывается текст, написанный УЖЕ ПОСЛЕ реплики. Пункт 0 велит
# начинать ход с переформулировки реплики своими словами — и признак сравнивал реплику
# с её собственным эхом.
#
# Цена по корпусу (243 расшифровки, 1929 настоящих реплик): срабатываний предметного
# признака 681, из них 414 (60,8%) держались ТОЛЬКО на тексте после реплики; словарь
# перехватывает из них 39. Ложная поправка не только шумит: срод `correction` даёт гейту
# разбора право на ОТКАЗ (five-whys-gate.sh:98), и первым же таким отказом в этой сессии
# был остановлен законный прогон набора тестов.
#
# КОНТРПРИМЕР (страж обязан СКАЗАТЬ): реплика, чьи слова стоят в ходе агента ДО неё, —
# это и есть объявленный предмет, и молчание на ней было бы починкой вырезанием проверки.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/user-correction-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_silent()   { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: $(printf '%s' "$1" | head -c 200)"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Записи расшифровки — в той форме, в какой их читает `transcript_agent_text_before_reply`.
# Записи user — в форме мира: `message.role` user у всех 99 255 записей выборки (1 ноября 2026); без роли правило
# владельца (`owner_reply`, D1156) записи не берёт, и нога молчания молчала бы от формы, а не от флага, который судит.
rec_user()  { jq -cn --arg t "$1" '{type:"user", origin:{kind:"human"}, message:{role:"user", content:[{type:"text", text:$t}]}}'; }
rec_meta()  { jq -cn --arg t "$1" '{type:"user", isMeta:true, message:{role:"user", content:[{type:"text", text:$t}]}}'; }
rec_agent() { jq -cn --arg t "$1" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'; }

run_guard() { # $1 sid, $2 transcript → stdout
    jq -cn --arg s "$1" --arg p "$2" \
        '{session_id:$s, transcript_path:$p, tool_name:"Bash", tool_input:{}, hook_event_name:"PreToolUse"}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# Реплика подобрана так, чтобы СЛОВАРЬ поправок её не брал: срабатывание или тишина
# ниже говорят о предметном признаке, а не о лексике.
REPLY='Доля переработок посчитана неверно'
BEFORE_HIT='Посчитана доля переработок в журнале: 13 процентов'
BEFORE_MISS='Открыл журнал и сверил числа'
ECHO_TURN='Проверяю: доля переработок посчитана по всем журналам'

# --- T0: положительный контроль — слова реплики стоят в ходе агента ДО неё → страж говорит ---
T="$TMP/t0.jsonl"
{ rec_user 'Посчитай долю переработок в журнале'; rec_agent "$BEFORE_HIT"; rec_user "$REPLY"; } > "$T"
OUT=$(run_guard t0 "$T")
assert_contains "$OUT" 'permissionDecision' 'T0 предмет назван — страж обязан сказать'

# --- T1: эхо текущего хода предметом не является → тишина (на прежнем коде нога красная) ---
T="$TMP/t1.jsonl"
{ rec_user 'Открой журнал'; rec_agent "$BEFORE_MISS"; rec_user "$REPLY"; rec_agent "$ECHO_TURN"; } > "$T"
OUT=$(run_guard t1 "$T")
assert_silent "$OUT" 'T1 сравнение с собственным эхом реплики'

# --- T2: первая реплика сессии — агент до неё не говорил, сравнивать не с чем ---
T="$TMP/t2.jsonl"
{ rec_user "$REPLY"; } > "$T"
OUT=$(run_guard t2 "$T")
assert_silent "$OUT" 'T2 сравнивать не с чем'

# --- T3: вставка харнесса границу не уводит ---
# Без признака авторства последней «репликой» стала бы вставка (:5), и в окно «до неё»
# попал бы эхо-текст текущего хода (:4) — то есть дефект вернулся бы через другую дверь.
T="$TMP/t3.jsonl"
{ rec_user 'Открой журнал'; rec_agent "$BEFORE_MISS"; rec_user "$REPLY"; rec_agent "$ECHO_TURN"
  rec_meta 'Доля переработок посчитана по журналам — тело скилла'; } > "$T"
OUT=$(run_guard t3 "$T")
assert_silent "$OUT" 'T3 граница по авторству, а не по роли записи'

# --- T4: ask, показанный ОДНОМУ актору, не гасит его ДРУГОМУ (D463) ---
# Подпись дросселя была одним хешем реплики, и первый сработавший гасил ask всем. Замер по
# корпусу: в сессии 08d60959 единственное срабатывание случилось у субагента, а дальше 26
# `muted` РОДИТЕЛЯ по тому же хешу — владелец ask не увидел ни разу.
run_guard_as() { # $1 sid, $2 transcript, $3 agent_id (пусто — родитель)
    jq -cn --arg s "$1" --arg p "$2" --arg a "$3" \
        'if $a == "" then {session_id:$s, transcript_path:$p, tool_name:"Bash", tool_input:{}, hook_event_name:"PreToolUse"}
         else {session_id:$s, transcript_path:$p, agent_id:$a, tool_name:"Bash", tool_input:{}, hook_event_name:"PreToolUse"} end' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
T="$TMP/t4.jsonl"
{ rec_user 'Посчитай долю переработок в журнале'; rec_agent "$BEFORE_HIT"; rec_user "$REPLY"; } > "$T"
# D1018 (22 октября 2026): агенту ask не выставляется вовсе — расшифровка у его вызова родительская, реплика обращена
# к родителю, а вопрос уходил человеку, которого рядом нет (111 вопросов агентам в 14 сессиях).
OUT=$(run_guard_as t4 "$T" "sub-1")
assert_silent "$OUT" 'T4 агенту — ни ask, ни подсказки (D1018)'
OUT=$(run_guard_as t4 "$T" "")
assert_contains "$OUT" 'permissionDecision' 'T4 владелец получает ask после вызова агента'
# Вторая половина предмета: дроссель ОДНОГО актора цел, иначе ask повторялся бы на каждом вызове.
OUT=$(run_guard_as t4 "$T" "")
assert_silent "$OUT" 'T4b повтор тому же актору гасится'
OUT=$(run_guard_as t4 "$T" "sub-1")
assert_silent "$OUT" 'T4c повтор тому же субагенту гасится'

# --- T5: сигнал «файл правится повторно» судит правку, а не чтение (D511) ---
# Поле file_path несут и читающие инструменты; до 4 октября 2026 Read файла, правленого до
# реплики, давал «ты правишь файл, который уже правил» — трём исполнителям за один прогон.
run_guard_tool() { # $1 sid, $2 transcript, $3 tool_name
    jq -cn --arg s "$1" --arg p "$2" --arg t "$3" \
        '{session_id:$s, transcript_path:$p, tool_name:$t, tool_input:{file_path:"/work/notes.md"}, hook_event_name:"PreToolUse"}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
T="$TMP/t5.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/work/notes.md"}}]}}' \
    '{"type":"user","message":{"role":"user","content":"запусти консолидацию накопленного за три недели"}}' > "$T"
OUT=$(run_guard_tool t5-edit "$T" Edit)
assert_contains "$OUT" 'permissionDecision' 'T5 контроль: правка правленого файла — страж говорит'
OUT=$(run_guard_tool t5-read "$T" Read)
assert_silent "$OUT" 'T5a чтение того же файла — молчание'
OUT=$(run_guard_tool t5-grep "$T" Grep)
assert_silent "$OUT" 'T5b поиск по тому же файлу — молчание'

# --- T6, T7 (D1138): реплика контекстного признака — реплика ВЛАДЕЛЬЦА, а служебный ход поправкой не судится ---
# Второе проявление 26 октября 2026: правка файла, уведомление задачи, вторая правка того же файла — и реплика, сказанная
# за 1 ч 41 мин до того, легла поправкой. Контроль T6b — та же раскладка с настоящей репликой владельца: страж говорит.
EDIT_REC='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/work/notes.md"}}]}}'
LONG_REPLY='запусти консолидацию накопленного за три недели'
T="$TMP/t6.jsonl"
printf '%s\n' "$(rec_user "$LONG_REPLY")" "$EDIT_REC" \
    '{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"}}' > "$T"
OUT=$(run_guard_tool t6 "$T" Edit)
assert_silent "$OUT" 'T6 уведомление задачи между правками принято за реплику (D1138)'
T="$TMP/t6b.jsonl"
printf '%s\n' "$EDIT_REC" "$(rec_user "$LONG_REPLY")" > "$T"
OUT=$(run_guard_tool t6b "$T" Edit)
assert_contains "$OUT" 'permissionDecision' 'T6b контроль: реплика владельца после правки — страж говорит'
# T6c/T6d: то же на ЗАПАСНОМ пути (jq в страже) — копия библиотеки без соседнего lib/transcript_window.py; два пути одного
# признака обязаны отвечать одинаково на формах мира. Быстрый `_is_reply_any` зовёт `is_owner_speech` — то же правило
# владельца, что у запасного пути (D1209).
mkdir -p "$TMP/nolib"; cp "$HOOKS/hook-input-lib.sh" "$TMP/nolib/"
OUT=$(INPUT_LIB="$TMP/nolib/hook-input-lib.sh" run_guard_tool t6c "$TMP/t6.jsonl" Edit)
assert_silent "$OUT" 'T6c запасной путь: уведомление задачи принято за реплику (D1138)'
OUT=$(INPUT_LIB="$TMP/nolib/hook-input-lib.sh" run_guard_tool t6d "$TMP/t6b.jsonl" Edit)
assert_contains "$OUT" 'permissionDecision' 'T6d контроль запасного пути: реплика владельца после правки — страж говорит'
# T6e–T6h (скептик D1138, M-1): служебная запись без origin — тело скилла (`isMeta`) и сводка сжатия — между правками
# тоже не реплика, на обоих путях. По корпусу на этом отсеве держится 287 из 962 снятых ложных срабатываний.
for _kind in isMeta isCompactSummary; do
    T="$TMP/t6-$_kind.jsonl"
    printf '%s\n' "$(rec_user "$LONG_REPLY")" "$EDIT_REC" \
        "$(jq -cn --arg k "$_kind" '{type:"user", message:{role:"user", content:[{type:"text", text:"служебный текст харнесса"}]}} | .[$k] = true')" > "$T"
    OUT=$(run_guard_tool "t6-$_kind" "$T" Edit)
    assert_silent "$OUT" "T6e запись $_kind между правками принята за реплику (быстрый путь)"
    OUT=$(INPUT_LIB="$TMP/nolib/hook-input-lib.sh" run_guard_tool "t6n-$_kind" "$T" Edit)
    assert_silent "$OUT" "T6g запись $_kind между правками принята за реплику (запасной путь)"
done
T="$TMP/t7.jsonl"
printf '%s\n' "$EDIT_REC" "$(rec_user "$(printf '%s\n' '<command-message>retro</command-message>' '<command-name>/retro</command-name>')")" > "$T"
OUT=$(run_guard_tool t7 "$T" Edit)
assert_silent "$OUT" 'T7 вызов слеш-команды судится поправкой (D1138)'
# T7b: третья служебная форма живого журнала (`correction-fired-532e1d40-…:2`) — вывод `!`-команды владельца.
T="$TMP/t7b.jsonl"
printf '%s\n' "$EDIT_REC" "$(rec_user '<bash-stdout>exit 0</bash-stdout><bash-stderr></bash-stderr>')" > "$T"
OUT=$(run_guard_tool t7b "$T" Edit)
assert_silent "$OUT" 'T7b вывод bash-команды владельца судится поправкой (D1138)'

echo "user correction guard subject window: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
