#!/usr/bin/env bash
# test_md_trailing_newline.sh — отслеживаемый .md кончается переводом строки.
#
# Повод (D296). У 20 файлов последний байт не был переводом строки, и построчное чтение
# теряет либо склеивает последнюю строку. Это не косметика: до правки в их числе был сам
# BACKLOG.md, и последняя строка — «Проверка» нижнего пункта — была невидима построчным
# читателям (`wc -l` печатал 209 при 210 строках). Тот же класс отказывает у любого стража,
# читающего файл строками, и у бегуна замеров, читающего реестр как TSV (D303).
#
# Почему страж, а не разовая правка: «Результат» пункта требует механизма, а не одного
# прохода. Редактор, дописавший файл без завершающего байта, вернёт дефект молча.
#
# Универсум ВЫВОДИТСЯ из индекса git: перечень шаблоном оболочки не спускается в
# подкаталоги и дал бы зелёный вердикт о непросмотренном (род F).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1
UNIVERSE_ROOT="$REPO"
. "$REPO/hooks/tests/universe-lib.sh"

PASS=0; FAIL=0
seen=0
bad=""

while IFS= read -r f; do
    [ -f "$f" ] || continue
    [ -s "$f" ] || continue          # пустой файл последней строки не имеет
    seen=$((seen + 1))
    if [ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" != "\n" ]; then
        bad="${bad}${f}"$'\n'
    fi
done <<< "$(universe_docs)"

if [ "$seen" -eq 0 ]; then
    echo "FAIL: универсум пуст — ни один .md не просмотрен, вердикт недействителен"
    echo "test_md_trailing_newline: 0 passed, 1 failed"
    exit 1
fi

if [ -n "$bad" ]; then
    n=$(printf '%s' "$bad" | grep -c .)
    echo "FAIL: .md без завершающего перевода строки: $n из $seen"
    printf '%s' "$bad" | head -10
    [ "$n" -gt 10 ] && echo "  … и ещё $((n - 10))"
    FAIL=1
else
    PASS=1
fi

echo "test_md_trailing_newline: $PASS passed, $FAIL failed (просмотрено $seen)"
exit "$FAIL"
