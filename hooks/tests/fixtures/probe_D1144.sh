#!/usr/bin/env bash
# СУДИТ: hooks/itr-event-detector.sh
# probe_D1144 — детектор интрузивности не приписывает вторую реплику предложению, на которое уже ответили. Ход:
# реплика → агент «…запускаем?» → «да» вложением посреди хода (`queued_command`) → только вызов инструмента → «нет,
# стоп, не так» вложением. Граница «последняя запись `user`» отдаёт второй реплике текст агента ДО первой, и «нет»
# ложится вторым событием «gentle → ignored» на уже принятое предложение. Красная (1), пока это событие пишется.
# Положительный контроль — на первой реплике событие «принято» записано; без него проба не судит (2).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/itr-event-detector.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
unset ITR_STATE_DIR   # библиотека состояния ставит её выше `STATE_DIR` ниже — унаследованная увела бы запись мимо (D1154, M2)
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1144.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT   # каталог прогона снимается на любом выходе — без этого их копилось по одному на прогон (D1154, L5)
rec() { jq -nc "$@"; }
{ rec '{type:"user",timestamp:"2026-04-01T10:00:00Z",message:{role:"user",content:[{type:"text",text:"напиши функцию"}]}}'
  rec '{type:"assistant",timestamp:"2026-04-01T10:00:05Z",message:{role:"assistant",content:[{type:"text",text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
  rec '{type:"attachment",timestamp:"2026-04-01T10:00:30Z",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"да"}}'
} > "$T/first.jsonl" || exit 2
{ cat "$T/first.jsonl"
  rec '{type:"assistant",timestamp:"2026-04-01T10:00:35Z",message:{role:"assistant",content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:"make"}}]}}'
  rec '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"b1",content:"ok"}]}}'
  rec '{type:"attachment",timestamp:"2026-04-01T10:00:50Z",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"нет, стоп, не так"}}'
} > "$T/second.jsonl" || exit 2
fire() {  # fire <расшифровка> <реплика> <каталог состояния> → события детектора
    mkdir -p "$3"
    jq -nc --arg p "$1" --arg u "$2" '{session_id:"p1144",transcript_path:$p,prompt:$u,hook_event_name:"UserPromptSubmit"}' \
        | STATE_DIR="$3" bash "$HOOK" >/dev/null 2>&1
    jq -r '(.events // [])[] | "\(.type) \(.outcome) \(.reason)"' "$3/intrusiveness-p1144.json" 2>/dev/null
}
fire "$T/first.jsonl" "да" "$T/s1" | grep -q '^gentle accepted' || exit 2
fire "$T/second.jsonl" "нет, стоп, не так" "$T/s2" | grep -q 'запускаем' && exit 1
# Пара вложений подряд, обе записаны до хуков: «да» судится по «запускаем?», а второе («и тесты прогони») — по
# ходу после «да» (он пуст), не по «запускаем?» второй раз. Граница «всё после последнего ответа агента — текущее»
# отдала бы обоим одно предложение.
{ cat "$T/first.jsonl"
  rec '{type:"attachment",timestamp:"2026-04-01T10:00:31Z",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"и тесты прогони"}}'
} > "$T/pair.jsonl" || exit 2
fire "$T/pair.jsonl" "да" "$T/s3" | grep -q '^gentle accepted' || exit 1
fire "$T/pair.jsonl" "и тесты прогони" "$T/s4" | grep -q 'запускаем' && exit 1
# Текущая ищется только ПОСЛЕ последнего ответа агента (скептик D1144, M1): «да» обычной репликой, на «запускаем?»
# уже отвеченное «да» и ответ агента без предложения — событие о «запускаем?» не пишется.
{ cat "$T/first.jsonl"
  rec '{type:"assistant",timestamp:"2026-04-01T10:00:40Z",message:{role:"assistant",content:[{type:"text",text:"Запустил, всё прошло."}]}}'
} > "$T/again.jsonl" || exit 2
fire "$T/again.jsonl" "да" "$T/s5" | grep -q 'запускаем' && exit 1
# Реплика больше предела аргумента не роняет хук (скептик D1144, M2): текст подачи идёт в jq не аргументом.
BIG=$(head -c 1200000 /dev/zero | tr '\0' x)
printf '{"session_id":"p1144big","transcript_path":"%s","prompt":"%s","hook_event_name":"UserPromptSubmit"}' "$T/first.jsonl" "$BIG" > "$T/big.json" || exit 2
mkdir -p "$T/s6"; STATE_DIR="$T/s6" bash "$HOOK" < "$T/big.json" >/dev/null 2>&1 || exit 1
echo "вторая реплика не судится по уже отвеченному предложению"
exit 0
