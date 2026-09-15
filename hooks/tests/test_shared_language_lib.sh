#!/usr/bin/env bash
# test_shared_language_lib.sh — shared-language-lib.sh (мост L3↔L7).
#
# Закрепляется:
#   - берётся только живая речь собеседника: роль user, БЕЗ вставок харнесса — роль
#     решают поля (isMeta, isCompactSummary, isSidechain, origin.kind), а конверты
#     внутри речи (ide_selection, command-message и др.) вырезаются спаном;
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
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then
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

# === T11-T12: вставки харнесса не идут в кандидаты словаря (8 сентября 2026) ===
# Повод наблюдаемый: в кандидаты попадали «workflow», «const», «when», «phase» — лексика
# справки инструмента, вставленной харнессом, а не словарь собеседника. Текстовый отсев
# судит по маркерам и справку не ловит; поле isMeta ставит сам харнесс.
# Форма записи взята из мира: реальная строка несёт isMeta рядом с message.role.
TMETA=$(mktemp -d)
TM="$TMETA/t.jsonl"
{
  printf '%s\n' '{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"# Workflow authoring reference workflow workflow workflow phase phase phase"}]}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"привет, посмотри задачу"}]}}'
} > "$TM"

OUT_META=$(shlang_user_text "$TM")
if grep -qF "Workflow authoring reference" <<< "${OUT_META}"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T11: вставка харнесса принята за речь собеседника]"
else PASS=$((PASS + 1)); fi

if grep -qF "привет, посмотри задачу" <<< "${OUT_META}"; then
    PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T12: настоящая реплика потеряна вместе со вставкой]"; fi

rm -rf "$TMETA"

# === T13-T16: роль решается полями харнесса, а не формой текста (12 сентября 2026, D356) ===
# Замер по 60 расшифровкам проекта: сводка после сжатия несёт isCompactSummary (19 из 19),
# уведомление фоновой задачи — origin.kind "task-notification" (146 из 146); у записи
# `<ide_selection>` полей роли нет, а за конвертом идёт реплика — вырезается спан, не запись.
# Тексты фикстур НАРОЧНО без прежних текстовых маркеров: зелёное здесь держит поле, а не слово.
TROLE=$(mktemp -d); TR="$TROLE/t.jsonl"
{
  printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":[{"type":"text","text":"Summary of earlier work: Stop says: summaryword summaryword summaryword"}]}}'
  printf '%s\n' '{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":[{"type":"text","text":"taskword taskword taskword finished"}]}}'
  printf '%s\n' '{"type":"user","isSidechain":true,"message":{"role":"user","content":[{"type":"text","text":"sidechainword sidechainword sidechainword"}]}}'
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"<ide_selection>selectedword selectedword selectedword</ide_selection>\n\nпосмотри выделение, там baseline-drift"}]}}'
} > "$TR"
OUT_ROLE=$(shlang_user_text "$TR")
assert_not_contains "$OUT_ROLE" "summaryword" "T13 сводка после сжатия отсеяна полем isCompactSummary"
assert_not_contains "$OUT_ROLE" "taskword" "T14 уведомление задачи отсеяно полем origin.kind"
assert_not_contains "$OUT_ROLE" "sidechainword" "T15 ветка субагента отсеяна полем isSidechain"
assert_not_contains "$OUT_ROLE" "selectedword" "T16 конверт ide_selection вырезан"
assert_contains "$OUT_ROLE" "посмотри выделение, там baseline-drift" "T16b реплика за конвертом сохранена"
rm -rf "$TROLE"

echo ""
echo "test_shared_language_lib: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
