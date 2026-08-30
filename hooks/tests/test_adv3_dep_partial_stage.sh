#!/usr/bin/env bash
# test_adv3_dep_partial_stage.sh — «поведение не менялось» сказано про коммит, который
# меняет поведение.
#
# Хук САМ объявляет, что обязан работать при `git commit -am`, и ради этого берёт
# объединение индекса git и рабочего дерева (комментарий в doc-impact-check.sh:63-66:
# «git commit -am кладёт файлы в индекс только В МОМЕНТ коммита… поэтому берётся
# объединение индекса и рабочего дерева»).
#
# А `changed_lines_are_data()` смотрит ТОЛЬКО в индекс: маркеры берутся из `git show :путь`,
# номера строк — из `git diff --cached -U0`. Рабочего дерева в этой ветке нет вообще.
#
# Отбор файлов и классификация правки читают, стало быть, РАЗНЫЕ снимки. Штатный порядок
# «поправил таблицу → git add → дописал функцию → git commit -a» даёт: застейджено —
# только данные, уходит в коммит — данные И поведение. Файл объявляется data_only,
# выбывает из `mech`, и вместе с ним из отчёта выбывает ВСЁ: документы, новые публичные
# имена, признак устаревшей строки (`stale` считается уже по отфильтрованному `mech`).
#
# Итог: на коммит, который переписывает тело функции и добавляет публичное имя, хук
# печатает «правка внутри объявленной области данных — поведение не менялось».
# Это не пропуск строки в отчёте — это ложное утверждение об обратном.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/doc-impact-check.sh"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq      >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
R="$TMP/repo"; mkdir -p "$R/hooks" "$R/scripts" "$R/docs" "$R/.claude-docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t

write_gamma() {  # $1 — значение данных, $2 — тело функции, $3 — «yes» добавить новое имя
    { printf '#!/usr/bin/env bash\n'
      printf '# dep-index: data-region-start\n'
      printf 'CONF="%s"\n' "$1"
      printf '# dep-index: data-region-end\n'
      printf 'gamma_fn() { echo %s; }\n' "$2"
      [ "${3:-}" = yes ] && printf 'brand_new_fn() { :; }\n'
      : ; } > "$R/hooks/gamma-hook.sh"
}

write_gamma "один" "old"
printf '# Справочник\n\nМеханизм gamma-hook описан здесь.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

# Штатный порядок: сначала правка данных и `git add`, потом правка поведения в дереве.
write_gamma "один два" "old"
git -C "$R" add hooks/gamma-hook.sh >/dev/null 2>&1
write_gamma "один два" "ПОЛНОСТЬЮ_НОВОЕ_ПОВЕДЕНИЕ" yes

# То, что реально уйдёт в коммит при `git commit -a`.
WILL_COMMIT=$(git -C "$R" diff HEAD -- hooks/gamma-hook.sh)

export STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"
IN=$(jq -cn --arg c 'git commit -am "правка"' --arg cwd "$R" \
     '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd,session_id:"adv3ps"}')
OUT=$(printf '%s' "$IN" | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null)
MSG=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

# Предпосылка: в коммит действительно уходит поведение, а не только данные.
if grep -q 'ПОЛНОСТЬЮ_НОВОЕ_ПОВЕДЕНИЕ' <<< "$WILL_COMMIT" \
   && grep -q 'brand_new_fn' <<< "$WILL_COMMIT"; then
    :
else
    echo "SKIP: предпосылка не собралась — git commit -a не унёс бы поведение"; exit 0
fi

if grep -q 'поведение не менялось' <<< "$MSG"; then
    bad "A1 ложное «поведение не менялось»" "коммит меняет тело gamma_fn и добавляет
      публичное имя brand_new_fn, а хук утверждает обратное. Ответ хука:
$(printf '%s\n' "$MSG" | sed 's/^/      /')
      уйдёт в коммит:
$(printf '%s\n' "$WILL_COMMIT" | sed -n '5,20p' | sed 's/^/      /')"
else
    ok "A1 правка поведения в дереве не объявлена данными"
fi

if grep -q 'docs/manual.md' <<< "$MSG"; then
    ok "A1b документ механизма назван"
else
    bad "A1b документ не назван" "docs/manual.md описывает gamma-hook и в коммит не входит,
      но в отчёте его нет — механизм выбыл из mech вместе со своими документами.
      Ответ хука:
$(printf '%s\n' "${MSG:-<пусто>}" | sed 's/^/      /')"
fi

if grep -q 'brand_new_fn' <<< "$MSG"; then
    ok "A1c новое публичное имя названо"
else
    bad "A1c новое имя не названо" "в коммите появляется публичное имя brand_new_fn;
      ветка «новые публичные имена» не сработала, потому что механизм отфильтрован как data_only"
fi

echo ""
echo "adv3 dep partial-stage: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
