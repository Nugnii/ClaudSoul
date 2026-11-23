#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh
# test_declared_problem_channel.sh — сверщик говорит в канал, который читает ход.
#
# Результат: сообщение сверщика попадает в посессионный файл `startup-signals-<sid>.txt`;
#            дроссель держит повтор того же СОСТАВА и пропускает изменившийся
# Проверка результата: bash hooks/tests/test_declared_problem_channel.sh даёт 0
#
# Повод. Внутреннее измерение (`hooks/error-tracker.sh:44-47`): «15 срабатываний прежней
# версии ушли в один только `systemMessage`, и ни на одно из них ход не отреагировал —
# записи `hook_system_message` в поток сообщений не попадают». Сверщик исхода и
# completion-gate печатали ровно туда: срабатывали, но не действовали, а в VSCode этот
# канал не рендерится вовсе. Прямой `additionalContext` на Stop незаконен — он
# перезапускает ход, — поэтому канал отложенный: файл своей сессии, который показывает
# `pending-alerts-surface.sh` на следующем UserPromptSubmit (с 24 октября 2026, D1044; прежде
# общая очередь `pending-alerts.txt`, и напоминание доставалось чужой сессии).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/declared-problem-recorded.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1));
       echo "FAIL: $1"; echo "   ожидалось: [$2]  получено: [$3]"; fi; }

# Помощника берём ИЗ ХОКА, а не переписываем: копия правила у потребителя — род K.
HELPER="$TMP/helper.sh"
cp "$ROOT/hooks/throttle-lib.sh" "$TMP/"   # dpr_surface ищет дроссель рядом с собой, затем в ~/.claude — на CI пусто
awk '/^dpr_surface\(\) \{/,/^\}/' "$HOOK" > "$HELPER"
[ -s "$HELPER" ] || { echo "FAIL: dpr_surface не извлечён — признак устарел"; exit 1; }

STATE="$TMP/state"; mkdir -p "$STATE"
SID=t1
# shellcheck source=/dev/null
. "$HELPER"

queued() { wc -l < "$STATE/stop-signals-${SID}.txt" 2>/dev/null | tr -d ' '; }

dpr_surface "turn:discovery:1" "сообщение А" >/dev/null 2>&1
ck "сообщение попало в очередь" "1" "$(queued)"

dpr_surface "turn:discovery:1" "сообщение А" >/dev/null 2>&1
ck "тот же состав — дроссель держит" "1" "$(queued)"

dpr_surface "turn:discovery,rework:2" "сообщение Б" >/dev/null 2>&1
ck "изменившийся состав — звучит заново" "2" "$(queued)"

ck "текст сообщения дошёл целиком" "сообщение Б" "$(tail -1 "$STATE/stop-signals-${SID}.txt")"

# ── Сквозь хуки (D1047): напоминание переживает старт той же сессии и доходит до следующей сессии проекта ──
# Песочница: свои STATE_DIR, HOME и SR_SESSIONS_DIR — раннер набора задаёт тесту свой каталог реестра
# (run_all.sh, D271), и метка живости под одним HOME без него не видна.
stop() {   # stop <каталог> <sid> <cwd> [текст] — Stop с итогом, где одна находка без пометки
    local t="$1/t-$2.jsonl"
    jq -nc '{type:"user",message:{role:"user",content:"привет"},timestamp:"2026-10-24T08:00:00Z"}' > "$t"
    jq -nc --arg m "$(printf '**Что найдено**\n- %s\n' "${4:-сирота канала без пометки}")" \
        '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$m}]},timestamp:"2026-10-24T08:01:00Z"}' >> "$t"
    jq -nc --arg t "$t" --arg s "$2" --arg c "$3" '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop"}' \
        | HOME="$1/home" SR_SESSIONS_DIR="$1/home/.claude/sessions" STATE_DIR="$1" bash "$HOOK" >/dev/null 2>&1
}
see() {    # see <каталог> <sid> <cwd> — что покажет следующая реплика этой сессии
    jq -nc --arg s "$2" --arg c "$3" '{session_id:$s,cwd:$c,hook_event_name:"UserPromptSubmit",prompt:"x"}' \
        | HOME="$1/home" SR_SESSIONS_DIR="$1/home/.claude/sessions" STATE_DIR="$1" bash "$ROOT/hooks/pending-alerts-surface.sh" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
sbox() { local b; b=$(mktemp -d "$TMP/sb.XXXX"); mkdir -p "$b/home/.claude/sessions/live" "$b/proj" "$b/other"; printf '%s' "$b"; }
has() { case "$2" in *"$3"*) PASS=$((PASS+1)) ;; *) FAIL=$((FAIL+1)); echo "FAIL: $1"; echo "   нет «$3» в: ${2:0:200}" ;; esac; }
hasnt() { case "$2" in *"$3"*) FAIL=$((FAIL+1)); echo "FAIL: $1"; echo "   лишнее «$3» в: ${2:0:200}" ;; *) PASS=$((PASS+1)) ;; esac; }

