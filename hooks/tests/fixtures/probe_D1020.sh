#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# probe_D1020.sh — страж слияния не засчитывает корнем «нет — …» (D1020).
#
# Коды: 0 — ветка, чей пункт несёт «**Корень.** нет — разбор не проводился», отбита, а ветка с «не дефект — …»
#       пропущена; 1 — «нет — …» засчитан корнем (дефект D1020: признак (б) берёт первое слово строки корня
#       и судит его префиксом «не», а «нет» тоже начинается с «не»); 2 — судить нечем: нет стража, git, jq
#       или python3, либо контроль «не дефект» отбит.
# Повод — 21 октября 2026: пункт D1016 записан с «Корень. нет — разбор не проводился», и ни страж записи,
# ни страж слияния этого бы не остановили. Пунктов с корнем «нет» в долге и архиве ClaudSoul — 38.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/merge-root-gate.sh"
[ -f "$HOOK" ] || exit 2
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || exit 2; done
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state" CLAUDSOUL_ROOT="$REPO"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$T/repo"; mkdir -p "$R/src" "$R/scripts/probes"
git -C "$R" init -q -b main || exit 2
printf '%s\n' '# ROOTS' '' '## R1 — тестовый корень' '**Устройство.** src делает BAD.' \
    '**Признак.** `scripts/probes/R1.sh`' '**Зависимости (чек-лист регрессии).** —' '**Держит.** —' > "$R/ROOTS.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/probes/R1.sh"
printf '%s\n' '# BACKLOG' '' '### X1 ☐ [P2] пункт без разбора' '**Корень.** нет — разбор не проводился' '' \
    '### X2 ☐ [P2] задача' '**Корень.** не дефект — новая возможность' > "$R/BACKLOG.md"
printf 'module.exports = 1;\n' > "$R/src/a.js"
git -C "$R" add -A && git -C "$R" commit -qm init || exit 2
br() { git -C "$R" checkout -q -b "$1" main && printf '%s\n' "$3" > "$R/src/a.js" \
       && git -C "$R" commit -qam "$2" && git -C "$R" checkout -q main; }
br noanalysis "fix: правка (X1)" 'module.exports = 2;' || exit 2
br notdefect "feat: возможность (X2)" 'module.exports = 3;' || exit 2

bash "$HOOK" --check "$R" main notdefect >/dev/null 2>&1 \
    || { echo "probe_D1020: контроль — ветка с «не дефект» отбита, судить нечем" >&2; exit 2; }
if bash "$HOOK" --check "$R" main noanalysis >/dev/null 2>&1; then
    echo "probe_D1020: дефект — корень «нет — разбор не проводился» засчитан" >&2
    exit 1
fi
exit 0
