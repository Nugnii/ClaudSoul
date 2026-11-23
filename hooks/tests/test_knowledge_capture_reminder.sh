#!/usr/bin/env bash
# СУДИТ: hooks/knowledge-capture-reminder.sh
# test_knowledge_capture_reminder.sh — тест мид-сессионного напоминания о захвате знаний.
#
# С 12 сентября 2026 (D400) захват задаётся ДЕЙСТВИЯМИ агента в расшифровке, а не свежестью
# файла в общем каталоге: база знаний общая для всех сессий и проектов, и прежний признак
# `find -newer` гасил напоминание от чужой записи. Поэтому фикстура подаёт транскрипт.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/knowledge-capture-reminder.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

mkdir -p "$TMP/home/.claude/global-lessons/_drafts" "$TMP/state"
LESSONS="$TMP/home/.claude/global-lessons"

assert_empty()    { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалось пусто, получено '${1:0:60}'"; fi; }
assert_contains() { if grep -qF "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2' в '${1:0:60}'"; fi; }

# mk_tr <файл> <путь правки> <время ISO> — расшифровка из одного вызова инструмента.
# Время задаётся ЯВНО и одной шкалой (UTC с «Z»), как у фикстуры declared-problem-recorded:
# смешать локальное время файла с меткой UTC значит переворачивать вердикт на машине в CEST.
mk_tr() {
    printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]},"timestamp":"%s"}\n' \
        "$2" "$3" > "$1"
}
NOW_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
OLD_ISO="2000-01-01T00:00:00Z"

