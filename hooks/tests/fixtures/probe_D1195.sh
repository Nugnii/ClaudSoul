#!/usr/bin/env bash
# СУДИТ: hooks/session-registry-lib.sh hooks/knowledge-counter-bump.sh
# (предмет словами: hooks/session-registry-lib.sh (умолчание SR_SESSIONS_DIR) через hooks/knowledge-counter-bump.sh и писателей библиотеки; в строке СУДИТ — только пути, иначе прибор свидетелей-атак читает слова путями — D1222)
# probe_D1195 — писатель реестра сессий, запущенный так, как его зовёт тест вне набора (песочный STATE_DIR или LESSONS_DIR,
# SR_SESSIONS_DIR нет, id живой сессии унаследован), не трогает боевой реестр. «Боевой»
# здесь — песочный HOME пробы, с заведёнными реестром и active/.
# Ноги: A — подъём счётчика в чужой базе и с чужим состоянием (рамка `test_adv_bump_*`) состоялся, а реестр не тронут;
# B — положительный контроль: тот же подъём в базе и состоянии самого HOME пишет дельту в носитель сессии (без него A
# зеленела бы на умершем писателе); C — регистрация сессии при песочном STATE_DIR (рамка `test_hint_age_always_named.sh`,
# `session-start.sh`); D — дельта при песочной базе без песочного состояния (путь `knowledge-frontmatter-check.sh`).
# Полный прогон 664 тестов набора вне набора (2 ноября 2026: на HEAD до правки каталог сессий трогали 4 —
# три `test_adv_bump_*` и `test_hint_age_always_named`, после — 0) идёт минуты и в постоянную пробу не взят: её
# исполняет каждая граница хода. Предел (скептик opus по 4843e13a, L2): рамку «оба пути не заданы к подключению»
# (`session-start.sh`, `session-end.sh` подключают библиотеку раньше paths-lib) проба не гоняет — мутанты, снявшие
# `[ -n "${STATE_DIR:-}" ]` либо проверку `-z SR_SESSIONS_DIR`, ловит набор, а не проба.
# Код: 0 — держится; 1 — нога красна (названа); 2 — писателя нет или он не ответил.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
BUMP="$R/hooks/knowledge-counter-bump.sh"; LIB="$R/hooks/session-registry-lib.sh"
[ -f "$BUMP" ] && [ -f "$LIB" ] || exit 2
command -v jq >/dev/null 2>&1 || { echo "нет jq — писатель реестра без него молчит, мерить нечего"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
H="$W/home"; S="$H/.claude/sessions"
mkdir -p "$H/.claude/global-lessons" "$H/.claude/hooks/state" "$W/lessons" "$W/state"
fresh() { rm -rf "$S"; mkdir -p "$S/active"; : > "$S/registry.jsonl"; }
fresh
kn() { printf '%s\n' '---' 'name: проба' 'confidence: 3' 'confirmed_count: 1' 'contradicted_count: 0' \
    'source_cases: []' 'provenance_log: []' '---' 'тело' > "$1/pattern-d1195.md"; }
frame() {  # рамка теста вне набора: живой (для пробы — песочный) HOME, id сессии унаследован, каталога реестра нет
    (cd "$W" && env -u SR_SESSIONS_DIR -u SR_OVERRIDE_SESSION_ID -u LESSONS_DIR -u STATE_DIR HOME="$H" \
        CLAUDE_CODE_SESSION_ID=probe-d1195 "$@" >/dev/null 2>&1 </dev/null)
}
touched() { find "$S" -type f ! -name registry.jsonl | grep -c . ; }
clean() {  # $1 — нога
    local n s; n=$(touched); s=$(wc -c < "$S/registry.jsonl" | tr -d ' ')
    [ "$n" = 0 ] && [ "$s" = 0 ] && return 0
    echo "$1: тронут боевой реестр (файлов $n, байт реестра $s)"; fresh; return 1
}
rc=0
# A
kn "$W/lessons"; frame LESSONS_DIR="$W/lessons" STATE_DIR="$W/state" bash "$BUMP" pattern-d1195 confirmed "проба D1195"
grep -q '^confirmed_count: 2' "$W/lessons/pattern-d1195.md" || { echo "писатель не поднял счётчик в чужой базе"; exit 2; }
clean "A: подъём в чужой базе" || rc=1
# B
kn "$H/.claude/global-lessons"
frame LESSONS_DIR="$H/.claude/global-lessons" STATE_DIR="$H/.claude/hooks/state" bash "$BUMP" pattern-d1195 confirmed "проба D1195"
d=$(jq -r '.knowledge_delta.confirmed // [] | join(",")' "$S/active/probe-d1195.json" 2>/dev/null)
case "$d" in *pattern-d1195.md*) ;; *) echo "B: подъём в базе HOME не записал дельту — писатель реестра умер"; rc=1 ;; esac
fresh
# C
frame STATE_DIR="$W/state" bash -c '. "$1" && sr_register_session "$PWD"' _ "$LIB"
clean "C: регистрация при песочном STATE_DIR" || rc=1
# D
frame LESSONS_DIR="$W/lessons" bash -c '. "$1" && sr_update_knowledge updated pattern-d1195.md' _ "$LIB"
clean "D: дельта при песочной базе" || rc=1
[ "$rc" = 0 ] && echo "писатели реестра: песочная рамка боевой реестр не трогает, своя пишет"
exit "$rc"
