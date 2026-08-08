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

# --- T1: одна ошибка ниже порога — молчит ---
mk "$TMP/t1" s e
[ -z "$(run "$TMP/t1" s1)" ] && ok || bad "T1" "сработал на одной ошибке"

# --- T2: две подряд — говорит «стой» и называет число ---
mk "$TMP/t2" s e e
M=$(msg "$(run "$TMP/t2" s2)")
printf '%s' "$M" | grep -q 'СТОП'            && ok || bad "T2a" "нет указания остановиться: $M"
printf '%s' "$M" | grep -q 'упало команд: 2' && ok || bad "T2b" "не названа длина серии: $M"

# --- T3: серия прерывается успехом — не серия ---
mk "$TMP/t3" e s e
[ -z "$(run "$TMP/t3" s3)" ] && ok || bad "T3" "две ошибки через успех приняты за серию"

# --- T4: серия растёт — число обновляется ---
mk "$TMP/t4" s e e e
printf '%s' "$(msg "$(run "$TMP/t4" s4)")" | grep -q 'упало команд: 3' && ok || bad "T4" "длина серии не обновилась"

# --- T5: та же серия дважды — второй раз молчит ---
# PreToolUse срабатывает перед каждой командой; без гашения текст шёл бы на одну неудачу дважды.
[ -z "$(run "$TMP/t4" s4)" ] && ok || bad "T5" "повторное сообщение на ту же серию"

# --- T6: серия кончилась успехом — предложение записать и скелет черновика ---
mk "$TMP/t6" s e e s
M=$(msg "$(run "$TMP/t6" s4)")
printf '%s' "$M" | grep -q '/learn' && ok || bad "T6a" "нет предложения записать: $M"
ls "$TMP/drafts"/case-*-auto-draft.md >/dev/null 2>&1 && ok || bad "T6b" "скелет черновика не создан"

# --- T7: тихая сессия без серии ничего не оставляет ---
mk "$TMP/t7" s s s
[ -z "$(run "$TMP/t7" s7)" ] && ok || bad "T7a" "сработал на успешной сессии"
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

echo ""
echo "error tracker tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
