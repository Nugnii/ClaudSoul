#!/usr/bin/env bash
# test_adv2_guard_absent_ignores_prior_checks.sh
#
# АТАКА: ABSENT выдаётся без оглядки на то, сверила ли что-нибудь ПРЕЖНЯЯ пара.
#
# Правило: ABSENT означает «установки на машине нет» и допустим только когда все файлы
# пары отсутствуют И ни одна прежняя пара ничего не сверила. В `_cmp_tree` второе условие
# проверяется (`[ "$_checked_total" -gt 0 ]` → DRIFT), в `_classify` и в рукописных ветках
# пар «скиллы»/«bin»/«правила»/«seed»/«регистрация» — нет.
#
# Вход: машина, где установка ЕСТЬ и доказана (хуки, библиотеки, шаблоны, правила, seed,
# регистрация, статусная строка совпадают — сверено 8 файлов), но НЕ установлены ни один
# скилл (каталог commands/ есть, в нём только чужой скилл) и резолвер ~/.claude/bin.
#
# Ожидание: две пары кричат — установка на машине есть, а их содержимого нет; код ≠ 0.
# Факт: ABSENT «установка не выполнялась» + ABSENT «не установлено», код 0, и итоговая
# строка run_all.sh печатает «9 пар совпадают, сверено 8 файлов».
set -uo pipefail

REAL_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REAL_REPO/hooks/tests/drift-check.sh"
MERGE="$REAL_REPO/lib/claude-md-merge.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }
[ -f "$MERGE" ] || { echo "FAIL: нет $MERGE"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq      >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

T=$(mktemp -d)
R="$T/repo"; H="$T/home"; SK="$R/skills"
mkdir -p "$R/hooks/lib" "$R/templates" "$R/scripts" "$R/lib" "$R/rules" "$R/bin" "$R/knowledge" \
         "$H/hooks/lib" "$H/commands/foreign" "$H/templates" "$H/global-lessons"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
cp "$CLAUDSOUL_DIR/bin/resolve-claudsoul-repo.sh" "$CLAUDE_HOME/bin/resolve-claudsoul-repo.sh"
HOOKS_CONFIG='{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}
    ]
  }
}'
INST

printf '#!/bin/sh\necho a\n'      > "$R/hooks/alpha.sh"
printf 'lib\n'                    > "$R/hooks/lib/x.sh"
printf 'tmpl\n'                   > "$R/templates/a.tmpl"
printf '# rules\nтело правил\n'   > "$R/rules/CLAUDE.md"
printf 'meta\n'                   > "$R/knowledge/META.md"
printf '#!/bin/sh\necho sl\n'     > "$R/scripts/statusline-claudsoul.sh"
printf '#!/bin/sh\necho repo\n'   > "$R/bin/resolve-claudsoul-repo.sh"
printf 'import sys\nsys.exit(0)\n' > "$R/scripts/regen-seed.py"
cp "$MERGE" "$R/lib/claude-md-merge.sh"
for s in retro learn; do
    mkdir -p "$SK/$s"
    printf 'версия из репозитория\n' > "$SK/$s/SKILL.md"
done

# Установленная сторона: всё на месте, КРОМЕ скиллов и ~/.claude/bin
cp "$R/hooks/alpha.sh"  "$H/hooks/alpha.sh"
cp "$R/hooks/lib/x.sh"  "$H/hooks/lib/x.sh"
cp "$R/templates/a.tmpl" "$H/templates/a.tmpl"
cp "$R/knowledge/META.md" "$H/global-lessons/META.md"
cp "$R/scripts/statusline-claudsoul.sh" "$H/statusline-claudsoul.sh"
printf 'чужой скилл\n' > "$H/commands/foreign/SKILL.md"
# shellcheck source=/dev/null
. "$MERGE"
_cm_write_managed_block "$R/rules/CLAUDE.md" > "$H/CLAUDE.md"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}]}}' > "$H/settings.json"

OUT=$(CLAUDSOUL_REPO="$R" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1); RC=$?
# Та же арифметика, что в run_all.sh
CHECKED=$(printf '%s\n' "$OUT" | awk -F'|' '{s += $3} END {print s + 0}')
PAIRS=$(printf '%s\n' "$OUT" | grep -c '^[A-Z]*|')

fail=0
echo "--- вывод drift-check (код $RC) ---"
printf '%s\n' "$OUT" | sed "s|$T|<tmp>|g"
echo "--- сверено файлов (по формуле run_all.sh): $CHECKED, пар: $PAIRS ---"

if grep -q '^ABSENT|скиллы|' <<< "$OUT"; then
    echo "FAIL: пара «скиллы» — ABSENT «установка не выполнялась», хотя предыдущие пары"
    echo "      сверили файлы: установка на машине есть, а ни одного скилла в ней нет."
    fail=1
fi
if grep -q '^ABSENT|bin|' <<< "$OUT"; then
    echo "FAIL: пара «bin» — ABSENT «не установлено», хотя установка доказана 8 сверенными"
    echo "      файлами: резолвер репозитория отсутствует, и это молчание."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0 — «всё сошлось». Итоговая строка run_all.sh при таком выводе:"
    echo "      «$PAIRS пар «репозиторий ↔ установленное» совпадают, сверено $CHECKED файлов»"
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: ABSENT учитывает прежние сверки"
exit "$fail"
