#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# D308: признак рода H узнаёт замок-потребитель (with_lock) и не узнаёт его там, где замка нет.
# Рамка — свой git-репозиторий (реестр берёт файлы из индекса). Миром дерева не меряет.
# 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
[ -f "$R/scripts/defect-class-carriers.py" ] || { echo "рамка: нет прибора" >&2; exit 2; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/scripts" "$d/hooks" || exit 2
cp "$R/scripts/defect-class-carriers.py" "$d/scripts/" || exit 2
printf '#!/usr/bin/env bash\ntrue\n' > "$d/install.sh"
cat > "$d/hooks/unlocked.sh" <<'X'
#!/usr/bin/env bash
STATE="$HOME/.claude/hooks/state/shared.json"
jq '.n += 1' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
X
cat > "$d/hooks/locked.sh" <<'X'
#!/usr/bin/env bash
. "$(dirname "$0")/state-lock-lib.sh"
STATE="$HOME/.claude/hooks/state/shared2.json"
with_lock "$STATE" true
jq '.n += 1' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
X
git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.email=t@t -c user.name=t commit -qm f || exit 2
out=$(cd "$d" && python3 scripts/defect-class-carriers.py --genus H 2>/dev/null)
grep -q 'hooks/unlocked.sh' <<<"$out" || { echo "ПОТЕРЯН настоящий носитель hooks/unlocked.sh"; exit 1; }
grep -q 'hooks/locked.sh' <<<"$out" && { echo "ЛОЖНЫЙ носитель hooks/locked.sh (замок with_lock не узнан)"; exit 1; }
exit 0
