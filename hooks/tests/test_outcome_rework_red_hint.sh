#!/usr/bin/env bash
# СУДИТ: scripts/outcome.sh hooks/lib/rework_red_run.py
# test_outcome_rework_red_hint.sh — «показалось» по поводу переработки при КРАСНОМ прогоне между заходами принимается, но
# прибор исходов называет это разворотом и пишет случай в журнал (D1303, решение владельца 16 ноября 2026 — подсказка).
#
# Повод: эталонная выборка ProjectA — «показалось» ошибочно у 8 из 15, у всех восьми между заходами упал прогон.
# H1 — красный прогон между правками в окне 10 минут: исход записан, подсказка есть;
# H2 — положительный контроль тишины: прогон между правками зелёный — подсказки нет;
# H3 — правки дальше окна друг от друга (первая — за 21 минуту), красный прогон между ними — подсказки нет;
# H5 — живой ложный случай 16 ноября 2026: правки с промежутком 3 часа, чужой красный прогон за 5 минут до второй — тишина;
# H4 — прогон спеки, называющий путь файла, правкой не считается: красный прогон после него всё ещё «между правками».
# H6 — отказ стража между правками (вызов НЕ исполнен) — не прогон, даже если в тексте отказа есть слово провала;
#      исполненная команда с кодом не 0 — прогон; отказ перед настоящим красным прогоном не прячет его (D1303, 22 ноября
#      2026: 26 из 50 подсказок живого журнала стояли на отказе стража, чаще всего самого стража разбора).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUTCMD="$REPO/scripts/outcome.sh"; GATE="$REPO/hooks/five-whys-gate.sh"
[ -f "$OUTCMD" ] && [ -f "$GATE" ] || { echo "FAIL: нет $OUTCMD или $GATE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ST="$TMP/state"; PROJ="$TMP/projects"
mkdir -p "$ST" "$PROJ/p" || { echo "FAIL: подготовка мира не удалась: mkdir"; exit 1; }
F="$TMP/w/spec.ts"
iso() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - float(sys.argv[1]))))' "$1"; }
use() { # <файл расшифровки> <секунд назад> <id> <имя> <json-вход>
    jq -cn --arg t "$(iso "$2")" --arg i "$3" --arg n "$4" --argjson in "$5" \
        '{type:"assistant", timestamp:$t, message:{role:"assistant", content:[{type:"tool_use", id:$i, name:$n, input:$in}]}}' >> "$1"
}
res() { # <файл расшифровки> <секунд назад> <id> <текст>
    jq -cn --arg t "$(iso "$2")" --arg i "$3" --arg b "$4" \
        '{type:"user", timestamp:$t, message:{role:"user", content:[{type:"tool_result", tool_use_id:$i, content:$b}]}}' >> "$1"
}
res_err() { # <файл расшифровки> <секунд назад> <id> <текст> — результат с флагом is_error (код не 0 либо вызов отказан)
    jq -cn --arg t "$(iso "$2")" --arg i "$3" --arg b "$4" \
        '{type:"user", timestamp:$t, message:{role:"user", content:[{type:"tool_result", tool_use_id:$i, content:$b, is_error:true}]}}' >> "$1"
}
scenario() { # <sid> <секунд назад у прогона> <текст результата прогона> [<секунд назад у первой правки>=400] → вывод
    local sid="$1" tr="$PROJ/p/$1.jsonl"
    : > "$tr"
    local e1="${4:-400}"
    use "$tr" "$e1" e1 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"a", new_string:"b"}')"; res "$tr" "$(( e1 - 1 ))" e1 ok
    use "$tr" "$2" b1 Bash "$(jq -cn --arg f "$F" '{command:("npx playwright test " + $f)}')"; "${RESF:-res}" "$tr" "$(( $2 - 5 ))" b1 "$3"
    use "$tr" 30 e2 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"b", new_string:"c"}')"; res "$tr" 29 e2 ok
    printf '{"path":"%s","cycles":2}\n' "$F" > "$ST/rework-fired-$sid.jsonl"
    jq -cn --arg s "$sid" --arg p "$tr" '{session_id:$s, tool_name:"Write", tool_input:{file_path:"/x/next.ts"}, transcript_path:$p}' \
        | STATE_DIR="$ST" bash "$GATE" >/dev/null 2>&1
    STATE_DIR="$ST" DIS_SESSION="$sid" CLAUDE_PROJECTS_DIR="$PROJ" bash "$OUTCMD" disproved rework "шаг плана, не разворот" 2>&1
}

