#!/usr/bin/env bash
# test_backlog_green_side.sh — у «Проверки» КАЖДОГО открытого пункта долга предъявлена зелёная
#                              сторона: фикстура, в которой та же команда даёт 0 (D405).
# Результат: для каждого открытого пункта BACKLOG.md здесь есть фикстура green_<ID>, и под ней
#            «Проверка» пункта зелёная; открытый пункт без фикстуры — красная нога, то есть новый
#            пункт обязан принести свою зелёную сторону вместе с собой. Отрицательный контроль:
#            без фикстуры та же команда красна.
# Проверка результата: bash hooks/tests/test_backlog_green_side.sh даёт 0
#
# Зачем. Красная команда открытого пункта доказывает лишь, что мир сейчас не таков, как
# объявлено; она не доказывает, что позеленеет от починки, а не оттого, что перестала видеть
# предмет (D405, дробь родителя: 4 промаха из 4 без такого контроля против 0 из 14 с ним).
# Фикстура — тот же приём, что у мутанта в копии дерева: «Проверка» исполняется под окружением,
# где мир уже починен. Общий рычаг — CLAUDSOUL_REPO указывает на каталог-фикстуру, потому что
# каждая «Проверка» сама делает туда cd; иные рычаги — STATE_DIR, HOME.
#
# ЧТО ПОКАЗАЛ ПЕРВЫЙ ПРОХОД (13 сентября 2026). У шести пунктов зелёная сторона — заглушка с
# нужным именем файла или словом: их «Проверка» судит по ФОРМЕ, а не по делу. Это записано у
# каждого такого пункта, и закрывать его можно только прибором — файл с нужным именем позеленит
# команду, не решив ничего.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"

