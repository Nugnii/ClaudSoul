#!/usr/bin/env bash
# knowledge-audit-digest.sh — weekly mechanical audit of global-lessons.
# en: Weekly mechanical audit of global-lessons: counts, reliability distribution, FSRS buckets.
# Computes counts, reliability distribution, FSRS status buckets; writes digest
# file to ~/.claude/global-lessons/_audit-history/audit-YYYY-WW.md and a brief
# hint to $STATE_DIR/audit-hint.txt for session-start surfacing.
#
# Mechanical only — no LLM reasoning. For full analysis agent invokes
# /knowledge-audit. Digest provides trend data between manual audits.
#
# Idempotent per ISO week: if current week's file already exists, updates it.
# Run by launchd weekly (com.claudsoul.knowledge-audit.plist), or manually.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
HISTORY_DIR="${HISTORY_DIR:-$LESSONS_DIR/_audit-history}"
STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
HINT_FILE="$STATE_DIR/audit-hint.txt"
FSRS_LIB="${FSRS_LIB:-$HOME/.claude/hooks/fsrs-lib.sh}"

# Shared YAML frontmatter parser (single source — see yaml-lib.sh).
YAML_LIB="${YAML_LIB:-$SCRIPT_DIR/yaml-lib.sh}"
if [ -f "$YAML_LIB" ]; then
    # shellcheck source=/dev/null
    source "$YAML_LIB"
else
    echo "Missing yaml-lib.sh: $YAML_LIB" >&2; exit 1
fi

# Единый источник путей (paths-lib.sh); аварийный inline-fallback если не задеплоена.
PATHS_LIB="${PATHS_LIB:-$SCRIPT_DIR/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; fi

# iso_epoch — единый разбор меток времени (BSD↔GNU). Нужен для возраста заявки на
# эскалацию; переписывать разводку `date -d` / `date -j` здесь нельзя (D40, блокер
# pattern-shell-portability). Сначала рядом с собой, потом в установленном каталоге.
for _kad_lib in "$SCRIPT_DIR/portable-lib.sh" "$HOME/.claude/hooks/portable-lib.sh"; do
    if [ -f "$_kad_lib" ]; then source "$_kad_lib"; break; fi
done
unset _kad_lib

[ -d "$LESSONS_DIR" ] || { echo "No lessons dir: $LESSONS_DIR" >&2; exit 1; }
mkdir -p "$HISTORY_DIR" "$STATE_DIR" 2>/dev/null || true

# Phase 5.0 (v1.6 prerequisite) — periodic cross-contour discovery refresh.
# Detection infra (mcp-server/ingest/discovery.py::detect_cross_contour_mentions)
# runs only on /ingest. Weekly rescan scans LESSONS_DIR for new
# knowledge↔entity mentions and appends to cross-contour-discoveries.jsonl,
# which knowledge-activator.sh (v1.3.9 consumer) reads for the 📎 inject.
# Silent on any error — must never fail the audit.
DISCOVERY_PYTHON="${DISCOVERY_PYTHON:-$CLAUDSOUL_ROOT/mcp-server/.venv/bin/python}"
DISCOVERY_MODULE_DIR="${DISCOVERY_MODULE_DIR:-$CLAUDSOUL_ROOT/mcp-server}"
if [ "${DISCOVERY_DISABLED:-0}" != "1" ] \
   && [ -x "$DISCOVERY_PYTHON" ] \
   && [ -d "$DISCOVERY_MODULE_DIR/ingest" ]; then
    LESSONS_DIR="$LESSONS_DIR" \
    PYTHONPATH="$DISCOVERY_MODULE_DIR" \
    "$DISCOVERY_PYTHON" - <<'PYEOF' >/dev/null 2>&1 || true
import os
from pathlib import Path
try:
    from ingest.discovery import (
        detect_cross_contour_mentions,
        _load_knowledge_files,
        _append_cross_contour_log,
    )
    from ingest.integrate import _load_by_type
    lessons = Path(os.environ["LESSONS_DIR"])
    if lessons.exists():
        entities = _load_by_type(lessons, "entity")
        kf = _load_knowledge_files(lessons)
        events = detect_cross_contour_mentions(kf, entities)
        _append_cross_contour_log(events)
except Exception:
    pass
