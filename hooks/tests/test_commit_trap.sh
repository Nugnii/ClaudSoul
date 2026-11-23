#!/usr/bin/env bash
# СУДИТ: hooks/commit-trap.sh
# test_commit_trap.sh — ловушки git стражей коммита (D1022): установка, суд по индексу и сообщению коммита, молчание
# PreToolUse там, где ловушка стоит, упавший страж коммит не держит.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRAP="$HOOK_DIR/commit-trap.sh"
ROOT="$(cd "$HOOK_DIR/.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$TMP/wt" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
printf '[user]\n\tname = t\n\temail = t@t\n' > "$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$ROOT"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
has() { grep -qF -- "$2" <<< "$1"; }
# commit <репозиторий> <аргументы коммита…> → stderr+stdout в $OUT, 0 если HEAD сдвинулся
commit() { local r="$1" h0; shift; h0=$(git -C "$r" rev-parse -q --verify HEAD 2>/dev/null)
    OUT=$(git -C "$r" commit "$@" 2>&1); [ "$(git -C "$r" rev-parse -q --verify HEAD 2>/dev/null)" != "$h0" ]; }
newrepo() { git init -q "$1" && printf 'x\n' > "$1/seed" && git -C "$1" add seed && git -C "$1" commit -qm init; }
# guard <страж> <команда> <каталог> <сессия> → вывод стража на PreToolUse (сессия у каждой ноги своя: дроссели)
guard() { jq -cn --arg c "$2" --arg d "$3" --arg s "$4" '{session_id:$s,tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
        | (cd "$3" && bash "$HOOK_DIR/$1.sh" 2>/dev/null); }
# commit_ed <репозиторий> <файл сообщения> — коммит через редактор: git снимает строки-комментарии (режим strip)
commit_ed() { local r="$1" m="$2" h0; h0=$(git -C "$r" rev-parse -q --verify HEAD 2>/dev/null)
    OUT=$(GIT_EDITOR="cp '$m'" git -C "$r" commit 2>&1); [ "$(git -C "$r" rev-parse -q --verify HEAD 2>/dev/null)" != "$h0" ]; }

# --- установка ------------------------------------------------------------------------------------------------------
R="$TMP/r"; newrepo "$R"
bash "$TRAP" --install "$R" >/dev/null 2>&1 \
  && grep -q claudsoul-commit-trap "$R/.git/hooks/commit-msg" && grep -q claudsoul-merge-root-gate "$R/.git/hooks/commit-msg" \
  && grep -q claudsoul-commit-trap "$R/.git/hooks/pre-commit" && [ -x "$R/.git/hooks/pre-commit" ] && ok \
  || bad I1 "обе ловушки с метками не встали"
bash "$TRAP" --install "$R" >/dev/null 2>&1 && ok || bad I2 "повторная установка своей ловушки не прошла"
# Старая ловушка суда корня (только его метка) переписывается своей.
F="$TMP/f"; newrepo "$F"
printf '#!/bin/sh\n# claudsoul-merge-root-gate: починка без пункта и корня в main не входит (D1021). Ставит: merge-root-gate.sh --install\nexit 0\n' > "$F/.git/hooks/commit-msg"; chmod +x "$F/.git/hooks/commit-msg"
bash "$TRAP" --install "$F" >/dev/null 2>&1 && grep -q claudsoul-commit-trap "$F/.git/hooks/commit-msg" && ok \
  || bad I3 "старая ловушка суда корня не заменена"
# Чужая commit-msg не переписывается, код 2, совет называет строку; pre-commit ставится.
printf '#!/bin/sh\nexit 0\n' > "$F/.git/hooks/commit-msg"; rm -f "$F/.git/hooks/pre-commit"
ADV=$(bash "$TRAP" --install "$F" 2>&1); rc=$?
[ "$rc" = 2 ] && [ "$(cat "$F/.git/hooks/commit-msg")" = "$(printf '#!/bin/sh\nexit 0')" ] \
  && has "$ADV" "claudsoul-commit-trap claudsoul-merge-root-gate" && [ -x "$F/.git/hooks/pre-commit" ] && ok \
  || bad I4 "чужая commit-msg: код $rc, переписана или совет без меток"
