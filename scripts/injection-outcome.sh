#!/usr/bin/env bash
# injection-outcome.sh — чем кончаются инжектированные знания: доли исходов по журналу подач (D228).
#
# Результат: у канала подачи есть метрика исхода — доли confirmed / not_applicable /
#            applicable_not_followed / outdated по инжектированным знаниям, с разрезом
#            по слоту подачи; «подали» и «помогло» перестают быть одним утверждением
# Проверка результата: bash scripts/injection-outcome.sh печатает доли и даёт 0;
#            при доле «не к месту» выше половины (n >= порога) — 1 (находка)
#
# Зачем (D228). Журнал подач (12 500 строк на 31 августа 2026) никем не потреблялся как
# метрика исхода: система знала, ЧТО подала, и не знала, ЧЕМ это кончилось — тот же класс,
# что D205 у стражей и D113 у blocker-fired. Замер 31 августа: 84 исхода из 216 (39%) —
# «не к месту»: шум доставки, который до этого прибора не имел владельца.
#
# ЧТО РЕШАЕТ ЭТО ЧИСЛО. Доля «не к месту» выше половины — якоря подач шумят: вход для
# очереди пересмотра якорей (anchor-review-queue). Рост доли «уместно и не применено» —
# вход для лестницы принуждения. Решение принимает владелец; скрипт даёт число.
#
# ПОЧЕМУ БЕЗ КОНТРОЛЬНОЙ ВЕТВИ. Задумывалось сравнение «инжектировано против контрольной
# группы рангов 4-6», и оно опровергнуто данными ДО постройки: продюсеры pending пишут
# только для инжектированных, пар «исход × контрольная подача» — 6 за всю историю против
# 116 у инжектированных. Контрольная роль отдана замеру delivery-miss (повтор-сигналы
# существуют независимо от инжекта).
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. (1) Сессия в исходе — сессия ВЕРДИКТА, не сессия инжекта: замерено
# 24 из 146 пар (16%) не находят свой инжект в логе — они считаются отдельной строкой
# «вердикт без инжекта в окне», не молча. (2) Окно начинается 2026-08-31: до D222 флаг
# injected был ранговым и контрольная группа была загрязнена. (3) Строки slot=research
# исключены из основного среза: слот исследования (D230) подаёт заведомо хвостовые
# знания, и его шум мерил бы не канал, а сам слот — его срез печатается отдельно.
#
# ОКНО В СЕССИЯХ, А НЕ В ДНЯХ: мера опыта — события, календарь между ними пуст
# (владелец: «могу за день запустить 1000 сессий, а могу полгода не подходить»).
# Источники едины, но несут поле сессии — окно строится как «последние K уникальных
# сессий журнала исходов». Нижняя граница D222 остаётся: это граница ЧИСТОТЫ данных,
# не ритма.
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SINCE="${INJECTION_OUTCOME_SINCE:-2026-08-31}"
MIN_N="${INJECTION_OUTCOME_MIN_N:-20}"
SESSIONS="${INJECTION_OUTCOME_SESSIONS:-20}"
command -v jq >/dev/null 2>&1 || { echo "нет jq"; exit 0; }

ILOG="$STATE/injection-log.jsonl"
OUTCOMES="$STATE/disagreement-outcomes.jsonl"
if [ ! -f "$ILOG" ] || [ ! -f "$OUTCOMES" ]; then
    echo "журналов ещё нет: подач или исходов не наработано (STATE=$STATE)"
    exit 0
fi

