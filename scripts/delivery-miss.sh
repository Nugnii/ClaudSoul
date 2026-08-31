#!/usr/bin/env bash
# delivery-miss.sh — пропуски доставки: был повтор знания, а подавалось ли оно (D228).
#
# Результат: у воронки подачи есть целевая метрика — не «сколько подали», а «сколько раз
#            НУЖНОЕ знание не было подано, когда его класс повторился»; три исхода
#            (подано / совпало-не-подано / не совпало) названы долями
# Проверка результата: bash scripts/delivery-miss.sh печатает доли и даёт 0; при доле
#            любого исхода выше половины (n >= порога) — 1 (находка с адресом решения)
#
# Зачем (D228). Оптимизировать валовую долю доставки (13%) бессмысленно: большинство
# знаний ситуативны. Правильный предмет — ПРОПУСК: сигнал «одно знание подтвердилось
# за сессию дважды/за сутки трижды» уже пишется гейтом разбора в five-whys-<SID>.seen
# с ИМЕНЕМ знания в подписи (сроды repeat: и daily:), и никем не сверялся с журналом
# подач той же сессии.
#
# ЧТО РЕШАЕТ ЭТО ЧИСЛО. «Подано и всё равно повтор» выше половины — доставка не меняет
# поведение: вход для лестницы принуждения (blocker/deny). «Не совпало» выше половины —
# отбор слеп к нужному: вход для слота исследования (D230). Решение принимает владелец.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. (1) Журнал .seen не несёт времени — «подано ДО повтора» не
# восстанавливается; считается наличие подачи В ТОЙ ЖЕ СЕССИИ. (2) Сроды без имени
# знания (rework/streak/discovery/correction/question/event) пропуск не определяют —
# только repeat и daily. (3) Глубина — живой injection-log (ротация: 200 сессий): сессии
# старше в категорию «не совпало» не записываются, а выбрасываются из счёта.
#
# ОКНО В СЕССИЯХ, А НЕ В ДНЯХ: ритм работы неравномерный.
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SESSIONS="${DELIVERY_MISS_SESSIONS:-20}"
MIN_N="${DELIVERY_MISS_MIN_N:-10}"
command -v jq >/dev/null 2>&1 || { echo "нет jq"; exit 0; }

ILOG="$STATE/injection-log.jsonl"
[ -f "$ILOG" ] || { echo "журнала подач нет (STATE=$STATE)"; exit 0; }

FILES=()
while IFS= read -r _f; do
    [ -n "$_f" ] && FILES+=("$_f")
done <<EOF
$(ls -t "$STATE"/five-whys-*.seen 2>/dev/null | head -n "$SESSIONS")
EOF
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "журналов повторов нет: гейт ещё не срабатывал (STATE=$STATE)"
    exit 0
fi

# Пары (sid, знание) из подписей repeat:/daily:. Имя сессии — из имени файла;
# в подписи repeat имена склеены запятой, у daily имя одно. Дедуп пар.
PAIRS=$(for f in "${FILES[@]}"; do
    sid=$(basename "$f" .seen)
    sid="${sid#five-whys-}"
    grep -oE '(repeat|daily):[^|]*' "$f" 2>/dev/null | cut -d: -f2- | tr ',' '\n' \
        | grep -v '^$' | grep -v '^none$' | while IFS= read -r name; do
            printf '%s\t%s\n' "$sid" "${name%.md}"
        done
done | sort -u)
N_PAIRS=$(printf '%s' "$PAIRS" | grep -c . 2>/dev/null || printf '0')
case "${N_PAIRS:-}" in ''|*[!0-9]*) N_PAIRS=0 ;; esac
if [ "$N_PAIRS" -eq 0 ]; then
    echo "повторов со связанным именем знания в окне нет (${#FILES[@]} сессий)"
    exit 0
fi

# Построчная чистка перед слурпом: одна битая строка журнала роняет slurpfile целиком,
# и прибор молчит вместо находки (прожарка 31.08; тот же приём — injection-outcome.sh).
ILOG_CLEAN=$(mktemp)
trap 'rm -f "$ILOG_CLEAN"' EXIT
jq -cRn 'inputs | fromjson? // empty' "$ILOG" > "$ILOG_CLEAN" 2>/dev/null || true
REPORT=$(printf '%s\n' "$PAIRS" | jq -rRn --argjson minn "$MIN_N" --slurpfile ilog "$ILOG_CLEAN" '
    [inputs | split("\t") | select(length == 2) | {sid: .[0], name: .[1]}] as $pairs |
    ($ilog | group_by("\(.session_id)|\(.file)")
           | map({key: (.[0].session_id + "|" + .[0].file),
                  delivered: (map(select(.injected == true)) | length > 0)})
           | map({(.key): (if .delivered then "delivered" else "matched" end)}) | add // {}) as $log |
    ($pairs | map(. + {cat: ($log["\(.sid)|\(.name).md"] // "not_matched")})) as $rows |
    ($rows | length) as $n |
    def cnt($c): ($rows | map(select(.cat == $c)) | length);
    "повторов знания с проверяемой доставкой: \($n) (окно сессий журналов повторов)",
    "  подано и всё равно повтор: \(cnt("delivered")) (\(cnt("delivered") * 100 / $n | floor)%)",
    "  совпало, но не подано (ранги 4-6): \(cnt("matched")) (\(cnt("matched") * 100 / $n | floor)%)",
    "  не совпало вовсе (пропуск отбора): \(cnt("not_matched")) (\(cnt("not_matched") * 100 / $n | floor)%)",
    (if $n < $minn then "  мало данных (n=\($n) < \($minn)), решения не принимаются"
     elif cnt("delivered") * 100 / $n > 50 then "FINDING:доставка не меняет поведение (\(cnt("delivered") * 100 / $n | floor)%) — вход для лестницы принуждения"
     elif cnt("not_matched") * 100 / $n > 50 then "FINDING:отбор слеп к повторяющемуся (\(cnt("not_matched") * 100 / $n | floor)%) — вход для слота исследования"
     else "  доли ниже порога решения (50%)" end)
' 2>/dev/null)

printf '%s\n' "$REPORT" | grep -v '^FINDING:'
FINDING=$(printf '%s\n' "$REPORT" | grep '^FINDING:' | head -1 | cut -d: -f2-)
if [ -n "${FINDING:-}" ]; then
    echo "[замер: находки, не сбой] $FINDING"
    exit 1
fi
exit 0
