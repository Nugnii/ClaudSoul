#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh install.sh
# test_rework_detector_subagent_edits.sh — правка в общем мире принадлежит исполнителю, только если файл менялся В ОКНЕ
# его команды (D1299, R6).
#
# Повод: ProjectA, сессия 194e3c16 (15 ноября 2026). Агент правил файлы оболочкой между вызовами оркестратора, а разница мира
# оркестратора (его снимок против нынешнего) писала эти правки ему: 4 из 43 срабатываний. Первая починка (e56276ea —
# «чью строку видели первой») отозвана скептиком: повод уходил наблюдателю, автор молчал (H1). Окно команды —
# `duration_ms` события (длительность исполнения инструмента); время изменения файла — вне окна, значит не эта команда.
#
# S1 — агент правит f.sh до команды оркестратора (время файла вне окна): правка в цепочку оркестратора не ложится;
# S2 — положительный контроль: оркестратор правит f.sh сам (время в окне) — цепочка растёт, третий заход горит;
# H1 — наблюдатель с коротким окном зовёт Bash после правки автора: автор правку получает, наблюдатель — нет;
# S4 — параллельная сессия правит p.sh вне окна сессии-соседа: соседу не пишется;
# F1 — событие провала (`PostToolUseFailure`) с окном, накрывшим правку: правка автора записана — упавшая команда
#      правок не теряет; F2 — хук зарегистрирован на `PostToolUseFailure` для Bash (`install.sh`);
# D  — нет `duration_ms` (поле необязательное): прежнее поведение — всё изменённое с прошлого вызова (предел назван).
#      Условие снятия: справка Claude Code объявит `duration_ms` обязательным полем PostToolUse и PostToolUseFailure.
# v3 — перечень клиента `tool_response.bashEditDiff` (файлы, изменённые ЭТОЙ командой; скептик opus по 99d31c91, M1–M4):
# B1 — канал жив, агент правит f.sh в запасе окна до старта команды оркестратора (клиент снимает дерево до и после
#      команды, и такой записи в своём ответе не называет), у команды поля нет: правка оркестратору не пишется (M3);
# B2 — своя правка с сохранённым временем файла (`cp -p`), в перечне клиента: записана, третий заход горит (M1);
# B3 — канал жив, но режим разрешений не auto: «нет поля» не значит «не изменила» — своя правка в окне записана;
# B4 — поле в сессии не приходило ни разу: прежний путь — своя правка в окне записана;
# F3 — упавшая команда без правок не прогон цепочки и не шаг серии холостых прогонов (M4);
# L5 — имя события ответа берётся из входа: повод на событии провала несёт `PostToolUseFailure` (L5).
# v4 (скептик opus по 1a0945f0):
# U1 — ответ `unavailable` без путей снимает отметку: дальше «нет поля» — прежний путь, своя правка в окне записана (M1);
# SH — `shared` без путей — ответ «не изменила»: чужая запись в окне оркестратору не пишется (M2);
# RS — откат своей правки в составной команде (клиент его перечисляет): правкой не считается (L3);
# NF — новый неотслеживаемый файл прогона в ответе клиента: правкой не считается (L4);
# FM — канал жив, команда упала: своя правка в окне записывается запасным путём (мутант без условия «успех»);
# CF — путь только в `changedFiles` (у клиента `files[]` не длиннее 5): правка записана.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"; HOOK="$HOOKS_DIR/rework-detector.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd) || exit 1   # логический путь, как вершина у хука (иначе `//` делал цель «черновиком»)
ST="$T/state"; mkdir -p "$ST"; W="$T/world"; mkdir -p "$W"
( cd "$W" && git init -q && printf 'a\n' > f.sh && printf 'a\n' > p.sh && printf 'a\n' > q.sh && printf 'a\n' > r.sh \
    && git add . \
    && git -c user.name=t -c user.email=t@t commit -qm 0 ) || { echo "FAIL: мир не собрался"; exit 1; }
