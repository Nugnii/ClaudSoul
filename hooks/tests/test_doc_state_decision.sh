#!/usr/bin/env bash
# test_doc_state_decision.sh — правка ПОВЕДЕНИЯ требует решения по документу состояния.
#
# Результат: при изменении поведения механизма, описанного в документе состояния, страж
#            требует наблюдаемого решения; правка комментария такого требования не вызывает
# Проверка результата: bash hooks/tests/test_doc_state_decision.sh даёт 0
#
# Повод (D209). Требование обновить документ состояния было привязано к бампу версии
# (`docs-family-check`) либо к появлению нового модуля (`module-doc-check`). Изменение
# поведения существующего механизма не требовало ничего: `docs/architecture.md` говорил
# «поводов семь» при фактических восьми, а правило эскалации жило в трёх местах без ADR.
# Нашёл это владелец вопросом «документация актуальна?», а не механизм.
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · правка ТОЛЬКО комментария поведения не меняет — требования нет (иначе страж станет
#     фоном: комментарии правятся чаще кода);
#   · документ состояния в том же коммите — решение принято, требования нет;
#   · отметка `doc-state:` в сообщении коммита — решение принято («не задето» законный исход);
#   · механизм, который документ состояния не описывает, требования не вызывает.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/doc-impact-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
for t in jq git python3; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP: нет $t"; exit 0; }; done

PASS=0; FAIL=0
assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 300)"; fi
}
assert_not_contains() {
    if ! grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: найдено лишнее '$2'"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO/hooks" "$REPO/docs" "$REPO/.claude-docs" "$REPO/scripts"
git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t

# Индексатор-заглушка: настоящий dep-index здесь не нужен, нужен его КОНТРАКТ —
# «печатает документы, описывающие изменённое». Подмена через DEP_INDEX_TOOL.
cat > "$REPO/scripts/fake-index.py" <<'PY'
import sys
print("описывают изменённое, но не тронуты (1):\n  · docs/architecture.md — про hooks/thing.sh")
PY

printf '#!/usr/bin/env bash\necho old\n' > "$REPO/hooks/thing.sh"
printf '# Архитектура\n\nМеханизм `hooks/thing.sh` делает то-то.\n' > "$REPO/docs/architecture.md"
printf 'path\tsha\n' > "$REPO/.claude-docs/dep-index.tsv"
git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -q -m init

STATE="$TMP/state"; mkdir -p "$STATE"
run() {  # <команда коммита>
    printf '{"session_id":"d1","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO" \
    | STATE_DIR="$STATE" DEP_INDEX_TOOL="$REPO/scripts/fake-index.py" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
reset_throttle() { rm -f "$STATE"/doc-impact-*.txt; }

# --- T1: изменилось ПОВЕДЕНИЕ, документ состояния не тронут → требование ---
printf '#!/usr/bin/env bash\necho new\n' > "$REPO/hooks/thing.sh"
git -C "$REPO" add -A >/dev/null 2>&1
OUT=$(run "git commit -m fix")
assert_contains "$OUT" "документ СОСТОЯНИЯ" "T1: требование решения выдано"
assert_contains "$OUT" "docs/architecture.md" "T1b: назван конкретный документ"
assert_contains "$OUT" "doc-state:" "T1c: назван исполнимый исход (D111)"

# --- T2: КОНТРПРИМЕР — отметка в сообщении коммита снимает требование ---
reset_throttle
OUT2=$(run "git commit -m 'fix: правка. doc-state: не задето — поведение то же'")
assert_not_contains "$OUT2" "документ СОСТОЯНИЯ" "T2: отметка принята как решение"

# --- T3: КОНТРПРИМЕР — документ состояния в том же коммите снимает требование ---
reset_throttle
printf '# Архитектура\n\nМеханизм `hooks/thing.sh` делает по-новому.\n' > "$REPO/docs/architecture.md"
git -C "$REPO" add -A >/dev/null 2>&1
OUT3=$(run "git commit -m fix")
assert_not_contains "$OUT3" "документ СОСТОЯНИЯ" "T3: документ в коммите принят как решение"

# --- T4: КОНТРПРИМЕР — правка ТОЛЬКО комментария требования не вызывает ---
git -C "$REPO" commit -q -m sync >/dev/null 2>&1
reset_throttle
printf '#!/usr/bin/env bash\n# пояснение к поведению\necho new\n' > "$REPO/hooks/thing.sh"
git -C "$REPO" add -A >/dev/null 2>&1
OUT4=$(run "git commit -m docs")
assert_not_contains "$OUT4" "документ СОСТОЯНИЯ" "T4: правка комментария не требует решения"

# --- T5: журнал решений пишется — это знаменатель для замера ---
J=$(ls "$STATE"/doc-state-*.jsonl 2>/dev/null | head -1)
if [ -n "$J" ] && grep -q '"status":"undecided"' "$J"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: журнал решений пуст или без статуса: $(cat "$J" 2>/dev/null | head -c 200)"; fi
if [ -n "$J" ] && grep -q '"status":"decided"' "$J"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5b]: принятое решение в журнал не попало"; fi

# --- T6: замер читает журнал и называет долю ---
REPORT=$(STATE_DIR="$STATE" bash "$(cd "$(dirname "$0")/../.." && pwd)/scripts/doc-state-decisions.sh" 2>&1)
assert_contains "$REPORT" "без принятого решения" "T6: замер называет долю"

echo "doc state decision: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