# core.hooksPath внутри рабочего дерева — отказ, файлов нет.
HP="$TMP/hp"; newrepo "$HP"; git -C "$HP" config core.hooksPath .githooks
bash "$TRAP" --install "$HP" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -e "$HP/.githooks/commit-msg" ] && [ ! -e "$HP/.githooks/pre-commit" ] && ok \
  || bad I5 "ловушка легла в каталог внутри рабочего дерева (код $rc)"
# Установка через суд корня передаётся сюда.
M="$TMP/m"; newrepo "$M"
bash "$HOOK_DIR/merge-root-gate.sh" --install "$M" >/dev/null 2>&1 && grep -q claudsoul-commit-trap "$M/.git/hooks/pre-commit" && ok \
  || bad I6 "merge-root-gate.sh --install не поставил общую ловушку"
has "$ADV" "@ $TRAP" && ok || bad I7 "совет установки без адреса стража: $ADV"
# Владелец дописал совет в чужие ловушки — повтор установки их не затирает (скептик D1022, F4).
W4="$TMP/w4"; newrepo "$W4"; for t in commit-msg pre-commit; do printf '#!/bin/sh
echo чужое
' > "$W4/.git/hooks/$t"; chmod +x "$W4/.git/hooks/$t"; done
bash "$TRAP" --install "$W4" 2>&1 | grep 'строку: ' | sed 's/.*строку: //' > "$TMP/advice"
while IFS= read -r l; do case "$l" in *--commit-msg*) t=commit-msg ;; *) t=pre-commit ;; esac; printf '%s\n' "$l" >> "$W4/.git/hooks/$t"; done < "$TMP/advice"
bash "$TRAP" --install "$W4" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'чужое' "$W4/.git/hooks/commit-msg" && grep -q 'чужое' "$W4/.git/hooks/pre-commit" && ok \
  || bad I8 "повтор установки затёр чужую ловушку с дописанной строкой (код $rc)"

# --- упавший страж не держит коммит, отказавший — держит ------------------------------------------------------------
FK="$TMP/fake hooks"; mkdir -p "$FK"; cp "$TRAP" "$HOOK_DIR/paths-lib.sh" "$FK/"
printf '#!/usr/bin/env bash\nexit 3\n' > "$FK/docs-family-check.sh"
K="$TMP/k"; newrepo "$K"; bash "$FK/commit-trap.sh" --install "$K" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
printf 'y\n' > "$K/seed"; git -C "$K" add seed
commit "$K" -m "chore: x" && has "$OUT" "docs-family-check упал" && ok || bad C1 "упавший страж: коммит не вошёл или не назван: $OUT"
printf '#!/usr/bin/env bash\necho "нельзя" >&2; exit "$CT_REFUSE_RC"\n' > "$FK/docs-family-check.sh"
printf 'z\n' > "$K/seed"; git -C "$K" add seed
commit "$K" -m "chore: x" && bad C2 "отказ стража не удержал коммит" || { has "$OUT" "нельзя" && ok || bad C2 "причина отказа не видна: $OUT"; }
# Код 1 — то, чем падает bash сам (`set -u`, нет библиотеки): это «упал», а не отказ (скептик D1022, F5).
printf '#!/usr/bin/env bash\necho "Missing throttle-lib.sh" >&2; exit 1\n' > "$FK/docs-family-check.sh"
commit "$K" -m "chore: x" && has "$OUT" "docs-family-check упал" && ok || bad C3 "падение кодом 1 прочитано отказом: $OUT"
# След прохода (D1023): коммит, пропущенный commit-msg, post-commit второй раз не судит; обход — судит и снимает.
printf '#!/usr/bin/env bash\ncase "$1" in --judge-commit) echo "$3" >> "%s"; exit 1 ;; esac\nexit 0\n' "$TMP/judged" > "$FK/merge-root-gate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FK/docs-family-check.sh"; : > "$TMP/judged"
h0=$(git -C "$K" rev-parse HEAD); printf 'u\n' > "$K/seed"; git -C "$K" add seed
OUT=$(CLAUDECODE=1 git -C "$K" commit -q -m "chore: через ловушку" 2>&1)
[ "$(git -C "$K" rev-parse HEAD)" != "$h0" ] && [ ! -s "$TMP/judged" ] && ok \
  || bad E9 "коммит через ловушку судился второй раз (след прохода не прочитан): $(cat "$TMP/judged") $OUT"
