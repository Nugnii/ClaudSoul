#!/usr/bin/env bash
# stop-context-restart.sh — перезапускает ли непустой additionalContext ход на событии Stop.
# Результат: свойство события Stop подтверждено или опровергнуто ПРОГОНОМ, а не выведено из
#            комментариев внутри самой системы
# Проверка результата: bash scripts/stop-context-restart.sh --check — запись есть, свежа и о
#            нынешней версии CLI
#
# Зачем (D349). На этом свойстве стоит устройство трёх Stop-хуков и раздел «Хук зовёт
# инструмент» в rules/CLAUDE.md. Принято оно по ДВУМ КОСВЕННЫМ свидетельствам ВНУТРИ системы:
# комментарии timestamp-canary-check.sh:37-43 и accepted-alternative-gap.sh:45-51, оба
# августа 2026, плюс описание инцидента 7 сентября (восемь пустых ходов в ProjectA). Знания об
# этом нет ни в knowledge/, ни в 500 файлах ~/.claude/global-lessons — проверено поиском по
# `stop_hook_active`. Замер отвечает и на вторую половину: НЕ перезапускает ли ход
# systemMessage — на этом допущении сидят четыре хука, ушедшие в тот канал ради безопасности.
#
# ПОЧЕМУ ЦИКЛ НЕВОЗМОЖЕН ПО ПОСТРОЕНИЮ, А НЕ ПО ПРИСМОТРУ. Проба печатает РОВНО ОДИН РАЗ за
# прогон: перед печатью она кладёт файл-отметку и на следующем вызове выходит с 0. Даже если
# посылка верна и ход перезапустится, он перезапустится однажды. Это структурная гарантия:
# сломать её может только правка самой пробы.
#
# ЧТО ЭТОТ СКРИПТ НЕ УТВЕРЖДАЕТ. Ответ годен для ТОЙ версии CLI, при которой снят: предмет —
# поведение харнесса, а не дерева. Поэтому версия пишется в запись, и `--check` краснеет при
# её смене. Природа второго вызова доказывается флагом `stop_hook_active`, то есть словом
# харнесса о себе; независимого свидетеля у неё нет.
#
# Режимы:
#   --check   (умолчание) — читает запись, ничего не запускает и денег не стоит.
#   --measure — поднимает ДВЕ headless-сессии (по одной на канал) и стоит денег.
#
# Код возврата (контракт реестра замеров): 0 — отработал, находок нет; 1 — отработал и НАШЁЛ;
# 2 — не смог отработать (нет claude/jq, авторизация не прошла, журнал пуст).
set -uo pipefail

_self_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
REPO="${CLAUDSOUL_REPO:-$(cd -- "$_self_dir/.." 2>/dev/null && pwd -P)}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
RECORD="${STOP_PROBE_RECORD:-$STATE/stop-context-restart.json}"
MAX_AGE_DAYS="${STOP_PROBE_MAX_AGE_DAYS:-90}"

MODE=check
case "${1:-}" in
    ""|--check|check)  MODE=check ;;
    --measure|measure) MODE=measure ;;
    *) printf 'stop-context-restart: неизвестный аргумент: %s (есть --check, --measure)\n' "$1" >&2
       exit 2 ;;
esac

# ------------------------------------------------------------------ --check
if [ "$MODE" = "check" ]; then
    command -v jq >/dev/null 2>&1 || { printf 'нет jq — запись не прочитать\n' >&2; exit 2; }
    if [ ! -f "$RECORD" ]; then
        printf 'НЕ ИЗМЕРЕНО: записи нет (%s). Свойство события Stop принято по косвенным\n' "$RECORD"
        printf 'свидетельствам внутри системы. Снять: bash scripts/stop-context-restart.sh --measure\n'
        exit 1
    fi
    _date=$(jq -r '.date // ""'        "$RECORD" 2>/dev/null)
    _cli=$(jq -r  '.cli_version // ""' "$RECORD" 2>/dev/null)
    _verd=$(jq -r '.verdict // ""'     "$RECORD" 2>/dev/null)
    _now_cli=$(claude --version 2>/dev/null | awk '{print $1}')
    if [ -n "$_now_cli" ] && [ "$_cli" != "$_now_cli" ]; then
        printf 'УСТАРЕЛО: запись о версии %s, сейчас %s. Предмет — поведение харнесса, и оно\n' "$_cli" "$_now_cli"
        printf 'меняется вместе с ним. Перемерить: bash scripts/stop-context-restart.sh --measure\n'
        exit 1
    fi
    # Возраст считается днями КАЛЕНДАРЯ намеренно: предмет — внешний харнесс, он живёт по
    # календарю выпусков, а не по темпу здешней работы.
    _rec_epoch=$(jq -r '.epoch // 0' "$RECORD" 2>/dev/null)
    _age_days=$(( ( $(date +%s) - _rec_epoch ) / 86400 ))
    if [ "$_rec_epoch" -gt 0 ] && [ "$_age_days" -gt "$MAX_AGE_DAYS" ]; then
        printf 'УСТАРЕЛО: записи %s дней (порог %s), вердикт «%s»\n' "$_age_days" "$MAX_AGE_DAYS" "$_verd"
        exit 1
    fi
    printf 'вердикт: %s (замер %s, CLI %s)\n' "$_verd" "$_date" "$_cli"
    case "$_verd" in
        additionalContext_restarts_systemMessage_does_not) exit 0 ;;
        *) exit 1 ;;
    esac