# Предмет этого свидетеля в публичный снимок не входит (рабочий долг BACKLOG.md). В неполном дереве
# «файла нет» значит «изъят по решению», а не «пропал»: пропуск называется, дефект не
# объявляется — иначе один канал несёт два состояния мира (корень R6).
UNIVERSE_ROOT="$REPO"; . "$REPO/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_backlog_green_side" "рабочий долг BACKLOG.md"; exit 0
fi
# shellcheck source=../backlog-lib.sh
. "$REPO/hooks/backlog-lib.sh"
command -v backlog_open_items >/dev/null 2>&1 || { echo "FAIL: backlog_open_items недоступна"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система
mkfix() { local d="$TMP/$1"; mkdir -p "$d"; printf '%s' "$d"; }

# Пробный git-репозиторий для реестра родов: ему хватает install.sh и каталога hooks/ (образец D360).
# Строится ОДИН раз и заранее: фикстуры исполняются в подстановке `$(…)`, где присваивание не
# переживает вызов, а повторный `git commit` печатал «nothing to commit» прямо в окружение.
TMP_PROBE="$TMP/probe"; mkdir -p "$TMP_PROBE/scripts" "$TMP_PROBE/hooks"
cp "$REPO/scripts/defect-class-carriers.py" "$TMP_PROBE/scripts/"; cp "$REPO/install.sh" "$TMP_PROBE/"
printf '#!/usr/bin/env bash\necho x\n' > "$TMP_PROBE/hooks/probe.sh"
git -C "$TMP_PROBE" init -q && git -C "$TMP_PROBE" add -A && git -C "$TMP_PROBE" -c user.name=t -c user.email=t@t commit -qm x >/dev/null

# --- фикстуры: green_<ID> готовит мир и печатает строки ИМЯ=значение окружения ---------------
green_D307() { echo "CLAUDSOUL_REPO=$TMP_PROBE"; }          # род G в пробе пуст
green_D310() { echo "CLAUDSOUL_REPO=$TMP_PROBE"; }          # род F не называет test_docs_family_check
green_D331() { local d; d=$(mkfix D331); printf '{"ts":"2026-09-01T10:00:00Z","session":"s","sha":"%040d","tag":"v1.0.0","critic":"rounds","evidence":7,"since":"x..HEAD"}\n' 0 > "$d/publications.jsonl"; echo "STATE_DIR=$d"; }
# Отрицательный контроль T0 ниже берёт D307: его «Проверка» судит МИР (носители рода G по реестру), без
# фикстуры красна. До 13 сентября 2026 предметом был D335 — закрыт вердиктом «признака нет».
# Зелёная сторона D342 — ДЕРЕВО, где у каждого свидетеля-атаки предмет назван и нога
# краснеет на выхолощенном предмете. Прежняя фикстура клала пустой файл с подходящим ИМЕНЕМ
# и тем зеленила команду, судившую имя; с поведенческим прибором такая заглушка не проходит.
green_D342() { local d; d=$(mkfix D342); mkdir -p "$d/hooks/tests"
    printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$d/hooks/subject.sh"
    { printf '#!/usr/bin/env bash\n'
      printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
      printf 'out=$(bash "$REPO/hooks/subject.sh" 2>&1)\n'
      printf 'case "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_honest.sh"
    mkdir -p "$d/scripts"; cp "$REPO/scripts/behavior-condition-probe.sh" "$d/scripts/"
    chmod +x "$d/hooks/subject.sh" "$d/hooks/tests/test_adv_honest.sh" "$d/scripts/behavior-condition-probe.sh"
    ( cd "$d" && git init -q . && git add -A \
        && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
    echo "CLAUDSOUL_REPO=$d"; }
green_D349() { local d; d=$(mkfix D349); mkdir -p "$d/scripts" "$d/knowledge"; printf 'stop-context-restart\t14\tx\n' > "$d/scripts/measurements.tsv"; echo "stop_hook_active" > "$d/knowledge/k.md"; echo "CLAUDSOUL_REPO=$d"; }
# Знаменатель «Проверки» D358 — записи СО СЛЕДОМ разбора, и их не меньше порога
# `OUTCOME_SHARE_MIN_N` (20): ниже порога владелец формулы честно отвечает «НЕ ИЗМЕРЕНО»
# кодом 2, и зелёная сторона стала бы неотличима от красной. 10 из 20 со следом = 50%.
green_D358() { local d i; d=$(mkfix D358); mkdir -p "$d/.claude/hooks/state"
    # ЖУРНАЛОВ ДВА, и это предмет, а не декорация (13 сентября 2026): условие закрытия
    # считается с `--exclude-newest`, то есть БЕЗ журнала закрывающей сессии. Зелёная
    # сторона обязана зеленеть на СТАРОМ журнале — иначе она доказывала бы ровно то, что
    # решением владельца запрещено: закрытие по данным самого закрывающего.
    for i in $(seq 1 20); do
        if [ "$i" -le 10 ]; then
            printf '{"signal":"rework","outcome":"chain-spoken","trace":{"why":3,"addr":1,"frac":1,"roots":1,"heads":2,"arrows":3,"inputs":1}}\n'
        else
            printf '{"signal":"rework","outcome":"none","trace":{"why":0,"addr":0,"frac":0,"roots":0,"heads":0,"arrows":0,"inputs":0}}\n'
        fi
    done > "$d/.claude/hooks/state/outcome-old.jsonl"
    # Свежий журнал без единой цепочки: при верном устройстве он в условие закрытия НЕ входит.
    for i in $(seq 1 20); do
        printf '{"signal":"rework","outcome":"none","trace":{"why":0,"addr":0,"frac":0,"roots":0,"heads":0,"arrows":0,"inputs":0}}\n'
    done > "$d/.claude/hooks/state/outcome-new.jsonl"
    touch -t 200001010000 "$d/.claude/hooks/state/outcome-old.jsonl"
    echo "HOME=$d"; }
green_D406() { local d; d=$(mkfix D406); mkdir -p "$d/.claude-docs" "$d/scripts" "$d/hooks"
    # Дерево БЕЗ взаимных ссылок: учёт пуст, значит рёбер исполнения нет и колец нет.
    # Предмет зелёной стороны — что прибор УМЕЕТ сказать «спаек: 0», а не только «есть».
    printf '# path\tsha\tdeps\tdocs\tests\tnames\n' > "$d/.claude-docs/dep-index.tsv"
    cp "$REPO/scripts/project-graph.py" "$d/scripts/" 2>/dev/null || true
    ( cd "$d" && git init -q . >/dev/null 2>&1 || true )
    echo "CLAUDSOUL_REPO=$d"; }
green_D407() { local d; d=$(mkfix D407); mkdir -p "$d/hooks"
    # Зелёная сторона: хук объявляет предметом ПРАВКУ и зарегистрирован на событии,
    # которое Bash ВИДИТ, — значит слепых носителей нет и прибор даёт 0.
    printf '#!/usr/bin/env bash\n# проба — при правке файла говорит о связях\n# en: probe\n#\n' > "$d/hooks/probe.sh"
    printf '%s\n' '"PreToolUse": {' '  "matcher": "Bash|Edit|Write",' '  "command": "bash ~/.claude/hooks/probe.sh"' '}' > "$d/install.sh"
    mkdir -p "$d/scripts"; cp "$REPO/scripts/guard-event-coverage.sh" "$d/scripts/"
    echo "CLAUDSOUL_REPO=$d"; }
green_D414() { local d; d=$(mkfix D414); mkdir -p "$d/scripts"
    # Зелёная сторона: прибор адресов, чей отчёт РАЗЛИЧАЕТ «проверено и цело» от «не судилось» —
    # неразличимые адреса названы поимённо, а не только счётчиком. Настоящий прибор печатает
    # «ожидание неразличимо: 8» без единого имени, и «Проверка» пункта на нём красна.
    printf '%s\n' '#!/usr/bin/env python3' \
      'print("адресов сверено по содержимому: 12; уплывших: 0; ожидание неразличимо: 2 — docs/a.md:7, docs/b.md:3")' \
      > "$d/scripts/docs-address-drift.py"
    echo "CLAUDSOUL_REPO=$d"; }
green_D408() { local d; d=$(mkfix D408); mkdir -p "$d/scripts" "$d/corpus/proj"
    # Зелёная сторона: корпус, где КАЖДОЕ опознание класса идёт с реестром носителей.
    # Живые расшифровки не читаются — прибор берёт корпус из CORPUS_DIR.
    cp "$REPO/scripts/signal-precision-corpus.py" "$d/scripts/" 2>/dev/null || true
    printf '%s\n' \
      '{"type":"assistant","message":{"content":[{"type":"text","text":"Тот же класс, что чинили вчера: носителей 3 из 7."}]}}' \
      '{"type":"user","isMeta":false,"origin":{"kind":"human"},"message":{"content":"дальше"}}' \
      > "$d/corpus/proj/probe.jsonl"
    echo "CLAUDSOUL_REPO=$d"; echo "CORPUS_DIR=$d/corpus"; }
green_D409() { local d; d=$(mkfix D409); mkdir -p "$d/scripts"
    printf 'id\tпериод\tкоманда\tчто мерит\n' > "$d/scripts/measurements.tsv"
    printf 'docs-address-anchor\t30c\ttrue\tадресов «файл:строка» без якоря содержимого\n' >> "$d/scripts/measurements.tsv"
    echo "CLAUDSOUL_REPO=$d"; }
green_D410() { local d; d=$(mkfix D410); mkdir -p "$d/hooks"
    # Зелёная сторона: страж берёт меру у владельца факта, а не считает свою.
    printf '#!/usr/bin/env bash\n# проба\nMAX="${COSTLY_CPU_MAX:-20}"\n' > "$d/hooks/test-cost-notice.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D411() { local d; d=$(mkfix D411); mkdir -p "$d/.claude-docs" "$d/scripts" "$d/hooks"
    # Дерево без взаимных ссылок: спайки данных нет, прибор печатает «спаек: 0».
    printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > "$d/.claude-docs/dep-index.tsv"
    cp "$REPO/scripts/project-graph.py" "$d/scripts/" 2>/dev/null || true
    ( cd "$d" && git init -q . >/dev/null 2>&1 || true )
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D415 — копия знания, где у близнеца на оболочке столько же форм, сколько
# у признака на правке. Подменяется ДОМАШНИЙ каталог: команда пункта читает знание по $HOME.
# Файл пишется построчно `printf`, без вложенного питона: тройные кавычки внутри heredoc
# закрывают друг друга, и первая редакция фикстуры умерла на разборе (14 сентября 2026).
# Зелёная сторона D415 — знание, у которого признак ловит путь ВНУТРИ тела heredoc, а не
# только цель перенаправления. Файл пишется построчно printf: вложенный питон здесь однажды
# умер на тройных кавычках, а литерал дефекта в фикстуре отбивает живой блокер.
green_D415() { local d f; d=$(mkfix D415); mkdir -p "$d/.claude/global-lessons"
    f="$d/.claude/global-lessons/pattern-shell-portability.md"
    {
        printf -- '---\nname: proba\nblocker: true\ndetection_signals: |\n'
        printf '  [\n'
        printf '    {\n'
        printf '      "name": "vidit_put_v_tele",\n'
        printf '      "all_of": [\n'
        printf '        { "tool_matches": ["Bash"] },\n'
        printf '        { "heredoc_body_regex": "(hooks|scripts)/[^ ]*[.](sh|bash)" },\n'
        printf '        { "heredoc_body_regex": "grep -oE" }\n'
        printf '      ],\n'
        printf '      "remedy": "proba"\n'
        printf '    }\n'
        printf '  ]\n'
        printf -- '---\n\nпроба\n'
    } > "$f"
    echo "TWIN_KNOWLEDGE=$f"; }
green_D405() { local d; d=$(mkfix D405); mkdir -p "$d/hooks"; cp "$REPO/hooks/backlog-lib.sh" "$d/hooks/"; printf -- '- ☐ **D999** проба\n  **Проверка.** `false` → 0\n  **Зелёная сторона.** `true`\n' > "$d/BACKLOG.md"; echo "CLAUDSOUL_REPO=$d"; }

run_check() {  # run_check <команда> <строки окружения> → код команды под окружением
    local cmd="$1" envs="$2" _e; local -a arr=()
    while IFS= read -r _e; do [ -n "$_e" ] && arr+=("$_e"); done <<< "$envs"
    # ПУСТОЙ МАССИВ ПОД set -u. `"${arr[@]}"` при нуле элементов — «unbound variable» в
    # bash 3.2 (macOS), подоболочка падает, и `echo $?` отдаёт не-0 — неотличимо от честной
    # красной команды. Отрицательный контроль T0 зову́т ровно с пустым окружением, то есть он
    # был зелен ОТ ОШИБКИ ОБОЛОЧКИ, а не оттого, что «Проверка» красна (13 сентября 2026).
    # Тот же класс, что D334: красный от рамки неотличим от красного по делу.
    ( cd "$REPO" && env ${arr[@]+"${arr[@]}"} bash -c "$cmd" >/dev/null 2>&1 ); echo $?
}

# --- САМОПРОВЕРКА РАМКИ: зову́щий механизм различает предмет и себя ------------------------
# Ноги ниже судят по коду возврата run_check, и любой не-0 читают как «команда красна». Пока
# сбой САМОГО вызова тоже даёт не-0, два состояния мира идут по одному проводу (корень R6), и
# ложно-зелёный контроль неотличим от честного. Ровно это и случилось 13 сентября 2026:
# `env "${arr[@]}"` с пустым массивом под set -u ронял подоболочку, T0 зеленел от ошибки
# оболочки. Свидетель различающий: заведомо зелёная команда при ПУСТОМ окружении обязана дать
# 0 — верни прежнюю форму, и эта нога покраснеет первой.
_SELF=$(run_check "true" "")
[ "$_SELF" = "0" ] && ok || bad "T00" "рамка run_check сломана: заведомо зелёная команда под пустым окружением дала $_SELF — ноги ниже судят о своём сбое, а не о «Проверке»"
_SELF2=$(run_check "true" "FOO=bar")
[ "$_SELF2" = "0" ] && ok || bad "T00b" "рамка run_check сломана при непустом окружении: дала $_SELF2"

# --- отрицательный контроль: без фикстуры «Проверка» красна (иначе ноги ниже ничего не различают)
NEG=$(backlog_open_items "$REPO/BACKLOG.md" | awk -F'\t' '$1 == "D307" { print $7 }')
if [ -n "$NEG" ]; then
    RC=$(run_check "$NEG" "")
    [ "$RC" != 0 ] && ok || bad "T0" "без фикстуры «Проверка» D307 зелёная (rc $RC) — пункт пора закрывать или команда не о дефекте"
fi

# --- каждый открытый пункт: фикстура есть и под ней «Проверка» зелёная ------------------------
# Строка библиотеки читается ЦЕЛИКОМ, поля — awk: `read` с IFS=таб схлопывает пустые поля
# (названный предел backlog-lib, первый прогон этого свидетеля подтвердил его заново).
N=0
while IFS= read -r ROW; do
    [ -n "$ROW" ] || continue
    ID=$(printf '%s' "$ROW" | awk -F'\t' '{print $1}')
    CHK=$(printf '%s' "$ROW" | awk -F'\t' '{print $7}')
    N=$((N + 1))
    if ! declare -F "green_$ID" >/dev/null 2>&1; then
        bad "$ID" "у открытого пункта нет зелёной стороны в этом свидетеле — добавь фикстуру green_$ID и строку «Зелёная сторона.» в пункт"; continue
    fi
    [ -n "$CHK" ] || { bad "$ID" "у пункта нет строки «Проверка»"; continue; }
    ENVS=$("green_$ID")
    RC=$(run_check "$CHK" "$ENVS")
    [ "$RC" = 0 ] && ok || bad "$ID" "под фикстурой «Проверка» не позеленела (rc $RC; окружение: $(printf '%s' "$ENVS" | tr '\n' ' '))"
done <<EOF
$(backlog_open_items "$REPO/BACKLOG.md")
EOF
[ "$N" -gt 0 ] && ok || bad "T-open" "библиотека не видит ни одного открытого пункта — положительный контроль не пройден"

echo "backlog green side: открытых $N, PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
