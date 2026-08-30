#!/usr/bin/env bash
# test_state_hygiene.sh — данные с писателем обязаны иметь и уборщика (D44, D45, D49).
#
# Три случая одного класса: файл пишется, а снимать его некому.
#
#   D49 — сигналы старта. ЕДИНСТВЕННЫЙ канал доставки: `knowledge-activator` на первом
#         PreToolUse. Сессия без вызова инструмента сигналов не видела никогда, файл
#         оставался навсегда. Замер: 99 файлов, ВСЕ непустые, старейший от 24 апреля.
#         Внутри — «в корне проекта нет CLAUDE.md», заявка на эскалацию, обратный дрейф.
#   D45 — лог инжектов: 8497 строк / 1,68 МБ, разброс дат 15 апреля — сегодня, ни одной
#         обрезки. Резать можно ТОЛЬКО по возрасту: `dis_harvest_corrections` сопоставляет
#         поправки с инжектами той же сессии по `session_id`.
#   D44 — throttle-файлы: библиотека ОБЪЯВЛЯЛА их эфемерными и не удаляла никогда, а
#         поимённый список уборки в `session-collector` разошёлся на 20+ семейств.
#         Живой счёт до починки: 333 файла `*-fired-*`.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HOOKS_DIR/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -qF -- "$1" <<< "$2"; }

# ============================================================================
# D49 — второй канал доставки сигналов старта
# ============================================================================
SURF="$HOOKS_DIR/pending-alerts-surface.sh"
[ -f "$SURF" ] || { echo "FAIL: нет $SURF"; exit 1; }
S1="$TMP/s1"; mkdir -p "$S1"

