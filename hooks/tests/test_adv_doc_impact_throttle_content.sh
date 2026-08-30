#!/usr/bin/env bash
# test_adv_doc_impact_throttle_content.sh — троттл ключуется НАБОРОМ ИМЁН staged, а не
# содержимым правки: вторая правка тех же файлов молчит, даже когда отчёт стал другим.
#
# Механика. KEY = md5 от вывода `git diff --cached --name-only`. Имена те же — ключ тот
# же — `exit 0` до вызова индексатора. Между двумя коммитами содержимое файла меняется
# как угодно: появляется новое публичное имя, ломается поведение, переписывается модуль.
#
# Почему достижимо в обычной работе, а не в вывернутом сценарии: первый коммит редко
# уходит с первого раза. Правило проекта — «одно изменение, один коммит»: правишь тот же
# файл, пересобираешь, коммитишь снова. Набор staged при этом не меняется по определению.
# Первый прогон в сессии съедает право стража высказаться про ВСЕ последующие состояния
# этого набора.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/doc-impact-check.sh"
INDEXER="$REPO/scripts/dep-index.py"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n' > "$R/hooks/alpha.sh"
printf '# Док\n\nМеханизм alpha описан.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

run() { jq -cn --arg c "git commit -m x" --arg d "$R" --arg s "$1" \
          '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:$s}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# --- попытка 1: косметическая правка, набор staged = {hooks/alpha.sh} --------------
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n# опечатка поправлена\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1
FIRST=$(run sess1)
[ -n "$FIRST" ] || { echo "SKIP: страж промолчал уже на первой попытке — предпосылки нет"; exit 0; }

# --- попытка 2: тот же файл, НОВОЕ публичное имя ------------------------------------
printf '#!/usr/bin/env bash\nfoo_one() { :; }\nbrand_new_api() { echo НОВОЕ; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1
SECOND=$(run sess1)
DIRECT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/alpha.sh 2>&1 )

if grep -qF "brand_new_api" <<< "$DIRECT"; then
    echo "  предпосылка: сам --impact новое имя видит:"
    printf '%s\n' "$DIRECT" | sed 's/^/      /'
else
    echo "SKIP: --impact не увидел brand_new_api — предмет проверки другой"; exit 0
fi

if grep -qF "brand_new_api" <<< "$SECOND"; then
    ok "A2 страж назвал новое публичное имя во второй правке того же набора"
else
    bad "A2" "вторая правка набора {hooks/alpha.sh} добавила публичное имя brand_new_api,
      страж выдал: [${SECOND:-«ТИШИНА»}]
      причина: ключ троттла — md5 от имён staged, содержимое в него не входит"
fi

echo ""
echo "adv throttle-by-nameset: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
