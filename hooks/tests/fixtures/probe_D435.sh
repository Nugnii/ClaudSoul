#!/usr/bin/env bash
# probe_D435.sh — проба пункта D435: страж исчезновения судит рабочую копию, а коммит унесёт индекс (аудит B7).
# Результат: при `git commit` без -a страж сравнивает HEAD с ИНДЕКСОМ — индекс без пункта при рабочей копии с ним даёт предупреждение; индекс и рабочая копия равны HEAD — тишина; с -a судится рабочая копия и страж молчит, пока пункт в ней есть.
# Проверка результата: bash hooks/tests/fixtures/probe_D435.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась (stderr называет, что).
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой).
# Фикстура — свой git-репозиторий; HOME подменён. Судится ВЫВОД стража на payload `git commit`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/backlog-vanish-check.sh"
[ -f "$HOOK" ] || { echo "probe_D435: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D435: нужен jq" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D435: нужен git" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D435: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R" "$T/home"
G="git -C $R -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
$G init -q 2>/dev/null || { echo "probe_D435: git init не удался" >&2; exit 2; }
WITH='# BACKLOG\n\n- ☐ **D901** живой пункт\n'
printf "$WITH" > "$R/BACKLOG.md"
$G add BACKLOG.md && $G commit -qm base >/dev/null 2>&1 || { echo "probe_D435: базовый коммит не состоялся" >&2; exit 2; }
run() {  # <команда коммита> → вывод стража
    jq -cn --arg cwd "$R" --arg c "$1" '{cwd:$cwd, session_id:"probe-d435", tool_name:"Bash", tool_input:{command:$c}}' \
        | HOME="$T/home" bash "$HOOK" 2>/dev/null
}

# Положительный контроль 1: индекс и рабочая копия равны HEAD — тишина.
O=$(run "git commit -m x")
[ -z "$O" ] || { echo "probe_D435: контроль — на нетронутом дереве страж не молчит: $O" >&2; exit 2; }
# Положительный контроль 2: рабочая копия без D901 при `git commit -a` — страж называет D901 (он умеет говорить).
printf '# BACKLOG\n' > "$R/BACKLOG.md"
O=$(run "git commit -a -m x")
grep -q 'D901' <<< "$O" || { echo "probe_D435: контроль — пропажа из рабочей копии при -a не названа, страж нем: [$O]" >&2; exit 2; }
git -C "$R" checkout -q -- BACKLOG.md 2>/dev/null || { echo "probe_D435: файл не восстановлен" >&2; exit 2; }

# Суд: в ИНДЕКСЕ пустой BACKLOG.md, в рабочей копии D901 восстановлен; коммит без -a унесёт индекс.
printf '# BACKLOG\n' > "$R/BACKLOG.md"
$G add BACKLOG.md || { echo "probe_D435: индекс не собран" >&2; exit 2; }
printf "$WITH" > "$R/BACKLOG.md"
IDXTXT=$(git -C "$R" show :BACKLOG.md 2>/dev/null || true)
grep -q 'D901' <<< "$IDXTXT" && { echo "probe_D435: индекс всё ещё несёт D901 — рамка не собралась" >&2; exit 2; }
grep -q 'D901' "$R/BACKLOG.md" || { echo "probe_D435: рабочая копия без D901 — рамка не собралась" >&2; exit 2; }
O=$(run "git commit -m x")
if ! grep -q 'D901' <<< "$O"; then
    echo "probe_D435: дефект — коммит унесёт индекс без D901, а страж судит рабочую копию и молчит: [$O]" >&2
    exit 1
fi
# Та же раскладка с -a: в коммит идёт рабочая копия, D901 в ней есть — страж обязан молчать.
O=$(run "git commit -a -m x")
if [ -n "$O" ]; then
    echo "probe_D435: дефект — при -a судится рабочая копия, D901 в ней есть, а страж предупредил: $O" >&2
    exit 1
fi
exit 0
