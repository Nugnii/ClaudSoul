#!/usr/bin/env bash
# test_agent_model_notice.sh — подсказка говорит о тяжёлом типе агента и о названном opus и молчит обо всём прочем.
#
# Результат: агент general-purpose (или без типа), волна без agentType и названный opus получают
#            подсказку с распределением по ролям; lean, Explore, свои типы, одно место с opus в
#            волне, волна без агентов, чужой инструмент и нечитаемый вход проходят молча, код
#            выхода всегда 0.
# Проверка результата: bash hooks/tests/test_agent_model_notice.sh даёт 0
#
# Ноги держат ОБЕ стороны различения: без ног тишины тест зеленел бы у хука, который говорит
# на всё подряд, без ног срабатывания — у того, который молчит всегда.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/agent-model-notice.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
# Хелперы взяты у соседа (test_test_cost_notice.sh), а не изобретены: прувер
# `test_guards_provable.sh` распознаёт доказательство тишины ПО СИГНАТУРЕ.
assert_silent() {   # $1 вывод, $2 метка — тишина
    [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: ${1}"
}
assert_contains() { # $1 вывод, $2 искомое, $3 метка — срабатывание
    if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: ${1}"; fi
}
assert_lacks() {    # $1 вывод, $2 лишнее, $3 метка — подсказка не говорит о чужом признаке
    if grep -Fq "$2" <<< "$1"; then bad "$3" "лишнее '$2' в: ${1}"; else ok; fi
}
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
run() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }
wf()  { jq -cn --arg s "$1" '{tool_name:"Workflow",tool_input:{script:$s}}'; }
HEAVY_MARK="subagent_type: 'lean'"
OPUS_MARK="Назван opus"

# --- агент
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"найди","subagent_type":"general-purpose"}}')
assert_contains "$OUT" "$HEAVY_MARK" "T1 general-purpose — подсказка о lean"
# Пара «роль — модель» проверяется ЦЕЛИКОМ: подсказка с перепутанными ролями несёт все слова.
assert_contains "$OUT" "без модели — haiku (поиск" "T1 исполнителю назван haiku"
assert_contains "$OUT" "model: 'opus' — только финальный скептик" "T1 opus назван только финальному скептику"
assert_contains "$OUT" '"hookEventName":"PreToolUse"' "T1 событие названо"
assert_lacks "$OUT" "$OPUS_MARK" "T1 opus не назван — о нём молчит"
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && ok || bad "T1" "вывод не JSON: $OUT"
OUT=$(run '{"tool_name":"Task","tool_input":{"prompt":"найди"}}')
assert_contains "$OUT" "$HEAVY_MARK" "T2 тип не назван — это general-purpose (и прежнее имя Task)"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"найди","subagent_type":"Explore"}}')
assert_silent "$OUT" "T3 Explore CLAUDE.md не грузит"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"найди","subagent_type":"lean","model":"sonnet"}}')
assert_silent "$OUT" "T4 lean с sonnet"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"найди","subagent_type":"lean"}}')
assert_silent "$OUT" "T4б lean без модели — haiku"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"как","subagent_type":"claude-code-guide"}}')
assert_silent "$OUT" "T5 тип со своей моделью"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"p","subagent_type":"fork","model":"opus"}}')
assert_silent "$OUT" "T5б форк наследует модель и контекст всегда"
OUT=$(run '{"tool_name":"Agent","tool_input":"строка"}')
assert_silent "$OUT" "T5в параметры не объект — вход не прочитан"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"проверь","subagent_type":"lean","model":"opus"}}')
assert_contains "$OUT" "$OPUS_MARK" "T6 lean с opus — подсказка об opus"
assert_lacks "$OUT" "$HEAVY_MARK" "T6 lean — о тяжёлом типе молчит"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"проверь","model":"opus"}}')
assert_contains "$OUT" "$OPUS_MARK" "T6б general-purpose с opus — оба признака"
assert_contains "$OUT" "$HEAVY_MARK" "T6б general-purpose с opus — оба признака"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"проверь","subagent_type":"lean","model":"claude-opus-5-5"}}')
assert_contains "$OUT" "$OPUS_MARK" "T6в полный ID opus — opus"
OUT=$(run '{"tool_name":"Agent","tool_input":{"prompt":"найди","subagent_type":"general-purpose","model":"sonnet"}}')
assert_lacks "$OUT" "$OPUS_MARK" "T6г sonnet — не opus"