# run_hook <команда> [транскрипт]
run_hook() {
    _tr="${2:-}"
    if [ -n "$_tr" ]; then
        _payload=$(printf '{"session_id":"test-kcr","tool_name":"Bash","tool_input":{"command":"%s"},"transcript_path":"%s"}' "$1" "$_tr")
    else
        _payload=$(printf '{"session_id":"test-kcr","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1")
    fi
    printf '%s' "$_payload" | env \
        HOME="$TMP/home" \
        STATE_DIR="$TMP/state" \
        LESSONS_DIR="$LESSONS" \
        KCR_THRESHOLD=3 \
        PATHS_LIB="$HOOK_DIR/paths-lib.sh" \
        KCR_RC_LIB="$HOOK_DIR/root-cause-lib.sh" \
        KCR_PORTABLE="$HOOK_DIR/portable-lib.sh" \
        bash "$HOOK" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_knowledge_capture_reminder.sh:$LINENO" >&2; exit 1; }
}

MARKER="$TMP/state/knowledge-capture-marker-test-kcr"

# T1: до порога (3) — тихо
assert_empty "$(run_hook 'git commit')" "T1a: коммит 1 тихо"
assert_empty "$(run_hook 'git commit')" "T1b: коммит 2 тихо"

# T2: на пороге — напоминание
OUT=$(run_hook 'git commit')
assert_contains "$OUT" "Захват знаний" "T2: коммит 3 — напоминание"
assert_contains "$OUT" "PostToolUse" "T2b: корректный конверт"

# T3: черновик записан ДЕЙСТВИЕМ хода → следующее окно подавлено
touch -t 200001010000 "$MARKER"
TR_DRAFT="$TMP/tr-draft.jsonl"; mk_tr "$TR_DRAFT" "$LESSONS/_drafts/new-draft.md" "$NOW_ISO"
assert_empty "$(run_hook 'git commit' "$TR_DRAFT")" "T3a: коммит 4 (окно не набрано) тихо"
assert_empty "$(run_hook 'git commit' "$TR_DRAFT")" "T3b: коммит 5 тихо"
assert_empty "$(run_hook 'git commit' "$TR_DRAFT")" "T3c: коммит 6 — подавлено (черновик записан ходом)"

# T3d-T3f: захватом считается ЛЮБАЯ запись знания, не только черновик.
#
# Повод. Версия до 29 июля 2026 смотрела исключительно в `_drafts/`, и за сессию трижды
# сообщила «материал не захвачен», когда в базу было записано ТРИ готовых кейса — прямо
# в `global-lessons/`, минуя черновики. Буквально верно, по существу нет: измерялась папка
# черновиков, а не захват. Черновик — один из путей записи, а не сам захват.
touch -t 200001010000 "$MARKER"
TR_CASE="$TMP/tr-case.jsonl"; mk_tr "$TR_CASE" "$LESSONS/case-2026-07-29-probe.md" "$NOW_ISO"
assert_empty "$(run_hook 'git commit' "$TR_CASE")" "T3d: окно не набрано тихо"
assert_empty "$(run_hook 'git commit' "$TR_CASE")" "T3e: окно не набрано тихо"
assert_empty "$(run_hook 'git commit' "$TR_CASE")" "T3f: готовый кейс мимо _drafts засчитан как захват"

# T3g: паттерн — тоже запись знания
touch -t 200001010000 "$MARKER"
TR_PAT="$TMP/tr-pat.jsonl"; mk_tr "$TR_PAT" "$LESSONS/pattern-probe.md" "$NOW_ISO"
assert_empty "$(run_hook 'git commit' "$TR_PAT")" "T3g1: тихо"
assert_empty "$(run_hook 'git commit' "$TR_PAT")" "T3g2: тихо"
assert_empty "$(run_hook 'git commit' "$TR_PAT")" "T3g3: новый паттерн засчитан как захват"

# T3h: ОБРАТНАЯ сторона — правка постороннего файла захватом НЕ считается.
# Без этого случая проверка засчитывала бы любое действие и молчала бы всегда.
touch -t 200001010000 "$MARKER"
TR_NOISE="$TMP/tr-noise.jsonl"; mk_tr "$TR_NOISE" "$TMP/home/notes-scratch.md" "$NOW_ISO"
assert_empty    "$(run_hook 'git commit' "$TR_NOISE")" "T3h1: тихо"
assert_empty    "$(run_hook 'git commit' "$TR_NOISE")" "T3h2: тихо"
assert_contains "$(run_hook 'git commit' "$TR_NOISE")" "Захват знаний" "T3h3: посторонний файл не засчитан, напоминание вышло"

# T4: не-коммит — не считается, тихо
assert_empty "$(run_hook 'ls -la')" "T4: не-коммит игнорируется"

# T5: без записей следующее окно снова напоминает
assert_empty   "$(run_hook 'git commit')" "T5a: коммит 7 тихо"
assert_empty   "$(run_hook 'git commit')" "T5b: коммит 8 тихо"
OUT2=$(run_hook 'git commit')
assert_contains "$OUT2" "Захват знаний" "T5c: коммит 9 — снова напоминание (записей нет)"

# T6 (D400): ЧУЖАЯ запись в общем каталоге напоминание НЕ гасит.
# Это и есть дефект, ради которого признак переведён на действия: база знаний общая, в неё
# пишут параллельная сессия, соседний проект и механизм симметрии ссылок. Файл лежит и он
# свежее маркера, действий хода нет — страж обязан говорить.
touch -t 200001010000 "$MARKER"
: > "$LESSONS/case-neighbour.md"
assert_empty    "$(run_hook 'git commit')" "T6a: тихо"
assert_empty    "$(run_hook 'git commit')" "T6b: тихо"
assert_contains "$(run_hook 'git commit')" "Захват знаний" "T6c: чужой файл в каталоге не засчитан как захват"

# T7: ОКНО уважается — запись СТАРШЕ маркера захватом этого окна не является.
# Маркер здесь свежий (его только что тронул хук на предыдущем напоминании), а действие
# датировано 2000 годом: без сверки времени признак засчитал бы любую давнюю запись.
TR_OLD="$TMP/tr-old.jsonl"; mk_tr "$TR_OLD" "$LESSONS/case-2026-07-29-probe.md" "$OLD_ISO"
assert_empty    "$(run_hook 'git commit' "$TR_OLD")" "T7a: тихо"
assert_empty    "$(run_hook 'git commit' "$TR_OLD")" "T7b: тихо"
assert_contains "$(run_hook 'git commit' "$TR_OLD")" "Захват знаний" "T7c: запись старше маркера не гасит окно"

echo ""
echo "knowledge-capture-reminder tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
