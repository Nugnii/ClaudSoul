set -u
# СУДИТ: hooks/doc-impact-check.sh
# probe_D1093.sh — поведенческая проба D1093: хук коммита не требует решения по второму документу состояния,
#   когда первый staged. Красная на наличном дефекте (сообщение про PLAN.md выходит при staged CLAUDE.md), зелёная после.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/doc-impact-check.sh"; L="$PWD/hooks/paths-lib.sh"
[ -f "$H" ] && [ -f "$L" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
R=$(mktemp -d) || exit 2
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t
  mkdir -p .claude-docs hooks
  printf '#!/usr/bin/env bash\necho a\n' > hooks/m.sh
  printf '# PLAN\nмеханизм hooks/m.sh\n' > PLAN.md
  printf '# CLAUDE\n' > CLAUDE.md
  printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > .claude-docs/dep-index.tsv
  git add -A && git commit -qm init ) >/dev/null 2>&1 || { rm -rf "$R"; exit 2; }
# стаб индексатора: отчёт называет PLAN.md (как будто PLAN описывает изменённый механизм)
STUB="$R/stub-dg.py"
printf 'print("описывают изменённое, но не тронуты (1):")\nprint("  . PLAN.md — про hooks/m.sh")\n' > "$STUB"
hk() { jq -cn --arg c "git commit -m x" --arg d "$R" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:"s"}' \
  | env STATE_DIR="$R/state" PATHS_LIB="$L" CLAUDSOUL_ROOT="$R" DEP_INDEX_TOOL="$STUB" \
    bash "$H" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (D1222, 7 ноября 2026): правка поведения в m.sh БЕЗ документа состояния — хук обязан
# потребовать решения по PLAN.md. Без контроля проба судила только отсутствие сообщения, и выпотрошенный хук,
# молчащий всегда, её проходил (прибор свидетелей-атак числил пробу ложно-зелёной).
printf '#!/usr/bin/env bash\necho b\n' > "$R/hooks/m.sh"
git -C "$R" add hooks/m.sh >/dev/null 2>&1
CTL=$(hk)
grep -q "PLAN.md" <<< "$CTL" || { rm -rf "$R"; echo "контроль: без документа состояния хук не потребовал решения по PLAN.md"; exit 1; }
# правка поведения в m.sh + staged CLAUDE.md (документ состояния в коммите = решение принято)
printf '# CLAUDE v2\nстрока\n' > "$R/CLAUDE.md"
git -C "$R" add CLAUDE.md >/dev/null 2>&1
OUT=$(hk)
rm -rf "$R"
# дефект: при staged CLAUDE.md сообщение всё равно требует решения по PLAN.md
grep -q "документ СОСТОЯНИЯ" <<< "$OUT" && grep -q "PLAN.md" <<< "$OUT" && exit 1
exit 0