hook() { # sid agent event tool json-input [duration_ms] [json-дополнение входа]
    jq -cn --arg s "$1" --arg a "$2" --arg e "$3" --arg t "$4" --arg d "$W" --argjson i "$5" --arg ms "${6:-}" \
        --argjson x "${7:-null}" \
        '{session_id:$s, hook_event_name:$e, tool_name:$t, cwd:$d, tool_input:$i} + ($x // {})
         + (if $ms == "" then {} else {duration_ms:($ms|tonumber)} end)
         + (if $a == "" then {} else {agent_id:$a, agent_type:"lean"} end)' \
        | env STATE_DIR="$ST" bash "$HOOK" 2>/dev/null
}
run_as() { hook "$1" "$2" "${4:-PostToolUse}" Bash "$(jq -cn '{command:"bash test.sh"}')" "${3:-}"; }
edit_as() { hook "$1" "$2" PostToolUse Edit "$(jq -cn --arg f "$W/$3" '{file_path:$f}')"; }
write_at() { # файл секунд-назад — дописать строку и выставить время изменения
    printf 'x%s\n' "$RANDOM" >> "$W/$1"
    python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$W/$1" "$2"
}
edits() { grep -c "\"kind\":\"edit\".*$2" "$ST/rework-$1.jsonl" 2>/dev/null; }

# S1. Оркестратор начал цепочку; агент трижды правит f.sh за 60 с до команды оркестратора (окно команды 2 с).
edit_as s1 "" p.sh >/dev/null; run_as s1 "" 2000 >/dev/null
OUT=""
for i in 1 2 3; do
    write_at f.sh 60; run_as s1 agentA 500 >/dev/null
    OUT="$OUT$(run_as s1 "" 2000)$(run_as s1 "" 2000)"
done
[ "$(edits s1 'f\.sh')" = 0 ] && ok || bad S1a "правка агента вне окна записана оркестратору: $(edits s1 'f\.sh')"
case "$OUT" in *f.sh*) bad S1b "оркестратору выдан повод по чужой правке" ;; *) ok ;; esac

# S2. Положительный контроль: правит сам оркестратор, время файла в окне его команды.
edit_as s2 "" p.sh >/dev/null; run_as s2 "" 2000 >/dev/null
OUT=""
for i in 1 2 3; do
    write_at f.sh 0; OUT="$OUT$(run_as s2 "" 2000)$(run_as s2 "" 2000)"
done
[ "$(edits s2 'f\.sh')" -ge 3 ] 2>/dev/null && ok || bad S2a "своя правка в окне не записана трижды: $(edits s2 'f\.sh')"
case "$OUT" in *f.sh*) ok ;; *) bad S2b "на трёх своих заходах повода нет — рамка не умеет ответить «да»" ;; esac

# H1. Автор правит q.sh за 5 с до конца своей 10-секундной команды; наблюдатель с журналом зовёт короткий Bash раньше
#     события автора. Наблюдатель правку не получает, автор — получает.
edit_as h1 obs p.sh >/dev/null; run_as h1 obs 300 >/dev/null
edit_as h1 "" p.sh >/dev/null; run_as h1 "" 2000 >/dev/null
write_at q.sh 5
run_as h1 obs 300 >/dev/null
run_as h1 "" 10000 >/dev/null
[ "$(grep -c '"kind":"edit".*q\.sh' "$ST/rework-h1.agent-obs.jsonl" 2>/dev/null)" = 0 ] && ok \
    || bad H1a "наблюдатель с окном 0,3 с получил правку, сделанную за 5 с до его вызова"
[ "$(edits h1 'q\.sh')" -ge 1 ] 2>/dev/null && ok || bad H1b "автор не получил свою правку в окне 10 с"

# S4. Параллельная сессия s4b правит p.sh за 30 с до команды сессии s4a.
edit_as s4a "" q.sh >/dev/null; run_as s4a "" 2000 >/dev/null
for i in 1 2; do write_at p.sh 30; run_as s4a "" 2000 >/dev/null; run_as s4a "" 2000 >/dev/null; done
[ "$(edits s4a 'p\.sh')" = 0 ] && ok || bad S4a "правка параллельной сессии вне окна записана соседу: $(edits s4a 'p\.sh')"

