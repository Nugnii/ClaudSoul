#!/usr/bin/env bash
# test_adv_dep_index_changed_partial.sh — команда, которую хук диктует в каждом своём
# сообщении, оставляет индекс несогласованным, а на пропавшем индексе — вырезает учёт.
#
# Хук заканчивает так:
#     Пересобрать индекс после правки: python3 scripts/dep-index.py --changed <файлы>
#
# A6a. `--changed` пересобирает строки ТОЛЬКО названных файлов. Но появление нового
# механизма меняет строки ЧУЖИЕ: `deps_of` ищет литералы имён файлов дерева, и всякий
# файл, который уже упоминал `beta-lib.sh` в тексте, обязан получить новое ребро. Про
# документы такая перестройка предусмотрена (любой .md в списке → полная сборка), про
# механизмы — нет. Исход: сделал ровно то, что велел страж, и `--check` красный.
# Это не косметика: `--check` стоит замером с периодом 7 дней, то есть красным его
# увидит уже другой ход, без контекста правки.
#
# A6b. Индекса нет на диске → `load()` возвращает пустоту, `--changed один-файл`
# записывает индекс из ОДНОЙ строки поверх места, где был полный учёт, и рапортует
# «индекс собран» как об успехе. Хук после этого продолжает работать (файл на месте) и
# молчит про все остальные механизмы.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# --- A6a ---------------------------------------------------------------------------
TMP=$(mktemp -d); R="$TMP/a"
mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\n# общая часть вынесена в beta-lib.sh\nfoo() { :; }\n' > "$R/hooks/gamma.sh"
printf '# Док\n\nМеханизм gamma описан.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\nbeta_fn() { :; }\n' > "$R/hooks/beta-lib.sh"
git -C "$R" add -A >/dev/null 2>&1
REBUILD=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --changed hooks/beta-lib.sh 2>&1 )
CHECK=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check 2>&1 ); CRC=$?
if [ "$CRC" -eq 0 ]; then
    ok "A6a после предписанной хуком пересборки --check зелёный"
else
    bad "A6a" "исполнено дословно предписание хука: --changed hooks/beta-lib.sh → «${REBUILD}»,
      сразу за ним --check (rc=$CRC):
$(printf '%s\n' "$CHECK" | sed 's/^/      /')"
fi

# --- A6b ---------------------------------------------------------------------------
R2="$TMP/b"; mkdir -p "$R2/hooks" "$R2/.claude-docs" "$R2/scripts"
cp "$INDEXER" "$R2/scripts/dep-index.py"
git -C "$R2" init -q; git -C "$R2" config user.email t@t.local; git -C "$R2" config user.name t
for n in a b c d; do printf '#!/usr/bin/env bash\n%s_fn() { :; }\n' "$n" > "$R2/hooks/$n.sh"; done
git -C "$R2" add -A >/dev/null 2>&1; git -C "$R2" commit -qm init >/dev/null 2>&1
( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --all >/dev/null )
BEFORE=$(grep -vc '^#' "$R2/.claude-docs/dep-index.tsv")
mv "$R2/.claude-docs/dep-index.tsv" "$TMP/index-set-aside.tsv"
SAY=$( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --changed hooks/a.sh 2>&1 ); SRC=$?
AFTER=$(grep -vc '^#' "$R2/.claude-docs/dep-index.tsv" 2>/dev/null || echo 0)
if [ "$SRC" -eq 0 ] && [ "$AFTER" -lt "$BEFORE" ]; then
    bad "A6b" "индекса не было на диске; --changed hooks/a.sh записал урезанный учёт
      и отчитался успехом (rc=$SRC): «${SAY}»
      строк было $BEFORE, стало $AFTER — про остальные механизмы страж теперь молчит"
else
    ok "A6b пересборка по одному файлу на пустом месте не урезала учёт"
fi

echo ""
echo "adv changed-partial: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