h0=$(git -C "$K" rev-parse HEAD); printf 'w2\n' > "$K/seed"; git -C "$K" add seed
OUT=$(CLAUDECODE=1 git -C "$K" commit -q -n -m "chore: в обход" 2>&1)
[ "$(git -C "$K" rev-parse HEAD)" = "$h0" ] && [ -s "$TMP/judged" ] && ok \
  || bad E9b "обход ловушки не судился в post-commit либо не снят: $OUT"
git -C "$K" reset -q --hard HEAD

# --- backlog-vanish-check в ловушке: «после» — индекс, «закрыт» — сообщение -----------------------------------------
B="$TMP/b"; newrepo "$B"; bash "$TRAP" --install "$B" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
printf -- '- ☐ **D10** первый\n- ☐ **D11** второй\n' > "$B/BACKLOG.md"; git -C "$B" add BACKLOG.md; git -C "$B" commit -qm "chore: долг"
printf -- '- ☐ **D10** первый\n' > "$B/BACKLOG.md"; git -C "$B" add BACKLOG.md
printf -- '- ☐ **D10** первый\n- ☐ **D11** второй\n' > "$B/BACKLOG.md"     # на диске пункт есть, в индексе — нет
commit "$B" -m "chore: правка" ; has "$OUT" "D11" && has "$OUT" "исчезли" && ok || bad V1 "пропажа в индексе не названа: $OUT"
git -C "$B" reset -q --hard HEAD~1
printf -- '- ☐ **D10** первый\n' > "$B/BACKLOG.md"                          # на диске пропал, индекс цел
printf 'q\n' > "$B/seed"; git -C "$B" add seed
commit "$B" -m "chore: код"; has "$OUT" "исчезли" && bad V2 "пропажа только на диске названа: коммит её не несёт" || ok
git -C "$B" checkout -q -- BACKLOG.md
printf 'D10 закрыт правкой\n' > "$TMP/msg"; printf 'w\n' > "$B/seed"; git -C "$B" add seed
commit "$B" -F "$TMP/msg"; has "$OUT" "объявлен закрытым" && ok || bad V3 "«закрыт» в файле -F не прочитан: $OUT"
printf 'chore: y\n# D10 закрыт\n' > "$TMP/msgc"; printf 'v\n' > "$B/seed"; git -C "$B" add seed
commit_ed "$B" "$TMP/msgc"; has "$OUT" "объявлен закрытым" && bad V4 "строка-комментарий, которую git вырезал, прочитана заявлением" || ok
printf -- '- ☐ **D10** первый\n' > "$B/BACKLOG.md"; git -C "$B" add BACKLOG.md     # D11 пропал из индекса
[ -z "$(guard backlog-vanish-check 'git commit -m x' "$B" tct-v5)" ] && ok || bad V5 "PreToolUse говорит там, где судит ловушка"
has "$(guard backlog-vanish-check 'git commit --no-verify -m x' "$B" tct-v6)" "D11" && ok \
  || bad V6 "обход ловушки: PreToolUse замолчал, и пропажу не судит никто"
git -C "$B" checkout -q HEAD -- BACKLOG.md