# F1. Упавшая команда: событие провала с окном, накрывшим правку, — правка записана.
edit_as f1 "" p.sh >/dev/null; run_as f1 "" 2000 >/dev/null
write_at f.sh 1; run_as f1 "" 3000 PostToolUseFailure >/dev/null
[ "$(edits f1 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad F1 "правка в упавшей команде не записана по событию провала"
# F2. Регистрация на событии провала для Bash.
python3 - "$HOOKS_DIR/../install.sh" <<'PY' && ok || bad F2 "rework-detector.sh не зарегистрирован на PostToolUseFailure для Bash"
import json, re, sys
s = open(sys.argv[1], encoding="utf-8").read(); i = s.index("HOOKS_CONFIG='") + len("HOOKS_CONFIG='"); j = s.index("'", i)
gs = json.loads(s[i:j])["hooks"].get("PostToolUseFailure", [])
sys.exit(0 if any(re.search(r"(^|\|)Bash(\||$)", g.get("matcher", "")) and any(h["command"].endswith("/rework-detector.sh")
         for h in g["hooks"]) for g in gs) else 1)
PY

# D. Без `duration_ms` — прежнее поведение: правка вне «окна» записывается (предел: поле необязательное).
edit_as d1 "" p.sh >/dev/null; run_as d1 "" >/dev/null
write_at f.sh 60; run_as d1 "" >/dev/null
[ "$(edits d1 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad D "без длительности разница мира перестала записываться вовсе"

# v3. Вход с ответом клиента: режим разрешений и перечень изменённого командой (пусто — поля нет вовсе).
runb() { # sid agent duration_ms режим [файлы мира через пробел]
    _x=$(jq -cn --arg m "$4" --arg w "$W" --arg f "${5:-}" '{permission_mode:$m, tool_response:({stdout:"", stderr:""}
        + (if $f == "" then {} else {bashEditDiff:{files:[$f | split(" ")[] | {filePath:($w + "/" + .)}], moreFiles:0}} end))}')
    hook "$1" "$2" PostToolUse Bash "$(jq -cn '{command:"bash test.sh"}')" "$3" "$_x"
}

# B1. Канал жив (своя правка p.sh пришла перечнем); агент трижды правит f.sh в окне команды оркестратора без поля.
edit_as b1 "" p.sh >/dev/null; run_as b1 "" 2000 >/dev/null
write_at p.sh 0; runb b1 "" 2000 auto p.sh >/dev/null
OUT=""
for i in 1 2 3; do write_at f.sh 0; OUT="$OUT$(runb b1 "" 2000 auto)$(runb b1 "" 2000 auto)"; done
[ "$(edits b1 'f\.sh')" = 0 ] && ok || bad B1a "правка агента в окне короткой команды записана оркестратору: $(edits b1 'f\.sh')"
case "$OUT" in *f.sh*) bad B1b "оркестратору выдан повод по чужой правке при живом канале" ;; *) ok ;; esac

# B2. Своя правка с временем файла минуту назад (копия с сохранением времени) — в перечне клиента.
edit_as b2 "" p.sh >/dev/null; run_as b2 "" 2000 >/dev/null
OUT=""
for i in 1 2 3; do write_at f.sh 60; OUT="$OUT$(runb b2 "" 2000 auto f.sh)$(runb b2 "" 2000 auto)"; done
[ "$(edits b2 'f\.sh')" -ge 3 ] 2>/dev/null && ok || bad B2a "своя правка из перечня клиента не записана трижды: $(edits b2 'f\.sh')"
case "$OUT" in *f.sh*) ok ;; *) bad B2b "на трёх своих заходах из перечня клиента повода нет" ;; esac

