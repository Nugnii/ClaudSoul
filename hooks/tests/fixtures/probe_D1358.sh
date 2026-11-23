#!/usr/bin/env bash
# СУДИТ: hooks/lib/playwright_snapshot.py hooks/playwright-cli-guard.sh
# probe_D1358.sh — печать снимка в отчёте снимает отказ D1356 только у проверки, чей снимок напечатан целиком.
#
# Повод (22 ноября 2026, сессия ProjectA, формат печати B737). Печать показывает снимок первых трёх упавших проверок,
# остальные — строкой `▶ <путь> — снимок в файле`; снимок длиннее 150 строк режется строкой `… ещё N строк — в файле`.
# Прежде любой заголовок «СНИМОК СТРАНИЦЫ» засчитывал прочитанными снимки всех проверок отчёта.
# Отчёт: четыре проверки упали на элементе; напечатаны a1 и a3 целиком, a2 обрезан, a4 «в файле».
# Отказ обязан быть: правка a4 (контроль «рамка умеет сказать да») и a2. Отказа быть не должно: a1, a3.
# Проверка результата: bash hooks/tests/fixtures/probe_D1358.sh → 0 — печать снимает отказ ровно там, где снимок
#   напечатан целиком; 1 — снимок «в файле» или обрезанный засчитан прочитанным, либо напечатанный — нет; 2 — не
#   измерено (нет стража, библиотеки, jq или python3).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
G="$REPO/hooks/playwright-cli-guard.sh"
[ -f "$G" ] && [ -f "$REPO/hooks/lib/playwright_snapshot.py" ] && command -v jq >/dev/null 2>&1 \
    && command -v python3 >/dev/null 2>&1 || { echo "нет стража, библиотеки, jq или python3 — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
fail() {   # fail <n> → блок падения проверки a<n>
    printf '  %s) [chromium] › audit/a%s.spec.ts:3:5 › t\n    TimeoutError: locator.click: Timeout 15000ms exceeded.\n    Error Context: test-results/a%s-t-chromium/error-context.md\n' "$1" "$1" "$1"
}
REP="Running 4 tests using 1 worker
$(fail 1)
$(fail 2)
$(fail 3)
$(fail 4)
  4 failed
════ СНИМОК СТРАНИЦЫ упавшей проверки (снят в конце проверки) — локатор правь по нему, не по памяти (B737) ════
▶ test-results/a1-t-chromium/error-context.md
- button \"Открыть\"
▶ test-results/a2-t-chromium/error-context.md
- dialog
  … ещё 40 строк — в файле
▶ test-results/a3-t-chromium/error-context.md
- textbox \"Сумма\"
▶ test-results/a4-t-chromium/error-context.md — снимок в файле"
python3 -I - "$W/t.jsonl" "$REP" <<'PY'
import json, sys
f, rep = sys.argv[1], sys.argv[2]
use = {'type': 'tool_use', 'id': 't1', 'name': 'Bash', 'input': {'command': 'cd web && npx playwright test tests/audit'}}
res = {'type': 'tool_result', 'tool_use_id': 't1', 'content': rep}
with open(f, 'w', encoding='utf-8') as o:
    o.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [use]}}, ensure_ascii=False) + '\n')
    o.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': [res]}}, ensure_ascii=False) + '\n')
PY
verdict() {   # verdict <спека> → deny | pass
    local o
    o=$(jq -nc --arg t "$W/t.jsonl" --arg f "/x/web/tests/audit/$1" \
        '{session_id:"probe-d1358", transcript_path:$t, tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' \
        | STATE_DIR="$W/state" bash "$G" 2>/dev/null)
    if grep -q '"permissionDecision": *"deny"' <<< "$o"; then echo deny; else echo pass; fi
}
[ "$(verdict a4.spec.ts)" = deny ] \
    || { echo "контроль: снимок a4 «в файле» засчитан напечатанным — печать снимает отказ со всего отчёта"; exit 1; }