# --- волна
# Оба места вызова стоят на ОДНОЙ строке: счёт строк вместо вхождений дал бы 1 (мутант скептика).
NOTYPE='export const meta = {name: "w", description: "d"}
const r = await parallel(items.map(i => () => agent(`сделай ${i}`, {label: i}))); const v = await agent("проверь", {schema: S})'
OUT=$(run "$(wf "$NOTYPE")")
assert_contains "$OUT" "Ни у одного из 2 мест вызова" "T7 волна без agentType — подсказка, места сосчитаны"
assert_contains "$OUT" "agentType: 'lean'" "T7 назван lean"
PARTIAL="${NOTYPE/\{schema: S\}/{schema: S, agentType: \"lean\", model: \"opus\"\}}"
TYPED="${PARTIAL/\{label: i\}/{label: i, agentType: 'lean'\}}"
OUT=$(run "$(wf "$TYPED")")
assert_silent "$OUT" "T8 agentType у каждого места вызова, opus у одного"
OUT=$(run "$(wf "$PARTIAL")")
assert_contains "$OUT" "agentType назван у 1 из 2" "T8б agentType у части вызовов — подсказка с дробью"
OUT=$(run "$(wf 'const a = await agent("делай", {"agentType": "lean", label:"x"})')")
assert_silent "$OUT" "T8в ключ agentType в кавычках — назван"
OUT=$(run "$(wf '// раньше было agentType: "lean", убрали
const rs = await parallel(items.map(i => () => agent(`делай ${i}`)))')")
assert_contains "$OUT" "Ни у одного" "T8г agentType: в строке-комментарии не считается"
OUT=$(run "$(wf 'const a = await agent("x"); const subagentType: string = "y"')")
assert_contains "$OUT" "Ни у одного" "T8д subagentType: — не ключ agentType"
OUT=$(run "$(wf 'const a = await agent ("делай", {label:"x"})')")
assert_contains "$OUT" "Ни у одного" "T8е agent ( с пробелом — вызов"
# Шаблон без кавычек: `\'` внутри ${var/шаблон/…} bash и zsh разбирают по-разному. Замена — из
# переменной: литеральные кавычки в замене bash 5.2 снимает (на CI фикстура теряла кавычки вокруг
# имени модели, и нога краснела), а bash 3.2 оставляет; у результата подстановки переменной
# кавычки не снимает ни одна версия.
_opus_lbl="{label: i, model: 'claude-opus-5-5',"
TWOOPUS="${TYPED/\{label: i,/$_opus_lbl}"
OUT=$(run "$(wf "$TWOOPUS")")
assert_contains "$OUT" "opus назван у 2 мест вызова" "T8ж opus у двух мест — подсказка (и полный ID)"
assert_lacks "$OUT" "Ни у одного" "T8ж agentType назван — о нём молчит"
OUT=$(run "$(wf 'export const meta = {name: "w", description: "d"}
log("без агентов"); return 1')")
assert_silent "$OUT" "T9 волна без вызовов agent("
OUT=$(run "$(wf '// раньше тут был agent( вызов, теперь нет
log("ничего"); const subagent = myagent("x")')")
assert_silent "$OUT" "T9б agent( в комментарии и внутри чужого имени — не вызов"
printf '%s' "$NOTYPE" > "$TMP/wf.js"
OUT=$(run "$(jq -cn --arg p "$TMP/wf.js" '{tool_name:"Workflow",tool_input:{scriptPath:$p}}')")
assert_contains "$OUT" "Ни у одного" "T10 текст волны читается с диска (scriptPath)"
printf '%s' "$TYPED" > "$TMP/wf.js"
OUT=$(run "$(jq -cn --arg p "$TMP/wf.js" '{tool_name:"Workflow",tool_input:{scriptPath:$p}}')")
assert_silent "$OUT" "T11 scriptPath с agentType"
OUT=$(run '{"tool_name":"Workflow","tool_input":{"name":"saved-one"}}')
assert_silent "$OUT" "T12 сохранённая волна без текста — названный предел"
OUT=$(run "$(jq -cn --arg p "$TMP/нет-такого.js" '{tool_name:"Workflow",tool_input:{scriptPath:$p}}')")
assert_silent "$OUT" "T13 файла волны нет"
# Длинный скрипт: счёт не должен зависеть от того, успел ли производитель
# дописать в пайп (SIGPIPE под pipefail читал бы найденное как провал).
BIG=$(printf '%s\n' "$TYPED"; i=0; while [ $i -lt 4000 ]; do printf '// строка набивки %s\n' "$i"; i=$((i+1)); done)
OUT=$(run "$(wf "$BIG")")
assert_silent "$OUT" "T14 agentType в начале длинного скрипта найден"

# --- не наш предмет и нечитаемый вход
OUT=$(run '{"tool_name":"Bash","tool_input":{"command":"echo agent( без модели"}}'); RC=$?
assert_silent "$OUT" "T15 чужой инструмент"
# Код выхода смотрится и тут: без ветки «чужой инструмент» хук падал под set -u, а тишина оставалась.
[ "$RC" -eq 0 ] && ok || bad "T15" "код выхода $RC, ожидался 0"
OUT=$(run 'это не json'); RC=$?
assert_silent "$OUT" "T16 нечитаемый вход"
[ "$RC" -eq 0 ] && ok || bad "T16" "код выхода $RC, ожидался 0"
OUT=$(run ''); RC=$?
assert_silent "$OUT" "T17 пустой вход"
[ "$RC" -eq 0 ] && ok || bad "T17" "код выхода $RC, ожидался 0"

echo "test_agent_model_notice: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