PYEOF

    # Phase 5.1 (v1.6) — semantic ranking of discoveries.
    # Embeds each (knowledge_file, entity_file) pair with fastembed, writes
    # cross-contour-ranked.jsonl. knowledge-activator reads it to surface
    # analogies independent of keyword-based injection set (R5 risk addressed:
    # no hot-path MCP calls).
    if [ -f "$DISCOVERY_MODULE_DIR/cli_cross_contour_rank.py" ]; then
        LESSONS_DIR="$LESSONS_DIR" \
        PYTHONPATH="$DISCOVERY_MODULE_DIR" \
            "$DISCOVERY_PYTHON" "$DISCOVERY_MODULE_DIR/cli_cross_contour_rank.py" \
            >/dev/null 2>&1 || true
    fi
fi

# Source FSRS lib if available; otherwise skip decay stats (return empty markers).
HAS_FSRS=false
if [ -f "$FSRS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$FSRS_LIB" && HAS_FSRS=true
fi

week_year=$(date +%G)
week_num=$(date +%V)
today=$(date +%Y-%m-%d)
digest_file="$HISTORY_DIR/audit-${week_year}-W${week_num}.md"

# Counters
total=0
case_n=0
pattern_n=0
principle_n=0
fresh_n=0
due_n=0
overdue_n=0
critical_n=0
sum_reliability=0
active_n=0
deprecated_n=0

# Top overdue (knowledge name + overdue days), top 5 by overdue_days desc.
overdue_list_tmp=$(mktemp)
escalation_list_tmp=$(mktemp)
self_list_tmp=$(mktemp)
trap 'rm -f "$overdue_list_tmp" "$escalation_list_tmp" "$self_list_tmp"' EXIT

for f in "$LESSONS_DIR"/case-*.md "$LESSONS_DIR"/pattern-*.md "$LESSONS_DIR"/principle-*.md; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    base=$(basename "$f")
    case "$base" in
        case-*)      case_n=$((case_n + 1)) ;;
        pattern-*)   pattern_n=$((pattern_n + 1)) ;;
        principle-*) principle_n=$((principle_n + 1)) ;;
    esac

    status=$(yaml_field "$f" status)
    [ "$status" = "active" ] && active_n=$((active_n + 1))
    [ "$status" = "deprecated" ] && deprecated_n=$((deprecated_n + 1))

    cc=$(yaml_field "$f" confirmed_count); cc="${cc:-0}"
    cd=$(yaml_field "$f" contradicted_count); cd="${cd:-0}"
    impact=$(yaml_field "$f" impact); impact="${impact:-1}"
    lc=$(yaml_field "$f" last_confirmed)

    # reliability = confirmed - contradicted
    if [[ "$cc" =~ ^-?[0-9]+$ ]] && [[ "$cd" =~ ^-?[0-9]+$ ]]; then
        rel=$((cc - cd))
        sum_reliability=$((sum_reliability + rel))
    fi

    if [ "$HAS_FSRS" = true ] && [ -n "$lc" ]; then
        overdue=$(fsrs_days_overdue "$lc" "$cc" "$impact" 2>/dev/null || echo 0)
        fstatus=$(fsrs_review_status "$overdue" 2>/dev/null || echo fresh)
        case "$fstatus" in
            fresh)    fresh_n=$((fresh_n + 1)) ;;
            due)      due_n=$((due_n + 1)) ;;
            overdue)  overdue_n=$((overdue_n + 1))
                      echo "${overdue}|${base}|${fstatus}" >> "$overdue_list_tmp" ;;
            critical) critical_n=$((critical_n + 1))
                      echo "${overdue}|${base}|${fstatus}" >> "$overdue_list_tmp" ;;
        esac
    fi
done

# avg reliability (rounded)
if [ "$total" -gt 0 ]; then
    avg_rel=$(awk -v s="$sum_reliability" -v n="$total" 'BEGIN { printf "%.1f", s / n }')
else
    avg_rel="—"
fi

# depth_ratio = (patterns + principles) / total (percent). Единое определение с
# hooks/metrics-collector.sh и skills/knowledge-audit/SKILL.md — до 2026-08-09
# каждое из трёх мест считало по-своему, и дайджест печатал 4% там, где метрики
# показывали 16% (principle-single-source-of-truth).
if [ "$total" -gt 0 ]; then
    depth_pct=$(awk -v p="$pattern_n" -v q="$principle_n" -v n="$total" 'BEGIN { printf "%.0f", (p + q) * 100 / n }')