# Джойн: исход (session, knowledge) × подача (session_id, file, injected=true).
# Имена в обоих журналах — basename с .md (сверено: 216/216 и 0 аномалий).
# --slurpfile, не «-s f1 f2»: слурп двух файлов склеивает записи в ОДИН плоский
# массив, и .[0] оказывается первой записью, а не первым журналом.
# Вход чистится ПОСТРОЧНО перед слурпом: slurpfile не терпит невалидный JSON, и одна
# битая строка журнала (писатель исторически рождал их, ротация хранит) роняла весь
# разбор в пустоту — прибор молчал вместо находки (прожарка 31.08, атака adv5).
# Битые строки считает отдельная метрика, здесь они не предмет. Тот же приём — в
# delivery-miss.sh (брат по конструкции).
ILOG_CLEAN=$(mktemp); OUT_CLEAN=$(mktemp)
trap 'rm -f "$ILOG_CLEAN" "$OUT_CLEAN"' EXIT
jq -cRn 'inputs | fromjson? // empty' "$ILOG" > "$ILOG_CLEAN" 2>/dev/null || true
jq -cRn 'inputs | fromjson? // empty' "$OUTCOMES" > "$OUT_CLEAN" 2>/dev/null || true
REPORT=$(jq -rn --arg since "$SINCE" --argjson minn "$MIN_N" --argjson sessions "$SESSIONS" \
         --slurpfile ilog "$ILOG_CLEAN" --slurpfile ojournal "$OUT_CLEAN" '
    ($ilog | map(select((.date // "") >= $since and (.injected == true)))) as $inj |
    ($ojournal | map(select((.date // "") >= $since))) as $out_all |
    ($out_all | map(.session) | unique) as $sids_all |
    # Свежесть сессии — дата её последней записи; `reverse | unique` было дефектом
    # (jq unique сортирует → окно было алфавитным, не последним). Синхронно с
    # scripts/anchor-review-queue.sh — общий шаблон окна.
    ($out_all | group_by(.session) | map({s: .[0].session, last: (map(.date) | max)})
              | sort_by(.last) | reverse | .[0:$sessions] | map(.s)) as $recent |
    ($out_all | map(select(.session as $s | $recent | index($s)))) as $out |
    ($inj | map({key: "\(.session_id)|\(.file)", slot: (.slot // "main")})
          | group_by(.key) | map({key: .[0].key, slot: .[0].slot})) as $pairs |
    ($pairs | map({(.key): .slot}) | add // {}) as $slotmap |
    ($out | map(. + {key: "\(.session)|\(.knowledge)",
                     matched: ($slotmap["\(.session)|\(.knowledge)"] != null),
                     slot: ($slotmap["\(.session)|\(.knowledge)"] // "none")})) as $j |
    ($j | map(select(.matched and .slot != "research"))) as $main |
    ($j | map(select(.matched and .slot == "research"))) as $research |
    ($j | map(select(.matched | not)) | length) as $orphans |
    def shares($rows): ($rows | length) as $n |
        if $n == 0 then "нет данных"
        else ($rows | group_by(.outcome) | map("\(.[0].outcome) \(length) (\(length * 100 / $n | floor)%)") | join(", "))
        end;
    "инжектированных с исходом (окно: \($recent | length) последних сессий журнала, данные с \($since)): \($main | length)",
    "  доли: \(shares($main))",
    "  slot=research (отдельный срез, в основной не входит): \($research | length) — \(shares($research))",
    "  вердикт без инжекта в окне (сессия вердикта не равна сессии инжекта): \($orphans)",
    (($main | length) as $n |
     ($main | map(select(.outcome == "not_applicable")) | length) as $na |
     if $n < $minn then "  мало данных (n=\($n) < \($minn)), решения не принимаются"
     elif $na * 100 / $n > 50 then "FINDING:\($na * 100 / $n | floor)"
     else "  доля «не к месту» \( if $n > 0 then ($na * 100 / $n | floor) else 0 end)% — ниже порога решения (50%)" end)
' 2>/dev/null)

printf '%s\n' "$REPORT" | grep -v '^FINDING:'
FINDING=$(printf '%s\n' "$REPORT" | grep '^FINDING:' | head -1 | cut -d: -f2)
case "${FINDING:-}" in ''|*[!0-9]*) FINDING="" ;; esac
if [ -n "$FINDING" ]; then
    echo "[замер: находки, не сбой] доля «не к месту» ${FINDING}% — выше половины: якоря подач шумят, вход для anchor-review-queue"
    exit 1
fi
exit 0
