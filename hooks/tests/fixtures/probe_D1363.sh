#!/usr/bin/env bash
# СУДИТ: scripts/publish-public.sh scripts/publish/forbidden.txt
# probe_D1363.sh — образцы в тестах не роняют гейт открытого снимка.
#
# Повод (23 ноября 2026, D1363). Сухой прогон публикации 1.37.0 остановил гейт на трёх строках `hooks/tests/`: полный
# идентификатор настоящей сессии владельца, образец ключа AWS вне разрешённых и адрес на `example.invalid`. Гейт судит
# снимок раз в публикацию, образцы копились два месяца. Здесь — те же правила, взятые у их владельцев, над файлами
# `hooks/tests/`, как они уйдут в снимок: перечень запретов `scripts/publish/forbidden.txt` (прочитан так, как читает
# гейт), чистка `scripts/publish/redact.sed` до гейта, разрешающие перечни `TOKEN_ALLOW` и `EMAIL_ALLOW` из
# `scripts/publish-public.sh`; исключённый из снимка `test_publish_public.sh` не судится.
# Проверка результата: bash hooks/tests/fixtures/probe_D1363.sh → 0 — ни одного совпадения вне разрешённого;
#   1 — есть (названы); 2 — не измерено (нет git, перечня, чистки или разрешающих перечней).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
F="$REPO/scripts/publish/forbidden.txt"; R="$REPO/scripts/publish/redact.sed"; P="$REPO/scripts/publish-public.sh"
command -v git >/dev/null 2>&1 && [ -f "$F" ] && [ -f "$R" ] && [ -f "$P" ] \
    || { echo "нет git, перечня, чистки или публикатора — не измерено"; exit 2; }
A=$(sed -n "s/^TOKEN_ALLOW='\(.*\)'\$/\1/p" "$P" | head -1)
M=$(sed -n "s/^EMAIL_ALLOW='\(.*\)'\$/\1/p" "$P" | head -1)
[ -n "$A" ] && [ -n "$M" ] || { echo "разрешающие перечни публикатора не прочитаны — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
while IFS= read -r pat; do
    pat="${pat%%#*}"; pat="$(printf '%s' "$pat" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
    [ -n "$pat" ] && printf '%s\n' "$pat"
done < "$F" > "$W/pats"
[ -s "$W/pats" ] || { echo "перечень гейта пуст — не измерено"; exit 2; }
# Снимок каталога тестов: отслеживаемые файлы, через ту же чистку, что у публикатора.
mkdir -p "$W/s"
( cd "$REPO" && git ls-files -z hooks/tests ) | while IFS= read -r -d '' f; do
    [ "$f" = hooks/tests/test_publish_public.sh ] && continue
    [ -f "$REPO/$f" ] || continue
    mkdir -p "$W/s/${f%/*}" && sed -f "$R" "$REPO/$f" > "$W/s/$f" 2>/dev/null || cp "$REPO/$f" "$W/s/$f"
done
[ -d "$W/s/hooks/tests" ] || { echo "каталог тестов не собран — не измерено"; exit 2; }
HITS=$( { LC_ALL=C grep -raEn -f "$W/pats" "$W/s" 2>/dev/null | LC_ALL=C grep -avE "$A"
          LC_ALL=C grep -raEno "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" "$W/s" 2>/dev/null | grep -vE "$M"; } \
        | sed -E "s|^$W/s/||; s|^([^:]*:[0-9]+):.*|\1|" | sort -u)
if [ -n "$HITS" ]; then echo "гейт снимка отверг бы:"; printf '  %s\n' $HITS; exit 1; fi
echo "образцы в тестах гейт снимка пропускает"