else
    depth_pct=0
fi

# overdue_pct = (overdue + critical) / total
overdue_total=$((overdue_n + critical_n))
if [ "$total" -gt 0 ]; then
    overdue_pct=$(awk -v o="$overdue_total" -v n="$total" 'BEGIN { printf "%.0f", o * 100 / n }')
else
    overdue_pct=0
fi

# Top 5 overdue (desc by days)
top_overdue=""
if [ -s "$overdue_list_tmp" ]; then
    top_overdue=$(sort -t'|' -k1,1rn "$overdue_list_tmp" | head -5 | awk -F'|' '{ printf "- `%s` — overdue %s days (%s)\n", $2, $1, $3 }')
fi

# --- Fragile по перекройкам правила (D89) -----------------------------------------
#
# `knowledge/META.md` объявляет: 3+ записи в `modification_history` → `fragile: true`,
# что блокирует промоушен в principle и, ПО ТЕКСТУ ПРАВИЛ, множит `source_factor` на 1.2 при следующих
# противоречиях. Правило было объявлено АВТОМАТИЧЕСКИМ и не исполнялось никем: на
# 2026-08-26 единственное знание базы с тремя перекройками (`pattern-shell-portability`)
# несло `fragile: false`, и промоушен у него не был заблокирован. Найдено при разборе
# D81 — искал, не затёр ли откат чужие флаги, и обнаружил, что ставить их было некому.
#
# Почему здесь, а не у источника записи: автоматического писателя `modification_history`
# не существует — перекройку вносит агент руками при `/retro` (narrow/branch/deprecate),
# и точки перехвата нет. Остаётся сверка по базе, и дайджест для неё естественное место:
# он уже обходит все pattern/principle и уже ставит поля механически (`escalation_opened`
# двадцатью строками ниже — тот же класс: следствие правила, суждения не требует).
#
# Флаг только ВЗВОДИТСЯ, никогда не снимается: перекройки не исчезают из истории, и
# снятие означало бы, что правило снова считается стабильным, — а это уже суждение.
_mh_count() {
    awk '/^---$/{d++; if(d>=2) exit; next}
         d==1 && /^modification_history:/{inmh=1; next}
         inmh && /^[A-Za-z_][A-Za-z0-9_]*:/{inmh=0}
         inmh && /^[[:space:]]*-[[:space:]]*date:/{n++}
         END{print n+0}' "$1" 2>/dev/null
}
fragile_marked=""
for f in "$LESSONS_DIR"/pattern-*.md "$LESSONS_DIR"/principle-*.md; do
    [ -f "$f" ] || continue
    mh=$(_mh_count "$f")
    [[ "$mh" =~ ^[0-9]+$ ]] || continue
    [ "$mh" -ge "${FRAGILE_MIN_REWRITES:-3}" ] || continue
    cur=$(yaml_field "$f" fragile)
    [ "$cur" = "true" ] && continue
    if [ "$cur" = "false" ]; then
        awk '/^fragile:[[:space:]]*false[[:space:]]*$/ && !done { print "fragile: true"; done=1; next } { print }'             "$f" > "$f.tmp.$$" 2>/dev/null && mv "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$"
    else
        # Поля нет — вставляем перед `status:`, единственной строкой, про которую точно
        # известно, что она внутри frontmatter у каждого знания.
        awk '/^status:/ && !done { print "fragile: true"; done=1 } { print }'             "$f" > "$f.tmp.$$" 2>/dev/null && mv "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$"
    fi
    fragile_marked="${fragile_marked} $(basename "$f" .md)($mh)"
done

