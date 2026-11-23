#!/usr/bin/env bash
# test_adv_dep_index_data_region_worktree.sh — приговор о КОММИТЕ выносится по файлу
# НА ДИСКЕ: правки, которых в коммите нет, переключают вердикт.
#
# Механика. `changed_lines_are_data` берёт границы области из `read(path)` — рабочее
# дерево, а номера изменённых строк из `git diff --cached` — индекс. Два разных снимка
# файла. Как только дерево уезжает от индекса (обычное `git add` и продолжение правки),
# номера прикладываются к чужой разметке.
#
# Сценарий ниже — рабочий порядок ClaudSoul, а не вывернутый: правишь поведение хука,
# ставишь в индекс, следом дописываешь регистрации ВНУТРЬ размеченной области данных
# (в install.sh это буквально её назначение), коммитишь первым делом фикс. В коммите —
# одна строка поведения. Вердикт — «поведение не менялось», документы молчат.
#
# Направление умолчания, объявленное в шапке indexer'а («лишняя строка в отчёте, а не
# тишина»), здесь нарушено: не размеченный файл шумит, а размеченный — глохнет от
# правки, которой в коммите нет.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
# Тело именованной секции отчёта: строки после заголовка до следующей строки с 0-й позиции.
sect() { awk -v h="$1" 'substr($0,1,length(h))==h{f=1;next} /^[^[:space:]]/{f=0} f'; }
die() { bad "$1" "$2"; echo ""; echo "adv data-region-worktree: $PASS/$((PASS+FAIL)) passed"; exit 1; }

TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
{ printf '#!/usr/bin/env bash\n'
  printf '# dep-index: data-region-start\n'
  printf 'REG_1=x\nREG_2=x\nREG_3=x\n'
  printf '# dep-index: data-region-end\n'
  printf 'behave() { echo v1; }\n'
  printf 'tail_fn() { :; }\n'; } > "$R/hooks/eps.sh"
# Имя механизма В ДОКУМЕНТЕ пишется С РАСШИРЕНИЕМ: `mentions()` засчитывает голое
# упоминание только составному имени (с дефисом или подчёркиванием), а односложное `eps`
# от обычного слова не отличает. С прежним текстом («Механизм eps описан») связь
# «документ → механизм» не возникала НИКОГДА, предпосылка была невыполнима, и тест жил
# в вечном SKIP.
printf '# Док\n\nМеханизм eps.sh описан.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dep_index_data_region_worktree.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dep_index_data_region_worktree.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

# 1) правка поведения → в индекс
python3 - "$R/hooks/eps.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read().replace("echo v1", "echo v2")
open(p, "w", encoding="utf-8").write(s)
PY
git -C "$R" add hooks/eps.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dep_index_data_region_worktree.sh:$LINENO" >&2; exit 1; }
BEFORE=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/eps.sh 2>&1 )
# Предполагалось: нет документа в отчёте — предпосылки нет, пропускаем.
# Ложно вдвойне: пропуск отдавал код УСПЕХА (тест зелен, не посмотрев на предмет), а
# «docs/manual.md» подстрокой ловилось и из строки «не прочитано: 1 — docs/manual.md» —
# при мутации read() предпосылка «выполнялась» именно так.
# Держит: предпосылка — вердикт с ненулевым кодом, а документ ищется точным адресом
# в теле секции «описывают изменённое», счёт которой обязан быть ≥ 1.
doc_named() { # 1: отчёт → 0, если docs/manual.md назван в секции документов
    local n; n=$(sed -n 's/^описывают изменённое, но не тронуты (\([0-9]*\)).*/\1/p' <<< "$1")
    # Конвейер обрывается ПЕРЕД утверждением: `grep -q` в хвосте трубы шлёт SIGPIPE
    # предыдущему звену, и под `set -o pipefail` код 141 делает утверждение ложным тем
    # чаще, чем выше нагрузка (D239). Результат обработки кладём в переменную, сверяем
    # here-string'ом.
    local lines
    lines=$(sect 'описывают изменённое, но не тронуты (' <<< "$1" | sed 's/^ *· *//;s/ *—.*//')
    [ "${n:-0}" -ge 1 ] && grep -qxF 'docs/manual.md' <<< "$lines"
}
doc_named "$BEFORE" \
  || die "предпосылка" "страж не назвал документ ещё до отъезда дерева — проверять нечего:
$(printf '%s\n' "$BEFORE" | sed 's/^/      /')"
echo "  предпосылка: до дописи в дерево вердикт верный:"
printf '%s\n' "$BEFORE" | sed 's/^/      /'

# 2) дописываем данные ВНУТРЬ области, в индекс НЕ ставим
python3 - "$R/hooks/eps.sh" <<'PY'
import sys
p = sys.argv[1]
L = open(p, encoding="utf-8").read().splitlines(True)
i = [n for n, l in enumerate(L) if "data-region-end" in l][0]
L[i:i] = ["REG_new_%d=x\n" % k for k in range(4, 9)]
open(p, "w", encoding="utf-8").writelines(L)
PY

AFTER=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/eps.sh 2>&1 )
# Предполагалось: подстрока «docs/manual.md» в отчёте = вердикт не съехал.
# Ложно: та же подстрока приходит из строки «не прочитано» — мутация read() держала ногу
# зелёной при полностью слепом приборе.
# Держит: адресный признак с двух сторон — документ назван в СВОЕЙ секции (тот же
# doc_named, что и в предпосылке) И механизм НЕ объявлен «правкой одних данных»; второе
# и есть предмет теста, а прежняя нога о нём не спрашивала вовсе.
DATA_ONLY=$(sect 'правка внутри объявленной области данных' <<< "$AFTER" | sed 's/^ *· *//')
if doc_named "$AFTER" && ! grep -qxF 'hooks/eps.sh' <<< "$DATA_ONLY"; then
    ok "A8 вердикт не зависит от правок вне коммита"
else
    bad "A8" "в коммите ровно одна строка — правка поведения:
$(git -C "$R" diff --cached -U0 -- hooks/eps.sh | sed -n '/^@@/p;/^[+-][^+-]/p' | sed 's/^/      /')
      после незастейдженной дописи данных в дерево вердикт:
$(printf '%s\n' "$AFTER" | sed 's/^/      /')"
fi

echo ""
echo "adv data-region-worktree: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
