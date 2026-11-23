#!/usr/bin/env bash
# СУД: свойство мира
# (судится ИСТОРИЯ: обе стороны — `git archive` коммитов 0508b711 и 199039cb, рабочее дерево проба не читает, и
#  выхолащивание его кода её не задевает по построению — прибор свидетелей-атак, D1222, 8 ноября 2026)
# probe_D488.sh — пакетный разбор шапок (D488) не изменил отбор знаний: хук до починки
# (коммит 0508b711) и хук САМОЙ ПОЧИНКИ (коммит 199039cb) на одних и тех же входах дают один и тот же
# список кандидатов (RESULTS, ANALOGIES, ведомость нечитаемого) и байт в байт тот же вывод.
# До D1234 второй стороной было РАБОЧЕЕ дерево, и проба краснела от законных правок отбора после
# 3 октября 2026 (`hooks/fsrs-lib.sh`, D1103, D1164): предмет «починка не сменила отбор» — свойство
# коммита починки, а нынешнее время хука мерит замер `activator-latency` (`scripts/activator-latency.sh`).
#
# Входы — восемь контекстов вызова: латиница, кириллица, правка файла, реплика собеседника,
# чужой каталог. База знаний — живая (~/.claude/global-lessons), состояние у каждого прогона
# своё, реестр сессий — во временном каталоге, семантический откат выключен (он внешний).
# Список кандидатов снимается строкой, вставленной в КОПИИ обоих хуков после цикла отбора;
# сами файлы дерева не трогаются. Идентификатор сессии у пары один: от него зависит
# тай-брейк при равных очках.
#
# Код: 0 — все контексты совпали; 1 — есть расхождение (печатается diff); 2 — не исполнимо
# здесь (нет истории git с коммитом 0508b711 или нет базы знаний).
# Цена: старый хук — 30–90 с на контекст, вся проба — минуты; в набор не входит.
set -uo pipefail

OLD_REV=0508b711
FIX_REV=199039cb
REPO="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$REPO" ] && [ -f "$REPO/hooks/knowledge-activator.sh" ] || exit 2
git -C "$REPO" cat-file -e "$OLD_REV^{commit}" 2>/dev/null || exit 2
git -C "$REPO" cat-file -e "$FIX_REV^{commit}" 2>/dev/null || exit 2
[ -d "$HOME/.claude/global-lessons" ] || exit 2   # снимок берётся отсюда, ниже
command -v jq >/dev/null 2>&1 && command -v perl >/dev/null 2>&1 || exit 2

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/old" "$W/new"
git -C "$REPO" archive "$OLD_REV" hooks | tar -x -C "$W/old" || exit 2
git -C "$REPO" archive "$FIX_REV" hooks | tar -x -C "$W/new" || exit 2
# База знаний — СНИМОК на начало прогона (D1234): пара сторон одного контекста идёт минуты, и запись в живую базу
# между ними (7 ноября 2026 — новый кейс посреди прогона) давала расхождение, которого у хуков нет. Хук обоих коммитов
# читает базу из `KNOWLEDGE_DIR="$HOME/.claude/global-lessons"` (`hooks/knowledge-activator.sh:34`), а не из
# LESSONS_DIR, поэтому снимок кладётся в песочный HOME обеих сторон (скептик opus по dbf5c8de, H1).
mkdir -p "$W/home/.claude" && cp -R "$HOME/.claude/global-lessons" "$W/home/.claude/" || exit 2
[ -f "$HOME/.claude/claudsoul-repo" ] && cp "$HOME/.claude/claudsoul-repo" "$W/home/.claude/"
# Реестр сессий — тоже снимок (скептик opus по 2f7b9d95, H1): без него `fsrs-lib.sh` обеих сторон уходит в календарный
# запасной путь, и ветка снимка дней опыта, добавленная самой починкой, не исполняется; живой реестр растёт посреди
# прогона (субагенты заводят сессии), а индекс дней пишется рядом с ним. Обе ревизии читают FSRS_SESSION_REGISTRY.
REG="${FSRS_SESSION_REGISTRY:-$HOME/.claude/sessions/registry.jsonl}"
[ -s "$REG" ] || { echo "probe_D488: реестра сессий нет ($REG) — дни опыта не исполнить"; exit 2; }
cp "$REG" "$W/registry.jsonl" || exit 2