bad=0
[ "$(verdict a2.spec.ts)" = deny ] || { echo "  ✗ обрезанный снимок a2 засчитан прочитанным"; bad=1; }
[ "$(verdict a1.spec.ts)" = pass ] || { echo "  ✗ напечатанный целиком снимок a1 не засчитан"; bad=1; }
[ "$(verdict a3.spec.ts)" = pass ] || { echo "  ✗ напечатанный целиком снимок a3 не засчитан"; bad=1; }
# Второй отчёт — находки скептика по 59ffaeb9. M1: блок печати упорядочен по коду символа, прогон — иначе, и сводка
# Playwright перечисляет спеки перед блоком: снимок ui-audit обрезан, ui-audit-rules напечатан целиком. L1: «снимка
# страницы в файле нет». L2: пробел в имени каталога. L3: текст страницы «… ещё 3 строки» внутри целого снимка.
REP2="Running 5 tests using 1 worker
  1) [chromium] › audit/ui-audit-rules.spec.ts:3:5 › r
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/audit-ui-audit-rules-r-chromium/error-context.md
  2) [chromium] › audit/ui-audit.spec.ts:3:5 › UI audit login screens
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/audit-ui-audit-UI-audit-login-screens/error-context.md
$(fail 5)
  4) [chromium] › audit/a6.spec.ts:3:5 › t x
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/a6-t x-chromium/error-context.md
$(fail 7)
  5 failed
    [chromium] › audit/ui-audit-rules.spec.ts:3:5 › r
    [chromium] › audit/ui-audit.spec.ts:3:5 › UI audit login screens
════ СНИМОК СТРАНИЦЫ упавшей проверки (снят в конце проверки) — локатор правь по нему, не по памяти (B737) ════
▶ test-results/a5-t-chromium/error-context.md
  снимка страницы в файле нет — причина в разделе ошибки этого файла
▶ test-results/a6-t x-chromium/error-context.md
- dialog
  … ещё 12 строк — в файле
▶ test-results/a7-t-chromium/error-context.md
- button \"… ещё 3 строки\"
- textbox
▶ test-results/audit-ui-audit-UI-audit-login-screens/error-context.md
- main
  … ещё 318 строк — в файле
▶ test-results/audit-ui-audit-rules-r-chromium/error-context.md
- button \"Открыть\""
python3 -I - "$W/t.jsonl" "$REP2" <<'PY'
import json, sys
f, rep = sys.argv[1], sys.argv[2]
use = {'type': 'tool_use', 'id': 't1', 'name': 'Bash', 'input': {'command': 'cd web && npx playwright test tests/audit'}}
res = {'type': 'tool_result', 'tool_use_id': 't1', 'content': rep}
with open(f, 'w', encoding='utf-8') as o:
    o.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [use]}}, ensure_ascii=False) + '\n')
    o.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': [res]}}, ensure_ascii=False) + '\n')
PY
[ "$(verdict ui-audit.spec.ts)" = deny ]       || { echo "  ✗ M1: обрезанный снимок ui-audit засчитан прочитанным"; bad=1; }
[ "$(verdict ui-audit-rules.spec.ts)" = pass ] || { echo "  ✗ M1: целый снимок ui-audit-rules не засчитан"; bad=1; }
[ "$(verdict a5.spec.ts)" = deny ]             || { echo "  ✗ L1: «снимка страницы в файле нет» засчитано снимком"; bad=1; }
[ "$(verdict a6.spec.ts)" = deny ]             || { echo "  ✗ L2: путь с пробелом не разобран, обрезанный снимок засчитан"; bad=1; }
[ "$(verdict a7.spec.ts)" = pass ]             || { echo "  ✗ L3: текст страницы «… ещё 3 строки» принят за обрезку"; bad=1; }
# L2 в чистом виде: единственная строка `▶` с пробелом в пути — неразобранная разметка падала в запасное правило «все».
REP3="Running 1 test using 1 worker
  1) [chromium] › audit/a8.spec.ts:3:5 › t x
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/a8-t x-chromium/error-context.md
  1 failed
════ СНИМОК СТРАНИЦЫ упавшей проверки (снят в конце проверки) — локатор правь по нему, не по памяти (B737) ════
▶ test-results/a8-t x-chromium/error-context.md
- dialog
  … ещё 12 строк — в файле"
python3 -I - "$W/t.jsonl" "$REP3" <<'PY'
import json, sys
f, rep = sys.argv[1], sys.argv[2]
use = {'type': 'tool_use', 'id': 't1', 'name': 'Bash', 'input': {'command': 'cd web && npx playwright test tests/audit'}}
res = {'type': 'tool_result', 'tool_use_id': 't1', 'content': rep}
with open(f, 'w', encoding='utf-8') as o:
    o.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [use]}}, ensure_ascii=False) + '\n')
    o.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': [res]}}, ensure_ascii=False) + '\n')
PY
[ "$(verdict a8.spec.ts)" = deny ]             || { echo "  ✗ L2: единственная строка ▶ с пробелом не разобрана — засчитаны все"; bad=1; }
if [ "$bad" -ne 0 ]; then echo "печать снимает отказ не там, где снимок напечатан целиком"; exit 1; fi
echo "снимок в файле и обрезанный печатью прочитанными не считаются"
exit 0
