#!/usr/bin/env bash
# commit-stamp.sh — отметка «чем проверен коммит агента»: критик, тесты или ничем; режим наблюдения, без отказа.
#
# Результат: у коммита агента в журнале `state/commit-stamps.tsv` есть строка «чем проверен», и коммиты, ушедшие
#            без проверки, называются одной командой (`--unverified`).
# Проверка результата: bash scripts/commit-stamp.sh --self-test даёт 0
#
# Зачем (18 ноября 2026, приём из статьи команды Claude Code «How the Claude Code team thinks about verification»,
# решение владельца): «штамп на каждом коммите — как он проверен, включая "ничем", — чтобы непроверенные можно было
# спросить». Пишет `post-commit` ловушки git (`hooks/commit-trap.sh`) отсоединённым процессом: коммит не ждёт.
# РЕЖИМ НАБЛЮДЕНИЯ: отметка только пишется. Отказ по ней — отдельное решение владельца по числам журнала: статья
# велит сперва наблюдать, где отказ был бы ложным, — у нас это правило уровня 4 «признак с измеренной точностью».
#
# ЧЕМ СУДИТСЯ. Расшифровки — сессии `CLAUDE_CODE_SESSION_ID` (харнесс отдаёт её каждому процессу вызова Bash, а
# значит и git с ловушкой) и её субагентов (`<сессия>/subagents/agent-*.jsonl`: у субагента та же сессия, и почти
# половина прогонов тестов — их). Окно — от времени родителя коммита; строка засчитывается, только если её `cwd`
# лежит в репозитории коммита (прогон в другом репозитории этот коммит не проверял).
#  · критик — вызов агента (Agent/Task), в начале промпта которого стоит «противник», «скептик» или «критик»; скилл
#    `adversary` или `code-review`; Workflow с adversary. Это ШИРЕ признака `hooks/lib/adversary-run-lib.sh`
#    («был прогон /adversary» — промпт начинается с «Ты противник»): финальный скептик проекта пишется иначе, и по
#    узкому признаку отметка «критик» не возникала бы (скептик opus 18 ноября 2026: 0 из 210 вызовов агентов);
#  · тесты — вызов Bash, чья команда зовёт набор, тест, пробу или самопроверку.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ.
#  1. Оба признака — перечни форм (корень R3): точность не измерена, поэтому отметка — наблюдение, а не отказ.
#  2. «Тесты» значит «прогон был», а не «прогон зелёный»: код выхода в расшифровке надёжно не различается.
#  3. Окно — от родителя, а не от прошлого коммита сессии; у коммита без родителя окно — вся сессия.
#  4. Критик из ДРУГОЙ сессии не засчитывается: связь «эта проверка о том коммите» в данных не записана.
#  5. Нет расшифровки, ни одной разобранной строки или ни одного вызова инструмента — «не прочитано», а не «ничем».
#     Коммит владельца в терминале и коммит мимо ловушки строки не получают — запрос называет их «не отмечен».
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
JOURNAL="${COMMIT_STAMP_JOURNAL:-$STATE/commit-stamps.tsv}"
TAB=$(printf '\t')

