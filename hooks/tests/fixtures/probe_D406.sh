#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py
# D406: карта разводит роли ребра — чтение файла кольцом исполнения НЕ становится,
# настоящая взаимная ссылка (source в обе стороны) — становится. Дерево — песочный git-репозиторий; живой граф не читается.
# 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
[ -f "$R/scripts/project-graph.py" ] || { echo "рамка: нет прибора" >&2; exit 2; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mk() { local t="$d/$1"; mkdir -p "$t/scripts" "$t/hooks" "$t/.claude-docs" "$t/mcp-server/visualization" || return 1
  cp "$R/scripts/project-graph.py" "$t/scripts/"; git -C "$t" init -q . && git -C "$t" config user.email t@t && git -C "$t" config user.name t; }
run() { ( cd "$d/$1" && LESSONS_DIR="$d/lessons" CLAUDSOUL_REPO="$PWD" python3 scripts/project-graph.py --scc --exec 2>&1 ); }
mkdir -p "$d/lessons"; mk safe && mk ring || exit 2
# safe: a исполняет b; b только ЧИТАЕТ a (одна форма на файл: смесь ролей в строках читается как «зовёт») — кольца исполнения нет
printf '#!/usr/bin/env bash\nsource hooks/b.sh\n' > "$d/safe/hooks/a.sh"
printf '#!/usr/bin/env bash\ngrep -c . hooks/a.sh\n' > "$d/safe/hooks/b.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'; printf 'hooks/a.sh\ta\thooks/b.sh\t\t\t\n'; printf 'hooks/b.sh\tb\thooks/a.sh\t\t\t\n'; } > "$d/safe/.claude-docs/dep-index.tsv"
# ring: оба исполняют друг друга
printf '#!/usr/bin/env bash\nsource hooks/b.sh\n' > "$d/ring/hooks/a.sh"
printf '#!/usr/bin/env bash\nsource hooks/a.sh\n' > "$d/ring/hooks/b.sh"
cp "$d/safe/.claude-docs/dep-index.tsv" "$d/ring/.claude-docs/dep-index.tsv"
for t in safe ring; do git -C "$d/$t" add -A >/dev/null 2>&1 && git -C "$d/$t" commit -qm i >/dev/null 2>&1 || exit 2; done
out=$(run safe); rc=$?
{ [ "$rc" -eq 0 ] && grep -qF 'спаек (кусков, где всё достижимо из всего): 0' <<<"$out"; } || { echo "ЛОЖНАЯ спайка исполнения: чтение файла сочтено вызовом (rc=$rc)"; exit 1; }
out=$(run ring); rc=$?
{ [ "$rc" -eq 1 ] && grep -q 'a.sh' <<<"$out" && grep -q 'b.sh' <<<"$out"; } || { echo "НЕ найдена настоящая спайка исполнения (rc=$rc)"; exit 1; }
exit 0
