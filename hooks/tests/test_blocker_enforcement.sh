#!/usr/bin/env bash
# test_blocker_enforcement.sh — стопор, который ОТКАЗЫВАЕТ, а не напоминает.
#
# Повод. Замер 2026-08-28: из 19 случаев «знание было уместно и не применено» минимум в
# девяти прямым текстом сказано, что знание было в контексте в момент действия. То есть
# напоминание как класс не меняет поведения. Собеседник: «нужен стопор, который будет
# заставлять, а не просто напоминать».
#
# Почему отказ, а не вопрос собеседнику. `permissionDecision: "ask"` останавливает
# СОБЕСЕДНИКА — по корпусу это ~10 вопросов за сессию. `deny` останавливает АГЕНТА и не
# трогает собеседника вовсе, то есть сохраняет прежнее решение «сторож молчит наружу»
# (feedback_silent_correct_decisions). Отказ обязан называть замену: отказ по строке
# команды не убирает потребности (case-2026-08-07-denial-targets-command-string-not-intent).
#
# Режим задаётся У СИГНАЛА, а не у знания: одно и то же знание отказывает там, где код
# уезжает в файл, и лишь напоминает на разовой команде. Замер разделения: за шесть сессий
# 10 записей признака в файл под hooks/scripts против 35 разовых команд.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/blocker-tier-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
K="$TMP/knowledge"; S="$TMP/state"; mkdir -p "$K" "$S"

mkk() { # mkk <имя> <enforcement-строка-или-пусто>
    cat > "$K/pattern-$1.md" <<EOF
---
name: $1
blocker: true
confidence: 5
confirmed_count: 9
blocker_reminder: "Бери готовое из hooks/portable-lib.sh"
detection_signals: |
  [
    {
      "name": "into_file",
      $2
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"command_uses": "timeout "}
      ]
    }
  ]
---
тело
EOF
}

mkk_remedy() { # знание, у сигнала которого своя замена
    cat > "$K/pattern-remedy.md" <<EOF
---
name: remedy
blocker: true
confidence: 5
confirmed_count: 9
blocker_reminder: "Бери готовое из hooks/portable-lib.sh"
detection_signals: |
  [
    {
      "name": "into_file",
      "enforcement": "deny",
      "remedy": "Замена именно для этого случая: обернуть в bash -c",
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"command_uses": "timeout "}
      ]
    }
  ]
---
тело
EOF
}

call() { # call <sid> <команда>
    jq -cn --arg s "$1" --arg c "$2" \
      '{session_id:$s, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' \
    | BLOCKER_KNOWLEDGE_DIR="$K" BLOCKER_STATE_DIR="$S" LESSONS_DIR="$K" bash "$HOOK" 2>/dev/null
}

# 1. enforcement: deny — вызов ОТКАЗАН, и в причине названа замена.
mkk deny '"enforcement": "deny",'
OUT=$(call s1 "timeout 60 bash x.sh")
[ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$OUT")" = "deny" ] \
    && ok || bad "deny" "вызов не отказан: $OUT"
_reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT")
grep -q "portable-lib" <<< "$_reason" \
    && ok || bad "замена в причине" "отказ не называет, чем заменить: $OUT"

# 2. Без enforcement — прежнее поведение: тихое напоминание, вызов проходит.
rm -f "$K"/*.md "$S"/*; mkk quiet ''
OUT=$(call s2 "timeout 60 bash x.sh")
[ -z "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$OUT")" ] \
    && ok || bad "умолчание" "без enforcement появился отказ — старое поведение сломано: $OUT"
_ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<< "$OUT")
grep -q "Blocker" <<< "$_ctx" \
    && ok || bad "умолчание" "тихое напоминание пропало: $OUT"

# 3. Упоминание в кавычках не отказывается (признак command_uses, а не подстрока).
rm -f "$K"/*.md "$S"/*; mkk deny2 '"enforcement": "deny",'
OUT=$(call s3 "printf '%s' 'timeout is missing'")
[ -z "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$OUT")" ] \
    && ok || bad "упоминание" "отказ пришёл на упоминание в кавычках: $OUT"

# 4. Посторонняя команда — тишина.
OUT=$(call s4 "ls -la")
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] \
    && ok || bad "посторонняя" "шум на безобидной команде: $OUT"

# 5. Порядок сигналов в файле НЕ решает исход: если совпали и напоминающий, и
# отказывающий, побеждает отказ. Найдено на живой пробе 2026-08-28: хук брал ПЕРВЫЙ
# совпавший сигнал, а первой в знании стояла ветвь разовой команды без принуждения —
# отказ не наступал никогда, и это зависело от порядка строк в файле знания.
rm -f "$K"/*.md "$S"/*
cat > "$K/pattern-both.md" <<'EOF'
---
name: both
blocker: true
confidence: 5
confirmed_count: 9
blocker_reminder: "Бери готовое из hooks/portable-lib.sh"
detection_signals: |
  [
    {
      "name": "gentle_first",
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"command_uses": "timeout "}
      ]
    },
    {
      "name": "strict_second",
      "enforcement": "deny",
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"command_uses": "timeout "},
        {"tool_input_regex": "(hooks|scripts)/"}
      ]
    }
  ]
---
тело
EOF
OUT=$(call s5 "timeout 5 bash hooks/x.sh")
[ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$OUT")" = "deny" ] \
    && ok || bad "порядок сигналов" "победил первый совпавший, а не сильнейший режим: $OUT"

# И обратное: совпал только мягкий — отказа нет.
OUT=$(call s6 "timeout 5 ls")
[ -z "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$OUT")" ] \
    && ok || bad "порядок сигналов" "отказ пришёл там, где совпал только мягкий сигнал: $OUT"


# 8. Замена берётся У СИГНАЛА, когда она там есть: у разных сигналов одного знания
#    чинится разное, и общий blocker_reminder на отказе читается как не про то.
rm -f "$K"/*.md "$S"/*; mkk_remedy
OUT=$(call s8 "timeout 60 bash x.sh")
_reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT")
grep -q "обернуть в bash -c" <<< "$_reason" \
    && ok || bad "замена у сигнала" "в причине не своя замена сигнала: $OUT"
grep -q "portable-lib" <<< "$_reason" \
    && bad "замена у сигнала" "общая замена знания не вытеснена своей: $OUT" || ok

# 9. Нет своей замены — остаётся общая у знания (прежнее поведение не сломано).
rm -f "$K"/*.md "$S"/*; mkk deny9 '"enforcement": "deny",'
OUT=$(call s9 "timeout 60 bash x.sh")
grep -q "portable-lib" <<< "$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT")" \
    && ok || bad "замена по умолчанию" "без remedy пропала и общая замена: $OUT"

echo ""
echo "blocker enforcement tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
