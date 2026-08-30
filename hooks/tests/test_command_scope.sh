#!/usr/bin/env bash
# test_command_scope.sh — стражи сопоставляют ДЕЙСТВИЕ, а не текст команды.
#
# Повод конкретный, не гипотетический. За одну сессию `trust-guard` дал восемь ложных
# срабатываний, а `playwright-cli-guard` дважды ЗАБЛОКИРОВАЛ работу: сперва запись
# собственного теста, потом запись раздела BACKLOG, где описывался этот же дефект.
# Причина общая — сигнатура искалась во всей строке команды, включая то, что никогда
# не исполняется: шаблоны grep, аргументы в кавычках, тела heredoc, уходящие в файл.
#
# Все строки ниже — настоящие, снятые с этой сессии, а не придуманные для теста.
# Обе стороны обязательны: страж должен молчать на тексте И гореть на действии.
# Проверка только «молчит» превратила бы фикс в отключение стража.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

SEQ=0
_run() { # $1=хук, $2=команда → stdout хука
    SEQ=$((SEQ + 1))
    jq -cn --arg c "$2" --arg s "scope-$SEQ" \
        '{session_id:$s, transcript_path:"", cwd:"/tmp", tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" bash "$HOOKS_DIR/$1" 2>/dev/null
}

fires() { # $1=хук $2=команда $3=имя
    if [ -n "$(_run "$1" "$2")" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: страж промолчал на реальном действии"; fi
}
silent() { # $1=хук $2=команда $3=имя
    local out; out=$(_run "$1" "$2")
    if [ -z "$out" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: ложное срабатывание — $(printf '%s' "$out" | tr -d '\n' | head -c 140)"; fi
}

echo "=== trust-guard: горит на действии ==="
fires trust-guard.sh 'rm -rf /tmp/claudsoul-verify' "T1 rm -rf с путём"
fires trust-guard.sh 'T=/tmp/x; rm -rf "$T"' "T2 rm -rf с целью в кавычках — кавычки не прячут действие"
fires trust-guard.sh 'git push --force origin main' "T3 force push"
fires trust-guard.sh 'cd /repo && git reset --hard HEAD~1' "T4 reset --hard после &&"

echo "=== trust-guard: молчит на тексте (реальные строки сессии) ==="
silent trust-guard.sh 'grep -n "DESTRUCTIVE\|rm -rf\|force" hooks/trust-guard.sh' \
    "T5 read-only grep, шаблон содержит rm -rf"
silent trust-guard.sh "grep -qE '(^|[[:space:];&|])rm[[:space:]]+(-[rRfv]*[rR])' hooks/trust-guard.sh" \
    "T6 grep по собственной сигнатуре стража"
silent trust-guard.sh 'printf "%s" "git push --force origin main" >> BACKLOG.md' \
    "T7 запись строки про force push в файл"
silent trust-guard.sh 'cat > /tmp/doc.md <<'"'"'EOF'"'"'
Пример: git push --force origin main
и rm -rf каталога
EOF' "T8 тело heredoc уходит в файл"

echo "=== playwright-cli-guard: горит на исполняемом скрипте ==="
fires playwright-cli-guard.sh 'python3 - <<'"'"'PY'"'"'
from playwright.sync_api import sync_playwright
browser = chromium.launch(headless=True)
PY' "T9 heredoc в интерпретатор — настоящий scratch-скрипт"
fires playwright-cli-guard.sh 'node -e "const {chromium} = require(\"playwright\"); chromium.launch()"' \
    "T10 node -e с запуском браузера"

echo "=== playwright-cli-guard: молчит, когда тело уходит в файл ==="
silent playwright-cli-guard.sh 'cat > /tmp/test_guard.sh <<'"'"'EOF'"'"'
# фикстура теста: строка chromium.launch( ниже — данные, не запуск
echo "chromium.launch("
EOF' "T11 запись собственного теста — первый реальный блок"
silent playwright-cli-guard.sh 'cat >> BACKLOG.md <<'"'"'EOF'"'"'
- ☐ **D2** playwright-cli-guard матчит chromium.launch( в тексте команды
EOF' "T12 запись раздела BACKLOG про этот дефект — второй реальный блок"
silent playwright-cli-guard.sh 'grep -rn "chromium.launch(" hooks/' "T13 поиск строки по репозиторию"

# ============================================================================
# T14-T29 (D68): `git commit` — команда, а не текст.
#
# Восемь хуков стоят на коммите, и все восемь искали подстроку `git commit` во всей
# строке команды. `echo "как сделать git commit правильно"` при крупном диффе в
# индексе давал напоминание, хотя коммита нет. Подтверждено адверсариальным прогоном
# 22.08 на code-review-reminder; проверка фикстурой показала тот же дефект ещё у
# четырёх, включая три с «улучшенным» матчером по границам слова — граница на тексте
# в кавычках совпадает так же, как на команде.
#
# Отдельная цена у knowledge-capture-reminder: он не просто напоминает, а СЧИТАЕТ
# коммиты за сессию. Упоминание в кавычках накручивало счётчик, то есть искажало
# данные, а не только шумело.
#
# Обе стороны обязательны: молчание на тексте доказывает что-то лишь рядом с
# горением на действии — иначе фикс неотличим от отключённого стража.
# ============================================================================
CR="$TMP/commit-repo"
mkdir -p "$CR/hooks" "$CR/skills/newone" "$CR/docs" "$CR/scripts" \
         "$CR/.claude-docs/modules" "$CR/lessons/_drafts" "$TMP/state-commit"
git -C "$CR" init -q 2>/dev/null
git -C "$CR" config user.email "t@e"; git -C "$CR" config user.name "t"
printf '# Changelog\n' > "$CR/CHANGELOG.md"
printf '# Plan\n' > "$CR/PLAN.md"
printf '# Arch\n' > "$CR/docs/architecture.md"
# CLAUDE.md за порогом claude-md-size-check (100 КБ).
{ printf '# Claude\n'; for i in $(seq 1 3000); do printf 'строка контекста номер %s, набивка до порога\n' "$i"; done; } > "$CR/CLAUDE.md"
# Генератор таблиц + README с блоком: даёт повод docs-family-check (путь A2).
cat > "$CR/scripts/regen-readme-skills.sh" <<'GEN'
#!/usr/bin/env bash
# Тело блока — вторая строка каждого хука. Без `awk -v`: многострочное значение
# рвёт его на переводах строки, генератор молча не меняет файл, и сверка ложно
# показывает согласованность (поймано при отладке этой самой фикстуры).
ROOT="${1:-.}"
F="${README_FILE:-$ROOT/README.md}"
{
    sed -n '1,/HOOKS-TABLE:START/p' "$F"
    for h in "$ROOT"/hooks/*.sh; do sed -n '2p' "$h"; done
    sed -n '/HOOKS-TABLE:END/,$p' "$F"
} > "$F.new" && mv "$F.new" "$F"
GEN
printf '# Readme v1.0.0\n\n<!-- HOOKS-TABLE:START -->\nстарое\n<!-- HOOKS-TABLE:END -->\n' > "$CR/README.md"
git -C "$CR" add -A >/dev/null 2>&1
git -C "$CR" commit -q -m seed 2>/dev/null
# Крупный дифф кода + новый скилл: поводы для остальных стражей.
for i in 1 2 3 4 5 6; do
    { for l in $(seq 1 40); do printf 'echo "строка %s"\n' "$l"; done; } > "$CR/hooks/mod$i.sh"
done
printf -- '---\nname: newone\ndescription: тест\n---\n\n# Скилл\n' > "$CR/skills/newone/SKILL.md"
git -C "$CR" add -A >/dev/null 2>&1

# session_id выводится из ИМЕНИ проверки, а не из счётчика: счётчик инкрементировался
# бы внутри подстановки команд, то есть в субшелле, и наружу не возвращался. Все вызовы
# шли бы с одним session_id — throttle от «горит» глушил бы следующее «молчит», и тест
# был бы зелёным независимо от поведения стража. Поймано отладкой, а не прогоном.
_sid_of() { printf '%s' "$1" | tr -cd '[:alnum:]-' | head -c 48; }
_run_commit() { # $1=хук $2=команда $3=session_id
    jq -cn --arg c "$2" --arg cwd "$CR" --arg s "$3" \
        '{session_id:$s, transcript_path:"", cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state-commit" LESSONS_DIR="$CR/lessons" bash "$HOOKS_DIR/$1" 2>/dev/null
}
c_fires() { # $1=хук $2=команда $3=имя $4=sid (опц.)
    if [ -n "$(_run_commit "$1" "$2" "${4:-$(_sid_of "$3")}")" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: страж промолчал на настоящем коммите"; fi
}
c_silent() { # $1=хук $2=команда $3=имя $4=sid (опц.)
    local out; out=$(_run_commit "$1" "$2" "${4:-$(_sid_of "$3")}")
    if [ -z "$out" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: ложное срабатывание — $(printf '%s' "$out" | tr -d '\n' | head -c 140)"; fi
}

TEXT='echo "как сделать git commit правильно"'
N=13
for HOOK in code-review-reminder changelog-reminder module-doc-check quality-gate-check \
            skill-review-check claude-md-size-check docs-family-check; do
    N=$((N + 1))
    c_fires  "$HOOK.sh" 'git commit -m "правка"'  "T$N-a $HOOK горит на настоящем коммите"
    N=$((N + 1))
    c_silent "$HOOK.sh" "$TEXT"                    "T$N-b $HOOK молчит на упоминании в кавычках"
done

# knowledge-capture-reminder считает коммиты, а не реагирует на один: порог 5.
# Ложное срабатывание там искажает счётчик, поэтому проверяются оба направления.
for _ in 1 2 3 4 5; do OUT_KCR=$(_run_commit knowledge-capture-reminder.sh 'git commit -m "правка"' "kcr-real"); done
if [ -n "$OUT_KCR" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T28-a knowledge-capture-reminder горит после порога коммитов]"; fi
for _ in 1 2 3 4 5 6 7; do OUT_KCR2=$(_run_commit knowledge-capture-reminder.sh "$TEXT" "kcr-text"); done
if [ -z "$OUT_KCR2" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T28-b]: текст в кавычках накрутил счётчик коммитов — $(printf '%s' "$OUT_KCR2" | tr -d '\n' | head -c 120)"; fi

# T29: heredoc, уходящий в файл, — тоже не коммит. Реальный случай: запись раздела
# BACKLOG про этот самый дефект (тот же класс, что T11-T12 у playwright-cli-guard).
c_silent code-review-reminder.sh 'cat >> BACKLOG.md <<'"'"'EOF'"'"'
- ☐ **D68** code-review-reminder считает коммитом любую строку с git commit
EOF' "T29 heredoc с текстом про git commit"

# ============================================================================
# T30: границы самого матчера (is_git_commit), а не поведения стражей.
#
# Понадобились после мутационной проверки: ослабление `[[:space:]]+commit([[:space:]]|$)`
# до `[[:space:]]*commit` не уронило ни одного теста выше — поведение стражей на
# типовых строках от этой границы не зависит. То есть `gitcommit` и `git commit-tree`
# прошли бы как коммит, и никто бы не заметил.
# ============================================================================
# shellcheck source=/dev/null
source "$HOOKS_DIR/command-scope-lib.sh"
igc_yes() { if is_git_commit "$1"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [T30 $2]: не распознан коммит: $1"; fi; }
igc_no()  { if is_git_commit "$1"; then FAIL=$((FAIL + 1)); echo "FAIL [T30 $2]: принято за коммит: $1"; else PASS=$((PASS + 1)); fi; }

igc_yes 'git commit'                          "голая команда"
igc_yes 'git commit -m "правка"'              "с сообщением"
igc_yes 'cd /repo && git commit -m x'         "после &&"
igc_yes 'git add -A; git commit -m x'         "после ;"
igc_yes 'git -C /path commit -m x'            "с -C"
igc_yes 'git --no-pager commit'               "с --no-pager"
igc_yes 'git -c user.name=t commit -m y'      "с -c"
igc_no  'echo "как сделать git commit"'       "текст в кавычках"
igc_no  "printf '%s' 'git commit' >> B.md"    "текст в апострофах"
igc_no  'gitcommit -m x'                      "нет границы слева"
igc_no  'git commit-tree abc'                 "нет границы справа — другая подкоманда"
igc_no  'git diff --name-only commit'         "commit как аргумент опции"
igc_no  'grep -rn "git commit" hooks/'        "шаблон поиска"
igc_yes '/usr/local/bin/git commit -m x'      "полный путь к git"
igc_no  'mygit commit -m x'                   "чужая команда с суффиксом git"

echo ""
echo "command scope tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
