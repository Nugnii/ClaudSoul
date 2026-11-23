#!/usr/bin/env bash
# probe_D434.sh — проба пункта D434: страж исчезновения долга молчит, когда BACKLOG.md удалён целиком (аудит B6).
# Результат: при `git commit`, когда HEAD несёт пункты, а BACKLOG.md удалён, страж называет исчезнувшие пункты; файл на месте с теми же пунктами — тишина; файл перезаписан без пункта — предупреждение.
# Проверка результата: bash hooks/tests/fixtures/probe_D434.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась (stderr называет, что).
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой).
# Фикстура — свой git-репозиторий; HOME подменён. Судится ВЫВОД стража на payload `git commit`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/backlog-vanish-check.sh"
[ -f "$HOOK" ] || { echo "probe_D434: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D434: нужен jq" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D434: нужен git" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D434: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R" "$T/home"
G="git -C $R -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
$G init -q 2>/dev/null || { echo "probe_D434: git init не удался" >&2; exit 2; }
printf '# BACKLOG\n\n- ☐ **D901** живой пункт\n' > "$R/BACKLOG.md"
$G add BACKLOG.md && $G commit -qm base >/dev/null 2>&1 || { echo "probe_D434: базовый коммит не состоялся" >&2; exit 2; }
HEADTXT=$(git -C "$R" show HEAD:BACKLOG.md 2>/dev/null || true)
grep -q 'D901' <<< "$HEADTXT" || { echo "probe_D434: HEAD не несёт D901 — фундамента нет" >&2; exit 2; }
run() { jq -cn --arg cwd "$R" '{cwd:$cwd, session_id:"probe-d434", tool_name:"Bash", tool_input:{command:"git commit -m x"}}' \
        | HOME="$T/home" bash "$HOOK" 2>/dev/null; }

# Положительный контроль 1: файл на месте с тем же пунктом — тишина.
O=$(run)
[ -z "$O" ] || { echo "probe_D434: контроль — на нетронутом файле страж не молчит: $O" >&2; exit 2; }
# Положительный контроль 2: файл перезаписан без пункта — страж называет D901 (он умеет говорить).
printf '# BACKLOG\n' > "$R/BACKLOG.md"
O=$(run)
grep -q 'D901' <<< "$O" || { echo "probe_D434: контроль — перезапись без D901 не названа, страж нем: [$O]" >&2; exit 2; }
git -C "$R" checkout -q -- BACKLOG.md 2>/dev/null || { echo "probe_D434: файл не восстановлен" >&2; exit 2; }

# Суд: файл удалён целиком (индекс и рабочая копия), HEAD несёт D901 — страж обязан назвать D901.
$G rm -q BACKLOG.md 2>/dev/null || { echo "probe_D434: git rm не удался" >&2; exit 2; }
[ ! -e "$R/BACKLOG.md" ] || { echo "probe_D434: файл не удалён" >&2; exit 2; }
O=$(run)
if grep -q 'D901' <<< "$O"; then
    exit 0
fi
echo "probe_D434: дефект — BACKLOG.md удалён целиком при D901 в HEAD, страж молчит: [$O]" >&2
exit 1
