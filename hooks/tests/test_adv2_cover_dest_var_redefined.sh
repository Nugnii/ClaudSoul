#!/usr/bin/env bash
# test_adv2_cover_dest_var_redefined.sh
#
# АТАКА: переменная назначения, переопределённая ниже по файлу, переписывает приёмник у
# ВСЕХ доставок — включая те, что стояли выше и шли в другой каталог.
#
# `env` — плоский словарь, заполняемый одним проходом `re.finditer`; последнее присваивание
# затирает прежние, а `expand()` подставляет его во все строки файла независимо от порядка.
# Разбор ведётся текстом, но приписывается исполнению, у которого порядок есть.
#
# Вход: install.sh раскладывает `agents/` через `TARGET="$CLAUDE_HOME/agents"`, ниже
# переиспользует то же имя под `TARGET="$CLAUDE_HOME/hooks"`. Пара есть только у hooks.
# Ожидание: код 1 — приёмник `agents` без пары.
# Факт: «приёмников install.sh: 1» (только hooks), `agents` не назван вовсе, код 0.
set -uo pipefail

REAL_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REAL_REPO/hooks/tests/test_drift_pairs_cover_install.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T=$(mktemp -d)
R="$T/repo"; mkdir -p "$R/hooks/tests"
cp "$GUARD" "$R/hooks/tests/"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
CLAUDE_HOME="$HOME/.claude"

# --- субагенты ---
TARGET="$CLAUDE_HOME/agents"
mkdir -p "$TARGET"
for agent_file in "$CLAUDSOUL_DIR"/agents/*.md; do
    cp "$agent_file" "$TARGET/$(basename "$agent_file")"
done

# --- хуки: то же имя переменной переиспользовано ---
TARGET="$CLAUDE_HOME/hooks"
mkdir -p "$TARGET"
for hook_script in "$CLAUDSOUL_DIR"/hooks/*.sh; do
    cp "$hook_script" "$TARGET/$(basename "$hook_script")"
done
INST

cat > "$R/hooks/tests/drift-check.sh" <<'DRIFT'
#!/usr/bin/env bash
_cmp_tree "хуки" "$REPO/hooks" "$CLAUDE_HOME/hooks" "*.sh"
DRIFT

OUT=$(bash "$R/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1); RC=$?

fail=0
echo "--- вывод стража покрытия (код $RC) ---"
printf '%s\n' "$OUT"

if ! grep -q 'agents' <<< "$OUT"; then
    echo "FAIL: приёмник ~/.claude/agents не назван. Его доставка приписана каталогу hooks —"
    echo "      разбор взял ПОСЛЕДНЕЕ значение TARGET и подставил его в строку, стоящую выше."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0 при непокрытом приёмнике."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: переопределение переменной не прячет приёмник"
exit "$fail"
