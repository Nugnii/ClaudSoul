#!/usr/bin/env bash
# test_adv_hooks_merge_id_from_last_slash.sh — АТАКА на lib/hooks-merge.jq.
#
# Обещание шапки: «у каждой объявленной команды РОВНО одна регистрация на событие …;
# чужие хуки и чужие команды внутри общих групп не тронуты».
#
# Ключ сопоставления считается так:
#   def hook_id: if is_ours then ((.command // "") | sub("^.*/"; "") | sub("[[:space:]].*$"; "")) …
# `sub("^.*/"; "")` жадный и режет по ПОСЛЕДНЕЙ косой ВСЕЙ строки команды, а не по
# исполняемому файлу. Отсюда два следствия одного корня:
#
#   1. СВОЯ запись с путём в аргументе (перенаправление лога, флаг с путём) даёт id
#      «hooks.log» вместо «error-tracker.sh» — она не вычищается, канон добавляется рядом,
#      и хук висит на одном событии ДВАЖДЫ. Это ровно тот дефект, ради которого файл
#      заведён 5 и 9 сентября 2026 («6 дублей регистрации из 75»).
#   2. ЧУЖАЯ запись, у которой последний путь в строке случайно оканчивается именем
#      нашего хука, получает НАШ id и вычищается молча — при том что `is_ours` для неё
#      верен лишь потому, что где-то в аргументах стоит `~/.claude/hooks/`.
set -uo pipefail

MJQ="$(cd "$(dirname "$0")/../.." && pwd)/lib/hooks-merge.jq"
[ -f "$MJQ" ] || { echo "FAIL: нет $MJQ"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

TMP=$(mktemp -d) || exit 1
CFG='{"PreToolUse":[{"matcher":"Bash","hooks":[
      {"type":"command","command":"bash ~/.claude/hooks/error-tracker.sh"},
      {"type":"command","command":"bash ~/.claude/hooks/session-collector.sh"}]}]}'

merge() {  # $1 — файл settings.json
    jq --argjson cfg "$CFG" -f "$MJQ" "$1" 2>/dev/null
}
count_cmd() {  # $1 — вывод слияния, $2 — подстрока команды
    printf '%s' "$1" | jq -r '[.. | objects | .command? // empty] | .[]' 2>/dev/null \
        | grep -cF "$2"
}

# ── контроль: каноничная своя запись сливается в одну ─────────────────────────────
cat > "$TMP/canon.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"$HOME/.claude/hooks/error-tracker.sh"}
]}]}}
EOF
OUT=$(merge "$TMP/canon.json")
N=$(count_cmd "$OUT" "error-tracker.sh")
if [ "${N:-0}" -eq 1 ]; then
    ok "контроль: запись в иной форме пути слита в одну"
else
    bad "контроль: запись в иной форме пути слита в одну" "регистраций: $N — фикстура не годится"
fi

# ── АТАКА 1: своя запись с путём в аргументе → ДВЕ регистрации ────────────────────
cat > "$TMP/withlog.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"bash ~/.claude/hooks/error-tracker.sh >> ~/.claude/logs/hooks.log 2>&1"}
]}]}}
EOF
OUT=$(merge "$TMP/withlog.json")
N=$(count_cmd "$OUT" "error-tracker.sh")
if [ "${N:-0}" -eq 1 ]; then
    ok "путь_в_аргументе: ровно одна регистрация"
else
    bad "путь_в_аргументе: ровно одна регистрация" \
        "регистраций error-tracker.sh: $N — хук сработает $N раза на одном событии; id взят по последней косой строки («hooks.log»)"
fi

# ── АТАКА 2: чужая запись исчезает из-за имени в аргументе ────────────────────────
cat > "$TMP/foreign.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"node /opt/lint/cli.js --hooks ~/.claude/hooks/ --rule /opt/lint/session-collector.sh"}
]}]}}
EOF
OUT=$(merge "$TMP/foreign.json")
N=$(count_cmd "$OUT" "/opt/lint/cli.js")
if [ "${N:-0}" -eq 1 ]; then
    ok "чужая_запись: сохранена"
else
    bad "чужая_запись: сохранена" \
        "чужих регистраций осталось: $N — команда собеседника удалена молча, хотя её исполняемый файл наш дереву не принадлежит"
fi

echo "hooks-merge-id-from-last-slash: $PASS ok, $FAIL FAIL"
exit $(( FAIL != 0 ))