DUMP='[ -n "${KA_DUMP:-}" ] && { printf "R %s\n" ${RESULTS[@]+"${RESULTS[@]}"}; printf "A %s\n" ${ANALOGIES[@]+"${ANALOGIES[@]}"}; printf "U %s|%s\n" "${UNREAD_N:-}" "${UNREAD_WHAT:-}"; } > "$KA_DUMP"'
for side in old new; do
    f="$W/$side/hooks/knowledge-activator.sh"
    awk -v line="$DUMP" '{ print } prev == "# End of knowledge scoring block" && $0 == "fi" { print line; n++ } { prev = $0 }
                         END { exit (n == 1 ? 0 : 1) }' "$f" > "$f.p" || { echo "probe_D488: якорь вставки не найден ($side)"; exit 2; }
    mv "$f.p" "$f"
done

now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
run() { # side name tool tool_input cwd prompt → печатает секунды
    local side="$1" name="$2" st sid in t0
    st=$(mktemp -d "$W/st.XXXXXX"); sid="d488probe-$name"; mkdir -p "$st/sessions"
    [ -n "$6" ] && printf '%s' "$6" > "$st/semantic-prefetch-$sid.json.prompt"
    in=$(jq -cn --arg t "$3" --argjson ti "$4" --arg c "$5" --arg s "$sid" \
        '{tool_name: $t, tool_input: $ti, cwd: $c, session_id: $s}')
    t0=$(now)
    ( cd "$5" && printf '%s' "$in" | HOME="$W/home" FSRS_SESSION_REGISTRY="$W/registry.jsonl" STATE_DIR="$st" SR_SESSIONS_DIR="$st/sessions" \
        CLAUDE_CODE_SESSION_ID="$sid" SKIP_MCP_FALLBACK=1 KA_DUMP="$W/dump-$side-$name" \
        bash "$W/$side/hooks/knowledge-activator.sh" > "$W/out-$side-$name" 2>/dev/null )
    perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$t0" "$(now)"
}

CTX=$(cat <<EOF
backlog	Bash	{"command":"sed -n 1,5p BACKLOG.md"}	$REPO
commit	Bash	{"command":"git commit -m \"fix(hooks): knowledge activator\""}	$REPO
edit	Edit	{"file_path":"$REPO/hooks/knowledge-activator.sh"}	$REPO
npm	Bash	{"command":"npm test -- --watch=false"}	/tmp
cyr	Bash	{"command":"echo проверка знаний и хуков, отладка ошибки"}	$REPO
jq	Bash	{"command":"jq -r .error log.json | grep timeout"}	$REPO
prompt	Bash	{"command":"ls"}	$REPO	почему хук работает медленно при первом вызове в сессии
deploy	Bash	{"command":"docker compose up -d nginx postgres"}	/tmp
EOF
)

N=0; SAME=0; T_OLD=""; T_NEW=""
while IFS=$'\t' read -r name tool tin cwd prompt; do
    [ -n "$name" ] || continue
    N=$((N + 1))
    to=$(run old "$name" "$tool" "$tin" "$cwd" "$prompt")
    tn=$(run new "$name" "$tool" "$tin" "$cwd" "$prompt")
    T_OLD="$T_OLD $to"; T_NEW="$T_NEW $tn"
    if [ -s "$W/dump-old-$name" ] && cmp -s "$W/dump-old-$name" "$W/dump-new-$name" \
       && cmp -s "$W/out-old-$name" "$W/out-new-$name"; then
        SAME=$((SAME + 1))
        echo "  $name: совпало (кандидатов $(grep -c '^R ' "$W/dump-new-$name"), старый ${to} с, новый ${tn} с)"
    else
        echo "  $name: РАСХОЖДЕНИЕ (старый ${to} с, новый ${tn} с)"
        diff "$W/dump-old-$name" "$W/dump-new-$name" | head -6
        cmp -s "$W/out-old-$name" "$W/out-new-$name" || echo "    вывод хука различается"
    fi
done <<< "$CTX"

range() { tr ' ' '\n' | grep . | sort -n | awk 'NR == 1 { a = $1 } { b = $1 } END { printf "%s–%s", a, b }'; }
echo "probe_D488: контекстов $N, совпали $SAME из $N; старый $(range <<< "$T_OLD") с, новый $(range <<< "$T_NEW") с"
[ "$N" -gt 0 ] && [ "$SAME" -eq "$N" ]
exit $?
