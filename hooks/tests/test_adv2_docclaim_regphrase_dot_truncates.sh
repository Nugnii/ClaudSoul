#!/usr/bin/env bash
# test_adv2_docclaim_regphrase_dot_truncates.sh
#
# АТАКА: фраза «Регистрация:» обрезается первой точкой, а точка есть в любом имени файла.
#
# Захват описан как `[Рр]егистрация:\s*([^.\n]*)`. Стоит написать «Регистрация: `hooks/x.sh`
# на Stop» — и в разбор уйдёт «`hooks/x` (до точки в «.sh»), события в куске нет,
# утверждение исчезает молча. Форма естественная: соседние доки пишут в этой фразе и имя,
# и событие.
#
# Вход: док alpha.md заявляет «Регистрация: `hooks/alpha.sh` на Stop», в install.sh
# alpha.sh висит на PreToolUse.
# Ожидание: расхождение названо, код 1.
# Факт: «проверено: 0», код 0. Контроль без имени файла в фразе — ловится.
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
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}
    ]
  }
}'
INST

cat > "$D/alpha.md" <<'DOC'
# alpha

**Файлы.** `hooks/alpha.sh` — страж.
Регистрация: `hooks/alpha.sh` на Stop, последним в группе
DOC
OUT=$(bash "$R/hooks/tests/test_module_doc_registration_claims.sh" 2>&1); RC=$?

cat > "$D/alpha.md" <<'DOC'
# alpha

**Файлы.** `hooks/alpha.sh` — страж.
Регистрация: Stop, последним в группе
DOC
CTL=$(bash "$R/hooks/tests/test_module_doc_registration_claims.sh" 2>&1); CRC=$?

fail=0
echo "--- имя файла во фразе (код $RC) ---"; printf '%s\n' "$OUT"
echo "--- контроль без имени файла (код $CRC) ---"; printf '%s\n' "$CTL"

if grep -q 'проверено: 0' <<< "$OUT"; then
    echo "FAIL: утверждение «Регистрация: \`hooks/alpha.sh\` на Stop» не извлечено — захват"
    echo "      оборвался на точке в имени файла. Заявлен Stop, в install.sh — PreToolUse."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0 при ложном утверждении."
    fail=1
fi
if [ "$CRC" -eq 0 ]; then
    echo "FAIL: контроль не сработал — то же утверждение без имени файла тоже не поймано."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: имя файла во фразе не прячет утверждение"
exit "$fail"