# Engineering escalation: blocker-tier patterns/principles with confirmed_count
# >= escalation_threshold. Embedded defense against recursive inside-out-blindness:
# when a blocker-tier pattern keeps reconfirming despite detection_signals, the
# system itself surfaces "next defense layer needed" rather than relying on the
# agent remembering. See principle-knowledge-in-the-world.md + case-2026-04-23-
# text-rule-vs-mechanism.md (15-е проявление pattern-inside-out-blindness).
for f in "$LESSONS_DIR"/pattern-*.md "$LESSONS_DIR"/principle-*.md; do
    [ -f "$f" ] || continue
    blocker=$(yaml_field "$f" blocker)
    [ "$blocker" = "true" ] || continue
    threshold=$(yaml_field "$f" escalation_threshold)
    [[ "$threshold" =~ ^[0-9]+$ ]] || continue
    cc=$(yaml_field "$f" confirmed_count); cc="${cc:-0}"
    [[ "$cc" =~ ^[0-9]+$ ]] || continue
    if [ "$cc" -ge "$threshold" ]; then
        base=$(basename "$f" .md)
        hint_text=$(yaml_field "$f" escalation_hint)
        [ -z "$hint_text" ] && hint_text="blocker-tier confirmed ${cc}× ≥ threshold ${threshold} — следующая defense layer требуется"

        # --- Возраст заявки (D46) ------------------------------------------------
        #
        # Единственным меняющимся числом здесь был `confirmed_count`, то есть дайджест
        # мерил, насколько знание ПОДКРЕПИЛОСЬ, а не насколько долго по нему не
        # действуют. Замер: строка эскалации стояла дословно одинаковой в 13 дайджестах
        # подряд (W19…W31), а `confirmed_count` рос — картина «всё под контролем».
        #
        # `escalation_opened` ставится механически при первом появлении заявки. Тогда
        # растущее число означает пропуск действия, а не рост уверенности в знании.
        opened=$(yaml_field "$f" escalation_opened)
        if [ -z "$opened" ]; then
            opened=$(date +%Y-%m-%d)
            # Вставка сразу после строки порога — единственное место, где поле точно
            # внутри frontmatter. `sed -i` разный на BSD и GNU, поэтому через временный файл.
            awk -v o="escalation_opened: $opened" '
                /^escalation_threshold:/ && !done { print; print o; done=1; next } { print }
            ' "$f" > "$f.tmp.$$" 2>/dev/null && mv "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$"
        fi
        age_days=0
        if [ -n "$opened" ]; then
            _o=$(iso_epoch "$opened" 2>/dev/null || echo 0)
            [ "${_o:-0}" -gt 0 ] && age_days=$(( ( $(date +%s) - _o ) / 86400 ))
        fi
        printf '%s|%s|%s|%s|%s\n' "$base" "$cc" "$threshold" "$age_days" "$hint_text" >> "$escalation_list_tmp"
    fi
done

escalation_section=""
escalation_count=0
if [ -s "$escalation_list_tmp" ]; then
    escalation_count=$(wc -l < "$escalation_list_tmp" | tr -d ' ')
    escalation_section=$(awk -F'|' '{
        printf "- `%s` — заявка открыта %s дн. назад (confirmed %s ≥ порога %s)\n  %s\n", $1, $4, $2, $3, $5
    }' "$escalation_list_tmp")
    # Возраст самой старой заявки — число, которое растёт от БЕЗДЕЙСТВИЯ.
    escalation_oldest=$(awk -F'|' 'BEGIN{m=0} {if ($4+0 > m) m=$4+0} END{print m}' "$escalation_list_tmp")
fi

