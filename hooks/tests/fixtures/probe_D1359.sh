#!/usr/bin/env bash
# СУДИТ: hooks/lib/playwright_snapshot.py hooks/playwright-cli-guard.sh
# probe_D1359.sh — падение, чей род срезан хвостом вывода (`| tail -N`), судится по снимку error-context.md на диске.
#
# Повод (22 ноября 2026, живая проверка сессии ProjectA в установленной копии). Прогон с `2>&1 | tail -8` оставил строку
# стека, «Error Context: …», «1 failed» и сводку — строки рода падения срезаны, и правка спеки, упавшей на элементе,
# прошла без отказа D1356. Корпус ProjectA: у 111 из 176 отчётов заголовок падения срезан, род «на элементе» по выводу
# виден у 70 из 192 падений. Скептик (M1): при `tail -3` срезана и строка «Error Context:» — у 450 из 753 падений
# корпуса пути снимка в выводе нет; тогда спека берётся из сводки «N failed», а её снимки — с диска.
# Снимок — в формате, который пишет Playwright (образец — снимок ProjectA из расшифровки, разделы «# Test info» с
# «- Location:», «# Error details», «# Page snapshot»); каталог снимка Playwright называет по ПУТИ спеки
# (`tests-audit-c1-…`). Прогон шёл из web/ (в нём playwright.config.ts), спеки лежат в web/tests/audit/ — путь снимка,
# напечатанный относительно web/, находится подъёмом от каталога спеки, но не выше папки прогона.
# Отказ обязан быть: снимок с падением на элементе (контроль «рамка умеет сказать да»); спека не видна в выводе
#   (только каталог снимка); путь снимка напечатан абсолютным; спека на другой глубине; смешанный вывод (одно падение
#   на элементе видно, у второго род срезан и снимка нет); `expect.soft` — видна ошибка на значении, снимок на
#   элементе; «Error Context:» срезан — спека в сводке, снимок по «- Location:» (и при двух падениях, где путь виден
#   только у второго); каталог снимка назван по пути спеки, а спеки в выводе нет.
# Отказа быть не должно: снимок с падением на значении; на значении, хотя в разделах «# Page snapshot» и «# Test
#   source» есть слова элемента; снимок на элементе, но прочитан; род в выводе виден и он — значение или исчерпанный
#   срок (снимка нет); снимок спеки из сводки прочитан; «- Location:» называет другую спеку с тем же началом имени.
# Подсказка вместо молчания: снимка на диске нет — один раз на набор путей (повтор того же — без подсказки, новый набор
#   — снова); `Error:` не в начале строки (`[WebServer] Error:`) родом падения не считается; спека в сводке без снимка;
#   одноимённый снимок выше папки прогона — чужой.
# Проверка результата: bash hooks/tests/fixtures/probe_D1359.sh → 0 — обрезанное падение судится по снимку на диске;
#   1 — нет отказа, где он должен быть, есть, где не должен, или подсказки нет/лишняя; 2 — не измерено (нет стража,
#   библиотеки, jq или python3).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
G="$REPO/hooks/playwright-cli-guard.sh"
[ -f "$G" ] && [ -f "$REPO/hooks/lib/playwright_snapshot.py" ] && command -v jq >/dev/null 2>&1 \
    && command -v python3 >/dev/null 2>&1 || { echo "нет стража, библиотеки, jq или python3 — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
WEB="$W/web"; mkdir -p "$WEB/tests/audit" "$W/state"
: > "$WEB/playwright.config.ts"
SID=probe-d1359
FENCE='```'

# snapat <корень> <каталог> <location> <текст «# Error details»> [<снимок страницы>] [<исходник>] — снимок на диске
snapat() {
    local d="$1/test-results/$2"; mkdir -p "$d"
    printf '# Instructions\n\n- Following Playwright test failed.\n- Explain why, be concise, respect Playwright best practices.\n\n# Test info\n\n- Name: %s >> t\n- Location: %s:2:5\n\n# Error details\n\n%s\n%s\n%s\n\n# Page snapshot\n\n%syaml\n%s\n%s\n\n# Test source\n\n%sts\n%s\n%s\n' \
        "$3" "$3" "$FENCE" "$4" "$FENCE" "$FENCE" "${5:-- generic [ref=e1]}" "$FENCE" "$FENCE" "${6:-test('t', async () => {});}" "$FENCE" \
        > "$d/error-context.md"
}
# snap <имя> <текст «# Error details»> [<снимок страницы>] [<исходник>] — снимок проверки <имя> в папке прогона
snap() { snapat "$WEB" "$1-t-chromium" "tests/audit/$1.spec.ts" "$2" "${3:-}" "${4:-}"; }
ELEM_ERR="TimeoutError: locator.click: Timeout 15000ms exceeded.
Call log:
  - waiting for getByRole('button', { name: 'Открыть' })
"
VALUE_ERR="Error: expect(received).toBe(expected) // Object.is equality

Expected: 3
Received: 2"
# cut <имя> [нет-стека|абсолютный|-] [<каталог снимка>] [<путь спеки от web/>] — хвост вывода, срезанный `| tail -8`
cut() {
    local sp="${4:-tests/audit/$1.spec.ts}" dir="${3:-$1-t-chromium}"
    local at="        at $WEB/$sp:4:78" ec="test-results/$dir/error-context.md"
    [ "${2:-}" = нет-стека ] && at=""
    [ "${2:-}" = абсолютный ] && ec="$WEB/$ec"
    printf '%s\n\n    Error Context: %s\n\n  1 failed\n    [chromium] › %s:2:5 › t ──────\n' "$at" "$ec" "$sp"
}
# tail3 <путь спеки от web/>… — хвост `| tail -3`: «N failed» и сводка, «Error Context:» срезан
tail3() {
    printf '  %s failed\n' "$#"
    local s; for s in "$@"; do printf '    [chromium] › %s:2:5 › t ──────\n' "$s"; done
}

# tr <файл> <элементы…> — расшифровка; run|<вывод> — прогон с выводом; read|<путь> — Read.
tr() {
    local f="$1"; shift
    python3 -I - "$f" "$@" <<'PY'
import json, sys
f, items = sys.argv[1], sys.argv[2:]
with open(f, 'w', encoding='utf-8') as o:
    for i, it in enumerate(items):
        kind, _, val = it.partition('|')
        tid = 't%d' % i
        if kind == 'run':
            name, inp, res = 'Bash', {'command': 'cd web && npx playwright test tests/audit 2>&1 | tail -8'}, val
        else:
            name, inp, res = 'Read', {'file_path': val}, 'ok'
        use = {'type': 'tool_use', 'id': tid, 'name': name, 'input': inp}
        o.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [use]}}, ensure_ascii=False) + '\n')
        o.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': tid, 'content': res}]}}, ensure_ascii=False) + '\n')
