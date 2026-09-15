#!/usr/bin/env bash
# dose-response.sh — меняется ли исход с числом повторных подач одного знания за сессию (D240).
#
# Результат: у решения «расширять ли доставку» есть замер цены шума — распределение ДОЗ
#            (строк журнала на пару сессия×знание) и доли исходов по корзинам дозы
#            1 / 2-3 / 4+; «подавали чаще» и «помогало лучше» перестают быть одним
#            утверждением. Базлайн снят ДО правок отбора (кириллизация, семантический
#            слот): «до» без него невосстановимо.
# Проверка результата: bash scripts/dose-response.sh печатает распределение и даёт 0;
#            при доле «не к месту» выше половины в корзине 4+ (n >= порога) — 1 (находка).
#
# ЧТО РЕШАЕТ ЭТО ЧИСЛО. Если исход НЕ улучшается с дозой (или ухудшается) — повторная
# подача того же знания в сессию тратит бюджет контекста впустую: вход для inject-rule
# «второй инжект только при новом сигнале» (PLAN, preconscious filtering) и довод против
# расширения квот. Если улучшается — довод за. Решение принимает владелец; скрипт даёт число.
#
# КОНСТРУКЦИЯ — брат injection-outcome.sh: тот же джойн (session, knowledge), то же окно
# в сессиях журнала исходов, та же построчная чистка перед слурпом. Отличие одно: пара
# несёт ДОЗУ (число строк инжекта), исход группируется по корзинам дозы.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. (1) Сессия исхода — сессия ВЕРДИКТА: вердикт без подачи в окне
# считается отдельной строкой, не молча (у брата таких 16%). (2) Данные с 2026-08-31:
# до D222 флаг injected был ранговым. (3) slot=research — отдельный срез: слот подаёт
# заведомо хвостовые знания с намеренным повтором, его доза мерила бы слот, а не канал.
# (4) Вывод живёт в собственном артефакте state/dose-response-last.txt. Прежний довод
# — будто бегун замеров выбрасывает вывод — с 3 сентября 2026 неверен — бегун сохраняет вывод и
# печатает его адрес; артефакт остаётся потому, что он ЧИТАЕМ по имени, а не по адресу
# внутри чужого прогона, и не исчезает вместе с очередным перезапуском замера.
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SINCE="${DOSE_RESPONSE_SINCE:-2026-08-31}"
MIN_N="${DOSE_RESPONSE_MIN_N:-10}"
SESSIONS="${DOSE_RESPONSE_SESSIONS:-20}"
command -v jq >/dev/null 2>&1 || { echo "dose-response: нет jq — не измерено"; exit 2; }

ILOG="$STATE/injection-log.jsonl"
OUTCOMES="$STATE/disagreement-outcomes.jsonl"
if [ ! -f "$ILOG" ] || [ ! -f "$OUTCOMES" ]; then
    echo "журналов ещё нет: подач или исходов не наработано (STATE=$STATE)"
    exit 0
fi

ILOG_CLEAN=$(mktemp); OUT_CLEAN=$(mktemp)
trap 'rm -f "$ILOG_CLEAN" "$OUT_CLEAN"' EXIT
jq -cRn 'inputs | fromjson? // empty' "$ILOG" > "$ILOG_CLEAN" 2>/dev/null || true
jq -cRn 'inputs | fromjson? // empty' "$OUTCOMES" > "$OUT_CLEAN" 2>/dev/null || true

