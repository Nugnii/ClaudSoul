#!/usr/bin/env bash
# СУДИТ: hooks/subagent-outcome.sh
# test_subagent_outcome.sh — обрыв субагента виден контуру, успех молчит.
#
# Результат: субагент, кончившийся вызовом инструмента или размышлением, заводит повод;
#            договоривший — молчит; недоступная расшифровка называется вслух
# Проверка результата: bash hooks/tests/test_subagent_outcome.sh даёт 0
#
# Повод, 9 сентября 2026. Прогон трёх субагентов (4 мин 17 с) завершился без единого
# результата — все три оборвались, структурированного ответа не вернул никто, и НИ ОДИН
# страж этого не заметил: события `SubagentStop` в settings.json не было вовсе. Все десять
# поводов разбора читают состояние СЕССИИ, а у субагента своя сессия и свой транскрипт:
# вынесенная в него работа выпадала из контура ПО ПОСТРОЕНИЮ.
# Собеседник назвал это прямо: «не дал результата = нерабочий инструмент, и сторож ошибки
# не сработал».
#
# ФОРМА ФИКСТУР ВЗЯТА ИЗ МИРА: строки повторяют настоящие записи транскрипта субагента
# (`.message.content[]` с полем `type`), а признак проверен на ТРЁХ настоящих оборвавшихся
# и ТРЁХ настоящих договоривших прогонах этой же сессии — 3 из 3 и 3 из 3.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/subagent-outcome.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Ожидание роста расшифровки (D1354) — 20 раз по 0,1 с на каждом вердикте «не договорил»: настоящим `sleep` ноги
# обрыва стоили бы по 2 с. Расшифровка ноги не растёт, поэтому `sleep` подменён пустым; ожидание с ростом файла
# держат нога T18 (свой `sleep` дописывает результат) и проба hooks/tests/fixtures/probe_D1354.sh.
NOSLEEP="$TMP/nosleep"; mkdir -p "$NOSLEEP"; printf '#!/bin/sh\nexit 0\n' > "$NOSLEEP/sleep"; chmod +x "$NOSLEEP/sleep"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

run() {  # run <расшифровка СУБАГЕНТА> [расшифровка родителя] ; печатает очередь
    # Форма payload ВЗЯТА ИЗ МИРА (замер 17 сентября 2026, D450): на `SubagentStop` харнесс
    # кладёт расшифровку субагента в `agent_transcript_path`, а в `transcript_path` — путь
    # РОДИТЕЛЯ. Прежде тест подавал расшифровку агента полем `transcript_path`, то есть
    # формой, которой харнесс не производит, и был зелён, пока страж судил родителя
    # (`pattern-fixture-form-not-taken-from-the-world`). Родитель по умолчанию кончается
    # `tool_use` — так он и выглядит в этот момент: он ждёт ответа от вызова Task.
    # РАСКЛАДКА ПУТЕЙ ТОЖЕ ВЗЯТА ИЗ МИРА: расшифровка агента лежит в
    # `<каталог проекта>/<session_id>/subagents/`, родительская — рядом с каталогом сессии.
    # Владелец резолва эту раскладку сверяет (иначе путь от харнесса вёл бы куда угодно), и
    # плоская фикстура в общем temp'е ему законно не годится.
    local st="$TMP/state.$RANDOM"; mkdir -p "$st"
    local sid="sid$RANDOM"; local proj="$TMP/proj-$sid"
    mkdir -p "$proj/$sid/subagents"
    local par="${2:-$TMP/parent-default.jsonl}"
    cp "$par" "$proj/$sid.jsonl" 2>/dev/null || :
    local ag="$proj/$sid/subagents/agent-a$RANDOM.jsonl"
    if [ -f "$1" ]; then cp "$1" "$ag"; fi
    jq -cn --arg a "$ag" --arg p "$proj/$sid.jsonl" --arg s "$sid" --arg i "a$RANDOM" \
        '{session_id:$s, transcript_path:$p, agent_id:$i, agent_transcript_path:$a}' \
      | PATH="$NOSLEEP:$PATH" STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
    cat "$st/pending-alerts.txt" 2>/dev/null || true
}
mk() {   # mk <файл> <тип последнего блока>
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"задача"}]}}\n' >> "$1"
    case "$2" in
        text)        printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"готовый ответ"}]}}\n' >> "$1" ;;
        tool_use)    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n' >> "$1" ;;
        thinking)    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"…"}]}}\n' >> "$1" ;;
        # Форма ВЗЯТА ИЗ МИРА (10 сентября 2026): в живой расшифварке `user tool_result`
        # ВСЕГДА следует за `assistant tool_use` — инструмент не может ответить, пока его не
        # позвали. Прежняя фикстура клала результат без предшествующего вызова, то есть
        # форму, которой мир не производит; после того как страж стал различать РОЛЬ, эта
        # фикстура превратилась в «расшифровку без единого блока ассистента» и нога
        # покраснела не по делу (`pattern-fixture-form-not-taken-from-the-world`).
        # Форма агента ВОЛНЫ, взятая из мира (замер 18 сентября 2026 по 400 живым
        # расшифровкам): он сдаёт результат ВЫЗОВОМ `StructuredOutput`, текстом не кончает
        # никогда. Таких 312 из 322 расшифровок, кончающихся вызовом инструмента.
        structured) printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"StructuredOutput","input":{}}]}}\n' >> "$1"
                     printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Structured output provided successfully"}]}}\n' >> "$1" ;;
        # Настоящий обрыв агента волны: вызов обычного инструмента, ответ «пользователь не
        # хочет продолжать» (8 из 10 живых обрывов выглядят так).
        interrupted) printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n' >> "$1"
                     printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"The user doesn t want to proceed with this tool use"}]}}\n' >> "$1" ;;
        # Форма ФОНОВОГО агента Agent, взятая из мира (2 октября 2026, 5 из 5 живых расшифровок,
        # кончающихся вызовом `SubagentHandback`): отчёт сдаётся вызовом, ответ харнесса —
        # «Report delivered to your caller.».
        handback)    jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"SubagentHandback",input:{}}]}}' >> "$1"
                     jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:[{type:"text",text:"{\"success\":true,\"message\":\"Report delivered to your caller.\"}"}]}]}}' >> "$1" ;;
        tool_result) printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n' >> "$1"
                     printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"вывод"}]}}\n' >> "$1" ;;
    esac
}

