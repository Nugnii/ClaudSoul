#!/usr/bin/env bash
# test_shared_language_lib.sh — shared-language-lib.sh (мост L3↔L7).
#
# Закрепляется:
#   - берётся только живая речь собеседника: роль user, БЕЗ служебных сообщений
#     (task-notification, загрузка скилла, ide_opened_file, продолжение сессии);
#   - кандидат: латинский/составной токен ≥ 4 симв., ≥ min раз, не URL-обломок,
#     не расширение файла, отсутствует в словаре (без учёта регистра);
#   - слова агента кандидатами не становятся;
#   - порог по умолчанию 3 (проект моста);
#   - кодировка пути словаря: '/' и пробел → '-'.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/shared-language-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
. "$LIB"

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly in output:"; echo "$haystack"
    else PASS=$((PASS + 1)); fi
}

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected '$expected', got '$actual'"; fi
}

command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- T1: кодировка пути словаря ---------------------------------------------------
assert_eq "$(shlang_vocab_path "/Users/x/My Project/Foo")" \
    "$HOME/.claude/projects/-Users-x-My-Project-Foo/memory/shared-vocabulary.md" \
    "T1 путь словаря"

# --- Фикстура: транскрипт --------------------------------------------------------
T="$TMP/transcript.jsonl"
cat > "$T" <<'EOF'
{"message":{"role":"user","content":[{"type":"text","text":"сделай quality-gate для quality-gate и ещё раз quality-gate"}]}}
{"message":{"role":"user","content":[{"type":"text","text":"quality-gate должен видеть blocker-tier и blocker-tier"}]}}
{"message":{"role":"user","content":[{"type":"text","text":"blocker-tier опять, и знакомый термин enrich тоже enrich и enrich"}]}}
{"message":{"role":"assistant","content":[{"type":"text","text":"agentword agentword agentword agentword agentword"}]}}
{"message":{"role":"user","content":[{"type":"text","text":"<task-notification> noiseterm noiseterm noiseterm noiseterm </task-notification>"}]}}
{"message":{"role":"user","content":[{"type":"text","text":"смотри https://example.com/urltoken?urltoken=urltoken и файл notes.md notes.md notes.md"}]}}
EOF
# Словарь: enrich уже есть
V="$TMP/vocab.md"
printf -- '## Словарь\n- **Enrich** — обогащение сущности\n' > "$V"

OUT=$(shlang_candidates "$T" "$V")
assert_contains "$OUT" "quality-gate ×4" "T2 составной термин посчитан"
assert_contains "$OUT" "blocker-tier ×3" "T3 порог 3 включительно"
assert_not_contains "$OUT" "enrich" "T4 уже в словаре (регистр не важен)"
assert_not_contains "$OUT" "agentword" "T5 слова агента не считаются"
assert_not_contains "$OUT" "noiseterm" "T6 служебное user-сообщение отброшено"
assert_not_contains "$OUT" "urltoken" "T7 URL вычищен до токенизации"
assert_not_contains "$OUT" "notes.md" "T8 расширение файла — не термин"

# --- T9: без словаря (файла нет) — кандидаты всё равно считаются ------------------
OUT2=$(shlang_candidates "$T" "$TMP/no-such-vocab.md")
assert_contains "$OUT2" "quality-gate ×4" "T9 отсутствие словаря не ломает счёт"

# --- T10: порог настраивается -----------------------------------------------------
OUT3=$(shlang_candidates "$T" "$V" 5)
assert_eq "$OUT3" "" "T10 min=5 — кандидатов нет"

echo ""
echo "test_shared_language_lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
