#!/usr/bin/env bash
# СУДИТ: hooks/playwright-cli-guard.sh hooks/lib/playwright_snapshot.py
# probe_D1356.sh — правка спеки, чья проверка упала на элементе страницы, отказывается до чтения её снимка.
#
# Повод (22 ноября 2026, решение владельца «Оба»). Знание «упал локатор — прочитай error-context.md до второй попытки»
# держалось текстом; замер корпуса: 29 правок упавшей спеки при непрочитанном снимке, после 15 та же проверка упала
# снова. Страж судит последовательность событий расшифровки, поэтому проба подаёт ему расшифровки, а не одну команду.
# Отказ обязан быть (каждый — своя форма, скептик D1356 M3: одна форма держала мутанта «элемент только по TimeoutError»):
#   упавший локатор и правка спеки без чтения — контроль «рамка умеет сказать да»; падение `expect(locator)` с
#   `Locator:`; после прогона прочитан посторонний файл (сама спека) — мутант «любое чтение снимает отказ»; отчёт
#   фонового прогона прочитан из файла (M1); после отчёта команда лишь упоминает `test:e2e` (L3); прочитан только PNG
#   того же каталога (L2); помощник — его расшифровка, а не родителя.
# Отказа быть не должно: снимок прочитан Read, `cat`, маской, `find` (L1), Grep с маской (L1); прочитана первая из
#   попыток (`-retry1`, L4); падение на значении, хотя во фрагменте кода соседняя строка с `.toBeVisible(` (H1);
#   упала `login-admin.spec.ts`, правится `login.spec.ts` (M2); чужая спека; новый прогон прошёл; снимок напечатан
#   в выводе («СНИМОК СТРАНИЦЫ», ProjectA B737); родитель с чистой расшифровкой.
# Проверка результата: bash hooks/tests/fixtures/probe_D1356.sh → 0 — отказ ровно там, где снимок упавшего элемента не
#   прочитан; 1 — отказа нет там, где должен быть, либо он есть там, где не должен; 2 — не измерено (нет стража,
#   библиотеки, jq или python3).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
G="$REPO/hooks/playwright-cli-guard.sh"
[ -f "$G" ] && [ -f "$REPO/hooks/lib/playwright_snapshot.py" ] && command -v jq >/dev/null 2>&1 \
    && command -v python3 >/dev/null 2>&1 || { echo "нет стража, библиотеки, jq или python3 — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
SID=probe-d1356
D=b702-invoice-link-local-opens-chromium
EC="test-results/$D/error-context.md"
HEAD="Running 1 test using 1 worker
  1) [chromium] › audit/b702-invoice-link-local.spec.ts:10:5 › opens"
ELEM="$HEAD
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Call log:
      - waiting for getByRole('button', { name: 'Открыть' })

    Error Context: $EC
  1 failed"
EXPECT="$HEAD
    Error: Timed out 5000ms waiting for expect(locator).toBeVisible()

    Locator: getByRole('dialog')
    Expected: visible

    Error Context: $EC
  1 failed"
VALUE="$HEAD
    Error: expect(received).toBe(expected) // Object.is equality
    Expected: 3
    Received: 2

      11 |   await page.getByRole('button').click();
    > 12 |   expect(await rows.count()).toBe(3);
         |                              ^
      13 |   await expect(page.getByRole('dialog')).toBeVisible();

    Error Context: $EC
  1 failed"
RETRY="$HEAD
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: $EC
    Retry #1
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/$D-retry1/error-context.md
  1 failed"
ADMIN="Running 1 test using 1 worker
  1) [chromium] › audit/login-admin.spec.ts:5:5 › opens
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/login-admin-opens-chromium/error-context.md
  1 failed"

# tr <файл> <элементы…> — расшифровка; элемент «вид|значение»: run|<отчёт> — прогон с выводом; bg — прогон в фоне;
# read|<путь> — Read; readout|<путь>§<содержимое> — Read файла с выводом; cmd|<команда>[§<вывод>] — Bash;
# grep|<маска> — инструмент Grep.
tr() {
    local f="$1"; shift
    python3 -I - "$f" "$@" <<'PY'
import json, sys
f, items = sys.argv[1], sys.argv[2:]
RUN = 'cd web && npx playwright test tests/audit/b702-invoice-link-local.spec.ts'
with open(f, 'w', encoding='utf-8') as o:
    for i, it in enumerate(items):
        kind, _, val = it.partition('|')
        arg, _, out = val.partition('§')
        tid = 't%d' % i
        if kind == 'run':
            name, inp, res = 'Bash', {'command': RUN}, val
        elif kind == 'bg':
            name, inp, res = 'Bash', {'command': RUN + ' > /tmp/pw.out 2>&1', 'run_in_background': True}, 'Command running in background with ID: b1'
        elif kind == 'read':
            name, inp, res = 'Read', {'file_path': val}, 'ok'
        elif kind == 'readout':
            name, inp, res = 'Read', {'file_path': arg}, out
        elif kind == 'grep':
            name, inp, res = 'Grep', {'pattern': 'button', 'glob': val}, 'ok'
        else:
            name, inp, res = 'Bash', {'command': arg}, out or 'ok'
        use = {'type': 'tool_use', 'id': tid, 'name': name, 'input': inp}
        o.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [use]}}, ensure_ascii=False) + '\n')
        o.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': tid, 'content': res}]}}, ensure_ascii=False) + '\n')