mk "$TMP/parent-default.jsonl" tool_use   # родитель в этот момент ждёт ответа от вызова Task

# --- T1: оборвался на вызове инструмента → повод заведён ---
mk "$TMP/a.jsonl" tool_use
grep -q 'ОБОРВАЛСЯ' <<< "$(run "$TMP/a.jsonl")" && ok || bad "T1: обрыв на tool_use не замечен"

# --- T2: оборвался на размышлении → повод заведён ---
mk "$TMP/b.jsonl" thinking
grep -q 'ОБОРВАЛСЯ' <<< "$(run "$TMP/b.jsonl")" && ok || bad "T2: обрыв на thinking не замечен"

# --- T3: оборвался на результате инструмента → повод заведён ---
mk "$TMP/c.jsonl" tool_result
grep -q 'ОБОРВАЛСЯ' <<< "$(run "$TMP/c.jsonl")" && ok || bad "T3: обрыв на tool_result не замечен"

# --- T4: ДОГОВОРИЛ → молчит. Без этой ноги страж кричал бы всегда ---
mk "$TMP/d.jsonl" text
[ -z "$(run "$TMP/d.jsonl")" ] && ok || bad "T4: успешный субагент не должен заводить повод"

# --- T5: расшифровки нет → называется вслух, а не выдаётся за успех (три состояния) ---
grep -q 'недоступна' <<< "$(run "$TMP/нет-такого.jsonl")" && ok || bad "T5: недоступная расшифровка выдана за успех"

# --- T6: дедуп — один оборвавшийся прогон даёт одно сообщение ---
st="$TMP/dedup"; mkdir -p "$st"
for _ in 1 2; do
    mkdir -p "$TMP/proj-same/same/subagents"
    cp "$TMP/parent-default.jsonl" "$TMP/proj-same/same.jsonl"
    cp "$TMP/a.jsonl" "$TMP/proj-same/same/subagents/agent-one.jsonl"
    jq -cn --arg a "$TMP/proj-same/same/subagents/agent-one.jsonl" --arg p "$TMP/proj-same/same.jsonl" --arg s same \
        '{session_id:$s, transcript_path:$p, agent_id:"one", agent_transcript_path:$a}' \
      | PATH="$NOSLEEP:$PATH" STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
