#!/usr/bin/env bash
# АТАКА: приёмник исчезает из разбора, потому что косая стоит ВНЕ кавычек источника.
#
# Страж покрытия отсеивает доставки, у которых источник не из репозитория, признаком
#   "\$(?:CLAUDSOUL_DIR|REPO)/[^"]*"
# — косая ОБЯЗАНА стоять внутри кавычек. Форма `cp "$CLAUDSOUL_DIR"/domains/*.md ...`
# (кавычки вокруг переменной, глоб снаружи — так же написаны шесть настоящих строк
# самого install.sh: hooks/*.sh, hooks/lib/*, bin/*.sh, knowledge/*.md) признаку не
# отвечает. Строка отбрасывается ДО того, как из неё извлекут приёмник, и вторым
# проходом тоже: там тот же признак источника.
#
# Вход: копия install.sh с новым приёмником ~/.claude/domains/, наполняемым из
# репозитория; drift-check не тронут — пары для domains в нём нет.
# Ожидание: приёмник назван непокрытым ЛИБО строка названа неразобранной («покрытие
# по ней неизвестно») — страж объявляет, что молчания не будет.
# Факт: «приёмников install.sh: 7, непокрытых пар: 0», код возврата 0. Ни то ни другое.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_drift_pairs_cover_install.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

TMP=$(mktemp -d)
D="$TMP/repo"
mkdir -p "$D/hooks/tests"
cp "$REPO/install.sh" "$D/install.sh"
cp "$REPO/hooks/tests/drift-check.sh" "$D/hooks/tests/"
cp "$GUARD" "$D/hooks/tests/"

cat >> "$D/install.sh" <<'NEWRECEIVER'

# --- 10. Граф доменов ---
DOMAINS_TARGET="$CLAUDE_HOME/domains"
mkdir -p "$DOMAINS_TARGET"
cp "$CLAUDSOUL_DIR"/domains/*.md "$CLAUDE_HOME/domains/"
info "Установлено доменов"
NEWRECEIVER

OUT=$(bash "$D/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1)
RC=$?
printf '%s\n' "$OUT" | sed 's/^/  | /'
echo "  код возврата: $RC"

if grep -q 'domains' <<< "$OUT"; then
    echo "PASS: приёмник domains назван (непокрытым либо неразобранным)"
    exit 0
fi
echo "FAIL: install.sh наполняет ~/.claude/domains/ из репозитория, пары для него в"
echo "      drift-check нет, а страж покрытия не назвал его ни непокрытым, ни"
echo "      неразобранным — расхождение в этом каталоге даст молчание, неотличимое от OK."
echo "      Причина: признак источника требует косую ВНУТРИ кавычек"
echo "      (\"\$CLAUDSOUL_DIR/...\"), а доставка написана как \"\$CLAUDSOUL_DIR\"/domains/*.md."
exit 1