# --- Знание о себе: счётчики по консолидированному слою (v1.11) ---
#
# Только pattern/principle: у case поле source_cases пусто (колонка «сессий» была бы
# бессмысленной), modification_history нет ни у одного, а 130 строк раз в неделю —
# стена, которую не читают.
#
# Фильтра «только про агента» здесь НЕТ намеренно. Отбор по domain даёт согласие с
# ручной разметкой 67%, по `actors ~ agent` — 76%; оба ниже порога 80%, и оба теряют,
# например, pattern-completion-by-internal-proxy (blocker-tier, знание буквально про
# поведение агента, но actors: [system]). Поэтому `actors ~ agent` — колонка-маркер,
# а не сито: лучше показать шесть лишних строк, чем молча потерять нужную.
#
# «сессий» = число уникальных ДАТ в source_cases — прокси «пережило N независимых
# сессий». Расходится с confirmed_count, и в этом смысл: 36 подтверждений на 22 датах
# и 6 подтверждений на одной дате — разные утверждения об устойчивости.
_self_dates() {
    awk '/^---$/{d++; if(d>=2) exit; next}
         d==1 && /^source_cases:/{ins=1; next}
         ins && /^[A-Za-z_][A-Za-z0-9_]*:/{ins=0}
         ins' "$1" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u | grep -c '' || echo 0
}
_self_last_kind() {
    awk '/^---$/{d++; if(d>=2) exit; next}
         d==1 && /^modification_history:/{inmh=1; next}
         inmh && /^[A-Za-z_][A-Za-z0-9_]*:/{inmh=0}
         inmh && /^[[:space:]]*kind:[[:space:]]*/{sub(/^[[:space:]]*kind:[[:space:]]*/,""); gsub(/^"|"$/,""); last=$0}
         END{print last}' "$1" 2>/dev/null
}
for f in "$LESSONS_DIR"/pattern-*.md "$LESSONS_DIR"/principle-*.md; do
    [ -f "$f" ] || continue
    actors=$(yaml_field "$f" actors)
    self_mark=" "
    # `,${actors// /},` → ",agent,interlocutor,"; шаблон не матчит ",subagent," и
    # "agent_design" — граница токена держится без regex.
    case ",${actors// /}," in *,agent,*) self_mark="·" ;; esac
    cc=$(yaml_field "$f" confirmed_count); cc="${cc:-0}"
    cd_=$(yaml_field "$f" contradicted_count); cd_="${cd_:-0}"
    [[ "$cc" =~ ^-?[0-9]+$ ]] && [[ "$cd_" =~ ^-?[0-9]+$ ]] || continue
    last_kind=$(_self_last_kind "$f")
    printf '%s|%s|%s|%s|%s\n' "$(basename "$f" .md)" "$((cc - cd_))" \
        "$(_self_dates "$f")" "${last_kind:-—}" "$self_mark" >> "$self_list_tmp"
done

self_section=""
if [ -s "$self_list_tmp" ]; then
    self_section=$(sort -t'|' -k2,2rn "$self_list_tmp" | awk -F'|' '{
        printf "| `%s` | %s | %s | %s | %s |\n", $1, $2, $3, ($4 == "" ? "—" : $4), $5
    }')
fi

# Compare with last week's digest for trend.
# Use natural sort — _audit-history files are YYYY-Www format so lexical sort works.
last_digest=$(ls -1 "$HISTORY_DIR"/audit-*.md 2>/dev/null | grep -v "$(basename "$digest_file")$" | sort | tail -1)
trend_line=""
if [ -n "$last_digest" ] && [ -f "$last_digest" ]; then
    prev_total=$(grep -E '^\*\*Total:\*\*' "$last_digest" 2>/dev/null | awk '{print $2}' | tr -d '[:alpha:]:')
    if [[ "$prev_total" =~ ^[0-9]+$ ]]; then
        diff=$((total - prev_total))
        if [ "$diff" -gt 0 ]; then
            trend_line="+${diff} files since last audit ($(basename "$last_digest" .md | sed 's/^audit-//'))"
        elif [ "$diff" -lt 0 ]; then
            trend_line="${diff} files since last audit ($(basename "$last_digest" .md | sed 's/^audit-//'))"
        else
            trend_line="No change since last audit ($(basename "$last_digest" .md | sed 's/^audit-//'))"
        fi
    fi
fi

# usage-outcome — замер с периодом 0 в реестре: он событийный (обновление снимка
# ~/.claude/usage-data), задания launchd у него нет, и до D216 (30 августа 2026) его не
# запускал никакой механизм — только чья-то память. Сторож теперь здесь: прогон раз в
# неделю вместе с дайджестом, а сам дайджест сторожит launchd-freshness по артефакту
# _audit-history. Прогон локальный и дешёвый — оговорка про режим check у measurement-due
# выше (docker-замеры) на него не распространяется. Протухший снимок — находка самого
# замера (он краснеет на возрасте данных); вердикт уезжает в тело дайджеста, не в hint:
# канал подсказки держит две строки, и приоритеты там заняты сигналами поважнее.
usage_outcome_line=""
_uoa="$CLAUDSOUL_ROOT/scripts/usage-outcome-audit.py"
if [ -f "$_uoa" ] && command -v python3 >/dev/null 2>&1; then
    _uoa_out=$(python3 "$_uoa" 2>/dev/null); _uoa_rc=$?
    usage_outcome_line="код ${_uoa_rc} — $(printf '%s\n' "$_uoa_out" | sed -n '1p')"
fi

