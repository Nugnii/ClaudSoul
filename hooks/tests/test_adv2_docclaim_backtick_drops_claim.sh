#!/usr/bin/env bash
# test_adv2_docclaim_backtick_drops_claim.sh
#
# АТАКА: одна обратная кавычка между именем хука и его скобкой стирает утверждение целиком.
#
# `PAREN = re.compile(r"`hooks/(...)`[^`\n]{0,80}?\(([^)\n]*)\)")` — промежуток между именем
# хука и открывающей скобкой описан классом `[^`\n]`, куда бэктик не входит. Модульные доки
# сплошь называют соседние файлы в бэктиках, и первый же такой упомянутый рядом файл рвёт
# связь «хук ↔ его скобка». Утверждение не проверяется и не называется: «проверено 0».
#
# Вход: док beta.md утверждает `PreToolUse[Bash]` у хука, который в install.sh висит на Stop,
# и по дороге упоминает в бэктиках библиотеку.
# Ожидание: расхождение названо, код 1.
# Факт: «утверждений о регистрации проверено: 0, расходятся: 0», код 0.
# Контроль: тот же док без бэктика — расхождение ловится.
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
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/beta.sh"}]}
    ]
  }
}'
INST

cat > "$D/beta.md" <<'DOC'
# beta — страж чего-нибудь

**Файлы.** `hooks/beta.sh` — считает признак, зовёт `hooks/lib/counter-lib.sh` (PreToolUse[Bash]).
DOC

OUT=$(bash "$R/hooks/tests/test_module_doc_registration_claims.sh" 2>&1); RC=$?

# Контроль: то же утверждение без бэктика в промежутке
cat > "$D/beta.md" <<'DOC'
# beta — страж чего-нибудь

**Файлы.** `hooks/beta.sh` — считает признак, зовёт вспомогательную библиотеку (PreToolUse[Bash]).
DOC
CTL=$(bash "$R/hooks/tests/test_module_doc_registration_claims.sh" 2>&1); CRC=$?

fail=0
echo "--- с бэктиком (код $RC) ---"; printf '%s\n' "$OUT"
echo "--- контроль без бэктика (код $CRC) ---"; printf '%s\n' "$CTL"

if grep -q 'проверено: 0' <<< "$OUT"; then
    echo "FAIL: утверждение не извлечено вовсе — «проверено: 0». Док заявляет PreToolUse[Bash]"
    echo "      у хука, который в install.sh висит на Stop, и это молчание."
    fail=1
fi
if [ "$RC" -eq 0 ]; then
    echo "FAIL: код возврата 0 при заведомо ложном утверждении в доке."
    fail=1
fi
if [ "$CRC" -eq 0 ]; then
    echo "FAIL: контроль не сработал — страж не ловит расхождение даже без бэктика."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: бэктик рядом не прячет утверждение"
exit "$fail"
