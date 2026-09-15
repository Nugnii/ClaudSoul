#!/usr/bin/env bash
# test_adv2_guard_reg_missing_is_silent.sh
#
# АТАКА: пара «регистрация хуков» сверяет только ЛИШНЕЕ и не видит ПРОПАВШЕГО.
#
# Направление сравнения этого файла объявлено в его шапке: «репозиторий → установленное».
# Цикл сверки идёт по `live` (`for name, evs in live.items()`), поэтому хук, объявленный в
# HOOKS_CONFIG и отсутствующий в settings.json, не попадает в сравнение вовсе. Такой хук
# лежит на диске побайтово верным (пара «хуки» — OK) и не срабатывает никогда.
#
# Вход: три хука объявлены в install.sh, файлы всех трёх установлены и совпадают,
# в settings.json зарегистрированы только два — gamma.sh не висит ни на одном событии.
# Ожидание: пара кричит — объявленная регистрация до машины не доехала.
# Факт: OK|регистрация хуков|2|0, код 0, «9 пар совпадают».
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
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"},
                                    {"type":"command","command":"bash ~/.claude/hooks/gamma.sh"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/beta.sh"}]}
    ]
  }
}'
INST

printf '#!/bin/sh\necho a\n'       > "$R/hooks/alpha.sh"
printf '#!/bin/sh\necho b\n'       > "$R/hooks/beta.sh"
printf '#!/bin/sh\necho g\n'       > "$R/hooks/gamma.sh"
printf 'lib\n'                     > "$R/hooks/lib/x.sh"
printf 'tmpl\n'                    > "$R/templates/a.tmpl"
printf '# rules\nтело правил\n'    > "$R/rules/CLAUDE.md"
printf 'meta\n'                    > "$R/knowledge/META.md"
printf 'skill\n'                   > "$SK/retro/SKILL.md"
printf '#!/bin/sh\necho sl\n'      > "$R/scripts/statusline-claudsoul.sh"
printf '#!/bin/sh\necho repo\n'    > "$R/bin/resolve-claudsoul-repo.sh"
printf 'import sys\nsys.exit(0)\n' > "$R/scripts/regen-seed.py"
cp "$MERGE" "$R/lib/claude-md-merge.sh"

cp "$R/hooks/alpha.sh" "$R/hooks/beta.sh" "$R/hooks/gamma.sh" "$H/hooks/"
cp "$R/hooks/lib/x.sh"   "$H/hooks/lib/x.sh"
cp "$R/templates/a.tmpl" "$H/templates/a.tmpl"
cp "$R/knowledge/META.md" "$H/global-lessons/META.md"
cp "$R/scripts/statusline-claudsoul.sh" "$H/statusline-claudsoul.sh"
cp "$R/bin/resolve-claudsoul-repo.sh"   "$H/bin/resolve-claudsoul-repo.sh"
mkdir -p "$H/commands/retro"; cp "$SK/retro/SKILL.md" "$H/commands/retro/SKILL.md"
# shellcheck source=/dev/null
. "$MERGE"
_cm_write_managed_block "$R/rules/CLAUDE.md" > "$H/CLAUDE.md"

# settings.json: gamma.sh не зарегистрирован НИГДЕ — хук на диске есть, не срабатывает никогда
cat > "$H/settings.json" <<'SET'
{"hooks":{
  "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}],
  "Stop":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/beta.sh"}]}]
}}
SET

OUT=$(CLAUDSOUL_REPO="$R" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1); RC=$?

fail=0
echo "--- вывод drift-check (код $RC) ---"
printf '%s\n' "$OUT" | sed "s|$T|<tmp>|g"
echo "--- в install.sh объявлено хуков: 3, в settings.json зарегистрировано: 2 (нет gamma.sh) ---"

if ! grep -q 'gamma' <<< "$OUT"; then
    echo "FAIL: gamma.sh объявлен в HOOKS_CONFIG, файл установлен и совпадает, а регистрации"
    echo "      нет ни на одном событии — хук не срабатывает никогда. В выводе он не назван."
    fail=1
fi
if grep -q '^OK|регистрация хуков|' <<< "$OUT"; then
    echo "FAIL: пара «регистрация хуков» — OK. Сверяются только ЛИШНИЕ регистрации,"
    echo "      пропавшая невидима, хотя направление сверки объявлено «репозиторий → установленное»."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: пропавшая регистрация названа"
exit "$fail"
