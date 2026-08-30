#!/usr/bin/env bash
# doc-figures.sh — одна величина документации по ключу, из источника, а не из памяти.
#
# Результат: у каждого числа в документах состояния есть команда, которая его считает;
#            `bash scripts/doc-figures.sh <ключ>` печатает нынешнее значение либо `n/a`,
#            когда источника на этой машине нет (чужая машина, CI)
# Проверка результата: bash scripts/doc-figures.sh hooks_registered печатает число
#
# Зачем (30 августа 2026). README нёс 176 находок при 185 в журнале, 52 хука при 54, «пять
# хуков прерывают» при девяти, 30 стартовых знаний при 37 — все числа были верны 25 августа
# и устарели за пять дней, потому что жили прозой: стражи проверяли форму документа (версия
# есть, ссылки живы, автотаблицы свежие), а правду чисел не проверял никто — у них не было
# команды. Тот же класс, что показания бэклога (D210): число, вписанное рукой, устаревает в
# ту же секунду. Здесь — единственное место, где величины считаются; реестр
# scripts/doc-claims.tsv связывает ключ с местом в документе, docs-refresh-claims.sh
# подставляет и сверяет.
#
# КОНТРПРИМЕР: величина без источника на машине (база знаний, журналы состояния) даёт `n/a`,
# а не ноль — ноль был бы ложным показанием; сверка такие ключи пропускает и говорит об этом.
set -uo pipefail

KEY="${1:-}"
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SESSIONS_REG="${SR_REGISTRY:-$HOME/.claude/sessions/registry.jsonl}"

stat_key() { bash "$REPO/scripts/count-stats.sh" 2>/dev/null | awk -F= -v k="$1" '$1==k {print $2}'; }
kb_count() { [ -d "$LESSONS" ] || { echo n/a; return; }; ls "$LESSONS"/"$1"-*.md 2>/dev/null | wc -l | tr -d ' '; }
need() { [ -f "$1" ] || { echo n/a; exit 0; }; }

