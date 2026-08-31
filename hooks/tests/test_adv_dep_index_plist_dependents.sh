#!/usr/bin/env bash
# test_adv_dep_index_plist_dependents.sh — зависимый, который не .sh и не .py, не
# существует для учёта: три расписания launchd держат хуки по полному имени, и ни
# одно из них страж не назовёт никогда.
#
# Механика. `rev` строится только из строк индекса, а строка заводится только на
# механизм (MECH_RE = \.(sh|py)$). Файл другого расширения не может оказаться в
# `dependents` ни при каком содержимом — даже когда имя механизма записано в нём
# ЛИТЕРАЛОМ, целиком, без всякой сборки пути в переменной. Объявленный в шапке
# indexer'а предел («путь, собранный по частям, не опознаётся») этот случай НЕ
# покрывает: здесь путь литеральный, не опознан носитель.
#
# Живая предпосылка: launchd/com.claudsoul.*.plist держат
#   __HOME__/.claude/hooks/auto-scanner.sh
#   __HOME__/.claude/hooks/bridge-health-digest.sh
#   __HOME__/.claude/hooks/knowledge-audit-digest.sh
# Переименуй или перенеси такой хук — расписание молча перестанет запускаться
# (launchd не жалуется в диалог), а страж на коммите об этом не скажет: в его отчёте
# для auto-scanner.sh перечислены документы и зависимые механизмы, plist'а среди них
# нет по устройству.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# --- предпосылка на живом дереве ---------------------------------------------------
HELD=$(grep -ho '[A-Za-z0-9_-]*\.sh' "$REPO"/launchd/*.plist 2>/dev/null | sort -u)
[ -n "$HELD" ] || { echo "SKIP: в launchd/*.plist нет ссылок на .sh"; exit 0; }
echo "  предпосылка (живое дерево): расписания launchd держат:"
printf '%s\n' "$HELD" | sed 's/^/      · /'

# --- воспроизведение на копии устройства -------------------------------------------
TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/docs" "$R/launchd" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nscan_all() { :; }\n' > "$R/hooks/auto-scanner.sh"
printf '# Док\n\nМеханизм auto-scanner описан.\n' > "$R/docs/manual.md"
cat > "$R/launchd/com.claudsoul.scanner.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>__HOME__/.claude/hooks/auto-scanner.sh</string>
  </array>
</dict></plist>
PL
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\nscan_all() { :; }\n# правка поведения\n' > "$R/hooks/auto-scanner.sh"
git -C "$R" add hooks/auto-scanner.sh >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/auto-scanner.sh 2>&1 )

if grep -qF "com.claudsoul.scanner.plist" <<< "$OUT"; then
    ok "A7 расписание launchd названо среди зависимых"
else
    bad "A7" "hooks/auto-scanner.sh изменён; launchd/com.claudsoul.scanner.plist держит его полным
      литеральным путём и сломается при переименовании — в отчёте его нет:
$(printf '%s\n' "$OUT" | sed 's/^/      /')"
fi

echo ""
echo "adv plist-dependents: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
