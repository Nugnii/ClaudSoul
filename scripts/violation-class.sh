#!/usr/bin/env bash
# violation-class.sh — нарушение знания получает адрес сигнала: три класса вместо одного числа (D242).
#
# Результат: у каждого applicable_not_followed назван класс —
#            «said» (страж сказал, знание проигнорировано) / «muted» (страж заглушен
#            троттлом) / «сигнал не совпал» (детекта в сессии не было) — а это три
#            РАЗНЫЕ починки: лестница принуждения / ослабление троттла / пересмотр
#            сигналов. Решение об ask-ступени принимается по доле said (слово владельца).
# Проверка результата: bash scripts/violation-class.sh печатает классы и даёт 0;
#            при доле said выше половины (n >= порога) — 1 (находка).
#
# КОНСТРУКЦИЯ. Писатели уже существовали, не было читателя: rc_note_detection пишет
# {ts, guard, act: said|muted, sig} в detection-<SID>.jsonl (sid — в имени файла; ключ
# знания — префикс sig до `@` или `:`), dis_close_outcome пишет исход с session+knowledge.
# Джойн по (session, knowledge): said побеждает muted (сказанное хоть раз — сказано).
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. (1) detection-файлы живут в state/ и чистятся реже журнала исходов —
# для старых сессий детект мог не сохраниться, класс «не совпал» тогда завышен; доля
# посчитана по имеющимся файлам, их число печатается. (2) Артефакт
# state/violation-class-last.txt обязателен: он читаем по имени. Прежний довод
# — будто бегун замеров выбрасывает вывод — с 3 сентября 2026 неверен — бегун сохраняет вывод.
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
MIN_N="${VIOLATION_CLASS_MIN_N:-5}"
command -v jq >/dev/null 2>&1 || { echo "violation-class: нет jq — не измерено"; exit 2; }

OUTCOMES="$STATE/disagreement-outcomes.jsonl"
[ -f "$OUTCOMES" ] || { echo "журнала исходов ещё нет (STATE=$STATE)"; exit 0; }

# Детекты всех сессий: sid из имени файла, ключ — префикс sig до @ или :.
DET=$(mktemp); trap 'rm -f "$DET"' EXIT
: > "$DET"
# Архив уборки (D1008): строки журналов вне окна уборка переносит в архив семейства — «имя файла ⇥ mtime ⇥ строка»;
# сессия берётся из имени, как у живого файла ниже. Нет библиотеки архива — нет и архива.
SA="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/hooks/lib/state_archive.py"
ARC=""
if [ -f "$SA" ]; then
    # Архив не прочитан — «не измерено», а не доля по живым журналам: неполное чтение неотличимо от полного (род B).
    ARC=$(python3 "$SA" archived "$STATE" detection) \
        || { echo "violation-class: архив детекта не прочитан — не измерено"; exit 2; }
    [ -z "$ARC" ] || printf '%s\n' "$ARC" | jq -cR '
        split("\t") as $p | ($p[0] | sub("^detection-"; "") | sub("\\.jsonl$"; "")) as $sid
        | ($p[2:] | join("\t") | fromjson? // empty)
        | select(.sig and (.act == "said" or .act == "muted"))
        | {sid: $sid, act, key: (.sig | split("@")[0] | split(":")[0])}' >> "$DET" 2>/dev/null || true
fi
for f in "$STATE"/detection-*.jsonl; do
    [ -f "$f" ] || continue
    sid=$(basename "$f"); sid="${sid#detection-}"; sid="${sid%.jsonl}"
    jq -cR --arg sid "$sid" 'fromjson? // empty
        | select(.sig and (.act == "said" or .act == "muted"))
        | {sid: $sid, act, key: (.sig | split("@")[0] | split(":")[0])}' \
        "$f" 2>/dev/null >> "$DET" || true
done
# Журналов — живых файлов и перенесённых в архив (по имени): число файлов после уборки занижало бы прочитанное.
N_DET_FILES=$( { ls "$STATE"/detection-*.jsonl 2>/dev/null | sed 's|.*/||'
                 [ -z "$ARC" ] || printf '%s\n' "$ARC" | cut -f1; } \
               | sort -u | grep -c '' || true)

REPORT=$(jq -rn --argjson minn "$MIN_N" --arg ndet "${N_DET_FILES:-0}" \
         --slurpfile det "$DET" \
         --slurpfile out <(jq -cRn 'inputs | fromjson? // empty' "$OUTCOMES" 2>/dev/null) '
    ($out | map(select(.outcome == "applicable_not_followed"))) as $anf |
    ($det | group_by("\(.sid)|\(.key)")
          | map({key: "\(.[0].sid)|\(.[0].key)",
                 act: (if any(.[]; .act == "said") then "said" else "muted" end)})
          | map({(.key): .act}) | add // {}) as $dmap |
    ($anf | map(. + {k: "\(.session)|\(.knowledge | sub("\\.md$"; ""))"}
              | . + {class: ($dmap[.k] // "none")})) as $j |
    ($j | length) as $n |
    def rows($cls): $j | map(select(.class == $cls));
    "нарушений (applicable_not_followed): \($n); detection-файлов прочитано: \($ndet)",
    "  said (страж сказал — проигнорировано):   \(rows("said") | length) — \(rows("said") | map(.knowledge) | unique | join(", "))",
    "  muted (страж заглушен троттлом):         \(rows("muted") | length) — \(rows("muted") | map(.knowledge) | unique | join(", "))",
    "  сигнал не совпал (детекта в сессии нет): \(rows("none") | length) — \(rows("none") | map(.knowledge) | unique | join(", "))",
    (if $n < $minn then "  мало данных (n=\($n) < \($minn)), решения не принимаются"
     elif (rows("said") | length) * 100 / $n > 50 then "FINDING:\((rows("said") | length) * 100 / $n | floor)"
     else "  доля said \((rows("said") | length) * 100 / $n | floor)% — ниже порога решения (50%)" end)
' 2>/dev/null)

VISIBLE=$(printf '%s\n' "$REPORT" | grep -v '^FINDING:')
printf '%s\n' "$VISIBLE"
{ printf 'violation-class %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; printf '%s\n' "$VISIBLE"; } \
    > "$STATE/violation-class-last.txt" 2>/dev/null || true

FINDING=$(printf '%s\n' "$REPORT" | grep '^FINDING:' | sed -n '1p' | cut -d: -f2)
case "${FINDING:-}" in ''|*[!0-9]*) FINDING="" ;; esac
if [ -n "$FINDING" ]; then
    echo "[замер: находка, не сбой] доля said ${FINDING}% — сказанное игнорируется чаще, чем глушится: материал для решения владельца об ask-ступени (META.md:413 — прежние отказы пересматриваются числом, не вслепую)"
    printf '[находка] said: %s%%\n' "$FINDING" >> "$STATE/violation-class-last.txt" 2>/dev/null || true
    exit 1
fi
exit 0