# H1. Красный прогон в окне.
OUT=$(scenario sH1 300 "  1 failed
  Error: element is not stable")
case "$OUT" in *"исход записан"*) ok ;; *) bad H1a "исход не записан — нога судила бы пустоту: ${OUT:0:200}" ;; esac
case "$OUT" in *"КРАСНЫЙ прогон"*) ok ;; *) bad H1b "подсказки нет при красном прогоне между заходами" ;; esac

# H2. Зелёный прогон — тишина.
OUT=$(scenario sH2 300 "  5 passed (3.2s)")
case "$OUT" in *"исход записан"*) ok ;; *) bad H2a "исход не записан — положительный контроль пуст: ${OUT:0:200}" ;; esac
case "$OUT" in *"КРАСНЫЙ прогон"*) bad H2b "подсказка при зелёном прогоне" ;; *) ok ;; esac

# H3. Красный прогон вне окна (20 минут до второй правки).
OUT=$(scenario sH3 1250 "  2 failed" 1300)
case "$OUT" in *"КРАСНЫЙ прогон"*) bad H3 "подсказка при правках дальше окна 10 минут друг от друга" ;; *) ok ;; esac

# H5. Правки с промежутком 3 часа, красный прогон за 5 минут до второй (по чужому файлу) — не разворот этого файла.
OUT=$(scenario sH5 300 "FAIL [T5]: чужой тест" 10800)
case "$OUT" in *"исход записан"*) ok ;; *) bad H5a "исход не записан — нога судила бы пустоту: ${OUT:0:200}" ;; esac
case "$OUT" in *"КРАСНЫЙ прогон"*) bad H5b "подсказка при правках с промежутком 3 часа" ;; *) ok ;; esac

# H4. Прогон спеки называет путь файла и правкой не считается: нога H1 видит его результат «между правками» — уже
#     проверено H1 (прогон в H1 — `npx playwright test <файл>`); здесь — помощник напрямую на той же расшифровке.
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$PROJ/p/sH1.jsonl" "$F" 600)
case "$R" in red*) ok ;; *) bad H4 "помощник не увидел красный прогон, когда команда прогона называет путь файла: «${R}»" ;; esac

# H6. Отказ стража между правками — вызов не исполнен, это не прогон.
OUT=$(RESF=res_err scenario sH6a 300 "PreToolUse:Bash hook error: ⛔ ОТКАЗ (вызов не выполнен). Правка не пройдёт, пока у повода нет названного исхода")
case "$OUT" in *"исход записан"*) ok ;; *) bad H6a0 "исход не записан — нога судила бы пустоту: ${OUT:0:200}" ;; esac
case "$OUT" in *"КРАСНЫЙ прогон"*) bad H6a "отказ стража принят за красный прогон" ;; *) ok ;; esac
# Без приставки харнесса и со словом провала внутри текста отказа (страж цитирует «FAIL») — всё равно не прогон.
OUT=$(RESF=res_err scenario sH6b 300 "⛔ ОТКАЗ (вызов не выполнен). Повод: FAIL [T5] в прошлом прогоне")
case "$OUT" in *"КРАСНЫЙ прогон"*) bad H6b "отказ стража со словом FAIL принят за красный прогон" ;; *) ok ;; esac
# Положительный контроль сужения: исполненная команда с кодом не 0 — прогон, подсказка есть.
OUT=$(RESF=res_err scenario sH6c 300 "Exit code 1
assertion mismatch")
case "$OUT" in *"КРАСНЫЙ прогон"*) ok ;; *) bad H6c "исполненная команда с кодом 1 не принята за красный прогон" ;; esac
# Отказ, а после него настоящий красный прогон между теми же правками — улика берётся у прогона.
TR6="$PROJ/p/sH6d.jsonl"; : > "$TR6"
use "$TR6" 400 e1 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"a", new_string:"b"}')"; res "$TR6" 399 e1 ok
use "$TR6" 300 d1 Bash '{"command":"npx playwright test"}'; res_err "$TR6" 299 d1 "PreToolUse:Bash hook error: ⛔ ОТКАЗ (вызов не выполнен)."
use "$TR6" 200 b1 Bash '{"command":"npx playwright test"}'; res "$TR6" 195 b1 "  1 failed"
use "$TR6" 30 e2 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"b", new_string:"c"}')"; res "$TR6" 29 e2 ok
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$TR6" "$F" 600)
case "$R" in "red	1 failed") ok ;; *) bad H6d "после отказа настоящий красный прогон не взят уликой: «${R}»" ;; esac
# Владельца имени отказа спросить нечем — помощник не выдаёт подсказку (не считает отказы прогонами молча), код 2.
R=$(DENY_MARK_RE='(' python3 -I "$REPO/hooks/lib/rework_red_run.py" "$TR6" "$F" 600 2>/dev/null); rc=$?
[ -z "$R" ] && [ "$rc" = 2 ] && ok || bad H6e "при недоступном владельце имени отказа: вывод «${R}», код $rc (ждали пусто и 2)"

