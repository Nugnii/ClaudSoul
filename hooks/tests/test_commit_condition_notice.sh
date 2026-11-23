#!/usr/bin/env bash
# СУДИТ: hooks/commit-condition-notice.sh
# test_commit_condition_notice.sh — коммит без своего условия называется: (1) коммит прошлого пакета ушёл, а правка
# того же репозитория в пакете не легла; (2) нынешняя команда коммитит после шага через `;` (D1298).
#
# Результат: подсказка называет коммит, файл и причину — один раз на коммит; называет шаг перед `;`; молчит на
#            прошедшей правке, правке вне репозитория (и во вложенном), коммите с ошибкой, правке в другом пакете или
#            после коммита, на шаге-выводе, под `&&`, `then`, `set -e`, в теле heredoc; у субагента о прошлом молчит;
#            сломанный разбор — сказан, а не промолчан.
# Проверка результата: bash hooks/tests/test_commit_condition_notice.sh даёт 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

HOOK="$(cd "$(dirname "$0")/.." && pwd)/commit-condition-notice.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
export STATE_DIR="$TMP/state"

mkrepo() { mkdir -p "$1" && git -C "$1" init -q && printf 'a\n' > "$1/a.txt" && git -C "$1" add a.txt \
    && git -C "$1" -c user.email=t@t -c user.name=t commit -qm init; }
R="$TMP/repo"; mkrepo "$R" && mkrepo "$R/nested" || { echo "FAIL [рамка]: репозиторий"; exit 1; }
O="$TMP/other"; mkdir -p "$O"
ERR='<tool_use_error>String to replace not found in file.</tool_use_error>'

use() {   # use <расшифровка> <сообщение> <id> <инструмент> <вход json> [cwd строки]
    jq -cn --arg m "$2" --arg i "$3" --arg n "$4" --argjson inp "$5" --arg d "${6:-$R}" \
        '{type:"assistant",cwd:$d,message:{id:$m,role:"assistant",content:[{type:"tool_use",id:$i,name:$n,input:$inp}]}}' >> "$1"
}
result() {   # result <расшифровка> <id> <ошибка true|false> <текст>
    jq -cn --arg i "$2" --argjson e "$3" --arg t "$4" \
        '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,is_error:$e,content:$t}]}}' >> "$1"
}
edit() { jq -cn --arg p "$1" '{file_path:$p,old_string:"x",new_string:"y"}'; }
bash_in() { jq -cn --arg c "$1" '{command:$c}'; }
run() {   # run <расшифровка> <команда> [сессия] [агент] [страж] → вывод
    jq -cn --arg c "$2" --arg t "$1" --arg s "${3:-s1}" --arg a "${4:-}" --arg d "$R" \
        '{tool_name:"Bash",tool_input:{command:$c},session_id:$s,transcript_path:$t,cwd:$d} + (if $a == "" then {} else {agent_id:$a} end)' \
        | bash "${5:-$HOOK}" 2>/dev/null
}
fired()   { grep -q 'additionalContext' <<< "$1"; }
assert_silent() { if [ -z "$1" ]; then ok; else bad "$2" "сказано зря: ${1:0:200}"; fi; }
C1="cd \"$R\" && git add a.txt && git commit -qm x"
LS="ls"
batch() {   # batch <расшифровка> <файл правки> <ошибка правки true|false> [результат коммита-ошибка true|false]
    use "$1" m1 e1 Edit "$(edit "$2")"; result "$1" e1 "$3" "$ERR"
    use "$1" m1 b1 Bash "$(bash_in "$C1")"; result "$1" b1 "${4:-false}" "[main 1a2b3c4] x"
}

# --- B1 (ГЛАВНАЯ): прошлый пакет — правка a.txt не легла, коммит ушёл → на следующем вызове названы коммит и файл -----
T="$TMP/b1.jsonl"; batch "$T" "$R/a.txt" true
OUT=$(run "$T" "$LS")
if fired "$OUT" && grep -q 'a.txt' <<< "$OUT" && grep -q 'String to replace not found' <<< "$OUT" && grep -q 'b1' <<< "$OUT"; then ok
else bad B1 "не названо: ${OUT:0:300}"; fi
# --- B2: о том же коммите второй раз — молчание (отметка по tool_use_id) -------------------------------------------
assert_silent "$(run "$T" "$LS")" B2

