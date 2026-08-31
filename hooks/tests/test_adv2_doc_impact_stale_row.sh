#!/usr/bin/env bash
# test_adv2_doc_impact_stale_row.sh — новый документ про уже существующий механизм не
# доходит до стража НИКОГДА: коммит документа проходит молча (а значит и предписания
# пересобрать индекс никто не получает), а следующая правка механизма читает старую
# строку и молчит про этот документ.
#
# Две дыры, замкнутые в кольцо.
#
# 1. Коммит только с документами даёт пустой отчёт: `impact()` берёт `mech = [c for c in
#    changed if c in rows]`, документов там нет; `new_mech` фильтруется по `\.(sh|py)$`.
#    Хук на пустом отчёте выходит `exit 0` — вместе с отчётом пропадает и хвост сообщения
#    «Пересобрать индекс после правки: --changed <файлы>». Единственное место, где это
#    предписание вообще произносится.
#
# 2. Индекс после этого устарел, и `--impact` этого не замечает, хотя средство под рукой:
#    в строке лежит поле `sha` — по собственному объявлению файла «по нему видно, устарела
#    ли строка». Ни один потребитель его не читает. Отчёт строится по старой строке и
#    подаётся как текущий.
#
# Исход: механизм правится, документ про него существует и не тронут, страж молчит дважды.
# Расхождение всплывёт на `dep-index --check` — он в scripts/measurements.tsv с периодом
# 7 дней, то есть в другом ходе и без контекста правки.
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
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

run() { jq -cn --arg c "git commit -m x" --arg d "$R" --arg s "$1" \
          '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:$s}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# --- коммит 1: заведён справочник про уже существующий механизм ----------------------
# Имя механизма в обратных кавычках — так документы этого дерева помечают, что это ИМЯ,
# а не слово. Голое односложное «alpha» учётом не считается ОСОЗНАННО: замер 28 августа
# 2026 показал, что такая форма ловит «silent inject» в PLAN.md и поле JSON «"phase"».
# Правило закреплено отдельно в test_doc_impact_check.sh; здесь предмет атаки другой —
# устаревшая строка учёта, и он сохранён.
printf '# Справочник\n\nМеханизм `alpha` делает то-то и то-то.\n' > "$R/docs/alpha-guide.md"
git -C "$R" add -A >/dev/null 2>&1
FIRST=$(run sess1)
if grep -qF "dep-index.py --changed" <<< "$FIRST"; then
    ok "D1 коммит документа получил предписание пересобрать индекс"
else
    bad "D1" "коммит завёл docs/alpha-guide.md — документ, меняющий строку hooks/alpha.sh.
      Страж выдал: [${FIRST:-«ТИШИНА»}]
      вместе с отчётом пропало и единственное место, где произносится «--changed <файлы>»"
fi
git -C "$R" commit -qm "docs: справочник alpha" >/dev/null 2>&1

# --- коммит 2: правка поведения механизма -------------------------------------------
printf '#!/usr/bin/env bash\nfoo_one() { echo ИНОЕ ПОВЕДЕНИЕ; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add -A >/dev/null 2>&1
SECOND=$(run sess2)
STALE=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check 2>&1 )
if grep -qF "docs/alpha-guide.md" <<< "$SECOND"; then
    ok "D2 правка механизма назвала документ, заведённый прошлым коммитом"
else
    bad "D2" "справочник docs/alpha-guide.md описывает механизм и не тронут,
      страж выдал: [${SECOND:-«ТИШИНА»}]
      при этом устаревание строки распознаётся, просто никем не проверяется:
$(printf '%s\n' "$STALE" | sed 's/^/      /')"
fi

echo ""
echo "adv2 stale-row: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
