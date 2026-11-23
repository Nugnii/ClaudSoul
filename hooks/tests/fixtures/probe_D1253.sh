#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/write_targets.py
# probe_D1253 — разбор вызовов (`write_targets.py --calls`, за ним `executable_call_targets` и страж «запускается файл,
#   которого нет») отдаёт запуск файла внутри `"$(…)"` и внутри обратных кавычек так же, как внутри `$(…)`:
#   `out="$(bash scripts/x.sh)"`, `echo "$(bash scripts/x.sh)"`, `` out=`bash scripts/x.sh` `` → `scripts/x.sh`;
#   контроли — `out=$(bash scripts/x.sh)` → путь (как прежде); `"bash scripts/x.sh"` и `echo '$(bash scripts/x.sh)'` —
#   пусто (текст, bash их не запускает, D424).
# Код: 0 — так; 1 — нет (названо); 2 — нет предмета.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
P="$R/hooks/lib/write_targets.py"
[ -f "$P" ] && command -v python3 >/dev/null 2>&1 || exit 2
c() { printf '%s' "$1" | python3 "$P" --calls 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
miss=""
for f in 'out=$(bash scripts/x.sh)' 'out="$(bash scripts/x.sh)"' 'echo "$(bash scripts/x.sh)"' 'out=`bash scripts/x.sh`'; do
    [ "$(c "$f")" = "scripts/x.sh" ] || miss="$miss «${f}» → «$(c "${f}")» вместо scripts/x.sh;"
done
for f in '"bash scripts/x.sh"' "echo '\$(bash scripts/x.sh)'"; do
    [ -z "$(c "$f")" ] || miss="$miss текст «${f}» принят за вызов: «$(c "${f}")»;"
done
[ -z "$miss" ] && { echo "запуск в \"\$(…)\" и в обратных кавычках виден, текст в кавычках — нет"; exit 0; }
echo "не держится:$miss"
exit 1
