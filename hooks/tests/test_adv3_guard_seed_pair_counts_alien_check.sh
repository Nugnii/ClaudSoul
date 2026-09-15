#!/usr/bin/env bash
# АТАКА: улика «установка на машине есть» набирается сравнением, не касавшимся машины.
#
# Пара «seed знаний» засчитывает себе `regen-seed.py --check` как одно сравнение. Но
# этот скрипт сверяет РЕПОЗИТОРИЙ с `Path.home()/.claude/global-lessons` (константа
# WORKING в scripts/regen-seed.py, строка 32) — он не смотрит на $CLAUDE_HOME вовсе.
# Сравнение приёмника не касается, а `_checked_total` растёт, и следующие пары выносят
# по этой улике вердикт «установка на машине есть».
#
# Вход: машина ПОСЛЕ uninstall.sh. По договору «база знаний не удаляется никогда»,
# поэтому ~/.claude/global-lessons/ остаётся вместе с META.md и source-tiers.md, а
# всего остального нет.
# Ожидание: все девять пар ABSENT, код возврата 0 — снятой установки не бывает «с
# расхождением».
# Факт: пары 7-9 печатают DRIFT «установка на машине есть: уже сверено файлов 3»
# и код возврата 1 — тревога на верном состоянии.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }

TMP=$(mktemp -d)
H="$TMP/home"
# Ровно то, что uninstall.sh оставляет: база знаний и ничего больше.
mkdir -p "$H/global-lessons"
cp "$REPO"/knowledge/META.md "$H/global-lessons/" 2>/dev/null
cp "$REPO"/knowledge/source-tiers.md "$H/global-lessons/" 2>/dev/null

OUT=$(CLAUDSOUL_REPO="$REPO" CLAUDE_HOME="$H" bash "$DRIFT" 2>/dev/null)
RC=$?
DRIFTS=$(printf '%s\n' "$OUT" | grep -c '^DRIFT|' | tr -d '[:space:]')

printf '%s\n' "$OUT" | sed 's/^/  | /'
echo "  код возврата: $RC, пар с DRIFT: $DRIFTS"

if [ "${DRIFTS:-0}" -eq 0 ]; then
    echo "PASS: снятая установка названа отсутствием, а не расхождением"
    exit 0
fi
echo "FAIL: на машине БЕЗ установки (остался только каталог знаний, как его и оставляет"
echo "      uninstall.sh) $DRIFTS пар(ы) кричат «установка на машине есть»."
echo "      Улика взята из пары «seed знаний»: её сравнение — regen-seed.py --check —"
echo "      сверяет репозиторий с РЕАЛЬНЫМ \$HOME/.claude/global-lessons и \$CLAUDE_HOME"
echo "      не читает вовсе. Приёмник не сверялся ни разу, а счёт сверок вырос."
exit 1
