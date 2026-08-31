#!/usr/bin/env bash
# test_adv_doc_impact_space_path.sh — пробел в имени staged-файла: `xargs` делит слово,
# страж теряет настоящий файл и выдумывает несуществующий.
#
# Механика. Хук передаёт список файлов так:
#     printf '%s\n' "$STAGED" | xargs python3 "$INDEXER" --impact
# `xargs` без `-0`/`-d` делит вход по ЛЮБОМУ пробельному, а не по переводу строки.
# `hooks/data lib.sh` приходит в indexer двумя аргументами: `hooks/data` и `lib.sh`.
# Дальше:
#   · `hooks/data lib.sh` нет среди changed → его документы не названы;
#   · его новое публичное имя не названо;
#   · `lib.sh` подходит под MECH_RE и не найден в индексе → печатается «новый механизм
#     lib.sh — нужен документ и пересборка индекса» про файл, которого не существует.
#
# Достижимость: на 157 путей под учётом сегодня ни одного с пробелом, то есть заряд
# лежит, но не выстрелил. Стреляет он первым же добавленным путём с пробелом; ничто в
# дереве этого не запрещает и ни один страж на это не смотрит.
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
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n' > "$R/hooks/data lib.sh"
printf '# Док\n\nМеханизм «data lib» описан тут.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\nfoo_one() { :; }\nnew_behaviour() { :; }\n' > "$R/hooks/data lib.sh"
git -C "$R" add -A >/dev/null 2>&1

DIRECT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact "hooks/data lib.sh" 2>&1 )
grep -qF "docs/manual.md" <<< "$DIRECT" || { echo "SKIP: сам --impact документ не поднял — предпосылки нет"; exit 0; }
echo "  предпосылка: при правильной передаче аргумента --impact отвечает:"
printf '%s\n' "$DIRECT" | sed 's/^/      /'

HOUT=$(jq -cn --arg c "git commit -m x" --arg d "$R" --arg s s1 \
         '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:$s}' \
       | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null \
       | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

if grep -qF "docs/manual.md" <<< "$HOUT"; then
    ok "A5a хук назвал документ файла с пробелом"
else
    bad "A5a" "изменён hooks/data lib.sh, docs/manual.md его описывает — хук про него молчит.
      Вывод хука:
$(printf '%s\n' "$HOUT" | sed 's/^/      /')"
fi

if grep -qE '^[[:space:]]*·[[:space:]]*lib\.sh' <<< "$HOUT"; then
    bad "A5b" "хук объявил новым механизмом файл lib.sh, которого нет ни в дереве, ни в staged:
      staged: $(git -C "$R" diff --cached --name-only | tr '\n' '|')"
else
    ok "A5b хук не выдумал несуществующий механизм"
fi

echo ""
echo "adv space-in-path: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
