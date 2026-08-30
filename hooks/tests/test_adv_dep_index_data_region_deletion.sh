#!/usr/bin/env bash
# test_adv_dep_index_data_region_deletion.sh — чистое УДАЛЕНИЕ поведения сразу за
# областью данных объявляется правкой данных, и все документы механизма замолкают.
#
# Механика. `changed_lines_are_data` берёт номера строк из `@@ -a,b +c,d @@` НОВОЙ
# стороны диффа. У чистого удаления новая сторона пуста: git пишет `+N,0`, где N —
# строка, ПОСЛЕ которой удалено. Разбор считает `range(N, N+max(0,1))` = [N], то есть
# приписывает удалению строку, которая осталась. Если эта строка — закрывающий маркер
# области данных, удаление любого объёма поведения ниже неё попадает внутрь области.
#
# В живом дереве это ровно install.sh: маркер `data-region-end` на 633, а на 634
# начинается `if command -v jq` — код слияния настроек установщика. У install.sh в
# индексе 16 описывающих документов; при таком удалении не называется ни один, зато
# печатается «поведение не менялось».
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)

# --- A1a. Синтетика: функция сразу под закрывающим маркером ------------------------
R="$TMP/a"; mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
{ printf '#!/usr/bin/env bash\n'
  printf '# dep-index: data-region-start\n'
  printf 'DATA=1\n'
  printf '# dep-index: data-region-end\n'
  printf 'behave() { echo real; }\n'; } > "$R/hooks/delta.sh"
# Имя в обратных кавычках — соглашение дерева: так документ помечает, что это ИМЯ, а не
# слово. Голое односложное «delta» учётом не считается осознанно (замер 28 августа 2026:
# голое «inject» ловило «silent inject», «phase» — поле JSON). Предмет атаки другой —
# чистое удаление сразу за областью данных, он сохранён.
printf '# Про delta\n\nМеханизм `delta` описан тут.\n' > "$R/docs/delta-doc.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

# удаляем ТОЛЬКО функцию — поведение, не данные
{ printf '#!/usr/bin/env bash\n'
  printf '# dep-index: data-region-start\n'
  printf 'DATA=1\n'
  printf '# dep-index: data-region-end\n'; } > "$R/hooks/delta.sh"
git -C "$R" add hooks/delta.sh >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/delta.sh 2>&1 )

if grep -qF "docs/delta-doc.md" <<< "$OUT"; then
    ok "A1a удаление функции подняло её документ"
else
    bad "A1a" "удалена функция behave(), документ docs/delta-doc.md не назван. Отчёт:
$(printf '%s\n' "$OUT" | sed 's/^/      /')
      hunk: $(git -C "$R" diff --cached -U0 -- hooks/delta.sh | sed -n '/^@@/p')"
fi

# --- A1b. Живой install.sh и живой индекс -----------------------------------------
LIVE_IDX="$REPO/.claude-docs/dep-index.tsv"
if [ ! -f "$LIVE_IDX" ] || [ ! -f "$REPO/install.sh" ]; then
    echo "SKIP [A1b]: нет живого индекса или install.sh"
else
  END_LINE=$(grep -n 'dep-index: data-region-end' "$REPO/install.sh" | head -1 | cut -d: -f1)
  NEXT=$((END_LINE + 1))
  DOCS_N=$(awk -F'\t' '$1=="install.sh"{n=split($4,a,","); print n}' "$LIVE_IDX")
  if [ -z "${END_LINE:-}" ] || [ -z "${DOCS_N:-}" ]; then
    echo "SKIP [A1b]: в install.sh нет маркера области данных либо строки в индексе"
  else
    echo "  предпосылка: маркер data-region-end на строке $END_LINE, поведение с $NEXT: $(sed -n "${NEXT}p" "$REPO/install.sh")"
    echo "  предпосылка: у install.sh в индексе описывающих документов — $DOCS_N"
    R2="$TMP/b"; mkdir -p "$R2/.claude-docs" "$R2/scripts"
    cp "$REPO/install.sh" "$R2/install.sh"
    cp "$LIVE_IDX" "$R2/.claude-docs/dep-index.tsv"
    cp "$INDEXER" "$R2/scripts/dep-index.py"
    git -C "$R2" init -q; git -C "$R2" config user.email t@t.local; git -C "$R2" config user.name t
    git -C "$R2" add -A >/dev/null 2>&1; git -C "$R2" commit -qm init >/dev/null 2>&1
    python3 - "$R2/install.sh" "$NEXT" <<'PY'
import sys
p, first = sys.argv[1], int(sys.argv[2])
L = open(p, encoding="utf-8").read().splitlines(True)
del L[first-1:first-1+27]          # 27 строк jq-слияния настроек — чистое поведение
open(p, "w", encoding="utf-8").writelines(L)
PY
    git -C "$R2" add install.sh >/dev/null 2>&1
    OUT2=$( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --impact install.sh 2>&1 )
    if grep -qF "описывают изменённое" <<< "$OUT2"; then
        ok "A1b удаление 27 строк поведения install.sh подняло документы"
    else
        bad "A1b" "из install.sh удалены 27 строк слияния настроек; ни один из $DOCS_N документов не назван. Отчёт:
$(printf '%s\n' "$OUT2" | sed 's/^/      /')
      hunk: $(git -C "$R2" diff --cached -U0 -- install.sh | sed -n '/^@@/p')"
    fi
  fi
fi

echo ""
echo "adv data-region-deletion: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
