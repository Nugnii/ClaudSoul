#!/usr/bin/env bash
# test_adv_guard_mention_counts_as_pair.sh — покрытие засчитывается по УПОМИНАНИЮ пути в
# drift-check.sh, а не по сравнению. Комментарий «пару ещё не завели» закрывает требование.
#
# Вход: копия drift-check.sh, где строка сравнения шаблонов
#     _cmp_tree "шаблоны" "$REPO/templates" "$CLAUDE_HOME/templates" "*.tmpl"
#   заменена комментарием
#     # TODO(D105): пару для $CLAUDE_HOME/templates ещё не завели — сравнения нет
#   install.sh при этом прежний: приёмник ~/.claude/templates он наполняет.
# Ожидание: непокрытых пар 1, код 1 — сравнения шаблонов в файле нет.
# Факт: проверка покрытия — `re.search(r'\$CLAUDE_HOME/' + key, drift)` по ТЕКСТУ файла.
#   Комментарий совпадает, страж печатает «непокрытых пар: 0» и выходит с 0. Контроль:
#   стоит убрать из комментария сам путь — тот же файл немедленно даёт «непокрытых пар: 1».
#   То есть предмет проверки — наличие подстроки, а не наличие сравнения.
#
# Достижимость: путь `$CLAUDE_HOME/<приёмник>` встречается в drift-check.sh не только в
#   сравнениях, но и в текстах сообщений («не установлено: $CLAUDE_HOME/bin») и в
#   комментариях-заголовках пар. Любая пара, у которой сравнение временно закомментировано
#   или сведено к сообщению об отсутствии, остаётся «покрытой» — а это ровно то состояние,
#   в котором пару правят.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_SRC="$REPO/hooks/tests/test_drift_pairs_cover_install.sh"
[ -f "$GUARD_SRC" ] || { echo "FAIL: нет $GUARD_SRC"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T="$(mktemp -d)"
P="$T/repo"
mkdir -p "$P/hooks/tests"
cp "$REPO/install.sh" "$P/install.sh"
cp "$GUARD_SRC" "$P/hooks/tests/guard.sh"

python3 - "$REPO/hooks/tests/drift-check.sh" "$P/hooks/tests/drift-check.sh" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
t = src.read_text()
old = '_cmp_tree "шаблоны" "$REPO/templates" "$CLAUDE_HOME/templates" "*.tmpl"'
if old not in t:
    print("SKIP-MARKER"); raise SystemExit(3)
dst.write_text(t.replace(old, '# TODO(D105): пару для $CLAUDE_HOME/templates ещё не завели — сравнения нет'))
PY
[ $? -eq 3 ] && { echo "SKIP: строка сравнения шаблонов изменилась — вход надо перестроить"; exit 0; }

echo "в подделанном drift-check.sh про templates осталось:"
grep -n 'templates' "$P/hooks/tests/drift-check.sh" | sed 's/^/  /'
grep -q '_cmp_tree "шаблоны"' "$P/hooks/tests/drift-check.sh" && { echo "FAIL: сравнение не удалено"; exit 1; }

out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
echo "код возврата стража: $rc"

fail=0
if [ "$rc" -eq 0 ]; then
    echo "ПРОВАЛ: сравнения шаблонов в файле нет, а страж доволен — покрытие засчитано по упоминанию в комментарии"
    fail=1
fi
case "$out" in
    *templates*) ;;
    *) echo "ПРОВАЛ: приёмник templates не назван непокрытым"; fail=1 ;;
esac

# Контроль: убираем путь из комментария — ничего, кроме текста комментария, не меняя.
sed -i.bak 's|# TODO(D105): пару для \$CLAUDE_HOME/templates ещё не завели — сравнения нет|# TODO(D105): пары нет|' "$P/hooks/tests/drift-check.sh"
ctl_out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; ctl_rc=$?
echo "контроль (тот же файл, из комментария убран путь): rc=$ctl_rc — $(printf '%s' "$ctl_out" | head -1)"

[ "$fail" -eq 0 ] && echo "OK: покрытие требует сравнения, а не упоминания"
exit "$fail"
