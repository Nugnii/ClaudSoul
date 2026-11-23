#!/usr/bin/env bash
# СУДИТ: hooks/code-review-reminder.sh hooks/lib/adversary-run-lib.sh hooks/portable-lib.sh
# test_adversary_run_elsewhere.sh — прогон противника в ДРУГОЙ сессии того же проекта виден
#                                   стражу и ретро-прогону в окне от времени HEAD (D373).
# Результат: adversary_run_elsewhere считает вызовы в соседних расшифровках каталога в окне
#            [с; по], свою расшифровку исключает, нечитаемых соседей называет кодом 2; страж
#            молчит на крупном диффе при чужом прогоне после HEAD и напоминает при чужом
#            прогоне до HEAD; мутант без счёта в окне даёт ноль там, где оригинал даёт один.
# Проверка результата: bash hooks/tests/test_adversary_run_elsewhere.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$(cd "$DIR/.." && pwd)"
LIB="$HOOKS/lib/adversary-run-lib.sh"
HOOK="$HOOKS/code-review-reminder.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
command -v adversary_run_elsewhere >/dev/null 2>&1 || { echo "FAIL: adversary_run_elsewhere не объявлена"; exit 1; }
TMP=$(mktemp -d)   # временное уберёт система

run_line() {  # run_line <ISO-время> — строка расшифровки с вызовом Skill adversary
    jq -cn --arg t "$1" '{timestamp:$t, message:{content:[{type:"tool_use",name:"Skill",input:{skill:"adversary"}}]}}'
}
talk_line() { jq -cn --arg t "$1" '{timestamp:$t, message:{content:[{type:"tool_use",name:"Bash",input:{command:"ls"}}]}}'; }

# Времена фикстуры — во ВЧЕРА, а не «сегодня в 10:00»: свежие файлы имеют mtime «сейчас»,
# и окно, начинающееся позже «сейчас», отсеяло бы их честно, а верхняя граница по умолчанию
# («сейчас») не пустила бы вызов из будущего. Первая сборка 13 сентября 2026 в 06:45 CEST
# ставила 08:00–10:00 UTC того же дня и получила нули (форма входа не из мира).
D=2026-09-12
P="$TMP/proj"; mkdir -p "$P"
talk_line "${D}T09:30:00Z" > "$P/own.jsonl"
run_line  "${D}T10:00:00Z" > "$P/a.jsonl"      # сосед с прогоном в 10:00
run_line  "${D}T08:00:00Z" > "$P/b.jsonl"      # сосед с прогоном в 08:00
T0900=$(iso_epoch "${D}T09:00:00Z"); T1100=$(iso_epoch "${D}T11:00:00Z"); T0930=$(iso_epoch "${D}T09:30:00Z")

# T1: окно с 09:00 — виден только a (10:00)
N=$(adversary_run_elsewhere "$P/own.jsonl" "$T0900"); RC=$?
[ "$RC" = 0 ] && [ "$N" = 1 ] && ok || bad "T1" "окно с 09:00: ждали 1 (rc 0), получили $N (rc $RC)"
# T2: окно с 11:00 — никого
N=$(adversary_run_elsewhere "$P/own.jsonl" "$T1100")
[ "$N" = 0 ] && ok || bad "T2" "окно с 11:00: ждали 0, получили $N"
# T3: верхняя граница 09:30 — a (10:00) за окном, b (08:00) до окна
N=$(adversary_run_elsewhere "$P/own.jsonl" "$T0900" "$T0930")
[ "$N" = 0 ] && ok || bad "T3" "окно 09:00–09:30: ждали 0, получили $N"
# T4: окно с нуля — оба соседа, СВОЯ расшифровка с прогоном не считается
run_line "${D}T12:00:00Z" > "$P/self-run.jsonl"
N=$(adversary_run_elsewhere "$P/self-run.jsonl" 0)
[ "$N" = 2 ] && ok || bad "T4" "с нуля без своей: ждали 2, получили $N"
# T5: adversary_run_count не изменился разбиением: своя с прогоном → 1, без → 0
[ "$(adversary_run_count "$P/self-run.jsonl")" = 1 ] && [ "$(adversary_run_count "$P/own.jsonl")" = 0 ] && ok || bad "T5" "adversary_run_count разошёлся после разбиения на выборку и счёт"
# T6: единственный сосед нечитаем (непуст, слово есть, JSON нет) → код 2, а не ноль
Q="$TMP/proj-broken"; mkdir -p "$Q"
talk_line "${D}T09:30:00Z" > "$Q/own.jsonl"
printf 'adversary {оборвано\n' > "$Q/broken.jsonl"
N=$(adversary_run_elsewhere "$Q/own.jsonl" 0); RC=$?
[ "$RC" = 2 ] && ok || bad "T6" "нечитаемый сосед: ждали код 2, получили $RC (n=$N)"
# T7: сосед, не менявшийся с начала окна, не читается вовсе (отсев по mtime) — и это честно:
#     вызов в окне есть запись в окне. Нога разностная: до состаривания a в окне с 09:00 двое
#     (a в 10:00 и self-run из T4 в 12:00), после — один.
N_BEFORE=$(adversary_run_elsewhere "$P/own.jsonl" "$T0900")
touch -t 202001010000 "$P/a.jsonl"
N=$(adversary_run_elsewhere "$P/own.jsonl" "$T0900")
[ "$N_BEFORE" = 2 ] && [ "$N" = 1 ] && ok || bad "T7" "отсев по mtime: до состаривания $N_BEFORE (ждали 2), после $N (ждали 1)"
touch "$P/a.jsonl"
# T8: мутант — счёт в окне выключен: там, где оригинал даёт 1, мутант даёт 0
M="$TMP/lib-mutant.sh"
sed 's/_are_n=$((_are_n + 1))/:/' "$LIB" > "$M"
grep -q '_are_n=$((_are_n + 1))' "$M" && bad "T8" "мутант не собрался" || true
N=$(bash -c '. "$1"; adversary_run_elsewhere "$2" "$3"' _ "$M" "$P/own.jsonl" "$T0900")
[ "$N" = 0 ] && ok || bad "T8" "мутант без счёта дал $N — нога не различает"