done
n=$(grep -c 'ОБОРВАЛСЯ' "$st/pending-alerts.txt" 2>/dev/null || true)
[ "$n" = "1" ] && ok || bad "T6: повторный вызов на том же прогоне дал $n сообщений (ожидалось 1)"

# --- T7: расшифровка НЕ ЧИТАЕТСЯ → говорит. Четвёртое состояние, прежде слитое со вторым ---
# `jq 2>/dev/null` на битом JSON давал пустой разбор, тот уходил в ветку «блоков нет вовсе»
# и молчал — то есть нечитаемая расшифровка выдавалась за успех. Проба прожарки дословно:
# `printf 'не json вовсе' > t.jsonl` → страж молчал.
printf 'не json вовсе\n' > "$TMP/broken.jsonl"
grep -q 'не читается' <<< "$(run "$TMP/broken.jsonl")" && ok || bad "T7: битая расшифровка выдана за успех"

# --- T8: обрыв заводит ПОВОД контура, а не только строку в очереди ---
# Прежде срода не было в RC_KINDS_RE, rc_note_event не звался, и свод незакрытого повода не
# видел: строка показывалась и исчезала, хотя шапка обещала «повод возвращается на границе
# хода». Проверяется журнал событий, а не текст сообщения.
st8="$TMP/event"; mkdir -p "$st8"
mkdir -p "$TMP/proj-ev/ev/subagents"; cp "$TMP/parent-default.jsonl" "$TMP/proj-ev/ev.jsonl"
cp "$TMP/a.jsonl" "$TMP/proj-ev/ev/subagents/agent-ev1.jsonl"
jq -cn --arg a "$TMP/proj-ev/ev/subagents/agent-ev1.jsonl" --arg p "$TMP/proj-ev/ev.jsonl" --arg s "ev" --arg c "$TMP" \
    '{session_id:$s, transcript_path:$p, agent_id:"ev1", agent_transcript_path:$a, cwd:$c}' \
  | STATE_DIR="$st8" bash "$HOOK" >/dev/null 2>&1
k8=$(jq -r 'select(.status=="open") | .kind' "$st8/pending-events.jsonl" 2>/dev/null | head -1)
[ "$k8" = "subagentcut" ] && ok || bad "T8: повод контура не заведён (kind=[$k8], ожидался subagentcut)"

# --- T9: повод ДОХОДИТ до читателя, а не только ложится в журнал ---
# Проверяется сквозной путь, а не объявленность в перечне: `subagentcut` — род СОБЫТИЯ
# (как `ci-red`, `revert`, `resurrected`), а не срод хода, и в `RC_KINDS_RE` ему не место —
# первая редакция этой ноги смешала два пространства имён и была поймана
# `test_kinds_writer_reader_parity` словами «писателя в дереве нет». Читатель у родов
# события один — `rc_open_events`, им же пользуется гейт.
if [ -f "$ROOT/hooks/root-cause-lib.sh" ]; then
    seen9=$(env -u CLAUDSOUL_REPO -u CLAUDE_HOME -u BACKLOG_FILE bash -c \
        '. "$1/hooks/root-cause-lib.sh"; rc_open_events "$2" "$3"' _ "$ROOT" "$st8" "$TMP")
    grep -q 'subagentcut' <<< "$seen9" && ok \
        || bad "T9: повод записан, но читателю событий не виден: [$seen9]"
else
    bad "T9: библиотеки контура нет — сквозной путь не проверен"
fi

# --- T10 (D450): судится расшифровка СУБАГЕНТА, а не родителя — направление «кричать» ---
# Родитель договорил текстом, субагент оборвался на вызове инструмента. Страж, читающий
# родителя, промолчал бы и настоящий обрыв потерял.
mk "$TMP/p10.jsonl" text
mk "$TMP/a10.jsonl" tool_use
grep -q 'ОБОРВАЛСЯ' <<< "$(run "$TMP/a10.jsonl" "$TMP/p10.jsonl")" && ok \
    || bad "T10: обрыв субагента не замечен при договорившем родителе"