PY
}
# verdict <расшифровка> <правимый файл> → deny | hint | pass
verdict() {
    local p o
    p=$(jq -nc --arg t "$1" --arg f "$2" --arg s "$SID" \
        '{session_id:$s, transcript_path:$t, tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}')
    o=$(printf '%s' "$p" | STATE_DIR="$W/state" bash "$G" 2>/dev/null)
    if grep -q '"permissionDecision": *"deny"' <<< "$o"; then echo deny
    elif grep -q 'род падения' <<< "$o"; then echo hint
    else echo pass; fi
}
bad=0
case_() {   # case_ <ожидание> <имя> <спека от web/tests/audit без .spec.ts | путь от web/> <элементы расшифровки…>
    local want="$1" name="$2" spec got; shift 2
    case "$1" in */*) spec="$WEB/$1" ;; *) spec="$WEB/tests/audit/$1.spec.ts" ;; esac; shift
    tr "$W/c.jsonl" "$@"; got=$(verdict "$W/c.jsonl" "$spec")
    [ "$got" = "$want" ] || { echo "  ✗ $name: ждал $want, получил $got"; bad=1; }
}

snap a1 "$ELEM_ERR"
tr "$W/ctl.jsonl" "run|$(cut a1)"
[ "$(verdict "$W/ctl.jsonl" "$WEB/tests/audit/a1.spec.ts")" = deny ] \
    || { echo "контроль: род срезан хвостом, снимок на диске — падение на элементе, а отказа нет: страж снимок на диске не судит"; exit 1; }
snap a2 "$VALUE_ERR"
snap a3 "$ELEM_ERR"
snap a5 "$VALUE_ERR" "- text: \"waiting for locator('#x') Locator: y\"" "await expect(page.getByRole('dialog')).toBeVisible();"
snap a7 "$ELEM_ERR"
snap a8 "$ELEM_ERR"
snap a12 "$ELEM_ERR"
snapat "$WEB" tests-b2-t-chromium tests/b2.spec.ts "$ELEM_ERR"
snapat "$WEB" tests-audit-c1-t-chromium tests/audit/c1.spec.ts "$ELEM_ERR"
snapat "$WEB" tests-audit-c3-t-chromium tests/audit/c3.spec.ts "$ELEM_ERR"
snapat "$WEB" tests-audit-c5-t-chromium tests/audit/c5.spec.ts "$ELEM_ERR"
snapat "$WEB" c6-admin-t-chromium tests/audit/c6-admin.spec.ts "$ELEM_ERR"
snapat "$W" a13-t-chromium tests/audit/a13.spec.ts "$ELEM_ERR"   # выше папки прогона — чужой прогон
C1="$WEB/test-results/tests-audit-c1-t-chromium/error-context.md"

case_ pass "снимок: падение на значении"                          a2 "run|$(cut a2)"
case_ pass "снимок прочитан"                                      a3 "run|$(cut a3)" "read|$WEB/test-results/a3-t-chromium/error-context.md"
case_ pass "значение; слова элемента только в снимке страницы и исходнике" a5 "run|$(cut a5)"
case_ deny "спека не видна в выводе, только каталог снимка"       a7 "run|$(cut a7 нет-стека)"
case_ deny "путь снимка напечатан абсолютным"                     a8 "run|$(cut a8 абсолютный)"
case_ deny "спека на другой глубине (tests/b2.spec.ts)"           tests/b2.spec.ts "run|$(cut b2 - tests-b2-t-chromium tests/b2.spec.ts)"
case_ pass "род в выводе виден — значение, снимка нет"            a6 "run|        Error: expect(received).toBe(expected) // Object.is equality

        Expected: 3
        Received: 2
$(cut a6)"
case_ pass "род в выводе виден — исчерпан срок, снимка нет"       a10 "run|    Test timeout of 30000ms exceeded.
$(cut a10)"
case_ hint "Error: не в начале строки — род не виден"             a11 "run|    [WebServer] Error: listen EADDRINUSE: address already in use
$(cut a11)"
case_ deny "expect.soft: видна ошибка на значении, снимок на элементе" a12 "run|        Error: expect(received).toBe(expected) // Object.is equality
$(cut a12)"
case_ deny "смешанный вывод: одно падение на элементе, у второго род срезан и снимка нет" a9 "run|Running 2 tests using 1 worker
  1) [chromium] › tests/audit/a9.spec.ts:2:5 › one
    TimeoutError: locator.click: Timeout 15000ms exceeded.
    Error Context: test-results/a9-one-chromium/error-context.md
        at $WEB/tests/audit/a9.spec.ts:9:9
    Error Context: test-results/a9-two-chromium/error-context.md
  2 failed"
# Текст отказа смешанного вывода называет только падение на элементе: строка подсказки `?<TAB>…` в него не попадает.
DENY_TEXT=$(jq -nc --arg t "$W/c.jsonl" --arg f "$WEB/tests/audit/a9.spec.ts" --arg s "$SID-text" \
    '{session_id:$s, transcript_path:$t, tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' \
    | STATE_DIR="$W/state" bash "$G" 2>/dev/null)
grep -q 'a9-two' <<< "$DENY_TEXT" && { echo "  ✗ смешанный вывод: в тексте отказа строка подсказки (a9-two)"; bad=1; }
case_ hint "одноимённый снимок выше папки прогона — чужой"        a13 "run|$(cut a13)"
case_ deny "«Error Context:» срезан: спека в сводке, снимок по Location" c1 "run|$(tail3 tests/audit/c1.spec.ts)"
case_ pass "«Error Context:» срезан, снимок спеки прочитан"       c1 "run|$(tail3 tests/audit/c1.spec.ts)" "read|$C1"
case_ hint "«Error Context:» срезан, снимка на диске нет"         c2 "run|$(tail3 tests/audit/c2.spec.ts)"
case_ deny "два падения, путь виден только у второго"             c3 "run|        at $WEB/tests/audit/c4.spec.ts:4:78
    Error Context: test-results/tests-audit-c4-t-chromium/error-context.md
$(tail3 tests/audit/c3.spec.ts tests/audit/c4.spec.ts)"
case_ deny "каталог назван по пути спеки, спеки в выводе нет"     c5 "run|    Error Context: test-results/tests-audit-c5-t-chromium/error-context.md

  1 failed"
case_ pass "Location называет другую спеку с тем же началом имени" c6 "run|    Error Context: test-results/c6-admin-t-chromium/error-context.md

  1 failed"
case_ hint "снимка на диске нет"                                  a4 "run|$(cut a4)"
case_ pass "снимка нет, вторая правка — без повтора подсказки"    a4 "run|$(cut a4)"
case_ hint "снимка нет, новый набор путей — подсказка снова"      a4 "run|$(cut a4 - a4-u-chromium)"

[ "$bad" = 0 ] || exit 1
echo "обрезанное хвостом падение судится по снимку на диске; снимка нет — подсказка"
exit 0
