#!/usr/bin/env bash
# test_adv2_guard_clean_machine_false_drift.sh
#
# АТАКА: на машине, где ClaudSoul НЕ установлен, две пары кричат DRIFT — потому что
# признаком «установка на машине есть» служит `_checked_total`, а его надувают чужие хуки.
#
# `_cmp_tree` и пара «статусная строка» отличают «не установлено» от «пропало» по
# `_checked_total > 0`. Пара «регистрация хуков» прибавляет к этому счётчику `len(live)` —
# число хуков в settings.json, включая чужие, ни с чем не сравнивавшиеся. Достаточно, чтобы
# у собеседника был свой хук, и стоящие ПОСЛЕ пары начинают утверждать обратное тому, что есть.
#
# Вход: чистая машина — в ~/.claude только settings.json с двумя своими хуками собеседника.
# Ожидание: девять ABSENT, код 0 («установки нет — сверять не с чем»).
# Факт: DRIFT на парах «шаблоны» и «статусная строка» с текстом «хотя установка на машине
# есть (уже сверено файлов: 2)», код 1.
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
# Каталоги-источники ВЫВОДЯТСЯ из самого сверщика, а не перечисляются (10 сентября 2026).
# Перечень отставал от пар: пара «сторож секретов» появилась, `security` в mkdir не дописали,
# и `_cmp_tree` честно объявил BROKEN «нет каталога-источника» — на чистой машине, где
# ожидаются одни ABSENT. Дефект не в сверщике: вердикт верен, неверна была фикстура,
# перечислявшая структуру вместо того, чтобы брать её у мира
# (`pattern-fixture-form-not-taken-from-the-world`). Теперь новая пара подхватывается сама.
# Берутся только КАТАЛОГИ: путь, чей последний сегмент содержит точку, — файл, и создавать
# его каталогом нельзя. Первая редакция этого не различала и делала каталог `install.sh`,
# после чего фикстура падала на «Is a directory» — прибор, построенный наспех, дал
# правдоподобный ложный результат ровно того рода, ради которого пишется.
# Берутся только КАТАЛОГИ — пути без точки в имени. Путь с точкой это ФАЙЛ, и создавать
# его каталогом нельзя: первая редакция этого не различала, делала каталог `install.sh`,
# и фикстура падала на «Is a directory». Каталоги файлов (`scripts/regen-seed.py`) сюда
# не нужны — они уже созданы строкой ниже.
_src_dirs=$(grep -oE '"\$REPO/[A-Za-z0-9_/.-]+"' "$DRIFT" 2>/dev/null \
            | tr -d '"' | sed 's|^\$REPO/||' | grep -v '\.' | sort -u)
mkdir -p "$R/hooks/lib" "$R/templates" "$R/scripts" "$R/lib" "$R/rules" "$R/bin" "$R/knowledge" \
         "$SK/retro" "$H"
for _d in $_src_dirs; do mkdir -p "$R/$_d" 2>/dev/null || true; done

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
printf '# rules\n'                 > "$R/rules/CLAUDE.md"
printf 'meta\n'                    > "$R/knowledge/META.md"
printf 'skill\n'                   > "$SK/retro/SKILL.md"
printf '#!/bin/sh\necho sl\n'      > "$R/scripts/statusline-claudsoul.sh"
printf '#!/bin/sh\necho repo\n'    > "$R/bin/resolve-claudsoul-repo.sh"
printf 'import sys\nsys.exit(0)\n' > "$R/scripts/regen-seed.py"
cp "$MERGE" "$R/lib/claude-md-merge.sh"

# Машина чистая: ClaudSoul не ставили ни разу, свои хуки у собеседника уже есть
cat > "$H/settings.json" <<'SET'
{"hooks":{"PreToolUse":[
  {"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/my-own-guard.sh"}]},
  {"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/my-own-logger.sh"}]}
]}}
SET

OUT=$(CLAUDSOUL_REPO="$R" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1); RC=$?
INSTALLED=$(ls -A "$H" | tr '\n' ' ')

fail=0
echo "--- вывод drift-check (код $RC) ---"
printf '%s\n' "$OUT" | sed "s|$T|<tmp>|g"
echo "--- содержимое ~/.claude на этой машине: $INSTALLED ---"

if grep -q '^DRIFT|шаблоны|' <<< "$OUT" || grep -q '^DRIFT|статусная строка|' <<< "$OUT"; then
    echo "FAIL: DRIFT «приёмник отсутствует, хотя установка на машине есть» — установки нет,"
    echo "      в ~/.claude лежит только settings.json с ЧУЖИМИ хуками. Признак «установка"
    echo "      есть» надут счётчиком пары регистрации."
    fail=1
fi
if [ "$RC" -ne 0 ]; then
    echo "FAIL: код возврата $RC на машине без установки — ожидался 0 (все пары ABSENT)."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: чистая машина не даёт DRIFT"
exit "$fail"
