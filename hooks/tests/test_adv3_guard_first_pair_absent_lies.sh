#!/usr/bin/env bash
# АТАКА: первая пара объявляет машину неустановленной, глядя только НАЗАД.
#
# `_absent_or_drift` и ветка ABSENT в `_classify` опираются на `_checked_total` —
# сколько файлов сверили ПРЕЖНИЕ пары. У первой пары прежних нет, поэтому её улика
# всегда равна нулю, и вердикт ABSENT («установка не выполнялась») выносится, даже
# когда восемь строк НИЖЕ в том же выводе показывают 48 сверенных файлов.
#
# Вход: полная установка ClaudSoul, из которой вычищены все hooks/*.sh (каталог
# ~/.claude/hooks/ есть, lib/ на месте, файлов хуков нет). Ровно то состояние, в
# котором система не работает целиком.
# Ожидание: DRIFT — 83 файла приёмника отсутствуют на установленной машине.
# Факт: ABSENT|хуки|0|0 и код возврата 0 — «всё OK/ABSENT».
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

TMP=$(mktemp -d)
H="$TMP/home"
SRC_SKILLS="$REPO/skills"
DST_SKILLS="$H/commands"

mkdir -p "$H/hooks/lib" "$DST_SKILLS" "$H/bin" "$H/templates" "$H/global-lessons"
cp "$REPO"/hooks/lib/* "$H/hooks/lib/" 2>/dev/null
cp "$REPO"/bin/*.sh "$H/bin/" 2>/dev/null
cp "$REPO"/templates/*.tmpl "$H/templates/" 2>/dev/null
cp "$REPO"/knowledge/META.md "$H/global-lessons/" 2>/dev/null
cp "$REPO"/knowledge/source-tiers.md "$H/global-lessons/" 2>/dev/null
cp "$REPO"/scripts/statusline-claudsoul.sh "$H/statusline-claudsoul.sh" 2>/dev/null
for _d in "$SRC_SKILLS"/*/ ; do
    [ -d "$_d" ] || continue
    _n=$(basename "$_d")
    mkdir -p "$DST_SKILLS/$_n"
    cp "$_d/SKILL.md" "$DST_SKILLS/$_n/SKILL.md" 2>/dev/null
    if [ -d "$_d/references" ]; then
        mkdir -p "$DST_SKILLS/$_n/references"
        cp "$_d"/references/*.md "$DST_SKILLS/$_n/references/" 2>/dev/null
    fi
done
# Правила: ровно тот блок, который пишет install.sh.
# shellcheck source=/dev/null
. "$REPO/lib/claude-md-merge.sh"
_cm_write_managed_block "$REPO/rules/CLAUDE.md" > "$H/CLAUDE.md"
# Регистрация: побайтовая копия HOOKS_CONFIG — все 50 хуков на своих событиях.
python3 - "$REPO/install.sh" "$H/settings.json" <<'PY'
import json, pathlib, re, sys
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S)
pathlib.Path(sys.argv[2]).write_text(json.dumps(json.loads(m.group(1)), ensure_ascii=False, indent=2))
PY

# ЕДИНСТВЕННОЕ отличие от здоровой машины: hooks/*.sh не установлены.
OUT=$(CLAUDSOUL_REPO="$REPO" CLAUDE_HOME="$H" bash "$DRIFT" 2>/dev/null)
RC=$?

# Сколько файлов сверили ОСТАЛЬНЫЕ пары того же вывода — это и есть улика,
# опровергающая «установка не выполнялась».
OTHERS=$(printf '%s\n' "$OUT" | awk -F'|' '$2 != "хуки" {s += $3} END {print s + 0}')

FAIL=0
if grep -q '^ABSENT|хуки|' <<< "$OUT" && [ "$OTHERS" -gt 0 ]; then
    FAIL=1
    echo "FAIL: пара «хуки» вынесла ABSENT («установка не выполнялась»), а соседние пары"
    echo "      того же вывода сверили $OTHERS файлов — установка на машине есть."
fi
if [ "$RC" -eq 0 ]; then
    FAIL=1
    echo "FAIL: код возврата 0 при полностью вычищенном ~/.claude/hooks/ — ни DRIFT, ни BROKEN."
fi
printf '%s\n' "$OUT" | sed 's/^/  | /'
echo "  код возврата: $RC, сверено соседними парами: $OTHERS"
[ "$FAIL" -eq 0 ] && echo "PASS: вычищенные хуки названы расхождением"
[ "$FAIL" -eq 0 ]