fi

# ------------------------------------------------------------------ --measure
command -v claude >/dev/null 2>&1 || { printf 'нет claude — мерить нечем\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1     || { printf 'нет jq\n' >&2; exit 2; }

SBX=$(mktemp -d) || exit 2
trap 'rm -rf "$SBX"' EXIT

# Проба: журналирует КАЖДЫЙ свой вызов и печатает ровно один раз за прогон.
cat > "$SBX/probe.sh" <<'PROBE'
#!/usr/bin/env bash
IN=$(cat 2>/dev/null)
ACTIVE=$(printf '%s' "$IN" | jq -r '.stop_hook_active // false' 2>/dev/null)
printf '{"active":"%s"}\n' "${ACTIVE:-?}" >> "$STOP_PROBE_JOURNAL"
# САМОГАШЕНИЕ: печатаем один раз за прогон. Отсюда структурная невозможность цикла.
[ -f "$STOP_PROBE_FIRED" ] && exit 0
: > "$STOP_PROBE_FIRED"
case "${STOP_PROBE_ARM:-}" in
    ac) printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"замер D349"}}\n' ;;
    sm) printf '{"systemMessage":"замер D349"}\n' ;;
esac
exit 0
PROBE
chmod +x "$SBX/probe.sh"

_arm() {  # _arm <ac|sm> — печатает число вызовов пробы и флаг второго вызова
    _a="$1"
    _j="$SBX/journal-$_a.jsonl"; : > "$_j"
    _f="$SBX/fired-$_a.flag";    rm -f "$_f"
    jq -cn --arg c "bash $SBX/probe.sh" \
        '{hooks:{Stop:[{hooks:[{type:"command",command:$c}]}]}}' > "$SBX/settings-$_a.json"
    STOP_PROBE_ARM="$_a" STOP_PROBE_JOURNAL="$_j" STOP_PROBE_FIRED="$_f" \
    claude -p "Ответь ровно одним словом: готово." \
        --settings "$SBX/settings-$_a.json" \
        --setting-sources "" \
        --no-session-persistence \
        --permission-prompts none \
        --restricted \
        --strict-mcp-config \
        --max-budget-usd "${STOP_PROBE_BUDGET:-0.20}" \
        >/dev/null 2>"$SBX/err-$_a.txt"
    _n=$(grep -c . "$_j" 2>/dev/null) || _n=0
    _second=$(sed -n '2p' "$_j" 2>/dev/null | jq -r '.active // "?"' 2>/dev/null)
    printf '%s %s' "${_n:-0}" "${_second:-?}"
}

read -r N_AC ACTIVE_AC <<<"$(_arm ac)"
read -r N_SM ACTIVE_SM <<<"$(_arm sm)"
printf 'additionalContext: вызовов пробы %s (у второго stop_hook_active=%s)\n' "$N_AC" "$ACTIVE_AC"
printf 'systemMessage:     вызовов пробы %s\n' "$N_SM"

if [ "${N_AC:-0}" -eq 0 ] || [ "${N_SM:-0}" -eq 0 ]; then
    printf 'НЕ ВЫПОЛНЕН: проба не вызвана ни разу — сессия не поднялась (авторизация?).\n' >&2
    sed -n '1,5p' "$SBX/err-ac.txt" >&2 2>/dev/null
    exit 2
fi

VERDICT=unexpected
if [ "$N_AC" -ge 2 ] && [ "$ACTIVE_AC" = "true" ] && [ "$N_SM" -eq 1 ]; then
    VERDICT=additionalContext_restarts_systemMessage_does_not
elif [ "$N_AC" -eq 1 ]; then
    VERDICT=additionalContext_does_NOT_restart   # посылка НЕВЕРНА: правило стоит на пустом
elif [ "$N_SM" -ge 2 ]; then
    VERDICT=systemMessage_ALSO_restarts          # канал systemMessage выбран зря
fi

mkdir -p "$STATE" 2>/dev/null
jq -n --arg d "$(date '+%Y-%m-%d %H:%M')" --argjson e "$(date +%s)" \
      --arg c "$(claude --version 2>/dev/null | awk '{print $1}')" \
      --argjson nac "${N_AC:-0}" --argjson nsm "${N_SM:-0}" \
      --arg aac "${ACTIVE_AC:-?}" --arg v "$VERDICT" \
      '{date:$d, epoch:$e, cli_version:$c, n_ac:$nac, n_sm:$nsm, active_ac:$aac, verdict:$v}' \
      > "$RECORD" 2>/dev/null || { printf 'не удалось записать %s\n' "$RECORD" >&2; exit 2; }

printf 'вердикт: %s → %s\n' "$VERDICT" "$RECORD"
[ "$VERDICT" = "additionalContext_restarts_systemMessage_does_not" ] && exit 0
exit 1