# B3. Канал жив, режим default: поля нет, потому что канал выключен, — своя правка в окне записывается.
edit_as b3 "" p.sh >/dev/null; run_as b3 "" 2000 >/dev/null
write_at q.sh 0; runb b3 "" 2000 auto q.sh >/dev/null
write_at f.sh 0; runb b3 "" 2000 default >/dev/null
[ "$(edits b3 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad B3 "в режиме default «нет поля» прочитано как «не изменила»"

# B4. Поле в сессии не приходило: прежний путь, своя правка в окне записывается.
edit_as b4 "" p.sh >/dev/null; runb b4 "" 2000 auto >/dev/null
write_at f.sh 0; runb b4 "" 2000 auto >/dev/null
[ "$(edits b4 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad B4 "без отметки канала «нет поля» прочитано как «не изменила»"

# F3. Упавшие прогоны без правок: журнал цепочки и серия холостых прогонов не растут.
edit_as f3 "" p.sh >/dev/null; run_as f3 "" 2000 >/dev/null
_n0=$(grep -c '"kind":"run"' "$ST/rework-f3.jsonl" 2>/dev/null)
for i in 1 2; do hook f3 "" PostToolUseFailure Bash "$(jq -cn '{command:"bash tests/t.sh"}')" 500 >/dev/null; done
[ "$(grep -c '"kind":"run"' "$ST/rework-f3.jsonl" 2>/dev/null)" = "$_n0" ] && ok \
    || bad F3a "упавшая команда без правок записана прогоном цепочки"
[ -s "$ST/rework-rerun-f3.txt" ] && bad F3b "упавший прогон сдвинул серию холостых прогонов: $(cat "$ST/rework-rerun-f3.txt")" || ok

# L5. Повод на событии провала: имя события ответа — из входа.
edit_as l5 "" p.sh >/dev/null; run_as l5 "" 2000 >/dev/null
OUT=""
for i in 1 2 3; do write_at f.sh 0; OUT="$OUT$(run_as l5 "" 2000 PostToolUseFailure)"; run_as l5 "" 2000 >/dev/null; done
_ev=$(printf '%s\n' "$OUT" | jq -r 'select(.hookSpecificOutput) | .hookSpecificOutput.hookEventName' 2>/dev/null | sort -u)
[ "$_ev" = PostToolUseFailure ] && ok || bad L5 "имя события повода на провале: «${_ev:-повода нет}»"

# v4. Вход с произвольным ответом клиента: sid событие duration_ms json-bashEditDiff|"" [режим]
runr() {
    _x=$(jq -cn --arg m "${5:-auto}" --arg b "$4" '{permission_mode:$m}
        + (if $b == "" then {} else {tool_response:{stdout:"", stderr:"", bashEditDiff:($b|fromjson)}} end)')
    hook "$1" "" "$2" Bash "$(jq -cn '{command:"bash test.sh"}')" "$3" "$_x"
}
bed() { jq -cn --arg w "$W" --arg f "$1" '{files:[$f | split(" ")[] | {filePath:($w + "/" + .)}], moreFiles:0}'; }

# U1. Канал жив, затем ответ `unavailable` без путей; своя правка f.sh в окне без поля — записана.
edit_as u1 "" p.sh >/dev/null; run_as u1 "" 2000 >/dev/null
write_at p.sh 0; runr u1 PostToolUse 2000 "$(bed p.sh)" >/dev/null
runr u1 PostToolUse 2000 '{"files":[],"moreFiles":0,"unavailable":true}' >/dev/null
write_at f.sh 0; runr u1 PostToolUse 2000 "" >/dev/null
[ "$(edits u1 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad U1 "после «клиент сдался» своя правка без поля потеряна"

# SH. `shared` без путей при чужой записи в окне: ответ «не изменила», оркестратору не пишется.
edit_as sh "" p.sh >/dev/null; run_as sh "" 2000 >/dev/null
for i in 1 2; do
    write_at f.sh 0; runr sh PostToolUse 2000 '{"files":[],"moreFiles":0,"shared":true}' >/dev/null
done
[ "$(edits sh 'f\.sh')" = 0 ] && ok || bad SH "«shared» без путей прочитан не ответом — чужая запись записана: $(edits sh 'f\.sh')"

# RS. Своя правка r.sh, прогон, затем откат r.sh к коммиту в составной команде (клиент перечисляет r.sh).
edit_as rs "" p.sh >/dev/null; run_as rs "" 2000 >/dev/null
write_at r.sh 0; runr rs PostToolUse 2000 "$(bed r.sh)" >/dev/null
runr rs PostToolUse 2000 "" >/dev/null
( cd "$W" && git checkout -q -- r.sh ); runr rs PostToolUse 2000 "$(bed r.sh)" >/dev/null
[ "$(edits rs 'r\.sh')" = 1 ] && ok || bad RS "откат к известному содержимому записан правкой: $(edits rs 'r\.sh') вместо 1"

# NF. Прогон создаёт новый неотслеживаемый файл, клиент его перечисляет.
edit_as nf "" p.sh >/dev/null; run_as nf "" 2000 >/dev/null
for i in 1 2; do printf '{}\n' > "$W/report-$i.json"; runr nf PostToolUse 2000 "$(bed report-$i.json)" >/dev/null; done
[ "$(edits nf 'report-')" = 0 ] && ok || bad NF "новый неотслеживаемый файл прогона записан правкой: $(edits nf 'report-')"

# FM. Канал жив, команда упала (ответа нет по устройству клиента): своя правка в окне записывается.
edit_as fm "" p.sh >/dev/null; run_as fm "" 2000 >/dev/null
write_at p.sh 0; runr fm PostToolUse 2000 "$(bed p.sh)" >/dev/null
write_at f.sh 0; runr fm PostToolUseFailure 2000 "" >/dev/null
[ "$(edits fm 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad FM "своя правка упавшей команды при живом канале потеряна"

# CF. Путь только в `changedFiles`, время файла вне окна (копия с сохранением времени).
edit_as cf "" p.sh >/dev/null; run_as cf "" 2000 >/dev/null
write_at f.sh 60
runr cf PostToolUse 2000 "$(jq -cn --arg f "$W/f.sh" '{files:[], moreFiles:1, changedFiles:[$f]}')" >/dev/null
[ "$(edits cf 'f\.sh')" -ge 1 ] 2>/dev/null && ok || bad CF "путь только в changedFiles не записан"

echo "rework-detector (окно команды): прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
