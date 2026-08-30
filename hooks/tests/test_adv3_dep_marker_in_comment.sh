#!/usr/bin/env bash
# test_adv3_dep_marker_in_comment.sh — строка, которая всего лишь НАЗЫВАЕТ пару маркеров,
# открывает область данных и накрывает ею настоящее поведение.
#
# Разбор в changed_lines_are_data():
#     if   DATA_START in line: start = i
#     elif DATA_END   in line and start is not None: regions.append((start, i))
# `elif` означает: строка, где есть ОБА маркера, только ОТКРЫВАЕТ область и никогда её
# не закрывает. Открытая область молча тянется до следующего одиночного `data-region-end`,
# и всё, что между ними, объявляется данными.
#
# Строка с обоими маркерами — не выдумка, это принятая в дереве форма записи соглашения:
#     scripts/dep-index.py:345  «размечается парой `dep-index: data-region-start` /
#                                `data-region-end`»
#     .claude-docs/modules/doc-impact-check.md:28
# Механизм, который в шапке объясняет собственную разметку той же фразой и имеет ниже
# настоящую область данных, получает область от шапки до конца настоящей — и правка
# поведения между ними проходит как «поведение не менялось».
#
# Проверка на сегодняшнем дереве (D2) показывает, что до срабатывания не хватает одного
# одиночного `data-region-end` ниже по файлу: разбор dep-index.py уже открывает область
# на 345-й строке и держит её открытой до конца файла.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

S=$(printf 'dep-index: data-region-start')
E=$(printf 'dep-index: data-region-end')
TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/scripts" "$R/docs" "$R/.claude-docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t

write_delta() {   # $1 — тело функции
    { printf '#!/usr/bin/env bash\n'
      printf '# Таблица ниже размечена парой %s / %s\n' "$S" "$E"
      printf 'delta_fn() { echo %s; }\n' "$1"
      printf 'TABLE="a b"\n'
      printf '# %s\n' "$E"; } > "$R/hooks/delta-hook.sh"
}
write_delta old
printf '# Справочник\n\nМеханизм delta-hook описан здесь.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

write_delta ПОЛНОСТЬЮ_НОВОЕ_ПОВЕДЕНИЕ
git -C "$R" add -A >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/delta-hook.sh 2>&1 )

# --- D1 -----------------------------------------------------------------------------
if grep -q 'поведение не менялось' <<< "$OUT"; then
    bad "D1 комментарий открыл область данных" "правка — только тело delta_fn, строка 3,
      вне какой бы то ни было настоящей области. Комментарий строки 2 называет оба маркера,
      разбор считает его ОТКРЫТИЕМ, закрывает область одиночным маркером строки 5 —
      и поведение попадает внутрь. Отчёт:
$(printf '%s\n' "$OUT" | sed 's/^/      /')
      документ docs/manual.md описывает delta-hook и не назван"
else
    ok "D1 строка с обоими маркерами не открыла область"
fi

# --- D2: то же на живом дереве, предпосылка ----------------------------------------
# Разбор берётся У ПРОДУКТА, а не переписывается копией: копия мерила бы саму себя.
# Ровно это и было в первой редакции теста — предмет замера не тот, о котором утверждение.
LIVE=$( cd "$REPO" && python3 - <<'PY' 2>/dev/null
import importlib.util
spec = importlib.util.spec_from_file_location("d", "scripts/dep-index.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
text = open("scripts/dep-index.py", encoding="utf-8").read()
regions, s, opened = [], None, []
for i, line in enumerate(text.splitlines(), 1):
    o = bool(m.MARK_START_RE.match(line)); c = bool(m.MARK_END_RE.match(line))
    if o and not c:
        s = i; opened.append(i)
    elif c and not o and s is not None:
        regions.append((s, i)); s = None
print("open_at=%s regions=%s dangling=%s" % (opened, regions, s))
PY
)
case "$LIVE" in
    *"dangling=None"*) ok "D2 в scripts/dep-index.py нет незакрытой области" ;;
    *) bad "D2 живое дерево уже держит область открытой" "разбор scripts/dep-index.py: $LIVE
      строка 345 называет оба маркера одной фразой, разбор трактует её как открытие;
      область висит открытой до конца файла. Любой одиночный data-region-end, добавленный
      ниже, закроет её — и вся правка кода между ними станет «данными»" ;;
esac

echo ""
echo "adv3 dep marker-in-comment: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
