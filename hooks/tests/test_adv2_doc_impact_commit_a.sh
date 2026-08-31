#!/usr/bin/env bash
# test_adv2_doc_impact_commit_a.sh — `git commit -am` уносит в коммит правку механизма,
# а страж молчит: он смотрит только в `--cached`, где при этой форме коммита пусто.
#
# Механика.
#     STAGED=$(git -C "$ROOT" diff --cached --name-only -z ...)
#     [ -n "$STAGED" ] || exit 0
# `git commit -a` коммитит ИЗМЕНЁННЫЕ ОТСЛЕЖИВАЕМЫЕ файлы, ничего не помещая в индекс до
# самого коммита. Индекс пуст → первая же проверка выходит нулём → ни строки на выходе.
#
# Что это не «по замыслу»: соседние хуки того же события ровно этот случай разбирают.
#   changelog-reminder.sh:31   «…`git commit -am` — да, `git commit --amend` — нет»
#   changelog-reminder.sh:81   сверяется с `git diff --name-only` (НЕотстейдженное)
#   docs-family-check.sh:109-110  объединяет `diff --cached --name-only` и `diff --name-only`
# То есть в этом дереве уже принято, что staged — не полный список коммитируемого.
# doc-impact-check объединения не делает.
#
# Класс исхода — молчание стража там, где он обязан говорить: агент видит пустоту и
# читает её как «документацию ничего не задело».
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

run() { jq -cn --arg c "$1" --arg d "$R" --arg s "$2" \
          '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:$s}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# Правка поведения + новое публичное имя, БЕЗ `git add` — ровно то состояние дерева,
# из которого работает `git commit -am`.
printf '#!/usr/bin/env bash\nfoo_one() { echo ИНОЕ; }\nbrand_new_api() { :; }\n' > "$R/hooks/alpha.sh"

COMMITTED=$(git -C "$R" diff --name-only)
DASH_A=$(run "git commit -am 'правка alpha'" sess-a)

if [ -n "$DASH_A" ]; then
    ok "A1 на git commit -am страж назвал документы изменённого"
else
    # Доказательство, что молчание — не «нечего сказать»: тот же файл, тот же индекс,
    # разница только в git add.
    git -C "$R" add hooks/alpha.sh >/dev/null 2>&1
    AFTER_ADD=$(run "git commit -m 'правка alpha'" sess-b)
    bad "A1" "в коммит уходит [$COMMITTED], страж выдал: [«ТИШИНА»]
      тот же файл после git add — тот же хук говорит:
$(printf '%s\n' "$AFTER_ADD" | sed 's/^/      /')"
fi

echo ""
echo "adv2 commit-a: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
