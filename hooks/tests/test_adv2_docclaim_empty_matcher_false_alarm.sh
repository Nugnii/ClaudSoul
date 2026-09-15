#!/usr/bin/env bash
# test_adv2_docclaim_empty_matcher_false_alarm.sh
#
# АТАКА: хук, зарегистрированный на одном событии ДВАЖДЫ — с matcher и без него, — сверяется
# только по первому: `matchers_of()` отбрасывает пустой matcher (`if e == event and m`).
# Пустой matcher означает «на всех инструментах», то есть самый широкий случай выпадает из
# сверки, и верное утверждение дока объявляется расхождением.
#
# Аддитивное слияние install.sh умеет ДОБАВЛЯТЬ записи и не умеет удалять — шапка пары
# «регистрация хуков» в drift-check описывает ровно этот механизм на живом примере
# (`error-tracker` оказался зарегистрирован на двух событиях сразу). Две записи одного хука
# на одном событии — та же форма.
#
# Вход: alpha.sh висит на PreToolUse дважды: matcher "Bash" и matcher "" (все инструменты).
# Док пишет `PreToolUse[Read]` — и это ПРАВДА: вторая запись срабатывает на Read.
# Ожидание: расхождений нет, код 0.
# Факт: «заявлено matcher PreToolUse[Read]; в install.sh — PreToolUse[Bash]», код 1.
set -uo pipefail

REAL_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REAL_REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T=$(mktemp -d)
R="$T/repo"; D="$R/.claude-docs/modules"
mkdir -p "$R/hooks/tests" "$D"
cp "$GUARD" "$R/hooks/tests/"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
HOOKS_CONFIG='{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]},
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}
    ]
  }
}'
INST

cat > "$D/alpha.md" <<'DOC'
# alpha

**Файлы.** `hooks/alpha.sh` — считает прочитанное (PreToolUse[Read]).
DOC

OUT=$(bash "$R/hooks/tests/test_module_doc_registration_claims.sh" 2>&1); RC=$?

fail=0
echo "--- вывод стража (код $RC) ---"; printf '%s\n' "$OUT"
echo "--- в install.sh alpha.sh стоит на PreToolUse дважды: matcher \"Bash\" и matcher \"\" ---"

if grep -q 'matcher PreToolUse' <<< "$OUT"; then
    echo "FAIL: страж требует править ВЕРНЫЙ документ. Вторая запись — пустой matcher, то есть"
    echo "      все инструменты, Read в их числе: хук на Read срабатывает. Пустой matcher"
    echo "      выброшен из сверки условием if e == event and m, и самый широкий случай невидим."
    fail=1
fi
if [ "$RC" -ne 0 ]; then
    echo "FAIL: код возврата $RC на верном утверждении."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: пустой matcher учитывается при сверке"
exit "$fail"
