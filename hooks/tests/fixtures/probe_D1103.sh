set -u
# СУДИТ: hooks/fsrs-lib.sh
# probe_D1103.sh — дни опыта «после отметки» считают сессии, начатые ПОСЛЕ мгновения отметки, а не после её даты.
#   Отметка — местные 01:00 позавчерашнего дня, 300 сессий — 12:00 того же дня (после отметки): опыт обязан быть > 0.
#   Прибор переводит мгновение в дату и считает дни строго после неё — сессии дня отметки выпадают (D1103, R4); так
#   нога T12 test_measurement_due краснела 25 октября 2026 в 23:00–24:00, когда «минус 48 часов» через переход на
#   зимнее время попадали на дату сессий фикстуры. 0 — опыт > 0; 1 — опыт 0; 2 — нет библиотеки или python3.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
L="$PWD/hooks/fsrs-lib.sh"
[ -f "$L" ] && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
read -r MARK DAY < <(python3 -c 'import datetime, time
d = datetime.date.today() - datetime.timedelta(days=2)
m = int(time.mktime(datetime.datetime(d.year, d.month, d.day, 1, 0).timetuple()))
print(m, d.isoformat())')
[ -n "${MARK:-}" ] || exit 2
python3 - "$W/reg.jsonl" "$DAY" <<'PY' || exit 2
import datetime, json, sys, time
d = datetime.date.fromisoformat(sys.argv[2])
noon = time.mktime(datetime.datetime(d.year, d.month, d.day, 12, 0).timetuple())   # местный полдень
iso = datetime.datetime.fromtimestamp(noon, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(sys.argv[1], 'w') as f:
    for i in range(300):
        f.write(json.dumps({"session_id": "s%d" % i, "started_at": iso}) + "\n")
PY
V=$(FSRS_SESSION_REGISTRY="$W/reg.jsonl" STATE_DIR="$W" bash -c '. "$1"; fsrs_experience_days_since_epoch "$2"' _ "$L" "$MARK" 2>/dev/null)
echo "опыт после отметки: ${V:-пусто}"
case "$V" in ''|*[!0-9]*) exit 2 ;; esac
[ "$V" -gt 0 ]
