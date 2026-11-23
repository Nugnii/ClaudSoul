#!/usr/bin/env bash
# СУДИТ: scripts/dep-index.py
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
# Тело именованной секции отчёта: строки после заголовка до следующей строки с 0-й позиции.
sect() { awk -v h="$1" 'substr($0,1,length(h))==h{f=1;next} /^[^[:space:]]/{f=0} f'; }
die() { bad "$1" "$2"; echo ""; echo "adv plist-dependents: $PASS/$((PASS+FAIL)) passed"; exit 1; }

# --- повод на живом дереве (НЕ гейт) ------------------------------------------------
# Предполагалось: ссылки на .sh в живых launchd/*.plist — предпосылка проверки.
# Ложно дважды: предпосылка снималась с ЖИВОГО дерева, а предмет мерится на КОПИИ (пустой
# `launchd/` уводил в SKIP, ни разу не тронув копию), и SKIP отдавал код УСПЕХА.
# Держит: живое дерево осталось поводом и печатается, гейтом стала сама фикстура ниже.
HELD=$(grep -ho '[A-Za-z0-9_-]*\.sh' "$REPO"/launchd/*.plist 2>/dev/null | sort -u)
if [ -n "$HELD" ]; then
    echo "  повод (живое дерево): расписания launchd держат:"
    printf '%s\n' "$HELD" | sed 's/^/      · /'
else
    echo "  повод: в живом дереве ссылок на .sh в launchd/*.plist сейчас нет — проверяется устройство"
fi

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
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dep_index_plist_dependents.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dep_index_plist_dependents.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

# Фикстура собралась: расписание держит путь литералом, а учёт КОПИИ знает механизм.
# Без этого «зависимых нет» неотличимо от «индекс не собрался» — ровно то, что дала
# мутация read(): индекс не записан, строк нет, а нога зеленела.
grep -qF 'hooks/auto-scanner.sh' "$R/launchd/com.claudsoul.scanner.plist" \
  || die "фикстура" "расписание копии не держит литеральный путь механизма"
# Здесь тоже here-string, а не труба: `grep -q` в хвосте обрывает `cut` сигналом, и под
# pipefail утверждение краснеет от нагрузки, а не от предмета (D239).
INDEX_COL1=$(cut -f1 "$R/.claude-docs/dep-index.tsv" 2>/dev/null)
grep -qxF 'hooks/auto-scanner.sh' <<< "$INDEX_COL1" \
  || die "фикстура" "в учёте копии нет строки hooks/auto-scanner.sh — индекс не собрался"

printf '#!/usr/bin/env bash\nscan_all() { :; }\n# правка поведения\n' > "$R/hooks/auto-scanner.sh"
git -C "$R" add hooks/auto-scanner.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dep_index_plist_dependents.sh:$LINENO" >&2; exit 1; }
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/auto-scanner.sh 2>&1 )

# Предполагалось: имя plist'а где угодно в отчёте = носитель назван среди зависимых.
# Ложно: тем же именем отчёт называет НЕПРОЧИТАННОЕ («не прочитано: … com.claudsoul.
# scanner.plist»). Мутация read() (все чтения падают) оставляла ногу зелёной при том,
# что корпус носителей не читался вовсе.
# Держит: счёт в заголовке секции зависимых ≥ 1 и точное совпадение адреса в ЕЁ теле.
DEP_N=$(sed -n 's/^зависят от изменённого (\([0-9]*\)).*/\1/p' <<< "$OUT")
DEP_LIST=$(sect 'зависят от изменённого (' <<< "$OUT" | tr ',' '\n' | sed 's/^ *//;s/ *$//')
if [ "${DEP_N:-0}" -ge 1 ] && grep -qxF 'launchd/com.claudsoul.scanner.plist' <<< "$DEP_LIST"; then
    ok "A7 расписание launchd названо среди зависимых"
else
    bad "A7" "hooks/auto-scanner.sh изменён; launchd/com.claudsoul.scanner.plist держит его полным
      литеральным путём и сломается при переименовании — в отчёте его нет:
$(printf '%s\n' "$OUT" | sed 's/^/      /')"
fi

echo ""
echo "adv plist-dependents: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
