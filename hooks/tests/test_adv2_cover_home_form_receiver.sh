#!/usr/bin/env bash
# test_adv2_cover_home_form_receiver.sh
#
# АТАКА: приёмник, записанный не через `$CLAUDE_HOME`, а через `$HOME/.claude` или `~`,
# не попадает НИ в приёмники, НИ в «не разобрано». Полное молчание.
#
# Разбор `expand()` знает подстановку `$HOME/.claude → $CLAUDE_HOME` только для ПРИСВАИВАНИЙ
# (`^([A-Z_]+)="(\$(?:CLAUDE_HOME|HOME)/...)"`). Путь, написанный в самой команде доставки,
# через неё не проходит: `dst.startswith("$CLAUDE_HOME/")` ложно → `continue`. Страховочный
# проход, который обязан НАЗВАТЬ неразобранное, ищет в строке буквальные имена
# `$CLAUDE_HOME|$GLOBAL_LESSONS|$SKILLS_DIR|$HOOKS_TARGET|$TEMPLATES_TARGET` — перечень имён,
# то есть ровно та эвристика по форме, против которой заведён сам страж.
#
# Вход: install.sh раскладывает `agents/` двумя обычными формами — `"$HOME/.claude/agents/..."`
# и `~/.claude/agents/...`; пары для agents в drift-check нет.
# Ожидание: код 1 — либо «непокрытый приёмник agents», либо «строка не разобрана».
# Факт: «приёмников install.sh: 1, непокрытых пар: 0», код 0.
set -uo pipefail

REAL_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REAL_REPO/hooks/tests/test_drift_pairs_cover_install.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T=$(mktemp -d)
R="$T/repo"; mkdir -p "$R/hooks/tests"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
CLAUDE_HOME="$HOME/.claude"
HOOKS_TARGET="$CLAUDE_HOME/hooks"
for hook_script in "$CLAUDSOUL_DIR"/hooks/*.sh; do
    cp "$hook_script" "$HOOKS_TARGET/$(basename "$hook_script")"
done

# --- субагенты: доставка написана через $HOME и через ~ ---
mkdir -p "$HOME/.claude/agents"
cp "$CLAUDSOUL_DIR/agents/reviewer.md" "$HOME/.claude/agents/reviewer.md"
cp "$CLAUDSOUL_DIR/agents/planner.md" ~/.claude/agents/planner.md
INST

cat > "$R/hooks/tests/drift-check.sh" <<'DRIFT'
#!/usr/bin/env bash
_cmp_tree "хуки" "$REPO/hooks" "$CLAUDE_HOME/hooks" "*.sh"
DRIFT

cp "$GUARD" "$R/hooks/tests/"
OUT=$(bash "$R/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1); RC=$?

fail=0
echo "--- вывод стража покрытия (код $RC) ---"
printf '%s\n' "$OUT"

if ! grep -q 'agents' <<< "$OUT"; then
    echo "FAIL: приёмник ~/.claude/agents не назван ни как непокрытый, ни как неразобранный."
    echo "      Он наполняется ИЗ репозитория, пары в drift-check у него нет — расхождение"
    echo "      в нём дало бы молчание, неотличимое от OK. Ровно то, что страж обязан ловить."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: приёмник через \$HOME/~ виден стражу"
exit "$fail"
