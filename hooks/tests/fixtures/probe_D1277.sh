#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/write_targets.py
# probe_D1277 — разбор целей записи (`write_targets.py`, режим по умолчанию и `--edits`) видит запись внутри подстановки
#   в двойных кавычках и в обратных кавычках и отдаёт путь без обратной кавычки:
#   (1) по умолчанию `x="$(echo a > f1.txt)"` → `f1.txt` (сейчас пусто: `_substs` включён только для `--edits`);
#   (2) по умолчанию и с `--edits` `` x=`echo a > f2.txt` `` → ровно `f2.txt` (сейчас `` f2.txt` ``);
#   (к) `echo '$(echo a > f3.txt)'` — `f3.txt` не цель ни в одном режиме (одинарные кавычки — текст).
# Код: 0 — так; 1 — нет (названо); 2 — нет предмета.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
P="$R/hooks/lib/write_targets.py"
[ -f "$P" ] && command -v python3 >/dev/null 2>&1 || exit 2
t() { printf '%s' "$2" | python3 "$P" $1 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'; }
miss=""
[ "$(t "" 'x="$(echo a > f1.txt)"')" = "f1.txt" ] || miss="$miss (1) «$(t "" 'x="$(echo a > f1.txt)"')» вместо f1.txt;"
for m in "" --edits; do
    [ "$(t "$m" 'x=`echo a > f2.txt`')" = "f2.txt" ] || miss="$miss (2${m:+ $m}) «$(t "$m" 'x=`echo a > f2.txt`')» вместо f2.txt;"
    [ -z "$(t "$m" "echo '\$(echo a > f3.txt)'")" ] || miss="$miss (к${m:+ $m}) текст в одинарных кавычках принят за цель;"
done
[ -z "$miss" ] && { echo "запись в подстановке в кавычках и в обратных кавычках видна, путь без кавычки"; exit 0; }
echo "не держится:$miss"
exit 1
