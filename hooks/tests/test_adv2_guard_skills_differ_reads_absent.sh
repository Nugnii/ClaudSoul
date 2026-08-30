#!/usr/bin/env bash
# test_adv2_guard_skills_differ_reads_absent.sh
#
# АТАКА: «файла нет» и «файл есть, но другой» снова сложены в одно число — в ветке скиллов.
#
# В `_cmp_tree` эти два факта разведены (`_miss` отдельно от `_d`), и шапка drift-check
# описывает, чем платили за их слияние: «пара, где все файлы отличаются по содержимому,
# печаталась как „установка не выполнялась" — утверждение, опровергаемое `ls` того же
# каталога, и с кодом возврата 0». Ветка скиллов зовёт `_classify` пятью аргументами, и
# `_c_miss="${6:-$3}"` подставляет туда `_skill_d` — число РАЗОШЕДШИХСЯ. Правило разведения
# в неё не дошло; та самая «вторая копия классификации», о которой предупреждает шапка.
#
# Вход: три скилла установлены, все три файла на месте, содержимое у всех трёх другое
# (обычный дрейф: репозиторий поправили, install.sh не перезапускали).
# Ожидание: DRIFT на три файла.
# Факт: ABSENT «ни одного из 3 файлов в нём нет», код 0.
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
         "$H/hooks/lib" "$H/commands" "$H/templates" "$H/global-lessons" "$H/bin"

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

printf '#!/bin/sh\necho a\n'       > "$R/hooks/alpha.sh"
printf 'lib\n'                     > "$R/hooks/lib/x.sh"
printf 'tmpl\n'                    > "$R/templates/a.tmpl"
printf '# rules\nтело правил\n'    > "$R/rules/CLAUDE.md"
printf 'meta\n'                    > "$R/knowledge/META.md"
printf '#!/bin/sh\necho sl\n'      > "$R/scripts/statusline-claudsoul.sh"
printf '#!/bin/sh\necho repo\n'    > "$R/bin/resolve-claudsoul-repo.sh"
printf 'import sys\nsys.exit(0)\n' > "$R/scripts/regen-seed.py"
cp "$MERGE" "$R/lib/claude-md-merge.sh"

cp "$R/hooks/alpha.sh"   "$H/hooks/alpha.sh"
cp "$R/hooks/lib/x.sh"   "$H/hooks/lib/x.sh"
cp "$R/templates/a.tmpl" "$H/templates/a.tmpl"
cp "$R/knowledge/META.md" "$H/global-lessons/META.md"
cp "$R/scripts/statusline-claudsoul.sh" "$H/statusline-claudsoul.sh"
cp "$R/bin/resolve-claudsoul-repo.sh"   "$H/bin/resolve-claudsoul-repo.sh"
# shellcheck source=/dev/null
. "$MERGE"
_cm_write_managed_block "$R/rules/CLAUDE.md" > "$H/CLAUDE.md"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}]}}' > "$H/settings.json"

# Скиллы: УСТАНОВЛЕНЫ (файлы на месте), содержимое у всех другое
for s in retro learn knowledge; do
    mkdir -p "$SK/$s" "$H/commands/$s"
    printf 'новая версия из репозитория: %s\n' "$s" > "$SK/$s/SKILL.md"
    printf 'старая установленная версия: %s\n' "$s" > "$H/commands/$s/SKILL.md"
done

OUT=$(CLAUDSOUL_REPO="$R" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1); RC=$?
INSTALLED=$(ls "$H/commands"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')

fail=0
echo "--- вывод drift-check (код $RC) ---"
printf '%s\n' "$OUT" | sed "s|$T|<tmp>|g"
echo "--- в $H/commands лежит файлов SKILL.md: $INSTALLED ---"

if grep -q '^ABSENT|скиллы|' <<< "$OUT"; then
    echo "FAIL: пара «скиллы» утверждает «ни одного из 3 файлов в нём нет — установка не"
    echo "      выполнялась», а в каталоге лежат все $INSTALLED. Утверждение опровергается ls."
    fail=1
fi
if ! grep -q '^DRIFT|скиллы|3|3|' <<< "$OUT"; then
    echo "FAIL: ожидался DRIFT на 3 разошедшихся файла — его нет."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0 при трёх разошедшихся скиллах."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: разошедшиеся скиллы дают DRIFT"
exit "$fail"
