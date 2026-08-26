#!/usr/bin/env bash
# ab-authorization-replay.sh — ADR-010 Ф3: A/B нового классификатора авторизации
# на накопленных транскриптах ДО включения гейта Ф2.
#
# A — семантика v1.22.0 (авторизация как состояние задачи);
# B — семантика до v1.22.0 (одношаговая проверка, ручка AUTH_ONESHOT_ONLY=1).
# Оба прогона идут через hooks/lib/backfill-replay-one.sh в песочницах —
# живое состояние не трогается, события читаются из stdout воркера.
#
# Выборка: свежайшие основные транскрипты сессий (~/.claude/projects/*/*.jsonl,
# без subagents/workflows), размером 50КБ..1.5МБ, N штук (default 8). Границы
# выборки печатаются в отчёте: молчаливое усечение читается как «всё покрыто».
#
# Ожидание ADR-010: proactive(A) < proactive(B) — часть «самовольных» правок
# на деле шла под действовавшим поручением, которого одношаговая проверка не видела.

set -uo pipefail

N="${1:-8}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKER="$ROOT/hooks/lib/backfill-replay-one.sh"
[ -f "$WORKER" ] || { echo "нет воркера $WORKER" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "нужен jq" >&2; exit 2; }

REAL_HOME="$HOME"
# Верхняя граница 6МБ, не 1.5МБ: длинные АВТОРИЗОВАННЫЕ сессии — именно та страта,
# где живут спорные proactive-классификации; кап 1.5МБ отбирал болтовню без правок
# (первый честный прогон: 3 деструктивных хода на 8 транскриптов — предмет замера
# был не тот, о котором утверждение).
SAMPLE=$(find "$REAL_HOME/.claude/projects" -maxdepth 2 -name "*.jsonl" -type f \
    ! -path "*subagents*" ! -path "*workflows*" -size +50k -size -6000k 2>/dev/null \
    | while IFS= read -r f; do
        # GNU-форма первой: на Linux `stat -f` возвращает 0 со справкой о ФС, и фоллбек
        # не наступает (см. hooks/portable-lib.sh, file_mtime).
        printf '%s %s\n' "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)" "$f"
      done | sort -rn | head -"$N" | sed 's/^[0-9]* //')

TOTAL_FOUND=$(printf '%s\n' "$SAMPLE" | grep -c '' || true)
[ "$TOTAL_FOUND" -gt 0 ] || { echo "выборка пуста — транскриптов 50КБ..1.5МБ не нашлось"; exit 1; }

# Отрицательный контроль ДО замера: фикстура с заведомо деструктивным ходом.
# Ноль событий на ней = реплей неисправен, и нули корпуса — поломка, не данные.
# Урок этого же дня: два прогона подряд публиковали нули как «нет ходов», пока
# причиной была расщеплённая песочница (прибор не отличал «нет» от «не измерил»).
_selfcheck() {
    local fx out
    fx=$(mktemp "${TMPDIR:-/tmp}/ab-selfcheck.XXXXXX.jsonl") || return 1
    {
        jq -cn '{type:"user",timestamp:"2026-01-01T10:00:00Z",message:{role:"user",content:[{type:"text",text:"обсуждаем дизайн"}]}}'
        jq -cn '{type:"assistant",timestamp:"2026-01-01T10:00:05Z",message:{role:"assistant",content:[{type:"text",text:"Поправил."},{type:"tool_use",name:"Edit",id:"x",input:{}}]}}'
        jq -cn '{type:"user",timestamp:"2026-01-01T10:00:30Z",message:{role:"user",content:[{type:"text",text:"спасибо, посмотрю позже обязательно"}]}}'
    } > "$fx"
    out=$(AUTH_ONESHOT_ONLY=0 bash "$WORKER" "$fx" 2>/dev/null)
    rm -f "$fx"
    printf '%s' "$out" | grep -q '"type":"proactive"'
}
_selfcheck || { echo "реплей неисправен: отрицательный контроль не дал события — нули корпуса были бы поломкой, не данными" >&2; exit 2; }

run_replay() { # $1 transcript, $2 oneshot(0|1) → события в stdout
    # Воркер САМ создаёт песочницу (export HOME=$WORK_DIR) и никогда не трогает
    # живое состояние. Внешние HOME/ITR_STATE_DIR ему не передавать: override
    # расщепляет песочницу — детектор пишет события в один каталог, воркер
    # читает из другого, и реплей молча выдаёт ноль (поймано вторым прогоном;
    # первый ноль был от того же класса — самодельной «помощи» самоизоляции).
    AUTH_ONESHOT_ONLY="$2" bash "$WORKER" "$1" 2>/dev/null || true
}

count_type() { grep -c "\"type\":\"$2\"" <<< "$1" 2>/dev/null || true; }

PA=0; SA=0; PB=0; SB=0; GA=0; ROWS=""
while IFS= read -r t; do
    [ -n "$t" ] || continue
    A=$(run_replay "$t" 0)
    B=$(run_replay "$t" 1)
    pa=$(count_type "$A" proactive); sa=$(count_type "$A" solicited)
    pb=$(count_type "$B" proactive); sb=$(count_type "$B" solicited)
    ga=$(count_type "$A" gentle)
    PA=$((PA + pa)); SA=$((SA + sa)); PB=$((PB + pb)); SB=$((SB + sb)); GA=$((GA + ga))
    ROWS="${ROWS}| $(basename "$t" .jsonl | cut -c1-8)… | ${pa} | ${sa} | ${pb} | ${sb} |\n"
done <<< "$SAMPLE"

DA=$((PA + SA)); DB=$((PB + SB))
echo "# A/B авторизации (ADR-010 Ф3) — $(date -u +%Y-%m-%d)"
echo ""
echo "Выборка: ${TOTAL_FOUND} транскриптов (свежайшие, 50КБ..6МБ, без subagents/workflows)."
echo "A = состояние задачи (v1.22.0), B = одношаговая проверка (до v1.22.0)."
echo ""
echo "| Транскрипт | proactive A | solicited A | proactive B | solicited B |"
echo "|------------|-------------|-------------|-------------|-------------|"
printf '%b' "$ROWS"
echo "| **итого** | **${PA}** | **${SA}** | **${PB}** | **${SB}** |"
echo ""
if [ "$DA" -gt 0 ] && [ "$DB" -gt 0 ]; then
    echo "Деструктивных ходов классифицировано: A=${DA}, B=${DB}; gentle (для контроля неизменности): ${GA}."
    echo "Доля самовольных (proactive) среди деструктивных: A = $((PA * 100 / DA))%, B = $((PB * 100 / DB))%."
    if [ "$PA" -lt "$PB" ]; then
        echo ""
        echo "Вывод: состояние задачи перевело $((PB - PA)) ходов из «самовольных» в «под поручением» — ожидание ADR-010 подтверждается на корпусе."
    elif [ "$PA" -eq "$PB" ]; then
        echo ""
        echo "Вывод: разницы нет — на этой выборке одношаговая проверка не ошибалась; расширить выборку прежде чем включать гейт."
    else
        echo ""
        echo "Вывод: proactive выросло — ПРОТИВОРЕЧИТ ожиданию ADR-010, гейт НЕ включать, разбираться."
    fi
else
    echo "Не измеряли: деструктивных ходов в выборке не нашлось — расширь выборку (N=${N})."
fi
