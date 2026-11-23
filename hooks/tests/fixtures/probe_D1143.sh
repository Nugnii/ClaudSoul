#!/usr/bin/env bash
# СУДИТ: scripts/authorization-replay.py scripts/question-survival.py scripts/colon-lead-in-count.py
# probe_D1143 — инструменты замеров по корпусу считают реплику владельца, набранную посреди хода (вложение
# `queued_command`, `commandMode: prompt`, автор human), репликой собеседника — как хуки после D1142. Корпус-фикстура:
# одна реплика записью `user`, одна — вложением, плюс отчёт субагента той же формы (`origin.kind: peer`), он репликой
# не считается. Красная (1), пока замер насчитывает не две реплики. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
for s in authorization-replay.py question-survival.py colon-lead-in-count.py; do [ -f "$R/scripts/$s" ] || exit 2; done
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1143.XXXXXX") || exit 2
mkdir -p "$T/home/.claude/projects/p" || exit 2
{ jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"посчитай строки в журнале"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Считаю."}]}}'
  jq -nc '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"удали старые логи"}}'
  jq -nc '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"peer"},prompt:"отчёт субагента: готово"}}'
} > "$T/home/.claude/projects/p/s.jsonl" || exit 2
for s in authorization-replay.py question-survival.py; do
    n=$(HOME="$T/home" python3 "$R/scripts/$s" 2>/dev/null | sed -n 's/^реплик собеседника в корпусе: \([0-9][0-9]*\).*/\1/p')
    [ -n "$n" ] || exit 2
    [ "$n" -eq 2 ] || exit 1
done
# Вложение посреди хода ход вопроса НЕ закрывает (живой `inquiry-gap` состояние дописывает): вопрос, вложение, правка,
# затем реплика хода — «ход дошёл до правки файлов» 1 (скептик D1143, M2).
mkdir -p "$T/home2/.claude/projects/p" || exit 2
{ jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"почему падает тест?"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Смотрю."}]}}'
  jq -nc '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"и логи глянь"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e1",name:"Edit",input:{file_path:"/x.py",old_string:"a",new_string:"b"}}]}}'
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"спасибо"}}'
} > "$T/home2/.claude/projects/p/s.jsonl" || exit 2
e=$(HOME="$T/home2" python3 "$R/scripts/question-survival.py" 2>/dev/null | sed -n 's/^из них ход дошёл до правки файлов: \([0-9][0-9]*\).*/\1/p')
[ -n "$e" ] || exit 2
[ "$e" -eq 1 ] || exit 1
# Вопрос вложением открывает вопрос, а второй вопрос при открытом не считается заново (второй круг скептика D1143,
# M-2 и L-1): реплика без вопроса, вопрос вложением, правка, ещё вопрос вложением, реплика хода — вопросов 1, дошёл 1.
mkdir -p "$T/home3/.claude/projects/p" || exit 2
{ jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"посчитай строки в журнале"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Считаю."}]}}'
  jq -nc '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"почему падает тест?"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e2",name:"Edit",input:{file_path:"/x.py",old_string:"a",new_string:"b"}}]}}'
  jq -nc '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"почему опять?"}}'
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"спасибо"}}'
} > "$T/home3/.claude/projects/p/s.jsonl" || exit 2
out=$(HOME="$T/home3" python3 "$R/scripts/question-survival.py" 2>/dev/null)
q=$(printf '%s\n' "$out" | sed -n 's/^признак считает вопросом: \([0-9][0-9]*\).*/\1/p')
e=$(printf '%s\n' "$out" | sed -n 's/^из них ход дошёл до правки файлов: \([0-9][0-9]*\).*/\1/p')
[ -n "$q" ] && [ -n "$e" ] || exit 2
[ "$q" -eq 1 ] && [ "$e" -eq 1 ] || exit 1
# Зачин-двоеточие вложением — тоже реплика (`colon-lead-in-count`, второй круг скептика D1143, M-1): реплика записью
# `user` и вложение, обе с зачином, — счёт 2.
mkdir -p "$T/home4/.claude/projects/p" || exit 2
{ jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:"смотри:\nстрока из лога"}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Вижу."}]}}'
  jq -nc '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",origin:{kind:"human"},prompt:"вот вывод:\nещё строка"}}'
} > "$T/home4/.claude/projects/p/s.jsonl" || exit 2
c=$(HOME="$T/home4" python3 "$R/scripts/colon-lead-in-count.py" 2>/dev/null | sed -n 's/^реплик с зачином-двоеточием: \([0-9][0-9]*\).*/\1/p')
[ -n "$c" ] || exit 2
[ "$c" -eq 2 ] || exit 1
echo "замеры по корпусу видят реплику посреди хода"
exit 0