# Write digest
{
    printf '# Knowledge Audit — %s (ISO week %s)\n\n' "$week_year-W$week_num" "$week_num"
    printf '**Generated:** %s (mechanical digest — for full analysis run `/knowledge-audit`)\n\n' "$today"
    printf '## Totals\n\n'
    printf -- '- **Total:** %s\n' "$total"
    printf -- '- Cases: %s · Patterns: %s · Principles: %s\n' "$case_n" "$pattern_n" "$principle_n"
    printf -- '- Active: %s · Deprecated: %s\n' "$active_n" "$deprecated_n"
    [ -n "$trend_line" ] && printf -- '- Trend: %s\n' "$trend_line"
    printf '\n## Health metrics\n\n'
    printf -- '- **depth_ratio** (patterns + principles / total): %s%% (healthy: 10-20%%)\n' "$depth_pct"
    printf -- '- **avg_reliability**: %s (confirmed - contradicted, average)\n' "$avg_rel"
    printf -- '- **overdue_ratio** (overdue + critical): %s%%\n' "$overdue_pct"
    if [ "$HAS_FSRS" = true ]; then
        printf '\n## FSRS status distribution\n\n'
        printf -- '- fresh: %s\n' "$fresh_n"
        printf -- '- due: %s\n' "$due_n"
        printf -- '- overdue: %s\n' "$overdue_n"
        printf -- '- critical: %s\n' "$critical_n"
    fi
    if [ -n "$top_overdue" ]; then
        printf '\n## Top overdue knowledge\n\n'
        printf '%s\n' "$top_overdue"
    fi
    if [ -n "$escalation_section" ]; then
        printf '\n## ⚠️ Engineering escalation needed\n\n'
        printf 'Blocker-tier knowledge где confirmed_count достиг `escalation_threshold` — следующая defense layer назрела (см. `principle-knowledge-in-the-world.md`):\n\n'
        printf '%s\n' "$escalation_section"
    fi
    if [ -n "$self_section" ]; then
        printf '\n## Знание о себе (консолидированный слой)\n\n'
        printf 'Счётчики по pattern/principle. «сессий» = уникальных дат в `source_cases` —\n'
        printf 'прокси «пережило N независимых сессий», намеренно расходится с confirmed_count.\n'
        printf 'Колонка `agent` — маркер `actors ~ agent`, а не фильтр (согласие с ручной\n'
        printf 'разметкой 76%%, ниже порога 80%% — сито потеряло бы нужное).\n\n'
        printf '| знание | reliability | сессий | последняя модификация | agent |\n'
        printf '|---|---|---|---|---|\n'
        printf '%s\n' "$self_section"
    fi
    if [ -n "$usage_outcome_line" ]; then
        printf '\n## Usage outcome (взгляд снаружи)\n\n'
        printf -- '- %s\n' "$usage_outcome_line"
    fi
    printf '\n---\n_Generated by `knowledge-audit-digest.sh` via launchd. Mechanical metrics only._\n'
} > "$digest_file"

# Write hint for session-start surfacing (overwrites prev).
# Priority: engineering escalation > overdue threshold > trend line.
#
# Секция «Знание о себе» СЮДА НЕ ДОБАВЛЯЕТСЯ — намеренно. Через hint она попала бы
# обратно в контекст агента на session-start, и измерение превратилось бы в инжект:
# черта, показанная экземпляру, перестаёт быть описанием и становится инструкцией,
# а подтверждения ей пишет тот же экземпляр, который её прочитал. Правило hold-out
# (knowledge/META.md): измеряемое и инжектируемое не пересекаются.
# Перепроверка закрытых пунктов долга. Закрытие, за которым стоит тест, проверяет себя
# само; закрытие разовым действием — нет, и откатывается молча (замер 2026-07-29: из
# 28 закрытых пунктов 17 держались разовым действием). Поэтому раз в неделю инварианты
# таких пунктов прогоняются заново, и сломавшийся получает ПЕРВЫЙ приоритет в подсказке:
# «сделано, а на деле откатилось» дороже любого накопительного сигнала.
backlog_broken=0
_recheck="$CLAUDSOUL_ROOT/scripts/backlog-recheck.sh"   # CLAUDSOUL_ROOT задан paths-lib (:33), повторный inline-хардкод убран (аудит 2026-08-08)
if [ -x "$_recheck" ] || [ -f "$_recheck" ]; then
    backlog_out=$(bash "$_recheck" 2>/dev/null || true)
    backlog_broken=$(printf '%s' "$backlog_out" | grep -c '^  ✗ ' || true)
    : "${backlog_broken:=0}"