# --- страж: крупный дифф, своя расшифровка без прогона ---
command -v git >/dev/null 2>&1 || { echo "adversary run elsewhere: PASS=$PASS FAIL=$FAIL (без git — ноги стража пропущены)"; exit $(( FAIL != 0 )); }
big_repo() {  # свой репозиторий в $d — параллельная фаза по правилу раннера
    local d="$1"; mkdir -p "$d"; git -C "$d" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_run_elsewhere.sh:$LINENO" >&2; exit 1; }
    git -C "$d" config user.email t@e; git -C "$d" config user.name t
    echo seed > "$d/seed.txt"; git -C "$d" add . >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adversary_run_elsewhere.sh:$LINENO" >&2; exit 1; }; git -C "$d" commit -q -m seed 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adversary_run_elsewhere.sh:$LINENO" >&2; exit 1; }
    local i; for i in 1 2 3 4 5 6; do seq 1 30 > "$d/f$i.py"; done
    git -C "$d" add . >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adversary_run_elsewhere.sh:$LINENO" >&2; exit 1; }
}
run_hook() {  # run_hook <repo> <state> <sid> <transcript>
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","transcript_path":"%s","tool_input":{"command":"git commit -m x"}}' \
        "$3" "$1" "$4" | env STATE_DIR="$2" PATHS_LIB="$HOOKS/paths-lib.sh" bash "$HOOK" 2>/dev/null
}
# T9: чужой прогон ПОСЛЕ времени HEAD → тишина и satisfied с src=elsewhere
R9="$TMP/repo9"; big_repo "$R9"; S9="$TMP/state9"; PR9="$TMP/proj9"; mkdir -p "$PR9"
talk_line "2020-01-01T00:00:00Z" > "$PR9/own.jsonl"
run_line "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PR9/other.jsonl"     # сейчас ≥ времени HEAD (в секундах)
OUT=$(run_hook "$R9" "$S9" sid-9 "$PR9/own.jsonl")
[ -z "$OUT" ] || [ "$OUT" = "{}" ] && ok || bad "T9a" "чужой прогон после HEAD, а страж напомнил: ${OUT:0:120}"
ACT=$(jq -r '"\(.act) \(.src // "-")"' "$S9/crr-pending-sid-9.jsonl" 2>/dev/null | tail -1)
[ "$ACT" = "satisfied elsewhere" ] && ok || bad "T9b" "ждали «satisfied elsewhere» в ожидании, получили «${ACT}»"
# T10: чужой прогон ДО времени HEAD → напоминание и said
R10="$TMP/repo10"; big_repo "$R10"; S10="$TMP/state10"; PR10="$TMP/proj10"; mkdir -p "$PR10"
talk_line "2020-01-01T00:00:00Z" > "$PR10/own.jsonl"
run_line "2020-01-01T00:00:00Z" > "$PR10/other.jsonl"
OUT=$(run_hook "$R10" "$S10" sid-10 "$PR10/own.jsonl")
grep -q "Крупный кодовый дифф" <<< "$OUT" && ok || bad "T10a" "чужой прогон до HEAD, а страж промолчал"
ACT=$(jq -r '.act' "$S10/crr-pending-sid-10.jsonl" 2>/dev/null | tail -1)
[ "$ACT" = "said" ] && ok || bad "T10b" "ждали said, получили «${ACT}»"
# T11: своя расшифровка с прогоном → satisfied БЕЗ src (прежний путь не задет)
R11="$TMP/repo11"; big_repo "$R11"; S11="$TMP/state11"; PR11="$TMP/proj11"; mkdir -p "$PR11"
run_line "2020-01-01T00:00:00Z" > "$PR11/own.jsonl"
OUT=$(run_hook "$R11" "$S11" sid-11 "$PR11/own.jsonl")
ACT=$(jq -r '"\(.act) \(.src // "-")"' "$S11/crr-pending-sid-11.jsonl" 2>/dev/null | tail -1)
[ -z "$OUT" ] && [ "$ACT" = "satisfied -" ] && ok || bad "T11" "свой прогон: ждали тишину и «satisfied -», получили «${ACT}» / ${OUT:0:80}"

echo "adversary run elsewhere: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
