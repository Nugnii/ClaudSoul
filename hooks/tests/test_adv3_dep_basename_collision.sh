#!/usr/bin/env bash
# test_adv3_dep_basename_collision.sh — одинаковый basename в разных каталогах: связи
# приписываются обоим, и отчёт называет чужой документ своим.
#
# Механизм всюду опознаётся по имени файла, не по пути:
#   deps_of()  — `if os.path.basename(m) == name and m != path`
#   build()    — `mentions(os.path.basename(path), docs_corpus)`
#   impact()   — `mentions(os.path.basename(m), docs_corpus)`, `base in c[1]` для носителей
#
# Два механизма `foo-hook.sh` — в hooks/ и в scripts/ — получают ОДИН и тот же набор
# документов и тестов, хотя каждый документ называет свой путь буквально и другой не
# упоминает вовсе. Хук печатает это как факт: «docs/scripts-ref.md — про hooks/foo-hook.sh».
# Утверждение ложное: в этом документе имени hooks/foo-hook.sh нет.
#
# Достижимость: в сегодняшнем дереве совпадений basename среди механизмов ноль
# (проверка F2 это и сверяет), запрета на них нет ни в одном страже.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/scripts" "$R/docs" "$R/.claude-docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nhook_fn() { :; }\n' > "$R/hooks/foo-hook.sh"
printf '#!/usr/bin/env bash\nscript_fn() { :; }\n' > "$R/scripts/foo-hook.sh"
printf '# Хуки\n\nhooks/foo-hook.sh — хук события, делает А.\n'     > "$R/docs/hooks-ref.md"
printf '# Скрипты\n\nscripts/foo-hook.sh — утилита, делает Б.\n'    > "$R/docs/scripts-ref.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\nhook_fn() { echo new; }\n' > "$R/hooks/foo-hook.sh"
git -C "$R" add -A >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/foo-hook.sh 2>&1 )

# --- F1 -----------------------------------------------------------------------------
if grep -q 'docs/scripts-ref.md' <<< "$OUT"; then
    bad "F1 чужой документ выдан за свой" "изменён только hooks/foo-hook.sh.
      docs/scripts-ref.md называет scripts/foo-hook.sh и hooks/foo-hook.sh не упоминает:
      «$(cat "$R/docs/scripts-ref.md" | tail -1)»
      Отчёт:
$(printf '%s\n' "$OUT" | sed 's/^/      /')
      Строки индекса — оба механизма получили ОБА документа:
$(grep -v '^#' "$R/.claude-docs/dep-index.tsv" | grep foo-hook | sed 's/^/      /')"
else
    ok "F1 документ приписан по пути, а не по имени файла"
fi

# --- F2: достижимость на живом дереве ----------------------------------------------
DUP=$( cd "$REPO" && git ls-files -z '*.sh' '*.py' | tr '\0' '\n' \
       | grep -vE '(^|/)tests?/|^templates/|^scripts/publish/|__init__\.py$' \
       | awk -F/ '{print $NF}' | sort | uniq -d | tr '\n' ' ' )
if [ -z "$DUP" ]; then
    ok "F2 в живом дереве совпадений basename среди механизмов нет"
else
    bad "F2 совпадения уже есть" "живые совпадения basename: $DUP"
fi

echo ""
echo "adv3 dep basename-collision: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