# H7. Срез по времени (повтор на время исхода): та же расшифровка sH6d до второй правки — правка одна, подсказки нет;
#     срез после второй — подсказка есть. Без среза нога H6d уже видела красный.
CUT_BEFORE=$(iso 100); CUT_AFTER=$(iso 10)
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$TR6" "$F" 600 "$CUT_BEFORE")
[ -z "$R" ] && ok || bad H7a "срез до второй правки, а помощник видит две правки: «${R}»"
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$TR6" "$F" 600 "$CUT_AFTER")
case "$R" in red*) ok ;; *) bad H7b "срез после второй правки, а красного прогона нет: «${R}»" ;; esac

# H8. Отказанная ПРАВКА — не правка (D1303, 22 ноября 2026: в эталонной выборке у 6 случаев из 20 первая из двух «правок»
#     была отказана стражем и повторена дословно). Настоящая правка за 15 минут, отказанная за 400 с, красный прогон, правка
#     за 30 с: без отказанной правки две последние — дальше окна друг от друга, подсказки нет.
TR8="$PROJ/p/sH8.jsonl"; : > "$TR8"
use "$TR8" 900 e0 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"a", new_string:"b"}')"; res "$TR8" 899 e0 ok
use "$TR8" 400 e1 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"b", new_string:"c"}')"
res_err "$TR8" 399 e1 "PreToolUse:Edit hook error: ⛔ ОТКАЗ (вызов не выполнен). Правка не пройдёт, пока у повода нет названного исхода"
use "$TR8" 300 b1 Bash '{"command":"npx playwright test"}'; res "$TR8" 295 b1 "  1 failed"
use "$TR8" 30 e2 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"b", new_string:"c"}')"; res "$TR8" 29 e2 ok
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$TR8" "$F" 600)
[ -z "$R" ] && ok || bad H8a "отказанная правка сочтена правкой: «${R}»"
# Положительный контроль: та же расшифровка, но первая правка не отказана (обычный результат) — подсказка есть.
sed 's/"is_error":true//; s/PreToolUse:Edit hook error: ⛔ ОТКАЗ (вызов не выполнен). Правка не пройдёт, пока у повода нет названного исхода/ok/' "$TR8" > "$PROJ/p/sH8b.jsonl"
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$PROJ/p/sH8b.jsonl" "$F" 600)
case "$R" in red*) ok ;; *) bad H8b "положительный контроль H8: исполненная правка, красный прогон — подсказки нет: «${R}»" ;; esac

# H9. Прогон — по владельцу (детектор переработки), а не всякий результат с признаком провала (скептик opus D1303, M1).
mk9() { # <файл> <команда> <текст результата>: правка, вызов с «красным» выводом, правка — всё в окне
    : > "$1"
    use "$1" 400 e1 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"a", new_string:"b"}')"; res "$1" 399 e1 ok
    use "$1" 300 c1 Bash "$(jq -cn --arg c "$2" '{command:$c}')"; res "$1" 295 c1 "$3"
    use "$1" 30 e2 Edit "$(jq -cn --arg f "$F" '{file_path:$f, old_string:"b", new_string:"c"}')"; res "$1" 29 e2 ok
}
mk9 "$PROJ/p/sH9a.jsonl" "sed -n 1,40p BACKLOG.md" "- ☑ **D1** × снято"
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$PROJ/p/sH9a.jsonl" "$F" 600)
[ -z "$R" ] && ok || bad H9a "читающая команда (sed) со знаком провала в выводе принята за прогон: «${R}»"
mk9 "$PROJ/p/sH9b.jsonl" "cd /x && bash scripts/outcome.sh disproved rework шаг" "⚠️ Между двумя последними правками x.ts был КРАСНЫЙ прогон (TimeoutError)"
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$PROJ/p/sH9b.jsonl" "$F" 600)
[ -z "$R" ] && ok || bad H9b "вывод прибора исходов (его же подсказка) принят за прогон: «${R}»"
mk9 "$PROJ/p/sH9c.jsonl" "npx vitest run x.test.ts | tail -5" "  1 failed"
R=$(python3 -I "$REPO/hooks/lib/rework_red_run.py" "$PROJ/p/sH9c.jsonl" "$F" 600)
case "$R" in red*) ok ;; *) bad H9c "положительный контроль: прогон тестов с «1 failed» не принят за прогон: «${R}»" ;; esac
# Перечень «не прогон» не у кого спросить — тишина и код 2 (как у владельца имени отказа).
L9="$TMP/lonely/lib"; mkdir -p "$L9" "$TMP/lonely/home"
cp "$REPO/hooks/lib/rework_red_run.py" "$REPO/hooks/lib/deny_mark.py" "$REPO/hooks/lib/write_targets.py" "$L9/"
R=$(env -u CLAUDSOUL_REPO -u CLAUDSOUL_ROOT HOME="$TMP/lonely/home" DENY_MARK_RE='\A\s*(PreToolUse:[A-Za-z_]+ hook error:\s*)?(⛔|🛑|🚫)' \
    python3 -I "$L9/rework_red_run.py" "$PROJ/p/sH9c.jsonl" "$F" 600 2>/dev/null); rc=$?