# --- T11 (D450): то же, направление «молчать» — ложная тревога на КАЖДОМ успехе ---
# Так выглядит мир: субагент договорил, а родитель в этот момент стоит на `tool_use` самого
# вызова Task. Прежний страж читал родителя и кричал «оборвался» на каждом успешном агенте,
# после чего постоянный ключ дедупа гасил все следующие — 16 файлов `.seen` по одной строке.
mk "$TMP/a11.jsonl" text
[ -z "$(run "$TMP/a11.jsonl" "$TMP/parent-default.jsonl")" ] && ok \
    || bad "T11: успешный субагент объявлен оборвавшимся по состоянию родителя"

# --- T12 (D450): поля нет (старый клиент) → «недоступна», а не суд над родителем ---
st12="$TMP/nofield"; mkdir -p "$st12"
out12=$(jq -cn --arg p "$TMP/parent-default.jsonl" --arg s "nf" '{session_id:$s, transcript_path:$p}' \
    | STATE_DIR="$st12" bash "$HOOK" >/dev/null 2>&1; cat "$st12/pending-alerts.txt" 2>/dev/null || true)
if grep -q 'недоступна' <<< "$out12"; then ok
elif grep -q 'ОБОРВАЛСЯ' <<< "$out12"; then bad "T12: без поля страж осудил расшифровку РОДИТЕЛЯ"
else bad "T12: без поля ожидалось «недоступна», получено: [${out12:0:80}]"; fi

# --- T13 (D450): дедуп принадлежит АГЕНТУ, а не сессии ---
# Ключ — cksum пути расшифровки. Пока читался путь родителя, он был постоянен в пределах
# сессии, и второй настоящий обрыв другого агента глохнул. Двое разных агентов в одной
# сессии обязаны дать два сообщения.
st13="$TMP/dedup2"; mkdir -p "$st13"
mk "$TMP/a13x.jsonl" tool_use
mk "$TMP/a13y.jsonl" thinking
mkdir -p "$TMP/proj-one/one/subagents"; cp "$TMP/parent-default.jsonl" "$TMP/proj-one/one.jsonl"
cp "$TMP/a13x.jsonl" "$TMP/proj-one/one/subagents/agent-x.jsonl"
cp "$TMP/a13y.jsonl" "$TMP/proj-one/one/subagents/agent-y.jsonl"
for id in x y; do
    jq -cn --arg a "$TMP/proj-one/one/subagents/agent-$id.jsonl" --arg p "$TMP/proj-one/one.jsonl" --arg s one --arg i "$id" \
        '{session_id:$s, transcript_path:$p, agent_id:$i, agent_transcript_path:$a}' \
      | STATE_DIR="$st13" bash "$HOOK" >/dev/null 2>&1
done
n13=$(grep -c 'ОБОРВАЛСЯ' "$st13/pending-alerts.txt" 2>/dev/null || true)
[ "$n13" = "2" ] && ok || bad "T13: два разных оборвавшихся агента дали $n13 сообщений (ожидалось 2)"

# --- T14 (D450): агент ВОЛНЫ сдал результат структурированным ответом → тишина ---
# Признак «договорил = последний блок text» взят по форме агента инструмента Task и на
# агентах волны ложен: замер 18 сентября 2026 — 312 из 322 расшифровок, кончающихся вызовом
# инструмента, суть `StructuredOutput` с успехом. Первая редакция починки D450 объявляла их
# оборвавшимися, и нога T11 этого не видела, потому что фикстура кончалась текстом.
mk "$TMP/a14.jsonl" structured
[ -z "$(run "$TMP/a14.jsonl")" ] && ok || bad "T14: сданный структурированный ответ объявлен обрывом"

# --- T15 (D450): прерванный вызов инструмента остаётся обрывом ---
mk "$TMP/a15.jsonl" interrupted
grep -q 'ОБОРВАЛСЯ' <<< "$(run "$TMP/a15.jsonl")" && ok || bad "T15: прерванный агент выдан за успех"

# --- T17: фоновый агент сдал отчёт вызовом `SubagentHandback` → тишина ---
# Живой случай 2 октября 2026: противник D498 отдал отчёт этим вызовом (родитель его получил),
# а страж, знавший единственный инструмент сдачи `StructuredOutput`, объявил обрыв.
mk "$TMP/a17.jsonl" handback
[ -z "$(run "$TMP/a17.jsonl")" ] && ok || bad "T17: отчёт, сданный вызовом SubagentHandback, объявлен обрывом"