PY
}
# verdict <расшифровка> <правимый файл> [agent_id] → deny | pass
verdict() {
    local p o
    p=$(jq -nc --arg t "$1" --arg f "$2" --arg a "${3:-}" --arg s "$SID" \
        '{session_id:$s, transcript_path:$t, tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}
         + (if $a == "" then {} else {agent_id:$a} end)')
    o=$(printf '%s' "$p" | STATE_DIR="$W/state" bash "$G" 2>/dev/null)
    if grep -q '"permissionDecision": *"deny"' <<< "$o"; then echo deny; else echo pass; fi
}
SPEC=/x/web/tests/audit/b702-invoice-link-local.spec.ts
bad=0
case_() {   # case_ <ожидание> <имя> <правимый файл> <элементы расшифровки…>
    local want="$1" name="$2" spec="$3" got; shift 3
    tr "$W/c.jsonl" "$@"; got=$(verdict "$W/c.jsonl" "$spec")
    [ "$got" = "$want" ] || { echo "  ✗ $name: ждал $want, получил $got"; bad=1; }
}

tr "$W/elem.jsonl" "run|$ELEM"
[ "$(verdict "$W/elem.jsonl" "$SPEC")" = deny ] \
    || { echo "контроль: упавший локатор и правка его спеки без чтения снимка — отказа нет: страж снимок не судит"; exit 1; }
case_ deny "падение expect(locator) с Locator:"        "$SPEC" "run|$EXPECT"
case_ deny "после прогона прочитана сама спека"         "$SPEC" "run|$ELEM" "read|$SPEC"
case_ deny "фоновый прогон, отчёт прочитан из файла"    "$SPEC" "bg|" "readout|/tmp/pw.out§$ELEM"
case_ deny "команда лишь упоминает test:e2e"            "$SPEC" "run|$ELEM" 'cmd|grep -n test:e2e web/package.json§12:  "test:e2e": "playwright test",'
case_ deny "прочитан только PNG того же каталога"       "$SPEC" "run|$ELEM" "read|/x/web/test-results/$D/test-failed-1.png"
case_ pass "прочитан Read"                              "$SPEC" "run|$ELEM" "read|/x/web/$EC"
case_ pass "прочитан cat"                               "$SPEC" "run|$ELEM" "cmd|cat web/$EC"
case_ pass "прочитан маской"                            "$SPEC" "run|$ELEM" "cmd|cat web/test-results/*/error-context.md"
case_ pass "прочитан find"                              "$SPEC" "run|$ELEM" "cmd|find web/test-results -name error-context.md -exec cat {} +"
case_ pass "прочитан Grep с маской"                     "$SPEC" "run|$ELEM" "grep|**/error-context.md"
case_ pass "прочитана первая из попыток"                "$SPEC" "run|$RETRY" "read|/x/web/$EC"
case_ pass "падение на значении, во фрагменте toBeVisible" "$SPEC" "run|$VALUE"
case_ pass "упала login-admin, правится login"          /x/web/tests/audit/login.spec.ts "run|$ADMIN"
case_ pass "чужая спека"                                /x/web/tests/audit/b703-other.spec.ts "run|$ELEM"
case_ pass "новый прогон прошёл"                        "$SPEC" "run|$ELEM" "run|Running 1 test using 1 worker
  1 passed (3.1s)"
case_ pass "снимок напечатан в выводе"                  "$SPEC" "run|$ELEM
СНИМОК СТРАНИЦЫ в момент падения
- button \"Открыть\" [disabled]"
# Помощник: его прогон лежит в его расшифровке; родительская чиста.
mkdir -p "$W/$SID/subagents"
tr "$W/parent.jsonl" "cmd|ls"
tr "$W/$SID/subagents/agent-a1b2.jsonl" "run|$ELEM"
[ "$(verdict "$W/parent.jsonl" "$SPEC" a1b2)" = deny ] || { echo "  ✗ помощник, его снимок не прочитан: ждал deny"; bad=1; }
[ "$(verdict "$W/parent.jsonl" "$SPEC")" = pass ] || { echo "  ✗ родитель с чистой расшифровкой: ждал pass"; bad=1; }

if [ "$bad" -ne 0 ]; then echo "отказ стоит не там, где снимок упавшего элемента не прочитан"; exit 1; fi
echo "правка спеки до чтения снимка отказана, после чтения пропущена"
exit 0