transcripts() {  # расшифровки: явная (свидетели) либо сессии CLAUDE_CODE_SESSION_ID и её субагентов
    if [ -n "${COMMIT_STAMP_TRANSCRIPT:-}" ]; then printf '%s\n' "$COMMIT_STAMP_TRANSCRIPT"; return 0; fi
    [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || return 0
    for f in "$HOME"/.claude/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl; do
        [ -f "$f" ] || continue
        printf '%s\n' "$f"
        for s in "${f%.jsonl}"/subagents/*.jsonl; do [ -f "$s" ] && printf '%s\n' "$s"; done
        return 0
    done
}

count() {        # <репозиторий> <с, эпоха> <расшифровки…> → «критик тесты»; код 2 — не прочитано
    python3 - "$@" <<'PY'
import json, os, re, sys
from datetime import datetime
root, since, files = os.path.realpath(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
# ponytail: перечни форм (корень R3) — точность не мерена, поэтому отметка лишь наблюдение.
TEST = re.compile(r"run_all\.sh|hooks/tests/(test_|fixtures/probe_)|\bpytest\b|--self-test\b|\bnpm (run )?test\b|\bplaywright test\b")
CRIT = re.compile(r"противник|скептик|критик|adversar|skeptic", re.I)
def inside(cwd):
    if not cwd: return False
    c = os.path.realpath(cwd)
    return c == root or c.startswith(root.rstrip("/") + "/")
parsed = tools = critic = tests = 0
for path in files:
    try: fh = open(path, encoding="utf-8", errors="replace")
    except OSError: continue
    with fh:
        for line in fh:
            try: d = json.loads(line)
            except ValueError: continue
            if not isinstance(d, dict): continue
            parsed += 1
            msg = d.get("message")
            content = msg.get("content") if isinstance(msg, dict) else None
            if not isinstance(content, list): continue
            for c in content:
                if not (isinstance(c, dict) and c.get("type") == "tool_use"): continue
                tools += 1
                try: e = datetime.fromisoformat((d.get("timestamp") or "").replace("Z", "+00:00")).timestamp()
                except ValueError: continue
                if e < since or not inside(d.get("cwd")): continue
                name, inp = c.get("name"), c.get("input") if isinstance(c.get("input"), dict) else {}
                if name == "Bash" and TEST.search(inp.get("command") or ""): tests += 1
                elif name in ("Agent", "Task") and CRIT.search((inp.get("prompt") or "")[:400]): critic += 1
                elif name == "Skill" and (inp.get("skill") or inp.get("name") or "") in ("adversary", "code-review"): critic += 1
                elif name == "Workflow" and "adversary" in json.dumps(inp, ensure_ascii=False)[:4000]: critic += 1
# Сам коммит — вызов инструмента: ни одного вызова значит «не прочёл» (сдвиг формата, мусор), а не «не проверял».
if parsed == 0 or tools == 0: sys.exit(2)
print(critic, tests)
PY
}

record() {       # <репозиторий> <коммит>
    _root="$1"; _sha="$2"
    _since=$(git -C "$_root" log -1 --format=%ct "$_sha^" 2>/dev/null) || _since=0
    case "${_since:-}" in ''|*[!0-9]*) _since=0 ;; esac
    _critic="?"; _tests="?"
    _files=(); while IFS= read -r _f; do [ -n "$_f" ] && _files+=("$_f"); done < <(transcripts)
    if [ "${#_files[@]}" -gt 0 ] && _ct=$(count "$_root" "$_since" "${_files[@]}"); then
        read -r _critic _tests <<< "$_ct"
    fi
    case "$_critic$_tests" in *[!0-9]*|'') _stamp="не прочитано"; _critic="?"; _tests="?" ;;
        *) if [ "$_critic" -gt 0 ] && [ "$_tests" -gt 0 ]; then _stamp="критик+тесты"
           elif [ "$_critic" -gt 0 ]; then _stamp="критик"
           elif [ "$_tests" -gt 0 ]; then _stamp="тесты"
           else _stamp="ничем"; fi ;;
    esac
    _r=$(printf '%s' "$_root" | tr '\t\n' '  ')   # таб и перевод строки в пути сдвинули бы колонки журнала
    mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_sha" "$(date +%s)" "$_r" "${CLAUDE_CODE_SESSION_ID:-}" \
        "$_critic" "$_tests" "$_stamp" >> "$JOURNAL"
}

list() {         # <репозиторий> <сколько> <только «ничем»: 0|1>
    _root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || { echo "не репозиторий git: $1" >&2; return 2; }
    git -C "$_root" log -n "$2" --format="%H${TAB}%s" | while IFS="$TAB" read -r _sha _subj; do
        _st=$(awk -F'\t' -v s="$_sha" '$1 == s { v = $7 } END { print v }' "$JOURNAL" 2>/dev/null)
        [ -n "$_st" ] || _st="не отмечен"
        [ "$3" = 1 ] && [ "$_st" != "ничем" ] && continue
        printf '%s  %-13s %s\n' "${_sha:0:8}" "$_st" "${_subj:0:90}"
    done
}

self_test() {
    FAIL=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    # Сам JOURNAL, а не переменная окружения: путь вычислен при загрузке, и поздний export увёл бы запись
    # в живой журнал состояния (так и было в первой редакции 18 ноября 2026).
    JOURNAL="$T/stamps.tsv"; export COMMIT_STAMP_JOURNAL="$JOURNAL"
    R="$T/r"; O="$T/other"; mkdir -p "$O"
    git init -q "$R" && GIT_COMMITTER_DATE=2026-01-01T00:00:00Z git -C "$R" -c user.name=t -c user.email=t@l \
        commit -q --allow-empty -m first --date=2026-01-01T00:00:00Z || { echo "FAIL: репозиторий не собран"; return 1; }
    mk() { GIT_COMMITTER_DATE=2026-01-01T00:00:00Z git -C "$R" -c user.name=t -c user.email=t@l commit -q \
        --allow-empty -m "$1" --date=2026-01-01T00:00:00Z; git -C "$R" rev-parse HEAD; }
    call() {   # <время> <cwd> <инструмент> <поле> <значение>
        printf '{"type":"assistant","timestamp":"%s","cwd":"%s","message":{"content":[{"type":"tool_use","name":"%s","input":{"%s":"%s"}}]}}\n' "$@"; }
    W=2026-06-01T10:00:00Z; OLD=2025-12-01T10:00:00Z
    mkdir -p "$T/t"
    { call "$W" "$R" Bash command "bash hooks/tests/test_x.sh"; call "$W" "$R" Agent prompt "Ты — финальный скептик перед коммитом"; } > "$T/t/both.jsonl"
    { call "$OLD" "$R" Bash command "bash hooks/tests/test_old.sh"; call "$W" "$R" Bash command "ls -la"; } > "$T/t/none.jsonl"
    { call "$W" "$R" Agent prompt "Ты противник. Докажи"; call "$W" "$R" Bash command "git status"; } > "$T/t/critic.jsonl"
    { call "$W" "$O" Bash command "bash hooks/tests/test_y.sh"; call "$W" "$R" Bash command "git commit -m x"; } > "$T/t/elsewhere.jsonl"
    { call "$W" "$R" Bash command "git commit -m x"; } > "$T/t/main.jsonl"
    mkdir -p "$T/t/main/subagents"; call "$W" "$R" Bash command "bash hooks/tests/run_all.sh --changed" > "$T/t/main/subagents/agent-a.jsonl"
    printf 'не json\n{"type":"assistant","message":{"content":[{"type":"tool_call","name":"Bash"}]}}\n' > "$T/t/garbage.jsonl"
    st() { awk -F'\t' -v s="$1" '$1 == s { print $7 }' "$JOURNAL"; }
    chk() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 — «$2», ждали «$3»"; FAIL=1; fi; }
    rec() { local s; s=$(mk "$1"); COMMIT_STAMP_TRANSCRIPT="$2" record "$R" "$s"; printf '%s\n' "$s"; }
    s1=$(rec both "$T/t/both.jsonl");           chk "скептик и тест в окне" "$(st "$s1")" "критик+тесты"
    s2=$(rec none "$T/t/none.jsonl");           chk "тест до окна и ls в окне — не тесты" "$(st "$s2")" "ничем"
    s3=$(rec critic "$T/t/critic.jsonl");       chk "только противник, git status не тест" "$(st "$s3")" "критик"
    s4=$(rec elsewhere "$T/t/elsewhere.jsonl"); chk "тест в другом репозитории не засчитан" "$(st "$s4")" "ничем"
    s5=$(rec garbage "$T/t/garbage.jsonl");     chk "мусор и сдвиг формата — не прочитано" "$(st "$s5")" "не прочитано"
    s6=$(rec unread "$T/нет.jsonl");            chk "нет расшифровки — не прочитано" "$(st "$s6")" "не прочитано"
    s7=$(mk sub); (unset COMMIT_STAMP_TRANSCRIPT; export CLAUDE_CODE_SESSION_ID=main HOME="$T/h"
        mkdir -p "$HOME/.claude/projects/p"; cp -R "$T/t/main.jsonl" "$T/t/main" "$HOME/.claude/projects/p/"; record "$R" "$s7")
    chk "прогон субагента сессии засчитан" "$(st "$s7")" "тесты"
    s8=$(mk owner)   # без строки журнала: коммит мимо ловушки
    L=$(list "$R" 20 0); U=$(list "$R" 20 1)
    grep -q "^${s8:0:8}  не отмечен" <<< "$L" && echo "PASS: коммит без строки — «не отмечен»" \
        || { echo "FAIL: коммит без строки не назван: $L"; FAIL=1; }
    [ "$(grep -c . <<< "$U")" = 2 ] && grep -q "^${s2:0:8}  ничем" <<< "$U" && grep -q "^${s4:0:8}  ничем" <<< "$U" \
        && echo "PASS: --unverified — только «ничем»" || { echo "FAIL: --unverified: $U"; FAIL=1; }
    return $(( FAIL != 0 ))
}

case "${1:-}" in
    --record)     record "${2:?репозиторий}" "${3:?коммит}" ;;
    --unverified) list "${2:-$PWD}" "${3:-30}" 1 ;;
    --self-test)  self_test ;;
    ''|--list)    list "${2:-$PWD}" "${3:-30}" 0 ;;
    *) echo "использование: $0 [--list [<репозиторий>] [N]] | --unverified [<репозиторий>] [N] | --record <репозиторий> <коммит> | --self-test" >&2; exit 2 ;;
esac
