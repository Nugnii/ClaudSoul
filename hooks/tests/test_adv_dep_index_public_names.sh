#!/usr/bin/env bash
# test_adv_dep_index_public_names.sh — «публичные имена» не видят двух живых форм
# объявления, и в РЕПОЗИТОРНОМ индексе это уже записано неправдой.
#
# Разбор имён — две строки регулярных выражений:
#   sh:  ^([a-z][a-z0-9_]*)\s*\(\)\s*\{     — форму `function имя() {` не берёт: `^`
#        цепляется за слово `function`, дальше ожидается `()`, а стоит имя.
#   py:  ^(?:def|class)\s+([A-Za-z]...)     — форму `async def имя(` не берёт вовсе.
#
# Живые последствия на момент написания:
#   mcp-server/server.py       — 10 объявлений `async def` (это и есть инструменты MCP,
#                                публичный контракт сервера), в индексе names ПУСТО.
#   hooks/knowledge-counter-bump.sh:176 — `function hist_entry() {`, в индексе имени нет.
# Значит ветка «новые публичные имена — учёт требует записи и на них» на этих файлах не
# сработает никогда: добавление нового инструмента MCP пройдёт мимо стража молча.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IDX="$REPO/.claude-docs/dep-index.tsv"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# --- A3a. Живой индекс: async def ---------------------------------------------------
if [ -f "$IDX" ] && [ -f "$REPO/mcp-server/server.py" ]; then
    N=$(grep -c '^async def ' "$REPO/mcp-server/server.py")
    NAMES=$(awk -F'\t' '$1=="mcp-server/server.py"{print $6}' "$IDX")
    FIRST=$(grep '^async def ' "$REPO/mcp-server/server.py" | head -1 | sed 's/^async def \([A-Za-z0-9_]*\).*/\1/')
    if [ "${N:-0}" -eq 0 ]; then
        echo "SKIP [A3a]: в server.py нет объявлений async def"
    elif grep -qF "$FIRST" <<< "$NAMES"; then
        ok "A3a индекс знает публичные имена mcp-server/server.py"
    else
        bad "A3a" "mcp-server/server.py объявляет $N инструментов через async def (первый — $FIRST),
      в индексе поле names = [${NAMES}]"
    fi
else
    echo "SKIP [A3a]: нет индекса или mcp-server/server.py"
fi

# --- A3b. Живой индекс: function имя() { --------------------------------------------
KCB="hooks/knowledge-counter-bump.sh"
if [ -f "$IDX" ] && [ -f "$REPO/$KCB" ]; then
    FN=$(grep -oE '^function [a-z][a-z0-9_]*' "$REPO/$KCB" | head -1 | awk '{print $2}')
    if [ -z "${FN:-}" ]; then
        echo "SKIP [A3b]: в $KCB нет формы 'function имя'"
    else
        NAMES=$(awk -F'\t' -v p="$KCB" '$1==p{print $6}' "$IDX")
        if grep -qF "$FN" <<< "$NAMES"; then
            ok "A3b индекс знает функцию, объявленную через ключевое слово function"
        else
            bad "A3b" "$KCB объявляет функцию $FN (форма 'function имя() {'),
      в индексе поле names = [${NAMES}] — имени нет"
        fi
    fi
else
    echo "SKIP [A3b]: нет индекса или $KCB"
fi

# --- A3c. Полная тишина стража на новом async-инструменте --------------------------
TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/mcp-server" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf 'import sys\n\n\nasync def old_tool():\n    pass\n' > "$R/mcp-server/srv.py"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )
printf 'import sys\n\n\nasync def old_tool():\n    pass\n\n\nasync def brand_new_tool():\n    pass\n' > "$R/mcp-server/srv.py"
git -C "$R" add mcp-server/srv.py >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact mcp-server/srv.py 2>&1 )
if grep -qF "brand_new_tool" <<< "$OUT"; then
    ok "A3c новый async-инструмент назван"
else
    bad "A3c" "в модуль без документов добавлен публичный async def brand_new_tool,
      отчёт --impact: [${OUT:-«ПУСТО, страж молчит целиком»}]"
fi

echo ""
echo "adv public-names-blind: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
