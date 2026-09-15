#!/usr/bin/env bash
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
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

run() {  # run <транскрипт> ; печатает очередь
    local st="$TMP/state.$RANDOM"; mkdir -p "$st"
    jq -cn --arg p "$1" --arg s "sid$RANDOM" '{session_id:$s, transcript_path:$p}' \
      | STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
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
        tool_result) printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n' >> "$1"
                     printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"вывод"}]}}\n' >> "$1" ;;
    esac
}

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
    jq -cn --arg p "$TMP/a.jsonl" --arg s "same" '{session_id:$s, transcript_path:$p}' \
      | STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
done
n=$(grep -c 'ОБОРВАЛСЯ' "$st/pending-alerts.txt" 2>/dev/null || echo 0)
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
jq -cn --arg p "$TMP/a.jsonl" --arg s "ev" --arg c "$TMP" \
    '{session_id:$s, transcript_path:$p, cwd:$c}' \
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

echo "subagent outcome: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