# --- changelog-reminder: в ловушке — индекс; PreToolUse молчит, где ловушка стоит, и говорит, где её нет --------------
C="$TMP/c"; newrepo "$C"; printf '# changelog\n' > "$C/CHANGELOG.md"; mkdir -p "$C/hooks"
git -C "$C" add CHANGELOG.md || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
git -C "$C" commit -qm init2 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
bash "$TRAP" --install "$C" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
printf 'a\n' > "$C/hooks/f.sh"; git -C "$C" add hooks/f.sh
commit "$C" -m "feat: f"; has "$OUT" "CHANGELOG" && ok || bad L1 "напоминание в ловушке не вышло: $OUT"
printf 'b\n' > "$C/hooks/f.sh"; printf 'запись\n' >> "$C/CHANGELOG.md"; git -C "$C" add hooks/f.sh CHANGELOG.md
commit "$C" -m "feat: f"; has "$OUT" "CHANGELOG" && bad L2 "CHANGELOG в коммите, а напоминание вышло" || ok
pre() { guard changelog-reminder "$@"; }
printf 'c\n' > "$C/hooks/f.sh"; git -C "$C" add hooks/f.sh
[ -z "$(pre 'git commit -m x' "$C" tct-l3)" ] && ok || bad L3 "PreToolUse говорит там, где судит ловушка"
N="$TMP/n"; newrepo "$N"; printf '# changelog\n' > "$N/CHANGELOG.md"; mkdir -p "$N/hooks"; printf 'a\n' > "$N/hooks/f.sh"
git -C "$N" add CHANGELOG.md; git -C "$N" commit -qm init2; git -C "$N" add hooks/f.sh
has "$(pre 'git commit -m x' "$N" tct-l4)" "CHANGELOG" && ok || bad L4 "без ловушки PreToolUse замолчал (решение владельца: оставить как есть)"
has "$(pre 'git commit -n -m x' "$C" tct-l5)" "CHANGELOG" && ok || bad L5 "обход -n: PreToolUse замолчал при ловушке, которую команда не исполнит"
has "$(pre 'git commit -m x && git log -n 1' "$C" tct-l5b)" "CHANGELOG" && bad L5b "-n соседней команды прочитан обходом" || ok
# Мёртвая ловушка: шим указывает на убранную установку и выходит с 0 — PreToolUse обязан судить (скептик D1022, F3).
DH="$TMP/dead hooks"; mkdir -p "$DH"; cp "$TRAP" "$HOOK_DIR/paths-lib.sh" "$DH/"
bash "$DH/commit-trap.sh" --install "$C" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
mv "$DH/commit-trap.sh" "$DH/gone.sh" || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
has "$(pre 'git commit -m x' "$C" tct-l6)" "CHANGELOG" && ok || bad L6 "мёртвая ловушка заглушила PreToolUse"
bash "$TRAP" --install "$C" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }

# --- docs-family Path B в ловушке судит индекс, а не рабочее дерево (мутация M6 скептика D1022) ---
P="$TMP/p"; newrepo "$P"; mkdir -p "$P/web/lib"; printf 'a\n' > "$P/web/lib/a-service.ts"; git -C "$P" add web; git -C "$P" commit -qm svc
bash "$TRAP" --install "$P" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
# В коммите — не документ: README снял бы подсказку Path B при любой редакции, и нога не различала бы (мутация M6).
printf 'b\n' > "$P/web/lib/a-service.ts"; printf 'r\n' > "$P/seed"; git -C "$P" add seed   # сервис правлен только на диске
commit "$P" -m "chore: r"; has "$OUT" "Doc drift" && bad B1 "правка только на диске названа: коммит её не несёт" || ok
git -C "$P" add web/lib/a-service.ts
commit "$P" -m "feat: s"; has "$OUT" "Doc drift" && ok || bad B2 "сервис в коммите без документов, а подсказки нет: $OUT"

# --- обход ловушки (D1023): след прохода, post-commit снимает непропущенную починку агента -----------------------------
# Стоит ДО копии ClaudSoul: та дописывает core.hooksPath в общие настройки теста.
# mkjudged <каталог> [настройка git…] — судимый репозиторий (карта корней, бэклог с пунктом X1) с ловушкой
mkjudged() { local d="$1"; shift; mkdir -p "$d/src" "$d/scripts/probes"; git init -q -b main "$d"
    for c in "$@"; do git -C "$d" config "${c%%=*}" "${c#*=}"; done
    printf '%s\n' '# ROOTS' '' '## R1 — тестовый корень' '**Устройство.** src делает BAD.' \
        '**Признак.** `scripts/probes/R1.sh`' '**Зависимости (чек-лист регрессии).** —' '**Держит.** —' > "$d/ROOTS.md"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/probes/R1.sh"
    printf '%s\n' '# BACKLOG' '' '### X1 ☐ [P2] пункт с корнем' '**Корень.** R1' > "$d/BACKLOG.md"
    printf 'module.exports = 1;\n' > "$d/src/a.js"; git -C "$d" add -A; git -C "$d" commit -qm init
    bash "$TRAP" --install "$d" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
    }
J="$TMP/j"; mkjudged "$J"
[ -x "$J/.git/hooks/post-commit" ] && grep -q claudsoul-commit-trap "$J/.git/hooks/post-commit" && ok \
  || bad E0 "ловушка post-commit не встала"
