#!/usr/bin/env bash
# test_error_tracker.sh — провалы считаются там, где они видны.
#
# Повод (D41). Хук стоял на PostToolUse[Bash] и читал `.tool_result.exit_code`. Зонд на
# установленной копии снял НАСТОЯЩЕЕ событие и дал два независимых факта:
#
#   1. Поля `tool_result` в payload нет: имя `tool_response`, внутри `stdout`, `stderr`,
#      `interrupted`, `isImage`, `noOutputExpected` — кода возврата среди них нет вовсе.
#   2. **На упавшей Bash-команде PostToolUse не срабатывает.** Из четырёх команд подряд
#      (`exit 7`, `grep` по несуществующему файлу, `echo`, разбор) события породили только
#      успешные. Счётчик провалов не мог заполниться НИ ПРИ КАКОМ имени поля.
#
# Наблюдаемое следствие: все `error_count_*` на диске = 0, ноль настоящих срабатываний за
# 3,5 месяца. Прежняя версия ЭТОГО теста была при этом зелёная, потому что конструировала
# ту же форму payload, которую хук предполагал:
#   jq -cn '{tool_result: {exit_code: ($ec|tonumber), stderr: $se}}'
# Это `pattern-detector-wired-to-failure` в чистом виде: проверка подтверждала допущение,
# а не поведение.
#
# Поэтому фикстура здесь — расшифровка в том виде, в каком её пишет Claude Code: блок
# `tool_result` с `is_error` и телом «Exit code N». Форма снята с живого события.
#
# Вторая правка (2026-08-21): счёт по ОКНУ, а не по непрерывной серии. Харнесс велит
# слать независимые вызовы одним блоком, поэтому соседний успех рвал серию, не отменяя
# буксования — за две недели хук сказал что-то 15 раз при 4 провалах в одной сессии.
# Прежний T3 закреплял ровно этот дефект («две ошибки через успех — не серия»), теперь
# он перевёрнут. Заодно закрепляется второй канал вывода: один `systemMessage` до хода
# не доходит.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/error-tracker.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/drafts"
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# $1=метка $2=вывод — хук обязан молчать. Отдельное имя, потому что мета-страж
# test_guards_provable.sh ищет утверждения о тишине лексически.
assert_empty() { [ -z "$2" ] && ok || bad "$1" "ожидалась тишина, получено: $2"; }

# Расшифровка: последовательность исходов, e=ошибка, s=успех (в порядке появления).
mk() {
    local out="$1"; shift
    : > "$out"
    local c r
    for c in "$@"; do
        if [ "$c" = "e" ]; then
            r='{"type":"tool_result","is_error":true,"content":"Exit code 1"}'
        else
            r='{"type":"tool_result","is_error":false,"content":"ok"}'
        fi
        printf '{"type":"user","message":{"content":[%s]}}\n' "$r" >> "$out"
    done
}
run() { # $1=расшифровка $2=sid
    printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Bash"}' "$2" "$1" \
        | STATE_DIR="$TMP/state" ERROR_TRACKER_DRAFT_DIR="$TMP/drafts" bash "$HOOK" 2>&1
}
msg() { printf '%s' "$1" | jq -r '.systemMessage // ""' 2>/dev/null; }

# Расшифровка с ЗАДАННЫМ телом ошибочного блока: не всякий is_error — буксование.
mk_body() {   # mk_body <файл> <тело1> <тело2> ...
    local out="$1"; shift
    : > "$out"
    local b
    for b in "$@"; do
        jq -cn --arg t "$b" '{type:"user",message:{content:[{type:"tool_result",is_error:true,content:$t}]}}' >> "$out"
    done
}

# --- T0 (D95): решение стража, таймаут и отказ классификатора — не провалы ---
# Замер 27 августа 2026 по 146 ошибочным блокам за неделю: из восьми «провалов»,
# положивших в _drafts четыре пустых скелета, настоящее буксование одно. Хук чинили
# 23 августа на ОТЗЫВ («перестал ловить вовсе»), точность после этого не мерили ни разу.
mk_body "$TMP/t0a" '🛑 playwright-cli-guard: одноразовый скрипт — запрещено.' '🛑 trust-guard: без явной auth.'
assert_empty "T0a" "$(run "$TMP/t0a" s0a)"
mk_body "$TMP/t0b" 'Exit code 143 Command timed out after 2m 0s' 'Exit code 143 Command timed out after 2m 0s ok'
assert_empty "T0b" "$(run "$TMP/t0b" s0b)"
mk_body "$TMP/t0c" 'Permission for this action was denied by the Claude Code auto mode classifier.' 'Permission for this action was denied by the Claude Code auto mode classifier.'
assert_empty "T0c" "$(run "$TMP/t0c" s0c)"