case "$KEY" in
    hooks|hooks_registered|hooks_deny|hooks_ask|skills|bridges|domains|libs|hook_test_files|mcp_test_files)
        stat_key "$KEY" ;;
    hooks_interrupt)   # спрашивают + отказывают
        echo $(( $(stat_key hooks_ask) + $(stat_key hooks_deny) )) ;;
    seed_items)        # знания в seed: всё в knowledge/, кроме META.md и source-tiers.md
        ls "$REPO"/knowledge/*.md 2>/dev/null | grep -v -e '/META\.md$' -e '/source-tiers\.md$' | wc -l | tr -d ' ' ;;
    kb_cases)      kb_count case ;;
    kb_patterns)   kb_count pattern ;;
    kb_principles) kb_count principle ;;
    kb_items)      # операционные + энциклопедические, без META.md и source-tiers.md
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        ls "$LESSONS"/*.md 2>/dev/null | grep -v -e '/META\.md$' -e '/source-tiers\.md$' | wc -l | tr -d ' ' ;;
    kb_cases_error)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -l '^outcome: *error' "$LESSONS"/case-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_cases_success)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -l '^outcome: *success' "$LESSONS"/case-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_co_cognition)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -lE '^origin: *"?co-cognition' "$LESSONS"/*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_contradicted_nonzero)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -lE '^contradicted_count: *[1-9]' "$LESSONS"/*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    findings_total)    # находки output-language-check за всё время (surfaced + pending)
        ls "$STATE"/output-violations-*.jsonl >/dev/null 2>&1 || { echo n/a; exit 0; }
        cat "$STATE"/output-violations-*.jsonl | wc -l | tr -d ' ' ;;
    findings_[0-9][0-9][0-9][0-9]-[0-9][0-9])
        ls "$STATE"/output-violations-*.jsonl >/dev/null 2>&1 || { echo n/a; exit 0; }
        cat "$STATE"/output-violations-*.jsonl | jq -r --arg m "${KEY#findings_}" 'select((.ts // "")[0:7] == $m) | 1' | wc -l | tr -d ' ' ;;
    sessions_[0-9][0-9][0-9][0-9]-[0-9][0-9])
        # уникальная сессия — по месяцу своей ПЕРВОЙ записи в телеметрии слоя 6
        need "$STATE/intrusiveness-history.jsonl"
        jq -r '[.session_id, (.date // "")] | @tsv' "$STATE/intrusiveness-history.jsonl" \
        | awk -F'\t' -v m="${KEY#sessions_}" '$1!="" && $2!="" { if(!($1 in f) || $2<f[$1]) f[$1]=$2 } END{for(s in f) if(substr(f[s],1,7)==m) c++; print c+0}' ;;
    per_session_[0-9][0-9][0-9][0-9]-[0-9][0-9])
        m="${KEY#per_session_}"; f=$(bash "$0" "findings_$m"); s=$(bash "$0" "sessions_$m")
        case "$f$s" in *n/a*) echo n/a; exit 0 ;; esac
        [ "$s" -gt 0 ] && awk -v f="$f" -v s="$s" 'BEGIN{printf "%.2f", f/s}' || echo n/a ;;
    sessions_unique)   # уникальных сессий в телеметрии слоя 6 за всё время
        need "$STATE/intrusiveness-history.jsonl"
        jq -r '.session_id' "$STATE/intrusiveness-history.jsonl" | sort -u | wc -l | tr -d ' ' ;;
    registry_sessions_since_2026-04-24)
        need "$SESSIONS_REG"
        jq -r 'select((.started_at // "") >= "2026-04-24") | .session_id' "$SESSIONS_REG" | sort -u | wc -l | tr -d ' ' ;;
    blocker_markers)   # пометок blocker-tier за всё время
        ls "$STATE"/blocker-fired-*.jsonl >/dev/null 2>&1 || { echo n/a; exit 0; }
        cat "$STATE"/blocker-fired-*.jsonl | wc -l | tr -d ' ' ;;
    blocker_sessions)
        ls "$STATE"/blocker-fired-*.jsonl >/dev/null 2>&1 || { echo n/a; exit 0; }
        ls "$STATE"/blocker-fired-*.jsonl | wc -l | tr -d ' ' ;;
    trust_guard_firings)
        ls "$STATE"/trust-guard-fired-*.jsonl >/dev/null 2>&1 || { echo n/a; exit 0; }
        cat "$STATE"/trust-guard-fired-*.jsonl | wc -l | tr -d ' ' ;;
    injections_total)  # из сводки метрик — единственный носитель, переживающий ротацию журнала
        need "$STATE/metrics.md"
        grep -oE 'Инжекций \(из лога\): [0-9]+' "$STATE/metrics.md" | grep -oE '[0-9]+$' | head -1 ;;
    disagreement_rate|disagreement_total)
        need "$STATE/metrics.md"
        v=$(grep -oE 'disagreement_resolution_rate *\| *[0-9]+% \([0-9]+/[0-9]+\)' "$STATE/metrics.md" | head -1)
        [ -n "$v" ] || { echo n/a; exit 0; }
        if [ "$KEY" = disagreement_rate ]; then printf '%s' "$v" | grep -oE '[0-9]+%' | tr -d '%'
        else printf '%s' "$v" | grep -oE '/[0-9]+' | tr -d '/'; fi ;;
    kb_generalisations)   # паттерны + принципы
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        echo $(( $(kb_count pattern) + $(kb_count principle) )) ;;
    kb_lineage)           # из них — с непустым source_cases (родословная записана)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -LE '^source_cases: *\[\] *$' "$LESSONS"/pattern-*.md "$LESSONS"/principle-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    ki_stored|ki_reached|ki_reached_pct|ki_acts)   # уровни знания из последнего отчёта замера knowledge-instrument
        need "$STATE/knowledge-instrument.md"
        case "$KEY" in
            ki_stored)      grep -E '^\| хранится' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3}' ;;
            ki_reached)     grep -E '^\| \*{0,2}доходил[оа]? до контекста' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3}' ;;
            ki_reached_pct) grep -E '^\| \*{0,2}доходил[оа]? до контекста' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9.]/,"",$4); print $4}' ;;
            ki_acts)        grep -E '^\| \*{0,2}действует' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3}' ;;
        esac ;;
    ki_date)              # дата последнего отчёта замера
        need "$STATE/knowledge-instrument.md"
        python3 -c "import os,sys,datetime; print(datetime.date.fromtimestamp(os.stat(sys.argv[1]).st_mtime))" "$STATE/knowledge-instrument.md" ;;
    kb_seed_principles) ls "$REPO"/knowledge/principle-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_seed_patterns)   ls "$REPO"/knowledge/pattern-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    tests_*)              # число проверок теста: запускает hooks/tests/<имя>.sh и читает его итог
        _t="$REPO/hooks/tests/${KEY#tests_}.sh"; [ -f "$_t" ] || { echo n/a; exit 0; }
        _out=$(bash "$_t" 2>&1 | tail -3)
        # Формы итога в тестах проекта: «N passed, M failed» · «PASS: N  FAIL: M» · «N/M passed»
        _n=$(printf '%s\n' "$_out" | grep -oE '([0-9]+) passed|PASS: *([0-9]+)|([0-9]+)/[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' | head -1)
        # Тест есть, а числа нет — «err» (сверка называет), а не «n/a» (сверка молча пропускает).
        [ -n "$_n" ] && echo "$_n" || echo err ;;
    today) date +%Y-%m-%d ;;
    "") echo "применение: bash scripts/doc-figures.sh <ключ>" >&2; exit 2 ;;
    *) echo "неизвестный ключ: $KEY" >&2; exit 2 ;;
esac