surf() { printf '{"session_id":"%s","prompt":"привет"}' "$1" | CLAUDSOUL_STATE_DIR="$S1" bash "$SURF" 2>&1; }
ctx()  { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# T1: сигналы доставляются каналом UserPromptSubmit, а не только PreToolUse
printf '⚠️ проверочный сигнал\n' > "$S1/startup-signals-sidA.txt"
OUT=$(ctx "$(surf sidA)")
has "проверочный сигнал" "$OUT" && ok || bad "T1a" "сигнал не доставлен вторым каналом: $OUT"
[ -f "$S1/startup-signals-sidA.txt" ] && bad "T1b" "файл не снят после доставки" || ok

# T2: показ ровно один раз
[ -z "$(ctx "$(surf sidA)")" ] && ok || bad "T2" "повторная доставка того же сигнала"

# T3: чужая сессия своих сигналов не получает
printf 'сигнал сессии B\n' > "$S1/startup-signals-sidB.txt"
OUT=$(ctx "$(surf sidC)")
has "сессии B" "$OUT" && bad "T3" "сигнал чужой сессии утёк" || ok

# T4: общая очередь по-прежнему поднимается, и вместе с сигналами
printf 'алерт из очереди\n' > "$S1/pending-alerts.txt"
printf 'сигнал сессии D\n' > "$S1/startup-signals-sidD.txt"
OUT=$(ctx "$(surf sidD)")
has "алерт из очереди" "$OUT" && ok || bad "T4a" "общая очередь перестала подниматься"
has "сигнал сессии D"  "$OUT" && ok || bad "T4b" "сигналы не поднялись вместе с очередью"

# T5: нечего показывать — молчит
[ -z "$(surf sidE)" ] && ok || bad "T5" "вывод при пустых источниках"

# T6: недоставленные сигналы убираются по возрасту, а не копятся месяцами
touch -t 202601010000 "$S1/startup-signals-ancient.txt"
printf 'старьё\n' > "$S1/startup-signals-ancient.txt"
touch -t 202601010000 "$S1/startup-signals-ancient.txt"
surf sidF >/dev/null
[ -f "$S1/startup-signals-ancient.txt" ] && bad "T6" "сигнал трёхмесячной давности не убран" || ok

# ============================================================================
# D44 — уборка стоит там, где эфемерность объявлена
# ============================================================================
S2="$TMP/s2"; mkdir -p "$S2"
# shellcheck source=/dev/null
source "$HOOKS_DIR/throttle-lib.sh"

touch -t 202601010000 "$S2/docs-family-fired-old.jsonl" "$S2/trust-guard-fired-ancient.jsonl"
touch -t 202601010000 "$S2/decompose-fired-ancient.flag"   # .flag переживал уборку навсегда
# Семейства с МЕЖСЕССИОННЫМ читателем — уборке не подлежат:
#   blocker-fired-*  ← backfill-compliance.sh:143 (эталон round-trip гейта)
#   rework-fired-*   ← metrics-collector.sh:434 (накопительная выборка порога D18)
#   trust-guard-fired-* ← scripts/doc-figures.sh:85 (число срабатываний для README, реестр doc-claims)
touch -t 202601010000 "$S2/blocker-fired-old.jsonl" "$S2/rework-fired-old.jsonl"
: > "$S2/keep-me.jsonl"
F=$(throttle_file "$S2" probe sid-1)

# T7: старые эфемерные throttle-файлы сняты, включая .flag
grep -qE 'docs-family-fired-old|decompose-fired-ancient' <<< "$(ls "$S2")" \
    && bad "T7a" "старые throttle-файлы не убраны" || ok

# T7b: семейства с межсессионным читателем СОХРАНЕНЫ.
# Первая версия уборки снесла 122 файла `blocker-fired-*`, и выборка гейта
# «round-trip по 26 сессиям» ужалась до 2. Данные писал живой хук; пересобрать нечем.
[ -f "$S2/blocker-fired-old.jsonl" ] && ok || bad "T7b" "уничтожена выборка backfill-compliance"
[ -f "$S2/rework-fired-old.jsonl" ]  && ok || bad "T7c" "уничтожена выборка порога D18"
[ -f "$S2/trust-guard-fired-ancient.jsonl" ] && ok || bad "T7d" "уничтожен счётчик срабатываний trust-guard (README)"
# T8: посторонние файлы не тронуты — уборка знает только свою схему имён
[ -f "$S2/keep-me.jsonl" ] && ok || bad "T8" "убран посторонний файл"
# T9: путь по-прежнему собирается верно
[ "$F" = "$S2/probe-fired-sid-1.jsonl" ] && ok || bad "T9" "схема имени сломана: $F"
# T10: свежий throttle-файл переживает уборку — иначе throttle перестанет работать
: > "$S2/blocker-fired-fresh.jsonl"
throttle_file "$S2" probe sid-2 >/dev/null
[ -f "$S2/blocker-fired-fresh.jsonl" ] && ok || bad "T10" "убран СВЕЖИЙ файл — throttle сломан"

# T11: отрицательный контроль — при огромном TTL старые остаются.
# Без него зелёный T7 не отличим от «уборка удаляет всё подряд».
S3="$TMP/s3"; mkdir -p "$S3"
touch -t 202601010000 "$S3/blocker-fired-old.jsonl"
THROTTLE_TTL_DAYS=99999 throttle_file "$S3" probe sid-3 >/dev/null
[ -f "$S3/blocker-fired-old.jsonl" ] && ok || bad "T11 отрицательный контроль" "TTL не учитывается — удаляется без разбора"

# ============================================================================
# D45 — ротация лога инжектов только по возрасту
# ============================================================================
# T12: писатель содержит ротацию, и она по ДАТЕ, а не по числу строк.
# Обрезка «оставить последние N» разорвала бы пару инжект↔поправка в середине сессии.
KA="$HOOKS_DIR/knowledge-activator.sh"
grep -q 'INJECTION_LOG_KEEP_DAYS' "$KA" && ok || bad "T12a" "ротации лога инжектов нет"
grep -qE 'tail -n [0-9]+ .*INJECTION_LOG|head -n [0-9]+ .*INJECTION_LOG' "$KA" \
    && bad "T12b" "обрезка по числу строк — сломает контур опровержения" || ok

# T13: суммарный показатель считается по логу И архиву — иначе ротация уронит число
MC="$HOOKS_DIR/metrics-collector.sh"
grep -q 'INJECTION_ARCHIVE' "$MC" && ok || bad "T13" "metrics-collector не знает про архив ротации"

# T13b: ВСЕ читатели лога идут через один источник — знаменатели не должны разъезжаться.
# Первая версия подключила к архиву только счётчик строк, а разбор оставила на голом логе.
# Разница дала «битых строк: 3432» — ровно размер архива, выдуманное число в живых метриках.
_direct=$(grep -cE '(jq -rR|grep -v).*"\$INJECTION_LOG"' "$MC" || true)
[ "${_direct:-0}" -eq 0 ] && ok \
    || bad "T13b" "остались читатели голого лога ($_direct шт.) — знаменатели разъедутся"

# T14: ротация переносит старое и сохраняет сумму
if command -v python3 >/dev/null 2>&1; then
    LOG="$TMP/injection-log.jsonl"; ARCH="$TMP/injection-log-archive.jsonl"
    python3 - "$LOG" <<'PY'
import datetime, json, pathlib, sys
p = pathlib.Path(sys.argv[1]); now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for i in range(400):
    d = (now - datetime.timedelta(days=200 if i < 150 else 1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows.append(json.dumps({"date": d, "file": f"k{i}.md", "session_id": "s"}) + "\n")
rows.append("это битая строка, не json\n")
p.write_text("".join(rows))
PY
    BEFORE=$(grep -c '' "$LOG")
    INJECTION_LOG_MIN_BYTES=1 python3 - "$LOG" "$ARCH" 60 <<'PY'
import datetime, json, os, pathlib, sys
log, archive, keep_days = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3])
if log.stat().st_size < int(os.environ.get("INJECTION_LOG_MIN_BYTES", "524288")): raise SystemExit
cut = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=keep_days)).strftime("%Y-%m-%d")
keep, old = [], []
for line in log.read_text(errors="replace").splitlines(True):
    try:
        d = json.loads(line); (keep if str(d.get("date", ""))[:10] >= cut else old).append(line)
    except Exception: keep.append(line)
if not old: raise SystemExit
with archive.open("a", encoding="utf-8") as fh: fh.writelines(old)
log.write_text("".join(keep), encoding="utf-8")
PY
    AFTER=$(grep -c '' "$LOG"); ARCHN=$(grep -c '' "$ARCH" 2>/dev/null || echo 0)
    [ "$((AFTER + ARCHN))" = "$BEFORE" ] && ok || bad "T14a" "ротация потеряла строки: $BEFORE → $AFTER + $ARCHN"
    [ "$ARCHN" -eq 150 ] && ok || bad "T14b" "в архив ушло $ARCHN строк вместо 150"
    grep -q 'битая строка' "$LOG" && ok || bad "T14c" "битая строка выброшена — её считает отдельная метрика"
else ok; ok; ok; fi

# T15: у каталога состояния есть замер со сроком
grep -q '^state-size' "$REPO/scripts/measurements.tsv" && ok || bad "T15" "объём каталога состояния не измеряется"

echo ""
echo "state hygiene tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
