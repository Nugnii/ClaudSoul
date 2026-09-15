#!/usr/bin/env bash
# test_semantic_parallel_slot.sh — горячий предкэш подаёт слотом, а не выбрасывается (D241).
#
# ПОВОД (диагностика 2026-08-31). Семантический путь — фолбэк за гейтом «keyword нашёл
# мало»; при 122 кандидатах keyword находит всегда, и via=mcp — 0 из 12 201 подачи за
# историю. Предкэш при этом строится на КАЖДОЙ реплике и выбрасывается неиспользованным.
#
# Контракт: при СИЛЬНОМ keyword-результате горячий кэш (embedding уже оплачен фоном)
# занимает один ОТДЕЛЬНЫЙ слот slot=semantic via=mcp — keyword-топ не вытесняется;
# кандидат берётся только вне keyword-результатов; протухший кэш слота не даёт;
# выключатель KA_SEMANTIC_SLOT=0.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/knowledge-activator.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"; STATE="$TMP/state"; WORK="$TMP/work"
mkdir -p "$FAKE_HOME/.claude/global-lessons" "$STATE" "$WORK"

mk() { # $1 имя, $2 теги
    cat > "$FAKE_HOME/.claude/global-lessons/$1.md" <<KF
---
name: ${1}
description: фикстура
type: pattern
confidence: 4
impact: 4
tags: [$2]
---
Правило.
KF
}
# Сильный keyword-топ: три знания с 3+ совпадениями тегов.
mk pattern-kw1 "docker, grep, tracker"
mk pattern-kw2 "docker, grep, tracker"
mk pattern-kw3 "docker, grep, tracker"
# Семантический кандидат — ПРОЦИТИРОВАННЫЙ кейс: цикл отбора сканирует только
# pattern/principle/сирот, а кейс, упомянутый в паттерне, структурно вне отбора
# (получает даже базовый бонус только через кэш). Ровно ему слот и открывает дверь.
cat > "$FAKE_HOME/.claude/global-lessons/case-sem-evidence.md" <<'KF'
---
name: семантический кейс
description: кейс вне цикла отбора
type: case
confidence: 3
impact: 4
tags: [vector]
---
Кейс-фикстура.
KF
printf 'Ссылка: case-sem-evidence\n' >> "$FAKE_HOME/.claude/global-lessons/pattern-kw1.md"

hot_cache() { # свежий кэш для сессии $1
    printf '' > "$STATE/semantic-prefetch-$1.json.prompt"
    sleep 1
    printf '[{"file_path":"%s","name":"семантический кейс","type":"case","confidence":3,"impact":4}]' \
        "$FAKE_HOME/.claude/global-lessons/case-sem-evidence.md" > "$STATE/semantic-prefetch-$1.json"
}

run() { # $1 sid, $2 env-довесок
    printf '{"session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"docker grep tracker compose"}}' "$1" "$WORK" \
      | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$1" STATE_DIR="$STATE" \
            SKIP_ENTITY_ACTIVATION=1 KA_RESEARCH_SLOT=0 ${2:-} bash "$HOOK" 2>/dev/null
}

# --- T1: горячий кэш + сильный keyword → строка slot=semantic via=mcp в журнале ---
hot_cache sem1
run sem1 >/dev/null
_got=$(jq -rR 'fromjson? // empty | select(.file == "case-sem-evidence.md" and .slot == "semantic" and .via == "mcp" and .injected == true) | .file' "$STATE/injection-log.jsonl" 2>/dev/null)
if grep -q case-sem-evidence <<< "$_got"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: slot=semantic не подан при сильном keyword: $(cat "$STATE/injection-log.jsonl" 2>/dev/null | tail -5)"; fi

# --- T2: keyword-топ не вытеснен (kw1-3 все injected) ---
N_KW=$(jq -rR 'fromjson? // empty | select(.injected == true and (.file | startswith("pattern-kw"))) | .file' \
    "$STATE/injection-log.jsonl" 2>/dev/null | sort -u | grep -c '' || true)
if [ "${N_KW:-0}" -ge 3 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: keyword-топ вытеснен (injected kw: $N_KW из 3)"; fi

# --- T3: протухший кэш (маркер новее кэша) слота не даёт, синхронного вызова нет ---
rm -f "$STATE/injection-log.jsonl"
hot_cache sem2
sleep 1
printf '' > "$STATE/semantic-prefetch-sem2.json.prompt"   # реплика новее кэша → протух
run sem2 >/dev/null
_got=$(jq -rR 'fromjson? // empty | select(.slot == "semantic") | .file' "$STATE/injection-log.jsonl" 2>/dev/null)
if grep -q . <<< "$_got"; then
    FAIL=$((FAIL+1)); echo "FAIL [T3]: протухший кэш дал слот"
else PASS=$((PASS+1)); fi

# --- T4: выключатель ---
rm -f "$STATE/injection-log.jsonl"
hot_cache sem3
run sem3 "KA_SEMANTIC_SLOT=0" >/dev/null
_got=$(jq -rR 'fromjson? // empty | select(.slot == "semantic") | .file' "$STATE/injection-log.jsonl" 2>/dev/null)
if grep -q . <<< "$_got"; then
    FAIL=$((FAIL+1)); echo "FAIL [T4]: выключатель не выключает"
else PASS=$((PASS+1)); fi

echo "test_semantic_parallel_slot: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