# --- B3: правка легла → молчание (посторонняя ошибка в другом пакете — чтобы судила сама правка, а не отсев хвоста) --
T="$TMP/b3.jsonl"; use "$T" m0 x1 Bash "$(bash_in false)"; result "$T" x1 true "Exit code 1"
batch "$T" "$R/a.txt" false; assert_silent "$(run "$T" "$LS" s3)" B3
# --- B4: не легла правка вне репозитория коммита → молчание -----------------------------------------------------
T="$TMP/b4.jsonl"; batch "$T" "$O/note.txt" true; assert_silent "$(run "$T" "$LS" s4)" B4
# --- B5: не легла правка во ВЛОЖЕННОМ репозитории → молчание (сверка корней, а не префикса пути) --------------------
T="$TMP/b5.jsonl"; batch "$T" "$R/nested/a.txt" true; assert_silent "$(run "$T" "$LS" s5)" B5
# --- B6: коммит вернулся ошибкой (не ушёл) → молчание ----------------------------------------------------------
T="$TMP/b6.jsonl"; batch "$T" "$R/a.txt" true true; assert_silent "$(run "$T" "$LS" s6)" B6
# --- B7: непрошедшая правка в ДРУГОМ пакете → молчание -------------------------------------------------------------
T="$TMP/b7.jsonl"; use "$T" m0 e1 Edit "$(edit "$R/a.txt")"; result "$T" e1 true "$ERR"
use "$T" m1 b1 Bash "$(bash_in "$C1")"; result "$T" b1 false ok; assert_silent "$(run "$T" "$LS" s7)" B7
# --- B8: правка ПОСЛЕ коммита в пакете → молчание ------------------------------------------------------------------
T="$TMP/b8.jsonl"; use "$T" m1 b1 Bash "$(bash_in "$C1")"; result "$T" b1 false ok
use "$T" m1 e1 Edit "$(edit "$R/a.txt")"; result "$T" e1 true "$ERR"; assert_silent "$(run "$T" "$LS" s8)" B8
# --- B9: вызов субагента о прошлых пакетах молчит (расшифровка — родителя) ----------------------------------------
T="$TMP/b9.jsonl"; batch "$T" "$R/a.txt" true; assert_silent "$(run "$T" "$LS" s9 agent-x)" B9
# --- B10: `git -C <репозиторий>` при чужом cwd строки, каталог правки не родился (Write) → названо -------------------
C10="git -C \"$R\" commit -qm x"
T="$TMP/b10.jsonl"; use "$T" m1 e1 Write "$(edit "$R/new/dir/b.txt")" "$O"; result "$T" e1 true "PreToolUse:Write hook error: ОТКАЗ"
use "$T" m1 b1 Bash "$(bash_in "$C10")" "$O"; result "$T" b1 false ok
OUT=$(run "$T" "$LS" s10)
if fired "$OUT" && grep -q 'new/dir/b.txt' <<< "$OUT"; then ok; else bad B10 "git -C / нерождённый каталог: ${OUT:0:300}"; fi

# --- S1: нынешняя команда `git add …; git commit` → назван шаг ----------------------------------------------------
E="$TMP/empty.jsonl"; : > "$E"
OUT=$(run "$E" "cd \"$R\"; git add a.txt; git commit -qm x" s11)
if fired "$OUT" && grep -q 'git add a.txt' <<< "$OUT"; then ok; else bad S1 "шаг не назван: ${OUT:0:300}"; fi
# --- S2: перевод строки как разделитель, шаг — интерпретатор → назван ---------------------------------------------
OUT=$(run "$E" "python3 fix.py"$'\n'"git commit -qam x" s12)
if fired "$OUT" && grep -q 'python3 fix.py' <<< "$OUT"; then ok; else bad S2 "перевод строки не разделитель: ${OUT:0:300}"; fi
# --- S3–S7: под `&&`, шаг-вывод, `set -e`, `then`, тело heredoc → молчание ------------------------------------------
assert_silent "$(run "$E" "git add a.txt && git commit -qm x" s13)" S3
assert_silent "$(run "$E" "git status --short; echo ok; git commit -qm x" s14)" S4
assert_silent "$(run "$E" "set -e; git add a.txt; git commit -qm x" s15)" S5
assert_silent "$(run "$E" "if bash t.sh; then git commit -qm x; fi" s16)" S6
assert_silent "$(run "$E" "git commit -q -F - <<'EOF'"$'\n'"msg: git add a; git commit"$'\n'"EOF" s17)" S7

# --- X1: сломанный разбор (write_targets без нужного) — сказан, а не промолчан --------------------------------------
B="$TMP/broken"; mkdir -p "$B/lib"; cp "$HOOK" "$B/"
for f in command-scope-lib.sh paths-lib.sh; do cp "$(dirname "$HOOK")/$f" "$B/" 2>/dev/null; done
cp "$(dirname "$HOOK")/lib/deny_mark.py" "$B/lib/"; printf 'x = 1\n' > "$B/lib/write_targets.py"
OUT=$(HOME="$TMP/nohome" run "$TMP/b1.jsonl" "git add a; git commit -qm x" s18 "" "$B/commit-condition-notice.sh")
if grep -q 'прибор сломан' <<< "$OUT"; then ok; else bad X1 "сломанный разбор промолчан: ${OUT:0:300}"; fi

echo "commit condition notice: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