[ -z "$R" ] && [ "$rc" = 2 ] && ok || bad H9d "перечень «не прогон» недоступен: вывод «${R}», код $rc (ждали пусто и 2)"

# H10. Пакетный режим (`--batch`, повтор по журналу исходов): по строке ответа на каждый запрос, в том же порядке.
printf '%s\t\n%s\t\n%s\t\n' "/нет/такого/файла.ts" "$F" "/нет/такого/файла.ts" \
    | python3 -I "$REPO/hooks/lib/rework_red_run.py" --batch "$TR6" 600 > "$TMP/batch.out"
[ "$(awk 'END { print NR }' "$TMP/batch.out")" = 3 ] && ok || bad H10a "пакетный ответ не по строке на запрос: $(awk 'END { print NR }' "$TMP/batch.out") строк из 3"
[ "$(sed -n 2p "$TMP/batch.out")" = "red	1 failed" ] && [ -z "$(sed -n 1p "$TMP/batch.out")$(sed -n 3p "$TMP/batch.out")" ] && ok \
    || bad H10b "пакетные ответы не на своих местах: «$(tr '\n' '|' < "$TMP/batch.out")»"

# H11. Проба D1303 различает: мир из одной сессии с красным прогоном между правками и 20 решениями по поводу.
pw_world() { # <каталог> <расшифровка-образец> <сколько disproved из 20>
    mkdir -p "$1/state" "$1/projects/p"
    printf '{"session_id":"pw1","project_name":"PX"}\n' > "$1/reg.jsonl"
    cp "$2" "$1/projects/p/pw1.jsonl"
    : > "$1/state/outcome-pw1.jsonl"
    local now n=0; now=$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))')
    while [ "$n" -lt 20 ]; do
        local o=fixed; [ "$n" -lt "$3" ] && o=disproved
        jq -cn --arg t "$now" --arg o "$o" --arg k "rework:$F:1" '{ts:$t, signal:"rework", outcome:$o, toks:[$k]}' >> "$1/state/outcome-pw1.jsonl"
        n=$((n + 1))
    done
}
probe() { STATE_DIR="$1/state" SESSION_REGISTRY="$1/reg.jsonl" CLAUDE_PROJECTS_DIR="$1/projects" D1303_PROJECT=PX \
    bash "$REPO/hooks/tests/fixtures/probe_D1303.sh" >/dev/null 2>&1; echo $?; }
pw_world "$TMP/pwA" "$PROJ/p/sH1.jsonl" 5;  [ "$(probe "$TMP/pwA")" = 0 ] && ok || bad H11a "5 «показалось» из 20 красных — проба не 0"
pw_world "$TMP/pwB" "$PROJ/p/sH1.jsonl" 15; [ "$(probe "$TMP/pwB")" = 1 ] && ok || bad H11b "15 «показалось» из 20 красных — проба не 1"
pw_world "$TMP/pwC" "$PROJ/p/sH2.jsonl" 5;  [ "$(probe "$TMP/pwC")" = 2 ] && ok || bad H11c "красного прогона нет — проба не «не измерено» (2)"

echo "подсказка разворота: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