REPORT=$(jq -rn --arg since "$SINCE" --argjson minn "$MIN_N" --argjson sessions "$SESSIONS" \
         --slurpfile ilog "$ILOG_CLEAN" --slurpfile ojournal "$OUT_CLEAN" '
    ($ilog | map(select((.date // "") >= $since and (.injected == true)))) as $inj |
    # Пара (сессия, файл) несёт дозу и слот. Доза = число строк — дедупа в журнале нет
    # намеренно, номер подачи и есть строки (D240).
    ($inj | group_by("\(.session_id)|\(.file)")
          | map({key: "\(.[0].session_id)|\(.[0].file)",
                 dose: length,
                 slot: (.[0].slot // "main")})) as $pairs |
    def bucket($d): if $d >= 4 then "4+" elif $d >= 2 then "2-3" else "1" end;
    def dosedist($rows):
        ["1","2-3","4+"] | map(. as $b |
            ($rows | map(select(bucket(.dose) == $b)) | length) as $n |
            select($n > 0) | "доза \($b): пар \($n)") | join(", ");
    ($pairs | map(select(.slot != "research"))) as $pmain |
    ($pairs | map(select(.slot == "research"))) as $pres |
    # Исходы: окно — последние K сессий журнала (свежесть по max(date), не unique —
    # jq unique сортирует и делает окно алфавитным).
    ($ojournal | map(select((.date // "") >= $since))) as $out_all |
    ($out_all | group_by(.session) | map({s: .[0].session, last: (map(.date) | max)})
              | sort_by(.last) | reverse | .[0:$sessions] | map(.s)) as $recent |
    ($out_all | map(select(.session as $s | $recent | index($s)))) as $out |
    ($pmain | map({(.key): .dose}) | add // {}) as $dosemap |
    ($out | map(. + {dose: ($dosemap["\(.session)|\(.knowledge)"] // 0)})) as $j |
    ($j | map(select(.dose == 0)) | length) as $orphans |
    ($j | map(select(.dose > 0))) as $matched |
    def shares($rows): ($rows | length) as $n |
        if $n == 0 then "нет данных"
        else ($rows | group_by(.outcome) | map("\(.[0].outcome) \(length) (\(length * 100 / $n | floor)%)") | join(", "))
        end;
    "пары (сессия × знание) с \($since), основной срез: \($pmain | length); дозы: \(dosedist($pmain))",
    "  slot=research (отдельный срез, намеренный повтор): пар \($pres | length); дозы: \(dosedist($pres))",
    "исходов в окне (\($recent | length) последних сессий): по корзинам дозы:",
    (["1","2-3","4+"][] | . as $b |
        ($matched | map(select(bucket(.dose) == $b))) as $rows |
        "  доза \($b): \(shares($rows))"),
    "  вердикт без подачи в окне (сессия вердикта не равна сессии подачи): \($orphans)",
    (($matched | map(select(bucket(.dose) == "4+"))) as $hi |
     ($hi | length) as $n |
     ($hi | map(select(.outcome == "not_applicable")) | length) as $na |
     if $n < $minn then "  корзина 4+: мало данных (n=\($n) < \($minn)), решения не принимаются"
     elif $na * 100 / $n > 50 then "FINDING:\($na * 100 / $n | floor)"
     else "  корзина 4+: доля «не к месту» \($na * 100 / $n | floor)% — ниже порога решения (50%)" end)
' 2>/dev/null)

VISIBLE=$(printf '%s\n' "$REPORT" | grep -v '^FINDING:')
printf '%s\n' "$VISIBLE"
# Артефакт: последний отчёт переживает глушение stdout в measurement-due (предел 4).
{ printf 'dose-response %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; printf '%s\n' "$VISIBLE"; } \
    > "$STATE/dose-response-last.txt" 2>/dev/null || true

FINDING=$(printf '%s\n' "$REPORT" | grep '^FINDING:' | sed -n '1p' | cut -d: -f2)
case "${FINDING:-}" in ''|*[!0-9]*) FINDING="" ;; esac
if [ -n "$FINDING" ]; then
    echo "[замер: находка, не сбой] в корзине 4+ доля «не к месту» ${FINDING}% — повторная подача шумит: вход для inject-rule «второй инжект только при новом сигнале»"
    printf '[находка] корзина 4+ не к месту: %s%%\n' "$FINDING" >> "$STATE/dose-response-last.txt" 2>/dev/null || true
    exit 1
fi
exit 0