fresh() { printf 'module.exports = %s;\n' "$1" > "$J/src/a.js"; git -C "$J" add src/a.js; }
head_of() { git -C "$J" rev-parse HEAD; }
h0=$(head_of); fresh 2
OUT=$(CLAUDECODE=1 git -C "$J" -c alias.ci='commit -n' ci -q -m "fix: правка без пункта" 2>&1)
[ "$(head_of)" = "$h0" ] && has "$OUT" "коммит снят" && [ -n "$(git -C "$J" diff --cached --name-only)" ] && ok \
  || bad E1 "починка без пункта в обход ловушки (псевдоним commit -n) осталась в main: $OUT"
OUT=$(CLAUDECODE=1 git -C "$J" commit -q -n -m "fix: правка (X1)" 2>&1)
[ "$(head_of)" != "$h0" ] && ok || bad E2 "обход с пунктом и корнем снят: $OUT"
h0=$(head_of); fresh 3
OUT=$(env -u CLAUDECODE -u AI_AGENT git -C "$J" commit -q -n -m "fix: владелец без пункта" 2>&1)
[ "$(head_of)" != "$h0" ] && ok || bad E3 "--no-verify владельца в терминале снят (его право): $OUT"
h0=$(head_of); fresh 4
OUT=$(CLAUDECODE=1 git -C "$J" commit -q -m "chore: учёт" 2>&1)
[ "$(head_of)" != "$h0" ] && ok || bad E4 "коммит через ловушку не вошёл: $OUT"
# cherry-pick зовёт post-commit: починка без пункта снимается тем же откатом.
git -C "$J" checkout -q -b side; printf 'module.exports = 8;\n' > "$J/src/a.js"; git -C "$J" add src/a.js
env -u CLAUDECODE -u AI_AGENT git -C "$J" commit -q -n -m "fix: на ветке без пункта"; pk=$(git -C "$J" rev-parse HEAD)
git -C "$J" checkout -q main; h0=$(head_of)
OUT=$(CLAUDECODE=1 git -C "$J" cherry-pick "$pk" 2>&1)
[ "$(head_of)" = "$h0" ] && has "$OUT" "коммит снят" && ok || bad E8 "cherry-pick починки без пункта остался в main: $OUT"
git -C "$J" reset -q --hard "$h0"
# Коммит без родителя судится от пустого дерева: пустая основа сравнивала его с HEAD, то есть с ним самим (скептик, b11).
c=$(git -C "$J" commit-tree "HEAD^{tree}" -m "fix: сирота без пункта")
CLAUDECODE=1 bash "$HOOK_DIR/merge-root-gate.sh" --judge-commit "$J" "$c" >/dev/null 2>&1; r=$?
[ "$r" -eq 1 ] && ok || bad E11 "коммит без родителя с кодом и без пункта пропущен судом (код $r)"
# Ветка удалена, обход даёт корневой коммит: `HEAD@{1}` отвечает им самим — «снят» здесь было бы неправдой.
h0=$(head_of); fresh 9; git -C "$J" update-ref -d refs/heads/main
OUT=$(CLAUDECODE=1 git -C "$J" commit -q -n -m "fix: корневой без пункта" 2>&1)
{ [ "$(head_of)" = "$h0" ] || has "$OUT" "снять его нечем"; } && ok \
  || bad E12 "корневой обход назван снятым, а остался в main: $OUT"
git -C "$J" update-ref refs/heads/main "$h0"; git -C "$J" reset -q --hard "$h0"
# Без журнала ссылок прежняя вершина неизвестна: `--amend` в обход называется, а исходный коммит не уносится откатом к
# HEAD^ (скептик, f02b).
J2="$TMP/j2"; mkjudged "$J2" core.logAllRefUpdates=false; i2=$(git -C "$J2" rev-parse HEAD)
printf 'module.exports = 5;\n' > "$J2/src/a.js"; git -C "$J2" add src/a.js
CLAUDECODE=1 git -C "$J2" commit -q -m "chore: законный" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
printf 'module.exports = 6;\n' > "$J2/src/a.js"; git -C "$J2" add src/a.js
OUT=$(CLAUDECODE=1 git -C "$J2" commit -q -n --amend -m "fix: без пункта" 2>&1)
[ "$(git -C "$J2" rev-parse HEAD^)" = "$i2" ] && has "$OUT" "снять его нечем" && ok \
  || bad E10 "без журнала ссылок откат обхода --amend унёс исходный коммит либо обход не назван: $OUT"