# T0f (D95): собственный замер, сообщающий находки кодом возврата, — вердикт, не сбой.
# Замер 28 августа 2026 по реестру: из 16 замеров с календарным периодом ТРИ выходят с
# кодом 1 при находках — second-contour-freshness, usage-outcome-audit,
# knowledge-independence. Это не небрежность: `measurement-due.sh:89` читает ровно эту
# разницу (0 — находок нет, 1 — есть), и «вернуть 0», предлагавшееся пунктом D95 первым
# вариантом, уничтожило бы её. Поэтому исключение, а не правка семантики.
mk_body "$TMP/t0f" 'Exit code 1 ⚠️ размечена меньшая часть сессий (39% < 50%) [замер: находки, не сбой]' 'Exit code 1 [замер: находки, не сбой]'
assert_empty "T0f" "$(run "$TMP/t0f" s0f)"

# Настоящие провалы считаться обязаны — сужение не смеет ослепить хук.
mk_body "$TMP/t0d" 'Exit code 1 Traceback (most recent call last): File "<string>"' 'Exit code 1 cp: no such file'
[ -n "$(run "$TMP/t0d" s0d)" ] && ok || bad "T0d" "настоящие провалы перестали считаться — сужение съело отзыв"
# Ловушка: «command not found: timeout» — НАСТОЯЩИЙ провал, слово timeout внутри.
mk_body "$TMP/t0e" 'Exit code 1 (eval):1: command not found: timeout Traceback' 'Exit code 1 Traceback'
[ -n "$(run "$TMP/t0e" s0e)" ] && ok || bad "T0e" "слово timeout внутри настоящего провала выбросило его"

# --- T1: одна ошибка ниже порога — молчит ---
mk "$TMP/t1" s e
assert_empty "T1" "$(run "$TMP/t1" s1)"   # одна ошибка ниже порога

# --- T2: две в окне — говорит «стой» и называет число ---
mk "$TMP/t2" s e e
M=$(msg "$(run "$TMP/t2" s2)")
grep -q 'СТОП' <<< "$M"     && ok || bad "T2a" "нет указания остановиться: $M"
grep -q 'упало 2' <<< "$M"  && ok || bad "T2b" "не названо число провалов: $M"

# --- T3: провалы через успех — всё равно буксование ---
# Суть правки. Независимые вызовы идут одним блоком: соседка в том же блоке проходит и
# рвёт непрерывность, хотя мы стоим на месте. Раньше здесь ожидалась тишина.
mk "$TMP/t3" e s e
[ -n "$(run "$TMP/t3" s3)" ] && ok || bad "T3" "две ошибки через успех не замечены — счёт снова по непрерывной серии"

# --- T4: провалов больше — число обновляется ---
mk "$TMP/t4" s e e e
grep -q 'упало 3' <<< "$(msg "$(run "$TMP/t4" s4)")" && ok || bad "T4" "число провалов не обновилось"

# --- T4b: фиксация серии дописывает ts-журнал (мост D229 для жнеца провалов) ---
# Файл-флаг времени не несёт; жнец джойнит «инжект × провал» по ts отсюда.
if [ -f "$TMP/state/error-streak-log-s4.jsonl" ] \
   && jq -e 'select(.ts != null and .attempts == 3)' "$TMP/state/error-streak-log-s4.jsonl" >/dev/null 2>&1; then ok
else bad "T4b" "ts-журнал серии не дописан: $(cat "$TMP/state/error-streak-log-s4.jsonl" 2>/dev/null)"; fi

# --- T5: то же число дважды — второй раз молчит ---
# PreToolUse срабатывает перед каждой командой; без гашения текст шёл бы на одну неудачу дважды.
assert_empty "T5" "$(run "$TMP/t4" s4)"   # то же число провалов — второй раз молчит
# ...и ts-журнал не растёт на той же длине серии (тот же гейт, что у сообщения)
N_TS=$(grep -c '' "$TMP/state/error-streak-log-s4.jsonl" 2>/dev/null || printf '0')
[ "${N_TS}" = "1" ] && ok || bad "T5b" "ts-журнал вырос без смены серии: $N_TS строк"

# --- T6: провалы вышли из окна — предложение записать и скелет черновика ---
# Окно шире одной команды, поэтому «отпустило» наступает не на первом успехе, а когда
# провалы выпали из последних RECENT исходов.
mk "$TMP/t6" s e e s s s s s s
M=$(msg "$(run "$TMP/t6" s4)")
grep -q '/learn' <<< "$M" && ok || bad "T6a" "нет предложения записать: $M"
ls "$TMP/drafts"/case-*-auto-draft.md >/dev/null 2>&1 && ok || bad "T6b" "скелет черновика не создан"
# Перенос строки — настоящий, а не литеральные два символа: в двойных кавычках bash
# не разворачивает \n, и путь к черновику приезжал одной строкой с «\n» в теле.
grep -q '\\n' <<< "$M" && bad "T6c-nl" "в тексте литеральное \\n вместо переноса: $M" || ok

