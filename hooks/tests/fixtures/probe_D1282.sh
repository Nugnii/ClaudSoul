#!/usr/bin/env bash
set -u
# СУДИТ: hooks/code-review-reminder.sh hooks/module-doc-check.sh hooks/quality-gate-check.sh hooks/skill-review-check.sh hooks/claude-md-size-check.sh hooks/skill-name-ascii-guard.sh hooks/revert-signal.sh
# probe_D1282 — братья D1279: стражи суда коммита судят репозиторий, В КОТОРЫЙ идёт коммит, а не папку сессии.
#   Песочница — та же, что у сквозных ног `hooks/tests/test_adv_git_commit_scope.sh` (повод сработать у каждого стража);
#   у `skill-name-ascii-guard` своя (staged скилл с именем кириллицей), у `revert-signal` — своя (две починки одного файла):
#   (к) `git commit` в самой песочнице — страж говорит (положительный контроль);
#   (к2) `cd <подкаталог песочницы> && git commit` — страж говорит: судится корень репозитория (урок M3 D1279);
#   (п) `cd <чистый другой> && git commit` — страж молчит.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
CR="$TMP/repo"; O="$TMP/other"
mkdir -p "$CR/hooks" "$CR/skills/newone" "$CR/docs" "$CR/scripts" "$CR/.claude-docs/modules" "$CR/lessons/_drafts" "$TMP/state" || exit 2
git -C "$CR" init -q && git -C "$CR" config user.email t@e && git -C "$CR" config user.name t || exit 2
printf '# Changelog\n' > "$CR/CHANGELOG.md"; printf '# Plan\n' > "$CR/PLAN.md"; printf '# Arch\n' > "$CR/docs/architecture.md"
{ printf '# Claude\n'; for i in $(seq 1 3000); do printf 'строка контекста номер %s, набивка до порога\n' "$i"; done; } > "$CR/CLAUDE.md"
printf '# Readme v1.0.0\n' > "$CR/README.md"
git -C "$CR" add -A && git -C "$CR" commit -q -m seed || exit 2
for i in 1 2 3 4 5 6; do { for l in $(seq 1 40); do printf 'echo "строка %s"\n' "$l"; done; } > "$CR/hooks/mod$i.sh"; done
printf -- '---\nname: newone\ndescription: тест\n---\n\n# Скилл\n' > "$CR/skills/newone/SKILL.md"
git -C "$CR" add -A || exit 2
mkdir -p "$O" && git -C "$O" init -q && printf 'x\n' > "$O/f.txt" && git -C "$O" add f.txt || exit 2
A="$TMP/asc"; mkdir -p "$A/skills/кир" "$A/sub" && git -C "$A" init -q || exit 2
printf -- '---\nname: x\n---\n' > "$A/skills/кир/SKILL.md" && git -C "$A" add -A || exit 2
H="$TMP/hot"; mkdir -p "$H/sub" && git -C "$H" init -q && git -C "$H" config user.email t@e && git -C "$H" config user.name t || exit 2
for i in 1 2; do printf 'code %s\n' "$i" > "$H/real.sh"; git -C "$H" add -A && git -C "$H" commit -q -m "fix(x): правка $i" || exit 2; done
run() {   # <хук> <команда> <метка> → вывод стража; папка сессии — $RCWD (по умолчанию песочница)
    local d="${RCWD:-$CR}"
    jq -cn --arg c "$2" --arg cwd "$d" --arg s "s-d1282-$3" \
        '{session_id:$s, transcript_path:"", cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}' \
        | (cd "$d" && env -u CLAUDECODE -u AI_AGENT STATE_DIR="$TMP/state" LESSONS_DIR="$CR/lessons" bash "$R/hooks/$1.sh") 2>/dev/null
}
ev() {   # <команда> <метка> → 1, если revert-signal завёл повод «повторная починка» (он говорит файлом, а не выводом)
    mkdir -p "$TMP/st-$2"
    # Переменные выбора дерева сняты (D1366): сверщик архива после коммита экспортирует CLAUDSOUL_REPO на клон под
    # TMPDIR, а `rc_env_is_real` (hooks/root-cause-lib.sh) такое окружение считает фикстурой и повод не пишет — нога (к)
    # молчала, и проба выходила кодом 2 «рамка: revert-signal молчит».
    jq -cn --arg c "$1" --arg cwd "$H" --arg s "s-d1282-$2" '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd}' \
        | (cd "$H" && env -u CLAUDECODE -u AI_AGENT -u CLAUDSOUL_REPO -u CLAUDE_HOME -u BACKLOG_FILE STATE_DIR="$TMP/st-$2" \
            bash "$R/hooks/revert-signal.sh") >/dev/null 2>&1
    grep -q 'hotfix-repeat' "$TMP/st-$2/pending-events.jsonl" 2>/dev/null && echo 1 || echo 0
}
miss=""
for h in code-review-reminder module-doc-check quality-gate-check skill-review-check claude-md-size-check skill-name-ascii-guard; do
    [ -f "$R/hooks/$h.sh" ] || exit 2
    RCWD="$CR"; [ "$h" = skill-name-ascii-guard ] && RCWD="$A"
    sub=hooks; [ "$h" = skill-name-ascii-guard ] && sub=sub
    [ -n "$(run "$h" 'git commit -m "правка"' "k-$h")" ] || { echo "рамка: $h молчит и на коммите в самой песочнице" >&2; exit 2; }
    [ -n "$(run "$h" "cd $sub && git commit -m \"правка\"" "k2-$h")" ] || miss="$miss $h (подкаталог сессии молчит);"
    [ -z "$(run "$h" "cd \"$O\" && git commit -m \"правка\"" "p-$h")" ] || miss="$miss $h;"
done
[ -f "$R/hooks/revert-signal.sh" ] || exit 2
[ "$(ev 'git commit -m x' k-rev)" = 1 ] || { echo "рамка: revert-signal молчит и на коммите в самой песочнице" >&2; exit 2; }
[ "$(ev 'cd sub && git commit -m x' k2-rev)" = 1 ] || miss="$miss revert-signal (подкаталог сессии молчит);"
[ "$(ev "cd \"$O\" && git commit -m x" p-rev)" = 0 ] || miss="$miss revert-signal;"
[ -z "$miss" ] && { echo "коммит в другой репозиторий судится там, куда идёт: семь стражей молчат; в самой сессии и её подкаталоге говорят"; exit 0; }
echo "судят папку сессии на коммите в другой репозиторий:$miss"
exit 1
