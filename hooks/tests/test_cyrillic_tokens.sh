#!/usr/bin/env bash
# СУДИТ: hooks/knowledge-activator.sh hooks/portable-lib.sh
# test_cyrillic_tokens.sh — кириллические якоря участвуют в отборе, реплика — в контексте.
#
# ПОВОД (диагностика 2026-08-31). Токенизатор отбора — 12 мест `grep -oE '[a-z_]{3,}'` —
# отбрасывал кириллицу: 131 из 314 situation и 130 из 314 trigger не давали ни одного
# токена, ~42% высоковесных якорей (W=30) не участвовали в скоринге. Вторая половина
# той же щели: в keyword-матчинг со стороны контекста попадали ТОЛЬКО текст Bash-команды
# и путь файла — реплика собеседника (по-русски) не попадала вовсе.
#
# Контракт:
#   T1 — to_tokens (portable-lib) даёт кириллические и латинские токены, нижний регистр;
#   T2 — token_in точен: токен из списка находится, подстрока чужого токена — нет;
#   T3 — знание с кириллическим situation подаётся, когда реплика (маркер .prompt от
#        semantic-prefetch) несёт то же слово;
#   T4 — латинский путь не сломан: знание с латинскими tags подаётся по Bash-команде.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/knowledge-activator.sh"
LIB="$HOOKS_DIR/portable-lib.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"; STATE="$TMP/state"
mkdir -p "$FAKE_HOME/.claude/global-lessons" "$STATE"

# --- T1: to_tokens — кириллица и латиница, нижний регистр, короткое отброшено ---
if ! command -v to_tokens >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); echo "FAIL [T1]: to_tokens отсутствует в portable-lib"
else
    TOK=$(to_tokens "Git Статус Конвейера — по df и by")
    ok=1
    for t in git статус конвейера; do
        grep -qx "$t" <<< "$TOK" || { ok=0; echo "FAIL [T1]: нет токена '$t' в: $(tr '\n' ' ' <<< "$TOK")"; }
    done
    # «df», «by», «по» короче порога — токенами не становятся
    grep -qx "df" <<< "$TOK" && { ok=0; echo "FAIL [T1]: короткое 'df' стало токеном"; }
    grep -qx "по" <<< "$TOK" && { ok=0; echo "FAIL [T1]: короткое 'по' стало токеном"; }
    [ "$ok" = 1 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
fi

# --- T2: token_in точен и не ловит подстроку ---
if ! command -v token_in >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); echo "FAIL [T2]: token_in отсутствует в portable-lib"
else
    ok=1
    token_in "статус" "статус конвейера git" || { ok=0; echo "FAIL [T2]: точный токен не найден"; }
    token_in "тат" "статус конвейера" && { ok=0; echo "FAIL [T2]: подстрока 'тат' совпала внутри 'статус'"; }
    [ "$ok" = 1 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
fi

# --- Фикстуры знаний ---
cat > "$FAKE_HOME/.claude/global-lessons/pattern-cyr.md" <<'KF'
---
name: кириллический якорь
description: фикстура кириллического отбора
type: pattern
confidence: 4
impact: 4
situation: статус конвейера используется как ответ
trigger: труба с ранним выходом
tags: []
---
Правило-фикстура.
KF
cat > "$FAKE_HOME/.claude/global-lessons/pattern-lat.md" <<'KF'
---
name: latin anchor
description: фикстура латинского отбора
type: pattern
confidence: 4
impact: 4
tags: [docker, grep]
---
Правило-фикстура.
KF

# cwd — песочница, НЕ репозиторий: активатор вшивает SESSION.md из cwd в вывод,
# и живой SESSION.md проекта содержит слова фикстур (ложно-зелёный T3 до починки).
WORK="$TMP/work"; mkdir -p "$WORK"
run() { # $1 sid, $2 команда
    printf '{"session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$WORK" "$2" \
      | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$1" STATE_DIR="$STATE" \
            SKIP_MCP_FALLBACK=1 SKIP_ENTITY_ACTIVATION=1 KA_RESEARCH_SLOT=0 bash "$HOOK" 2>/dev/null
}

# Ассерты — по score в журнале подач, не по присутствию в выводе: одинокая фикстура
# попадает в топ-3 и с нулём совпадений (безусловный бонус даёт score 1) — grep по
# выводу был вакуумно-зелёным до починки. Совпадение situation (W=30) даёт score >= 3.
# --- T3: реплика в маркере .prompt открывает кириллическому якорю дверь ---
printf 'почему статус конвейера красный' > "$STATE/semantic-prefetch-cyr1.json.prompt"
run cyr1 "ls -la" >/dev/null
# Отказ чтения журнала (нет файла, `jq` не тот, все строки битые) НЕ равен «совпадений
# не дало»: балл — ЗНАЧЕНИЕ, а не счёт, и `${CYR_SCORE:-0}` превращал «не смог посмотреть»
# в «признак не сработал», роняя тест по причине, которой нет в мире. Род B, 5 сентября 2026.
CYR_SCORE=$(jq -rR 'fromjson? // empty | select(.file == "pattern-cyr.md") | .score' \
    "$STATE/injection-log.jsonl" 2>/dev/null | sort -n | tail -1)
if [ -z "$CYR_SCORE" ]; then
    FAIL=$((FAIL+1)); echo "FAIL [T3]: балл НЕ ПРОЧИТАН из $STATE/injection-log.jsonl — это не «совпадений не дало»"
elif [ "$CYR_SCORE" -ge 3 ] 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: кириллический situation не дал совпадений по реплике (score=$CYR_SCORE)"; fi

# --- T4: латинский путь не сломан (2 совпадения tags → score >= 2) ---
run lat1 "docker grep compose" >/dev/null
LAT_SCORE=$(jq -rR 'fromjson? // empty | select(.file == "pattern-lat.md") | .score' \
    "$STATE/injection-log.jsonl" 2>/dev/null | sort -n | tail -1)
if [ -z "$LAT_SCORE" ]; then
    FAIL=$((FAIL+1)); echo "FAIL [T4]: балл НЕ ПРОЧИТАН из $STATE/injection-log.jsonl — это не «совпадений не дало»"
elif [ "$LAT_SCORE" -ge 2 ] 2>/dev/null; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: латинские tags не дали совпадений по команде (score=$LAT_SCORE)"; fi

echo "test_cyrillic_tokens: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
