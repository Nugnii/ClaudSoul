#!/usr/bin/env bash
# test_adv2_guard_reg_counts_foreign_hooks.sh
#
# АТАКА: счётчик пары «регистрация хуков» считает ЧУЖИЕ записи, и им же гасится правило
# «ноль сравнений — это BROKEN».
#
# В `REGPY` печатается `len(live)` — сколько хуков найдено в settings.json ВСЕГО, включая
# те, что тут же отбрасываются как чужие (`if name not in declared: continue`). Это число
# уходит в `_reg_n` и служит сразу двум целям: (1) ветка «ноль сравнённых записей — BROKEN»
# смотрит на него, (2) `_emit` прибавляет его к `_checked_total`, а run_all.sh печатает его
# как «сверено M файлов».
#
# Вход: settings.json, где висят три ЧУЖИХ хука и ни одного объявленного в install.sh
# (реальная форма: собеседник переписал блок hooks своими руками).
# Ожидание: BROKEN — сверить было нечего, ни одна наша регистрация не проверена.
# Факт: OK|регистрация хуков|3|0 — «сверено» три чужие записи, которые ни с чем не сравнивали.
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
         "$H/hooks/lib" "$H/commands" "$H/templates" "$H/global-lessons" "$H/bin" "$SK/retro"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
cp "$CLAUDSOUL_DIR/bin/resolve-claudsoul-repo.sh" "$CLAUDE_HOME/bin/resolve-claudsoul-repo.sh"
HOOKS_CONFIG='{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/beta.sh"}]}
    ]
  }
}'
INST

printf '#!/bin/sh\necho a\n'       > "$R/hooks/alpha.sh"
printf '#!/bin/sh\necho b\n'       > "$R/hooks/beta.sh"
printf 'lib\n'                     > "$R/hooks/lib/x.sh"
printf 'tmpl\n'                    > "$R/templates/a.tmpl"
printf '# rules\nтело правил\n'    > "$R/rules/CLAUDE.md"
printf 'meta\n'                    > "$R/knowledge/META.md"
printf 'skill\n'                   > "$SK/retro/SKILL.md"
printf '#!/bin/sh\necho sl\n'      > "$R/scripts/statusline-claudsoul.sh"
printf '#!/bin/sh\necho repo\n'    > "$R/bin/resolve-claudsoul-repo.sh"
printf 'import sys\nsys.exit(0)\n' > "$R/scripts/regen-seed.py"
cp "$MERGE" "$R/lib/claude-md-merge.sh"

cp "$R/hooks/alpha.sh" "$R/hooks/beta.sh" "$H/hooks/"
cp "$R/hooks/lib/x.sh"   "$H/hooks/lib/x.sh"
cp "$R/templates/a.tmpl" "$H/templates/a.tmpl"
cp "$R/knowledge/META.md" "$H/global-lessons/META.md"
cp "$R/scripts/statusline-claudsoul.sh" "$H/statusline-claudsoul.sh"
cp "$R/bin/resolve-claudsoul-repo.sh"   "$H/bin/resolve-claudsoul-repo.sh"
mkdir -p "$H/commands/retro"; cp "$SK/retro/SKILL.md" "$H/commands/retro/SKILL.md"
# shellcheck source=/dev/null
. "$MERGE"
_cm_write_managed_block "$R/rules/CLAUDE.md" > "$H/CLAUDE.md"

# Только чужие хуки: ни alpha.sh, ни beta.sh не зарегистрированы
cat > "$H/settings.json" <<'SET'
{"hooks":{"PreToolUse":[
  {"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/foreign-one.sh"}]},
  {"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/foreign-two.sh"}]},
  {"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/foreign-three.sh"}]}
]}}
SET

OUT=$(CLAUDSOUL_REPO="$R" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1); RC=$?
LINE=$(grep '|регистрация хуков|' <<< "$OUT")
NCHECK=$(cut -d'|' -f3 <<< "$LINE")
CHECKED=$(printf '%s\n' "$OUT" | awk -F'|' '{s += $3} END {print s + 0}')

fail=0
echo "--- вывод drift-check (код $RC) ---"
printf '%s\n' "$OUT" | sed "s|$T|<tmp>|g"
echo "--- строка пары: $LINE ---"
echo "--- «сверено файлов» по формуле run_all.sh: $CHECKED ---"

if [ "${NCHECK:-0}" -ne 0 ]; then
    echo "FAIL: пара насчитала $NCHECK сравнений, а наших регистраций в settings.json ноль:"
    echo "      счётчик показывает число ЧУЖИХ хуков (len(live)), ни один из них ни с чем"
    echo "      не сравнивали. Эти же $NCHECK уходят в «сверено $CHECKED файлов» у run_all.sh."
    fail=1
fi
if ! grep -q '^BROKEN|регистрация хуков|' <<< "$OUT"; then
    echo "FAIL: правило «ноль сравнённых записей — это BROKEN» не сработало: оно смотрит на"
    echo "      len(live), а не на число сверенных наших хуков, и гасится любым чужим хуком."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: чужие регистрации не считаются сверенными"
exit "$fail"
