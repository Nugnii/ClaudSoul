#!/usr/bin/env bash
# test_git_add_sweep_guard.sh — свидетель стража захвата `git add` каталогом.
#
# Судит ПОВЕДЕНИЕ на настоящем репозитории во временном каталоге: страж зовёт git,
# поэтому фикстура — репозиторий, а не подставной вывод.
#
# Нога T7 — свидетель дефекта, пойманного при написании самого стража: проверка
# «этот путь неотслеживаем» стояла конвейером `printf | grep -q`, а `grep -q` выходит
# на первом совпадении; под `set -o pipefail` успешное совпадение читалось бы как
# провал, когда производителю есть что дописать после выхода потребителя. Нога даёт
# ровно такой мир: сотни неотслеживаемых файлов, совпадение в начале списка.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/git-add-sweep-guard.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT не найден"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
mkdir -p "$REPO/docs"
echo tracked > "$REPO/docs/tracked.md"
git -C "$REPO" add docs/tracked.md
git -C "$REPO" commit -qm base

# Неотслеживаемое — то, чего автор команды не называл.
echo new > "$REPO/docs/secret.ru.md"

payload() {  # $1 — команда, $2 — cwd (по умолчанию $REPO), $3 — tool_name
    jq -cn --arg c "$1" --arg d "${2:-$REPO}" --arg t "${3:-Bash}" \
        '{tool_name: $t, tool_input: {command: $c}, cwd: $d}'
}

run() { payload "$@" | bash "$SCRIPT" 2>/dev/null; }

assert_fires() {  # $1 — метка, $2 — команда, $3 — что обязано быть названо
    local out; out=$(run "$2")
    local dec; dec=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
    local why; why=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
    # here-string, а не конвейер: см. шапку, нога T7 — тот же дефект, что она судит
    if [ "$dec" = "ask" ] && grep -qF "$3" <<< "$why"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [$1]: решение='$dec', в поводе нет '$3'"
    fi
}