# --- T16 (D450): расшифровка ОТСТАЁТ от ответа — судит поле харнесса, а не файл ---
# Живой случай 18 сентября 2026 после переноса: агент ответил текстом «сделано», а страж
# прочитал последним блоком `tool_use` — строка ответа легла в файл уже после вызова хука.
run_with_msg() {  # run_with_msg <расшифровка агента> <last_assistant_message>
    local st="$TMP/state.$RANDOM"; mkdir -p "$st"
    local sid="sid$RANDOM"; local proj="$TMP/proj-$sid"
    mkdir -p "$proj/$sid/subagents"
    cp "$TMP/parent-default.jsonl" "$proj/$sid.jsonl"
    local ag="$proj/$sid/subagents/agent-a$RANDOM.jsonl"; cp "$1" "$ag"
    jq -cn --arg a "$ag" --arg p "$proj/$sid.jsonl" --arg s "$sid" --arg i "a$RANDOM" --arg m "$2" \
        '{session_id:$s, transcript_path:$p, agent_id:$i, agent_transcript_path:$a, last_assistant_message:$m}' \
      | PATH="$NOSLEEP:$PATH" STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
    cat "$st/pending-alerts.txt" 2>/dev/null || true
}
mk "$TMP/a16.jsonl" tool_use
[ -z "$(run_with_msg "$TMP/a16.jsonl" "сделано")" ] && ok \
    || bad "T16: ответ харнесса не зачтён — судится отставшая расшифровка"

# --- T17 (D450): поле пустое — судит расшифровка, обрыв остаётся обрывом ---
# Без этой ноги «поле есть» глушило бы стража всегда, и обрыв стал бы невидим.
grep -q 'ОБОРВАЛСЯ' <<< "$(run_with_msg "$TMP/a16.jsonl" "")" && ok \
    || bad "T17: при пустом ответе обрыв не замечен"

# --- T18 (D510): результат сдачи ложится ПОСЛЕ события — страж ждёт его, а не кричит ---
# Живой случай 3 октября 2026: строка «Report delivered» легла через 0,23 с после события.
# Гонка разыграна без таймингов: подменённый `sleep` дописывает результат, когда страж ждёт.
run_race() {  # run_race <дописывать результат: 1|0> ; печатает очередь
    local st="$TMP/state.$RANDOM" sid="sid$RANDOM"; mkdir -p "$st" "$TMP/bin.$sid"
    local proj="$TMP/proj-$sid"; mkdir -p "$proj/$sid/subagents"
    cp "$TMP/parent-default.jsonl" "$proj/$sid.jsonl"
    local ag="$proj/$sid/subagents/agent-a$RANDOM.jsonl"
    mk "$ag" handback; head -n 2 "$ag" > "$ag.cut"; tail -n 1 "$ag" > "$TMP/bin.$sid/r.json"; mv "$ag.cut" "$ag"
    if [ "$1" = 1 ]; then
        # Результат ложится на 5-м сне, а не на первом: на первом ожидание, выходящее при неизменном файле или ждущее
        # один раз, выглядело бы верным (M1 скептика D1354).
        printf '#!/bin/sh\nn=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "%s/n"\n[ "$n" -eq 5 ] && cat "%s" >> "%s"\nexit 0\n' \
            "$TMP/bin.$sid" "$TMP/bin.$sid" "$TMP/bin.$sid/r.json" "$ag" > "$TMP/bin.$sid/sleep"
    else
        printf '#!/bin/sh\nexit 0\n' > "$TMP/bin.$sid/sleep"
    fi
    chmod +x "$TMP/bin.$sid/sleep"
    jq -cn --arg a "$ag" --arg p "$proj/$sid.jsonl" --arg s "$sid" --arg i "a$RANDOM" \
        '{session_id:$s, transcript_path:$p, agent_id:$i, agent_transcript_path:$a}' \
      | PATH="$TMP/bin.$sid:$PATH" STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
    cat "$st/pending-alerts.txt" 2>/dev/null || true
}
[ -z "$(run_race 1)" ] && ok || bad "T18: результат сдачи, легший после события, не дождались — объявлен обрыв"
# --- T19 (D510): результат сдачи не пришёл вовсе — это обрыв, ожидание не глушит стража ---
grep -q 'ОБОРВАЛСЯ' <<< "$(run_race 0)" && ok || bad "T19: сдача без результата выдана за успех"

echo "subagent outcome: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
