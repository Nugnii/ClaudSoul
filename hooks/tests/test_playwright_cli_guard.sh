#!/usr/bin/env bash
# СУДИТ: hooks/playwright-cli-guard.sh
# test_playwright_cli_guard.sh — свидетель стража Playwright CLI: отказ одноразовому скрипту и подсказка на
# чтение снимка прогона.
#
# Результат: снимок, снятый прогоном Playwright этой сессии (новее отметки прогона) или лежащий в его выходных
#            каталогах, при чтении получает подсказку «доказывай CLI» — раз на прогон; картинка, бывшая до
#            прогона, не-PNG и прогон чужой сессии — тишина; одноразовый скрипт по-прежнему отбивается
# Проверка результата: bash hooks/tests/test_playwright_cli_guard.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$(cd "$DIR/.." && pwd)/playwright-cli-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/shots" "$TMP/pics" "$TMP/web/test-results/spec-a"

call() {  # call <инструмент> <поле> <значение> [сессия]
    printf '{"tool_name":"%s","session_id":"%s","tool_input":{"%s":%s}}' \
        "$1" "${4:-s-1}" "$2" "$(jq -Rn --arg c "$3" '$c')" \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
hint() { jq -e '.hookSpecificOutput.additionalContext and (.hookSpecificOutput.permissionDecision == null)' <<< "$1" >/dev/null 2>&1; }
deny() { jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<< "$1" >/dev/null 2>&1; }
# Снимок «после прогона» — время в будущем: отметка прогона ставится «сейчас», и равенство секунд не мешает.
shot() { printf 'png' > "$1"; touch -t 203001010000 "$1"; }

printf 'png' > "$TMP/pics/owner.png"; touch -t 202601010000 "$TMP/pics/owner.png"   # картинка до прогона
shot "$TMP/shots/a.png"; shot "$TMP/shots/b.png"; shot "$TMP/shots/c.png"; shot "$TMP/shots/D.PNG"
shot "$TMP/web/test-results/spec-a/test-failed-1.png"; printf 'x' > "$TMP/shots/note.ts"; touch -t 203001010000 "$TMP/shots/note.ts"

# T1 — прогона в сессии не было, путь не из выходных каталогов Playwright: тишина.
[ -z "$(call Read file_path "$TMP/shots/a.png")" ] && ok || bad T1 "подсказка без прогона Playwright"

# T2 — запуск Playwright CLI — правильный путь: не отказ, тишина.
O=$(call Bash command "cd web && AUDIT_BASE=http://localhost:3100 npx playwright test --config tests/ui-audit.config.ts tax-limit-local")
[ -z "$O" ] && ok || bad T2 "запуск playwright test получил ответ: ${O:0:120}"

# T3 — снимок, снятый после прогона, прочитан: подсказка (не отказ), называет CLI и след.
O=$(call Read file_path "$TMP/shots/a.png")
hint "$O" && ok || bad T3 "нет подсказки на снимок прогона: ${O:0:160}"
grep -q 'show-trace' <<< "$O" && grep -q 'playwright test' <<< "$O" && ok || bad T3b "подсказка не называет show-trace и playwright test"

# T4 — второй снимок того же прогона: тишина, вопрос уже задан.
[ -z "$(call Read file_path "$TMP/shots/b.png")" ] && ok || bad T4 "повтор в том же прогоне не заглушён"

# T5 — картинка, бывшая до прогона: тишина.
[ -z "$(call Read file_path "$TMP/pics/owner.png")" ] && ok || bad T5 "подсказка на картинку старше прогона"

# T6 — не-PNG новее прогона: тишина.
[ -z "$(call Read file_path "$TMP/shots/note.ts")" ] && ok || bad T6 "подсказка на чтение не-PNG"

# T7 — новый прогон — новая подсказка (ключ дедупа — прогон, а не сессия).
call Bash command "npx playwright test tests/e2e/smoke.spec.ts" >/dev/null
hint "$(call Read file_path "$TMP/shots/c.png")" && ok || bad T7 "второй прогон заглушён ключом первого"

# T8 — расширение заглавными тоже снимок.
call Bash command "npm run test:e2e" >/dev/null
hint "$(call Read file_path "$TMP/shots/D.PNG")" && ok || bad T8 "снимок .PNG не узнан"

# T9 — выходной каталог Playwright узнаётся и без прогона в сессии.
hint "$(call Read file_path "$TMP/web/test-results/spec-a/test-failed-1.png" s-2)" && ok || bad T9 "снимок из test-results без подсказки"

# T10 — прогон ЧУЖОЙ сессии эту сессию не метит.
call Bash command "npx playwright test" s-3 >/dev/null
[ -z "$(call Read file_path "$TMP/shots/a.png" s-4)" ] && ok || bad T10 "прогон сессии s-3 пометил сессию s-4"

# T11 — прежнее поведение: одноразовый скрипт вне тестов отбивается.
deny "$(call Write file_path "$TMP/scratch.ts" s-1 | cat)" && bad T11 "пустой Write отбит" || ok
O=$(printf '{"tool_name":"Write","session_id":"s-1","tool_input":{"file_path":"%s","content":%s}}' "$TMP/scratch.ts" \
    "$(jq -Rn --arg c "import { chromium } from 'playwright'; const b = await chromium.launch();" '$c')" \
    | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
deny "$O" && ok || bad T11b "одноразовый скрипт с chromium.launch не отбит"

# T12 — отказ оставляет маркер сработавшего стража: его читает cross-hook recall gate (blocker-tier-check, D530).
[ -s "$TMP/state/playwright-cli-guard-fired-s-1.jsonl" ] && ok || bad T12 "отказ не оставил маркер playwright-cli-guard-fired"

# T13 — правка спеки, упавшей на элементе страницы, отказывается до чтения снимка (D1356): проба держит отказ и
# семь пропусков, включая помощника с собственной расшифровкой.
bash "$DIR/fixtures/probe_D1356.sh" >/dev/null 2>&1 && ok || bad T13 "проба D1356: отказ стоит не там, где снимок упавшего элемента не прочитан"

# T14 — три состояния прибора снимка. Библиотеки нет — тишина (другая машина); библиотека сломалась (код 2) —
# подсказка, а не отказ и не тишина: молчание читалось бы «снимок прочитан».
printf '{}\n' > "$TMP/t.jsonl"
spec_edit() {  # spec_edit <SNAP_LIB>
    printf '{"tool_name":"Edit","session_id":"s-9","transcript_path":"%s","tool_input":{"file_path":"/x/web/tests/a.spec.ts","old_string":"a","new_string":"b"}}' "$TMP/t.jsonl" \
        | SNAP_LIB="$1" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
[ -z "$(spec_edit "$TMP/no-such-lib.py")" ] && ok || bad T14a "библиотеки нет, а страж заговорил"
printf 'import sys\nsys.exit(2)\n' > "$TMP/broken.py"
O=$(spec_edit "$TMP/broken.py")
hint "$O" && ok || bad T14b "сломанная библиотека дала тишину или отказ вместо подсказки: $O"
# T14c — исключение python даёт код 1, а не 2; страж обязан говорить и о нём (скептик D1356, L5: прежде молчал).
printf 'import sys\nsys.exit(1)\n' > "$TMP/raised.py"
O=$(spec_edit "$TMP/raised.py")
hint "$O" && ok || bad T14c "код 1 библиотеки прочитан как «прочитано»: $O"
# T15 — отказ по непрочитанному снимку маркера «поймана импровизация» не пишет: его читает recall gate
# blocker-tier-check со знанием pattern-inside-out-blindness, а это отказ не о том (скептик D1356, L6).
mkdir -p "$TMP/state15"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"r1","name":"Bash","input":{"command":"npx playwright test"}}]}}' \
    '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r1","content":"Running 1 test using 1 worker\n  1) [chromium] › a.spec.ts:3:5 › t\n    TimeoutError: locator.click: Timeout 15000ms exceeded.\n    Error Context: test-results/a-t-chromium/error-context.md\n  1 failed"}]}}' > "$TMP/t15.jsonl"
O=$(printf '{"tool_name":"Edit","session_id":"s-15","transcript_path":"%s","tool_input":{"file_path":"/x/web/tests/a.spec.ts","old_string":"a","new_string":"b"}}' "$TMP/t15.jsonl" \
    | STATE_DIR="$TMP/state15" bash "$HOOK" 2>/dev/null)
deny "$O" && ok || bad T15a "фикстура T15 не дала отказа — рамка не проверяет маркер"
[ ! -e "$TMP/state15/playwright-cli-guard-fired-s-15.jsonl" ] && ok || bad T15b "отказ по снимку записал маркер импровизации"

# T16 — печать снимка (ProjectA B737) снимает отказ только у проверки, чей снимок напечатан целиком: «— снимок в файле» и
# обрезанный строкой «… ещё N строк» прочитанными не считаются (D1358).
bash "$DIR/fixtures/probe_D1358.sh" >/dev/null 2>&1 && ok || bad T16 "проба D1358: печать снимает отказ не там, где снимок напечатан целиком"

echo "playwright cli guard: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
