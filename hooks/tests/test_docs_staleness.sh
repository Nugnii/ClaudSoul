#!/usr/bin/env bash
# test_docs_staleness.sh — документ старше механизма без решения назван; с решением — нет.
#
# Результат: пара «документ ← механизм» попадает в находки, только когда механизм менялся
#            позже документа И в том коммите нет ни документа, ни решения doc-state; правки
#            механизма до появления требования решения не считаются
# Проверка результата: bash hooks/tests/test_docs_staleness.sh даёт 0
#
# Повод (30 августа 2026): владелец — «остальная документация это не только README, но и
# файлы модулей, хуков, скриптов». Числа держит реестр утверждений; описаниям поведения
# остаётся возраст.
# КОНТРПРИМЕРЫ: документ в том же коммите → тишина; решение doc-state в коммите → тишина;
# правка механизма до отсечки → тишина; индекса нет → код 0 и слово об этом.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/docs-staleness.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 250)"; fi
}
assert_empty() {
    if [ -z "${1//[[:space:]]/}" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина: $(printf '%s' "$1" | head -c 200)"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
commit() { git -C "$R" add -A >/dev/null; GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git -C "$R" commit -q -m "$2" --date "$1"; }
printf '# doc\nописывает hooks/m.sh\n' > "$R/docs/m.md"; printf 'echo 1\n' > "$R/hooks/m.sh"
commit "2026-08-01T10:00:00" "seed"
# отсечка: страж с требованием решения появляется в отдельном коммите
printf '# doc-state:\n' > "$R/hooks/doc-impact-check.sh"; commit "2026-08-10T10:00:00" "feat: doc-impact-check с doc-state:"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/m.sh\tx\t\tdocs/m.md\t\t\n' > "$R/.claude-docs/dep-index.tsv"
run() { CLAUDSOUL_REPO="$R" bash "$SCRIPT" 2>&1; }

# --- T1: документ свежее механизма → тишина, код 0 ---
OUT=$(run); RC=$?
[ "$RC" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1]: свежий док дал $RC: $OUT"; }

# --- T2: механизм изменён позже без решения → находка, код 1 ---
printf 'echo 2\n' > "$R/hooks/m.sh"; commit "2026-08-20T10:00:00" "fix: поведение m"
OUT2=$(run); RC2=$?
assert_contains "$OUT2" "docs/m.md ← hooks/m.sh" "T2: пара названа"
[ "$RC2" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2b]: находка не сообщена кодом: $RC2"; }

# --- T3: КОНТРПРИМЕР — решение doc-state в коммите → тишина ---
printf 'echo 3\n' > "$R/hooks/m.sh"; commit "2026-08-21T10:00:00" "fix: ещё

doc-state: не задето — комментарий"
OUT3=$(run); RC3=$?
[ "$RC3" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T3]: решение в коммите не признано: $OUT3"; }
assert_contains "$OUT3" "старше с решением doc-state 1" "T3b: пара с решением посчитана отдельно"

# --- T4: КОНТРПРИМЕР — документ в том же коммите → тишина ---
printf 'echo 4\n' > "$R/hooks/m.sh"; printf '# doc\nописывает hooks/m.sh v4\n' > "$R/docs/m.md"; commit "2026-08-22T10:00:00" "fix: с доком"
OUT4=$(run); RC4=$?
[ "$RC4" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4]: док в том же коммите принят за устаревший: $OUT4"; }

# --- T5: КОНТРПРИМЕР — правка механизма ДО отсечки не считается ---
R2="$TMP/repo2"; mkdir -p "$R2/hooks" "$R2/docs" "$R2/.claude-docs"
git -C "$R2" init -q; git -C "$R2" config user.email t@t.local; git -C "$R2" config user.name t
printf '# doc\n' > "$R2/docs/m.md"; printf 'echo 1\n' > "$R2/hooks/m.sh"; git -C "$R2" add -A >/dev/null
GIT_COMMITTER_DATE="2026-08-01T10:00:00" git -C "$R2" commit -q -m seed --date "2026-08-01T10:00:00"
printf 'echo 2\n' > "$R2/hooks/m.sh"; git -C "$R2" add -A >/dev/null
GIT_COMMITTER_DATE="2026-08-05T10:00:00" git -C "$R2" commit -q -m "fix: до отсечки" --date "2026-08-05T10:00:00"
printf '# doc-state:\n' > "$R2/hooks/doc-impact-check.sh"; git -C "$R2" add -A >/dev/null
GIT_COMMITTER_DATE="2026-08-10T10:00:00" git -C "$R2" commit -q -m "feat: doc-state:" --date "2026-08-10T10:00:00"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/m.sh\tx\t\tdocs/m.md\t\t\n' > "$R2/.claude-docs/dep-index.tsv"
OUT5=$(CLAUDSOUL_REPO="$R2" bash "$SCRIPT" 2>&1); RC5=$?
[ "$RC5" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5]: правка до отсечки засчитана: $OUT5"; }
assert_contains "$OUT5" "до D209 (разовый аудит) 1" "T5b: правка до отсечки посчитана отдельно"

# --- T6: КОНТРПРИМЕР — индекса нет → код 0 и слово об этом ---
OUT6=$(CLAUDSOUL_REPO="$R" DEP_INDEX_FILE="$TMP/none.tsv" bash "$SCRIPT" 2>&1); RC6=$?
assert_contains "$OUT6" "нет индекса" "T6: отсутствие индекса названо"
[ "$RC6" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6b]: без индекса код $RC6"; }

echo "docs staleness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