fi

# Просроченные замеры. Замер без срока держится на том, что кто-то о нём вспомнит, —
# это намерение, а не механизм. Реестр `scripts/measurements.tsv` называет период каждого,
# а этот прогон запускает просроченные и сообщает, если что-то не удалось выполнить.
measure_overdue=0
_mdue="$CLAUDSOUL_ROOT/scripts/measurement-due.sh"
if [ -f "$_mdue" ]; then
    # Режим `check`: дайджест СООБЩАЕТ о просрочке и не выполняет замеры сам. Первая версия
    # запускала их — и прогон дайджеста стал зависеть от docker-замера переносимости, то есть
    # отчётный канал начал выполнять долгую работу и перестал быть предсказуемым по времени.
    measure_out=$(bash "$_mdue" check 2>/dev/null || true)
    measure_overdue=$(printf '%s' "$measure_out" | grep -c '^  просрочен:' || true)
    : "${measure_overdue:=0}"
fi

# Подсказка СКЛАДЫВАЕТСЯ из сигналов, а не выбирает один. Прежде тут стояла цепочка
# `elif`: срабатывал первый подходящий, остальные не показывались никогда. Цена измерена —
# эскалация занимала единственный слот 12 недель подряд (W20…W31), вытесняя сигнал о
# просрочке знаний при 44-87% просроченных. Приоритет остаётся (порядок строк), но нижние
# сигналы больше не пропадают: берём до двух самых важных.
#
# Порядок обоснован тем, ЧТО именно сообщает сигнал:
#   1. откат закрытия — ложное утверждение «сделано»: система говорит неправду о себе;
#   2. просроченный замер — неизвестно текущее состояние;
#   3. эскалация — знание созрело до механизма;
#   4. просрочка знаний, 5. тренд — накопительные, терпят.
_hint_lines=""
_hint_add() { [ -z "$_hint_lines" ] && _hint_lines="$1" || _hint_lines="${_hint_lines}
$1"; }

[ "${backlog_broken:-0}" -gt 0 ] 2>/dev/null && \
    _hint_add "📋 Долг: ${backlog_broken} инвариант(ов) закрытых пунктов перестали держаться — закрытие откатилось. Прогони scripts/backlog-recheck.sh и верни пункту ☐ в BACKLOG.md."
[ "${measure_overdue:-0}" -gt 0 ] 2>/dev/null && \
    _hint_add "📏 Замеры: просрочено ${measure_overdue}. Замер без срока держится на чьей-то памяти — прогони scripts/measurement-due.sh, реестр в scripts/measurements.tsv."
[ -n "${fragile_marked// /}" ] && \
    _hint_add "🏷️ Fragile по перекройкам:${fragile_marked} — 3+ записи в modification_history, флаг взведён механически (D89). Механически работает ОДНО последствие: метка при инжекте. Блокировка промоушена и source_factor × 1.2 — правила для агента в /learn и /retro, кода за ними нет (D90, проверено 27 августа 2026: у compute_source_factor ноль вызывающих во всём репозитории)."
[ "$escalation_count" -gt 0 ] && \
    _hint_add "🛠️ Engineering escalation: ${escalation_count} blocker-tier pattern(s) crossed escalation_threshold — см. digest §«Engineering escalation needed». Принцип: knowledge in the world, not in the head."
{ [ "$overdue_total" -ge 5 ] || [ "$overdue_pct" -ge 30 ]; } && \
    _hint_add "⚠️ Knowledge audit: ${overdue_total} overdue/critical (${overdue_pct}%) — рекомендую /knowledge-audit для ревизии."
[ -n "$trend_line" ] && [ "$total" -gt 0 ] && \
    _hint_add "📊 Weekly knowledge audit: total=${total}, ${trend_line}. Digest: _audit-history/audit-${week_year}-W${week_num}.md"

# Не больше двух строк: подсказка читается на старте сессии, и длинный список там
# превращается в фон — ровно то, от чего лечились в v1.7.2.
hint_parts=$(printf '%s\n' "$_hint_lines" | grep -v '^$' | head -2)

if [ -n "$hint_parts" ]; then
    printf '%s\n' "$hint_parts" > "$HINT_FILE"
else
    # No-op week: leave old hint intact if recent, else clear.
    rm -f "$HINT_FILE" 2>/dev/null || true
fi

exit 0
