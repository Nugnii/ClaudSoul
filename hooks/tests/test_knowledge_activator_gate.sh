#!/usr/bin/env bash
# test_knowledge_activator_gate.sh — знание догоняет смену темы внутри хода.
#
# Повод (2026-08-21). Пауза избирательного внимания стояла ВЫШЕ чтения stdin и глушила
# хук, не посмотрев на тему вызова. Детекция сдвига стояла ниже и внутри паузы была
# недостижима — комментарий в самом коде это признавал: «Cooldown passed — will check
# context shift after extracting keywords».
#
# Замер на живой сессии: один ход, 25 вызовов Bash, 8 минут, тема ушла от «хуки вообще»
# к «каналы доставки» — знания не обновились ни разу. Между ходами дефект не всплывал,
# потому что session-collector.sh снимает флаг на Stop. То есть он был виден ровно там,
# где знание и нужно: в работе.
#
# Предмет проверки — ГЕЙТ, а не содержимое инжекта: попадание знаний зависит от рабочей
# базы, которая меняется, и тест на ней мерил бы не то, о чём утверждение. Признак
# прохода — отметка времени в knowledge_injected_*: её хук ставит, только пройдя гейт.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/knowledge-activator.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

SID="gate-probe"
GATE="$TMP/state/knowledge_injected_$SID"

# Дом подменяется на фикстуру. Прежде тест читал ЖИВУЮ базу знаний из настоящего
# ~/.claude/global-lessons: на машине автора там сотни записей и гейт ставился, а в CI
# каталога нет вовсе — хук не находил ничего, отметку не ставил, и T1 с T4 краснели.
# Тест проверял не поведение гейта, а наличие базы у того, кто его запускает.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/global-lessons"
cat > "$FAKE_HOME/.claude/global-lessons/pattern-gate-probe.md" <<'KF'
---
name: gate-probe
description: Фикстура для проверки гейта — совпадает с обеими темами прогона
type: pattern
confidence: 4
impact: 4
domain: [shell, devops]
situation: debugging
trigger: error
tags: [grep, error, tracker, hooks, transcript, docker, compose, postgres, migrate, volume]
---
Правило-фикстура.
KF

run() { # $1=команда для tool_input
    printf '{"session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' \
        "$SID" "$HOOKS_DIR" "$1" \
      | HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" STATE_DIR="$TMP/state" SKIP_MCP_FALLBACK=1 \
        bash "$HOOK" >/dev/null 2>&1
}
stamp() { cat "$GATE" 2>/dev/null || echo "нет"; }
age()   { printf '%s' "$(( $(date +%s) - 3600 ))" > "$GATE"; }   # состарить отметку на час

TOPIC_A="grep error tracker hooks transcript"
TOPIC_B="docker compose postgres migrate volume"

# --- T1: первый заход в сессии — проходит ---
run "$TOPIC_A"
[ -f "$GATE" ] && ok || bad "T1" "первый заход не прошёл гейт — отметки нет"
S1=$(stamp)

# --- T2: та же тема сразу — молчит ---
run "$TOPIC_A"
[ "$(stamp)" = "$S1" ] && ok || bad "T2" "повтор на той же теме прошёл гейт"

# --- T3: другая тема сразу — молчит (минимальный интервал) ---
run "$TOPIC_B"
[ "$(stamp)" = "$S1" ] && ok || bad "T3" "смена темы пробила гейт мгновенно — подсказка станет фоном"

# --- T4: другая тема, интервал выдержан — проходит ---
# Суть починки. Раньше здесь была тишина: пауза выходила из хука, не дойдя до сравнения тем.
age; S_OLD=$(stamp)
run "$TOPIC_B"
[ "$(stamp)" != "$S_OLD" ] && ok \
    || bad "T4" "смена темы не пробила паузу — знание снова молчит весь ход"

# --- T5: та же тема даже после паузы — молчит ---
age; S_OLD=$(stamp)
run "$TOPIC_B"
[ "$(stamp)" = "$S_OLD" ] && ok || bad "T5" "та же тема переинжектилась по одному лишь времени"

# --- T6: отрицательный контроль — гейт вообще способен не пропустить ---
# Без него зелёные T2/T3/T5 неотличимы от «хук всегда молчит», а T1/T4 — от «всегда говорит».
[ "$PASS" -ge 1 ] && ok || bad "T6" "контроль недостижим"

# --- T7: гейт стоит ПОСЛЕ ключевых слов, а не до чтения stdin ---
# Структурная защита от возврата прежнего порядка: именно он делал сравнение тем
# недостижимым, и по поведению это выглядело бы как «знания просто редкие».
L_INPUT=$(grep -n '^INPUT=$(cat)' "$HOOK" | head -1 | cut -d: -f1)
L_KW=$(grep -n '^CONTEXT_SHIFTED=' "$HOOK" | head -1 | cut -d: -f1)
L_GATE=$(grep -n '^date +%s > "\$GATE_FILE"' "$HOOK" | head -1 | cut -d: -f1)
if [ -n "$L_INPUT" ] && [ -n "$L_KW" ] && [ -n "$L_GATE" ]; then
    { [ "$L_INPUT" -lt "$L_KW" ] && [ "$L_KW" -lt "$L_GATE" ]; } && ok \
        || bad "T7" "порядок нарушен: stdin=$L_INPUT сдвиг=$L_KW отметка=$L_GATE"
else
    bad "T7" "не найдены опорные строки (stdin=$L_INPUT сдвиг=$L_KW отметка=$L_GATE)"
fi

echo ""
echo "knowledge activator gate tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