# --- docs-family-check и doc-impact-check в копии ClaudSoul: отказ автотаблиц, учёт входит в коммит, doc-state в -F ----
if git -C "$ROOT" worktree add -q --detach "$TMP/wt" HEAD >/dev/null 2>&1; then
    WT="$TMP/wt"; mkdir -p "$TMP/wthooks"
    printf '[core]\n\thooksPath = %s\n' "$TMP/wthooks" >> "$TMP/gitconfig"
    bash "$TRAP" --install "$WT" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
    H=hooks/revert-signal.sh
    sed '2s/$/ (тест D1022)/' "$WT/$H" > "$TMP/h" && cp "$TMP/h" "$WT/$H" && git -C "$WT" add "$H"
    commit "$WT" -m "docs: шапка" && bad D1 "расхождение автотаблиц вошло в коммит" \
        || { has "$OUT" "Автотаблицы разошлись" && ok || bad D1 "отказ без причины: $OUT"; }
    [ -z "$(guard docs-family-check 'git commit -m x' "$WT" tct-d1b)" ] && ok || bad D1b "PreToolUse автотаблиц говорит там, где судит ловушка"
    has "$(guard docs-family-check 'git commit -n -m x' "$WT" tct-d1c)" '"deny"' && ok \
        || bad D1c "обход -n: расхождение таблиц не судит никто (скептик D1022, F2)"
    git -C "$WT" checkout -q HEAD -- "$H"
    printf '\nrevert_signal_trap_probe() { :; }\n' >> "$WT/$H"; git -C "$WT" add "$H"
    [ -z "$(guard doc-impact-check 'git commit -m x' "$WT" tct-d5)" ] && ok || bad D5 "PreToolUse отчёта о документах говорит там, где судит ловушка"
    [ -n "$(guard doc-impact-check 'git commit --no-verify -m x' "$WT" tct-d5b)" ] && ok || bad D5b "обход: отчёт о документах не дал никто"
    git -C "$WT" checkout -q HEAD -- .claude-docs/dep-index.tsv 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
    git -C "$WT" add "$H" || { echo "подготовка мира не удалась: hooks/tests/test_commit_trap.sh:$LINENO" >&2; exit 1; }
    printf 'feat: имя\n\ndoc-state: не задето — проба ловушки\n' > "$TMP/msg"
    if commit "$WT" -F "$TMP/msg"; then
        grep -qx '.claude-docs/dep-index.tsv' <<< "$(git -C "$WT" show --name-only --format= HEAD)" && ok \
            || bad D2 "пересобранный учёт не вошёл в коммит: $OUT"
        has "$OUT" "документ СОСТОЯНИЯ" && bad D3 "doc-state: в файле -F не прочитан" || ok
        [ -z "$(git -C "$WT" diff --cached --name-only)" ] && ok || bad D4 "после коммита индекс разошёлся с HEAD"
    else
        bad D2 "коммит с новым именем не вошёл: $OUT"
    fi
    # Решение только в строке-комментарии, которую git вырезает, — решения нет (скептик D1022, F6).
    printf '\nrevert_signal_trap_probe2() { :; }\n' >> "$WT/$H"; git -C "$WT" add "$H"
    printf 'feat: имя2\n# doc-state: не задето — в комментарии\n' > "$TMP/msgc"
    commit_ed "$WT" "$TMP/msgc" && { has "$OUT" "документ СОСТОЯНИЯ" && ok || bad D6 "doc-state: из вырезанного комментария засчитан: $OUT"; } \
        || bad D6 "коммит через редактор не вошёл: $OUT"
    # Коммит путями: учёт не пересобирается в обход основного индекса и называется (скептик D1022, F1).
    printf '\nrevert_signal_trap_probe3() { :; }\n' >> "$WT/$H"
    if commit "$WT" -F "$TMP/msg" -- "$H"; then
        has "$OUT" "коммит путями" && ok || bad D7 "коммит путями: учёт не назван: $OUT"
        [ -z "$(git -C "$WT" diff --cached --name-only)" ] && ok || bad D7b "после коммита путями индекс разошёлся с HEAD — следующий коммит откатит учёт"
    else
        bad D7 "коммит путями не вошёл: $OUT"
    fi
else
    bad D0 "копия ClaudSoul не создалась"
fi

echo "test_commit_trap: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
