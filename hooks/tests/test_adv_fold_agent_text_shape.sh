#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/hook-input-lib.sh hooks/lib/transcript_window.py
# test_adv_fold_agent_text_shape.sh — противник свёртки (D498): шаг хода разбирает текст КАЖДОЙ записи агента, прежние читатели — только нужные; запись агента с текстом не строкой ДО границы хода роняет свёртку, и rc_turn_key, rc_last_block, rc_turn_text отдают пусто там, где прежняя версия отдавала метку и речь.
#
# Прежние читатели: `rc_turn_key` тексты агента не разбирал вовсе (только записи user), а
# `rc_last_block` и `rc_turn_text` — только записи агента ПОСЛЕ последней записи user с текстом.
# `RC_TURN_STEP` зовёт `get_text` на каждой записи агента окна: блок `{"type":"text","text":{…}}`
# роняет `join` в jq («string and object cannot be added»), шаг отказывает, запасной путь гонит тот
# же шаг по окну — тот же отказ, итог пуст. Запись стоит до уведомления задачи, то есть до границы,
# по которой читают все три функции, и прежняя версия её не касалась.
# Ожидания — вывод прежней версии (ec157dbd) на этом же файле: метка = cksum строки «задача»
# (последняя запись user с текстом), последний блок и текст хода — «ответ».
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
unset INPUT_LIB HOOK_INPUT_LIB STATE_LOCK_LIB
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "ожидалось «$3», получено «$2»"; fi; }
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"   # временные файлы помощника — тоже под каталогом теста
F="$T/t.jsonl"
{
  jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"раз"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:{rich:"block"}}]}}'
  jq -nc '{type:"user",origin:{kind:"task-notification"},message:{role:"user",content:[{type:"text",text:"задача"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"ответ"}]}}'
} > "$F"
read -r KEY _ <<< "$(cksum <<< "задача")"

run() {  # run <функция> <каталог состояния> [расшифровка]
    mkdir -p "$2"
    STATE_DIR="$2" bash -c '. "$1/root-cause-lib.sh"; "$2" "$3"' _ "$HOOKS" "$1" "${3:-$F}"
}
# Положительный контроль: без записи с текстом не строкой те же ожидания достижимы — значит,
# расхождение ниже даёт именно эта запись, а не ожидания.
grep -v '"rich"' "$F" > "$T/plain.jsonl"
eq K0 "$(run rc_turn_key "$T/st-k0" "$T/plain.jsonl")|$(run rc_last_block "$T/st-l0" "$T/plain.jsonl")" "$KEY|ответ"
# Холодно (свежий каталог состояния) и тепло (тот же каталог, второй вызов).
for st in cold warm warm; do
    eq "K-$st" "$(run rc_turn_key "$T/st-$st")" "$KEY"
done
eq L "$(run rc_last_block "$T/st-l")" "ответ"
eq X "$(run rc_turn_text "$T/st-x")" "ответ"

echo "test_adv_fold_agent_text_shape: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