# E1 — compact той же сессии (SessionStart с тем же sid) напоминание не стирает (скептик D1044, С1).
B=$(sbox); stop "$B" s1 "$B/proj"
jq -nc --arg c "$B/proj" '{session_id:"s1",source:"compact",cwd:$c,hook_event_name:"SessionStart"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-start.sh" >/dev/null 2>&1
O=$(see "$B" s1 "$B/proj")
has "E1: напоминание пережило compact той же сессии" "$O" "сирота канала без пометки"
has "E1б: напоминание отдельным блоком со своей шапкой, а не строкой сигналов старта" "$O" "$(printf '\n\n📌 В итоге прошлого хода')"

# E2 — метки живости нет (снесла уборка реестра), но конца сессии не было: молчащая открытая вкладка своё
# напоминание держит (D1049). Через сутки молчания без SessionEnd (сбой) — отдаёт с честной подписью.
B=$(sbox); stop "$B" s1 "$B/proj"
hasnt "E2: без конца сессии напоминание другой не отдано" "$(see "$B" s2 "$B/proj")" "сирота канала"
[ -s "$B/stop-signals-s1.txt" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: E2а: файл молчащей сессии пропал"; }
touch -t 202001010000 "$B/stop-signals-s1.txt"
O=$(see "$B" s2 "$B/proj")
has "E2б: через сутки молчания напоминание дошло" "$O" "сирота канала без пометки"
has "E2в: подпись не называет сессию закрытой" "$O" "молчащей больше суток"
[ ! -e "$B/stop-signals-s1.txt" ] && [ ! -e "$B/stop-signals-s1.project" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL: E2г: файлы отданной сессии не забраны"; }

# E3 — параллельная ЖИВАЯ сессия (свежая метка live/) чужое напоминание не получает, своя — получает.
B=$(sbox); stop "$B" s1 "$B/proj"; : > "$B/home/.claude/sessions/live/s1.json"
hasnt "E3: живой параллельной сессии чужое напоминание не показано" "$(see "$B" s2 "$B/proj")" "сирота канала"
has "E3б: своя сессия получила своё" "$(see "$B" s1 "$B/proj")" "сирота канала без пометки"

# E4 — сессия ДРУГОГО проекта напоминание закрытой не забирает.
B=$(sbox); stop "$B" s1 "$B/proj"
hasnt "E4: чужой проект не забрал напоминание" "$(see "$B" s2 "$B/other")" "сирота канала"
[ -s "$B/stop-signals-s1.txt" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: E4б: файл закрытой сессии пропал у чужого проекта"; }

# E5 — конец сессии (SessionEnd) снимает метку живости, и следующая сессия проекта забирает сразу.
B=$(sbox); stop "$B" s1 "$B/proj"; : > "$B/home/.claude/sessions/live/s1.json"
jq -nc --arg c "$B/proj" '{session_id:"s1",reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1
O=$(see "$B" s2 "$B/proj")
has "E5: после SessionEnd напоминание дошло до следующей сессии" "$O" "сирота канала без пометки"
has "E5б: после SessionEnd сессия названа закрытой" "$O" "Из закрытой сессии s1"

# E6 — метка живости УСТАРЕЛА (вкладка молчит дольше SR_LIVE_TTL_MIN), конца не было: не отдаётся (D1049).
B=$(sbox); stop "$B" s1 "$B/proj"; : > "$B/home/.claude/sessions/live/s1.json"; touch -t 202001010000 "$B/home/.claude/sessions/live/s1.json"
hasnt "E6: молчащей вкладке с устаревшей меткой напоминание не отдано" "$(see "$B" s2 "$B/proj")" "сирота канала"

# E9 — сессия вернулась через resume с тем же sid после SessionEnd: её новая находка параллельной не отдаётся, а своя
# реплика её получает (D1055). E10 — пустой `.project` ни с чем не совпадает.
B=$(sbox); stop "$B" s1 "$B/proj"
jq -nc --arg c "$B/proj" '{session_id:"s1",reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1
: > "$B/home/.claude/sessions/live/s1.json"; see "$B" s1 "$B/proj" >/dev/null; stop "$B" s1 "$B/proj" "вторая сирота после возврата"
hasnt "E9: находку вернувшейся сессии параллельная не получила" "$(see "$B" s2 "$B/proj")" "вторая сирота"
has "E9б: вернувшаяся сессия получила свою находку" "$(see "$B" s1 "$B/proj")" "вторая сирота после возврата"
B=$(sbox); echo "чужая пустая сирота" > "$B/stop-signals-s3.txt"; : > "$B/stop-signals-s3.project"; : > "$B/stop-signals-s3.ended"
hasnt "E10: пустой корень проекта ни с чем не совпал" "$(cd "$B/proj" && see "$B" s2 "$B/proj")" "чужая пустая"

# E11 — сессия вернулась через resume (SessionStart с тем же sid) и ещё не ответила: её находку параллельная не получает,
# а своя реплика — получает (D1060). E12 — метку живости освежили ПОСЛЕ конца сессии: напоминание закрытой доходит
# сразу, а не через срок живости. E13 — блок реестра в SessionEnd упал: пометка конца всё равно легла.
B=$(sbox); stop "$B" s1 "$B/proj" "сирота вернувшейся"
jq -nc --arg c "$B/proj" '{session_id:"s1",reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1
jq -nc --arg c "$B/proj" '{session_id:"s1",source:"resume",cwd:$c,hook_event_name:"SessionStart"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-start.sh" >/dev/null 2>&1
hasnt "E11: находку вернувшейся до её реплики параллельная не получила" "$(see "$B" s2 "$B/proj")" "сирота вернувшейся"
has "E11б: вернувшаяся получила своё" "$(see "$B" s1 "$B/proj")" "сирота вернувшейся"
B=$(sbox); stop "$B" s1 "$B/proj" "сирота закрытой"
jq -nc --arg c "$B/proj" '{session_id:"s1",reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1
: > "$B/home/.claude/sessions/live/s1.json"
has "E12: метка живости после конца не задержала напоминание закрытой" "$(see "$B" s2 "$B/proj")" "сирота закрытой"
B=$(sbox); stop "$B" s1 "$B/proj"; : > "$B/notadir"
jq -nc --arg c "$B/proj" '{session_id:"s1",reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/notadir/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1
[ -e "$B/stop-signals-s1.ended" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: E13: при сбое реестра пометка конца не легла"; }

# E13б — старт вернувшейся сессии при сломанном реестре всё равно снимает её пометку конца (D1063): снятие стоит до
# подключения библиотеки реестра. E14 — живая сессия без пометки, чей файл напоминаний старше суток, своё не отдаёт:
# живость спрашивается (мутант «без sr_record_alive»). E15 — resume без реплики, затем чистый конец: напоминание доходит
# (старт не трогает `.project`). E16 — старт ДРУГОЙ сессии чужую пометку конца не снимает.
se() { jq -nc --arg c "$1/proj" --arg s "$2" '{session_id:$s,reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$1/home" SR_SESSIONS_DIR="${3:-$1/home/.claude/sessions}" STATE_DIR="$1" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1; }
ss() { jq -nc --arg c "$1/proj" --arg s "$2" '{session_id:$s,source:"resume",cwd:$c,hook_event_name:"SessionStart"}' \
    | HOME="$1/home" SR_SESSIONS_DIR="${3:-$1/home/.claude/sessions}" STATE_DIR="$1" bash "$ROOT/hooks/session-start.sh" >/dev/null 2>&1; }
B=$(sbox); stop "$B" s1 "$B/proj" "сирота сбойного старта"; se "$B" s1; : > "$B/notadir"; ss "$B" s1 "$B/notadir/sessions"
hasnt "E13б: старт при сломанном реестре снял пометку конца" "$(see "$B" s2 "$B/proj")" "сирота сбойного старта"
B=$(sbox); stop "$B" s1 "$B/proj" "сирота живой старой"; : > "$B/home/.claude/sessions/live/s1.json"
touch -t 202001010000 "$B/stop-signals-s1.txt"
hasnt "E14: живая сессия без пометки своё не отдала и через сутки" "$(see "$B" s2 "$B/proj")" "сирота живой старой"
B=$(sbox); stop "$B" s1 "$B/proj" "сирота второго конца"; se "$B" s1; ss "$B" s1; se "$B" s1
has "E15: resume без реплики и чистый конец — напоминание дошло" "$(see "$B" s2 "$B/proj")" "сирота второго конца"
B=$(sbox); stop "$B" s1 "$B/proj" "сирота чужого старта"; se "$B" s1; ss "$B" s2
has "E16: старт другой сессии чужую пометку не снял" "$(see "$B" s2 "$B/proj")" "сирота чужого старта"

# E7 — без HOME канал не теряет уже забранное: сигнал старта доходит сейчас либо остаётся до следующей реплики (D1052).
B=$(sbox); echo "сигнал старта без дома" > "$B/startup-signals-s1.txt"
O=$(jq -nc '{session_id:"s1",cwd:"/",hook_event_name:"UserPromptSubmit",prompt:"x"}' \
    | env -u HOME STATE_DIR="$B" bash "$ROOT/hooks/pending-alerts-surface.sh" 2>/dev/null)
case "$O" in *"сигнал старта без дома"*) PASS=$((PASS+1)) ;;
    *) [ -s "$B/startup-signals-s1.txt" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: E7: без HOME сигнал старта пропал"; } ;; esac

# E8 — корень проекта записан через ссылку, реплика пришла по физическому пути: передача идёт (D1052).
B=$(sbox); ln -s "$B/proj" "$B/link"; stop "$B" s1 "$B/link"
jq -nc --arg c "$B/link" '{session_id:"s1",reason:"other",cwd:$c,hook_event_name:"SessionEnd"}' \
    | HOME="$B/home" SR_SESSIONS_DIR="$B/home/.claude/sessions" STATE_DIR="$B" bash "$ROOT/hooks/session-end.sh" >/dev/null 2>&1
has "E8: корень через ссылку совпал с физическим" "$(see "$B" s2 "$B/proj")" "сирота канала без пометки"

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