# --- T6c: один провал в окне — ниже порога, молчит ---
# Отделяет «буксуем» от «одна команда упала и поехали дальше».
mk "$TMP/t6c" s s e s s
assert_empty "T6c" "$(run "$TMP/t6c" s6c)"

# --- T6d: старые провалы за окном не считаются ---
mk "$TMP/t6d" e e e s s s s s s
assert_empty "T6d" "$(run "$TMP/t6d" s6d)"

# --- T7: тихая сессия без серии ничего не оставляет ---
mk "$TMP/t7" s s s
assert_empty "T7a" "$(run "$TMP/t7" s7)"
[ -f "$TMP/state/error_streak_fired_s7" ] && bad "T7b" "оставлен след при отсутствии серии" || ok

# --- T8: нет расшифровки — молча выходит, а не падает ---
OUT=$(printf '{"session_id":"x","transcript_path":"/nope/missing.jsonl"}' | STATE_DIR="$TMP/state" bash "$HOOK" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT" ]; } && ok || bad "T8" "без расшифровки: код $rc, вывод '$OUT'"

# --- T9: хук зарегистрирован на PreToolUse, и только на нём ---
# Суть починки: на упавшей команде PostToolUse не срабатывает, поэтому регистрация на нём
# делает хук неработоспособным независимо от его кода. Двойная регистрация — тоже дефект:
# `install.sh` умеет добавлять запись и не умеет удалять, поэтому перенос хука между
# событиями оставляет старую (найдено здесь же, заведено как D55).
INST="$HOME/.claude/settings.json"
if [ -f "$INST" ] && command -v python3 >/dev/null 2>&1; then
    EV=$(python3 - "$INST" <<'PY'
import json, sys, pathlib
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(",".join(sorted({ev for ev, ms in d.get("hooks", {}).items()
                       for m in ms for h in m.get("hooks", [])
                       if "error-tracker" in h.get("command", "")})))
PY
)
    [ "$EV" = "PreToolUse" ] && ok || bad "T9" "error-tracker зарегистрирован как '$EV', ожидалось только PreToolUse"
else
    ok
fi

# --- T10: install.sh описывает ту же регистрацию, что установлена ---
if command -v python3 >/dev/null 2>&1; then
    EV_SRC=$(python3 - "$HOOKS_DIR/../install.sh" <<'PY'
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S)
if not m:
    print("не-разобрано"); raise SystemExit
d = json.loads(m.group(1))
print(",".join(sorted({ev for ev, ms in d.get("hooks", {}).items()
                       for mm in ms for h in mm.get("hooks", [])
                       if "error-tracker" in h.get("command", "")})))
PY
)
    [ "$EV_SRC" = "PreToolUse" ] && ok \
        || bad "T10" "install.sh регистрирует error-tracker как '$EV_SRC' — на чистой машине хук встанет не туда"
else
    ok
fi

# --- T11: отрицательный контроль — фикстура заведомо содержит серию ---
# Без него зелёные T1/T3/T7 не отличимы от «хук всегда молчит».
mk "$TMP/t11" e e e e
[ -n "$(run "$TMP/t11" s11)" ] && ok \
    || bad "T11 отрицательный контроль" "на четырёх ошибках подряд хук молчит — он не измеряет ничего"

# --- T12: прежняя выдуманная форма payload больше ничего не даёт ---
# Закрепляет суть D41: если кто-то вернёт чтение `.tool_result.exit_code`, покраснеют
# T2/T4/T11 — проверка перестала зависеть от допущения и зависит от данных.
OUT=$(printf '{"tool_result":{"exit_code":1,"stderr":"boom"}}' | STATE_DIR="$TMP/state" bash "$HOOK" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT" ]; } && ok || bad "T12" "хук отреагировал на выдуманную форму payload: '$OUT'"

# --- T13: текст идёт обоими каналами ---
# Замер по истории расшифровок: 15 срабатываний ушли в один `systemMessage`, и ход не
# отреагировал ни разу — записи `hook_system_message` в поток сообщений не попадают.
# Без этой проверки регресс канала снова будет выглядеть как «хук молчит».
mk "$TMP/t13" s e e
OUT=$(run "$TMP/t13" s13)
AC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
EV=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
grep -q 'СТОП' <<< "$AC"  && ok || bad "T13a" "additionalContext пуст — до хода текст не дойдёт"
[ "$EV" = "PreToolUse" ]  && ok || bad "T13b" "hookEventName '$EV', ожидалось PreToolUse"
[ -n "$(msg "$OUT")" ]    && ok || bad "T13c" "systemMessage пропал — владелец больше не видит"

echo ""
echo "error tracker tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