assert_silent() {  # $1 — метка, далее аргументы payload
    local label="$1"; shift
    local out; out=$(run "$@")
    if [ -z "$out" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: ждали молчания, получили: $out"
    fi
}

# T1 — каталогом: файл не назван, страж обязан показать его поимённо.
assert_fires "T1 каталогом" "git add -A -- docs" "docs/secret.ru.md"

# T2 — поимённо: автор назвал файл сам, вопроса нет.
assert_silent "T2 поимённо" "git add docs/secret.ru.md"

# T3 — осознанный обход записан в команде.
assert_silent "T3 обход" "CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add -A -- docs"

# T4 — не Bash.
assert_silent "T4 чужой инструмент" "git add -A" "$REPO" "Write"

# T5 — не репозиторий: судить нечем, страж молчит.
mkdir -p "$TMP/plain"
assert_silent "T5 вне репозитория" "git add -A" "$TMP/plain"

# T6 — в индекс идёт только УЖЕ отслеживаемое изменение.
echo changed >> "$REPO/docs/tracked.md"
assert_silent "T6 только отслеживаемое" "git add docs/tracked.md"

# T7 — регрессия конвейера: совпадение в начале длинного списка неотслеживаемых.
for i in $(seq 1 300); do echo x > "$REPO/docs/zz$i.tmp"; done
assert_fires "T7 длинный список" "git add -A -- docs" "docs/secret.ru.md"
rm -f "$REPO"/docs/zz*.tmp

# --- Ноги, заведённые по находкам скептика 19 сентября 2026 ---------------------------
# Каждая названа находкой: свидетель из семи ног не различал мутанта, снимавшего
# ЕДИНСТВЕННУЮ содержательную строку стража, и молчал о трёх формах вызова.

# T8 — СУБЪЕКТ СТРАЖА. Отслеживаемый файл, НЕ названный в команде буквально, в перечень
# захвата попадать не смеет. Без этой ноги мутант `grep -qxF … || continue` → `:` проходил
# 7 из 7: остальные ноги либо называют файл буквально (и он отсекается вторым условием),
# либо не имеют в дереве изменённого отслеживаемого файла.
echo changed2 >> "$REPO/docs/tracked.md"
_t8=$(run "git add -A -- docs")
_t8why=$(printf '%s' "$_t8" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
if grep -qF "docs/secret.ru.md" <<< "$_t8why" && ! grep -qF "docs/tracked.md" <<< "$_t8why"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T8 отслеживаемый не предмет]: в поводе ждали secret.ru.md без tracked.md, получили: $_t8why"
fi

# T9-T11 — ФОРМЫ ВЫЗОВА, на которых прежняя редакция молчала: глобальный ключ между `git`
# и `add`, два пробела, несколько вызовов в строке (жадный разбор брал последний).
assert_fires "T9 git -C" "git -C . add -A -- docs" "docs/secret.ru.md"
assert_fires "T10 два пробела" "git   add -A -- docs" "docs/secret.ru.md"
assert_fires "T11 два вызова в строке" "git add -A -- docs && git add docs/tracked.md" "docs/secret.ru.md"

# T12 — ОБХОД СНИМАЕТСЯ ПРИСВАИВАНИЕМ, а не упоминанием литерала в кавычках.
assert_fires "T12 обход в кавычках не снимает" \
    'echo "CLAUDSOUL_ALLOW_ADD_SWEEP=1 это обход"; git add -A -- docs' "docs/secret.ru.md"

# T13-T14 — СТРАЖ СУДИТ КОМАНДУ, А НЕ ИСПОЛНЯЕТ ЕЁ. Текст непринятой команды оболочке не
# отдаётся: первая редакция звала `eval`, и подстановка отрабатывала ДО решения владельца,
# а относительное перенаправление писало в рабочее дерево.
_mark="$TMP/EXECUTED"
rm -f "$_mark"
run "git add \$(touch $_mark)" >/dev/null 2>&1
run "git add \`touch $_mark\`" >/dev/null 2>&1
if [ ! -e "$_mark" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T13 подстановка исполнилась]: страж развернул текст команды оболочкой"
fi
run "git add docs > docs/OOPS.txt" >/dev/null 2>&1
if [ ! -e "$REPO/docs/OOPS.txt" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T14 запись в дерево]: перенаправление из текста команды создало файл"
    rm -f "$REPO/docs/OOPS.txt"
fi

# --- Ноги D471: три формы, на которых страж молчал, найдены противником 20 сентября 2026 --
# Все три — один корень: перечень «что уйдёт в индекс» имел ДВУХ владельцев, отвечавших в
# РАЗНЫХ единицах. `git add --dry-run` называет файлы поимённо и как есть; `git status
# --porcelain` без `-uall` схлопывает целиком новый каталог в одну строку, а при
# `core.quotePath` (умолчание) отдаёт не-ASCII путь в кавычках с восьмеричными escape.
# Сверка `grep -qxF` не совпадала ни разу, и «файл не захвачен» было неотличимо от «страж
# его не разглядел». Третья форма — тот же класс в признаке обхода: литерал искался в
# ТЕКСТЕ команды, а не в команде.

# T15 — ЦЕЛИКОМ НОВЫЙ КАТАЛОГ. Без `-uall` мир отвечает `?? brandnew/`, а захват идёт
# поимённо — страж молчал ровно на той форме, ради которой написан.
mkdir -p "$REPO/brandnew"
echo a > "$REPO/brandnew/a.md"
echo b > "$REPO/brandnew/b.md"
assert_fires "T15 новый каталог целиком" "git add -A -- brandnew" "brandnew/a.md"
assert_fires "T15b второй файл того же каталога" "git add -A -- brandnew" "brandnew/b.md"
rm -rf "$REPO/brandnew"

# T16 — НЕ-ASCII ИМЯ. При живом ASCII-соседе страж спрашивал, но русский файл из перечня
# выпадал: `porcelain` отдавал его как "docs/\321\200..." и `grep -qxF` не совпадал.
# Нога судит именно ВЫПАДЕНИЕ: сосед назван — значит рамка собралась, вопрос задан.
printf 'ru\n' > "$REPO/docs/русский.ru.md"
assert_fires "T16 не-ASCII сосед назван" "git add -A -- docs" "docs/secret.ru.md"
assert_fires "T16b не-ASCII путь назван" "git add -A -- docs" "docs/русский.ru.md"
rm -f "$REPO/docs/русский.ru.md"

# T17 — ЛИТЕРАЛ ОБХОДА В ПРОЗЕ. T12 закрыла ОДНО написание (сразу после `echo "`), класс
# остался: отступ, heredoc, комментарий снимали отказ так же.
assert_fires "T17 обход в комментарии" \
    '# CLAUDSOUL_ALLOW_ADD_SWEEP=1 когда-нибудь
git add -A -- docs' "docs/secret.ru.md"
assert_fires "T17b обход в heredoc" \
    'cat <<EOF
CLAUDSOUL_ALLOW_ADD_SWEEP=1
EOF
git add -A -- docs' "docs/secret.ru.md"
assert_fires "T17c обход в одинарных кавычках" \
    "printf '%s' 'CLAUDSOUL_ALLOW_ADD_SWEEP=1'; git add -A -- docs" "docs/secret.ru.md"

# T18 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ признака обхода: настоящее присваивание в позиции команды
# обязано молчать и ПОСЛЕ вырезания кавычек. Без неё правка T17 прошла бы ценой отмены T3.
assert_silent "T18 обход с отступом всё ещё снимает" "  CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add -A -- docs"
assert_silent "T18b обход после && снимает" "true && CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add -A -- docs"

# --- Ноги второго раунда противника (20 сентября 2026) --------------------------------
# Шесть находок одного корня: страж разбирал грамматику оболочки СВОЕЙ копией, тогда как у
# факта «что здесь исполнит оболочка» в дереве уже был владелец (`hooks/lib/write_targets.py`,
# правило — `command-scope-lib.sh:330`). Три формы давали МОЛЧАНИЕ на настоящем захвате,
# три — лишний вопрос на законном обходе. T17d-f судят первую тройку, T18c-d вторую;
# порознь они не закрывают класс, потому и стоят вместе.

# T17d — heredoc С КАВЫЧКАМИ В МЕТКЕ. Главная форма: в дереве таких 604 против 230 без
# кавычек, а прежняя нога T17b судила меньшинство. Вырезание съедало метку раньше, чем
# признак heredoc успевал её увидеть, и тело уходило в текст команды целиком.
assert_fires "T17d обход в heredoc с кавычками в метке" \
    "cat <<'EOF' > /dev/null
CLAUDSOUL_ALLOW_ADD_SWEEP=1
EOF
git add -A -- docs" "docs/secret.ru.md"

# T17e — ОДНОСЛОЖНОЕ СЛОВО В ТЕЛЕ heredoc. Прежний признак снимал режим пропуска на любой
# строке из одного слова, а не на терминаторе, и остаток тела вываливался наружу.
assert_fires "T17e тело heredoc начинается одним словом" \
    'cat <<EOF > /dev/null
hello
CLAUDSOUL_ALLOW_ADD_SWEEP=1 в прозе
EOF
git add -A -- docs' "docs/secret.ru.md"

# T17f — ЭКРАНИРОВАННАЯ КАВЫЧКА. Вырезание считало кавычки парами и слепло к `\"`:
# чётность сдвигалась, содержимое строки выходило наружу вместе с разделителем.
assert_fires "T17f экранированная кавычка не вскрывает обход" \
    'git add -A -- docs ; echo "x\"; CLAUDSOUL_ALLOW_ADD_SWEEP=1 y"' "docs/secret.ru.md"

# T18c-T18d — ЗЕРКАЛЬНАЯ ТРОЙКА: законный обход обязан сниматься. Вырезание комментария
# рубило строку по решётке ВНУТРИ кавычек, а метка heredoc с цифрой не совпадала с
# шаблоном слова — в обоих случаях страж спрашивал там, где спрашивать не о чем.
assert_silent "T18c обход после команды с решёткой в кавычках" \
    'grep "#" docs/tracked.md; CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add -A -- docs'
assert_silent "T18d обход после heredoc с меткой EOF1" \
    'cat <<EOF1 > /dev/null
данные
EOF1
CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add -A -- docs'
assert_silent "T18e обход после арифметического сдвига" \
    'echo $((1<<3)); CLAUDSOUL_ALLOW_ADD_SWEEP=1 git add -A -- docs'

# T20 — ПРОБЕЛ В ИМЕНИ НЕОТСЛЕЖИВАЕМОГО ФАЙЛА. `git status --porcelain` берёт такой путь
# в кавычки НЕЗАВИСИМО от `core.quotePath` (тот снимает лишь восьмеричные escape у
# не-ASCII), и сверка с поимённым выводом `--dry-run` не совпадала — страж молчал на любом
# захвате файла с пробелом в имени. Третий случай одного класса единиц после D471; найден
# не глазом, а проверкой снятия названного предела этого же файла
# (`hooks/tests/fixtures/limit_quoted_path.sh`), на её первом прогоне.
printf 'sp\n' > "$REPO/docs/мой файл.md"
assert_fires "T20 пробел в имени файла" "git add -A -- docs" "docs/мой файл.md"
rm -f "$REPO/docs/мой файл.md"

# T19 — КЛЮЧ git, ЧИТАЮЩИЙ ЧУЖОЙ ФАЙЛ. Слова уходят в git массивом, и это правильно, но
# среди них бывает ключ самого git: `--pathspec-from-file` заставлял стража прочитать файл
# ВНЕ репозитория, а на FIFO — повиснуть навсегда (хук PreToolUse, то есть вся сессия).
# Нога судит ОБА последствия: файл-приманка не прочитан, и вызов уложился в срок.
# Приманка лежит ВНЕ репозитория и содержит путь неотслеживаемого файла. Прочитал её страж
# или нет, видно по его же поводу: прочитав, он назовёт этот путь. Признак прямой, без
# времени доступа — `stat` разный на двух системах, а `noatime` сделал бы ногу немой.
_bait="$TMP/outside.txt"
printf 'docs/secret.ru.md\n' > "$_bait"
_t19out=$(perl -e 'alarm 10; exec @ARGV' bash -c 'cat | bash "$0"' "$SCRIPT" <<< "$(payload "git add --pathspec-from-file=$_bait")" 2>/dev/null)
_t19rc=$?
if [ "$_t19rc" = "142" ] || [ "$_t19rc" = "124" ]; then
    FAIL=$((FAIL + 1)); echo "FAIL [T19 зависание]: страж не уложился в срок на --pathspec-from-file"
else
    PASS=$((PASS + 1))
fi
if grep -qF "docs/secret.ru.md" <<< "$_t19out"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T19b чужой файл прочитан]: путь из файла вне репозитория попал в повод"
else
    PASS=$((PASS + 1))
fi

echo "---"
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
