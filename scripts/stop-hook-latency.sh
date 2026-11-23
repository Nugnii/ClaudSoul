#!/usr/bin/env bash
# stop-hook-latency.sh — синхронный хук Stop держит ответ владельцу не дольше предела своей ценой, а не нагрузкой машины.
#
# Результат: на границах хода за окно ни один синхронный хук Stop не идёт дольше предела там, где остальные хуки той же
#            границы укладываются; граница, где медленны все разом, — остановка машины, она называется числом, но
#            находкой не считается
# Проверка результата: bash hooks/tests/test_stop_hook_latency.sh даёт 0
#
# Повод (D1235, 7 ноября 2026). Хуки Stop идут параллельно, и ответ ждёт самый долгий из синхронных (D1000). Сырое
# «максимум за сутки» мешает две разные причины: 7 ноября в 17:28 медленны были семь хуков из десяти разом (нагрузка
# машины 21 — параллельные наборы и скептики), а за 3–6 ноября 13 из 19 одиночных выходов за 10 с дал один
# `carrier-growth-check.sh` (холодный прогон реестра родов, до 52 с) — его цена, а не нагрузка. Остановка — граница, где
# за предел вышла половина хуков и больше; одиночный выход — находка с именем хука.
# Источник — записи `stop_hook_summary` расшифровок проекта ClaudSoul (их же читает «Проверка» D1000): у каждой границы
# список синхронных хуков с `durationMs`; фоновые хуки (`"async": true`) в список не входят.
# Коды: 0 — одиночных выходов нет; 1 — есть (хук, время, граница названы); 2 — границ в окне нет (не измерено).
# Переменные: SHL_DAYS (окно, дней, по умолчанию 3), SHL_LIMIT (предел, с, по умолчанию 10), SHL_TRANSCRIPTS (каталог
#             расшифровок — для свидетеля; иначе каталог проекта ClaudSoul в ~/.claude/projects).
# НАЗВАННЫЙ ПРЕДЕЛ: окно меряется по времени изменения файла расшифровки и по метке записи; граница без метки не судится.
# Условие снятия: харнесс начнёт писать метку времени у каждой записи хука Stop в расшифровке.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
# ЧЬИ СЕССИИ ЧИТАТЬ — ФАКТ МИРА, А НЕ КОРНЯ КОДА (D1295, 15 ноября 2026). Прибор свидетелей-атак привязывает
# `CLAUDSOUL_REPO` к снимку дерева, а у снимка расшифровок нет по построению: замер отвечал «не измерено» в каждой рамке.
# Ключ каталога берётся у указателя установки на настоящий репозиторий; без указателя — корень кода, как прежде.
WORLD=$(cat "$HOME/.claude/claudsoul-repo" 2>/dev/null) || WORLD=""
[ -n "$WORLD" ] && [ -d "$WORLD" ] || WORLD="$REPO"
DIR="${SHL_TRANSCRIPTS:-$HOME/.claude/projects/$(printf '%s' "$WORLD" | sed 's|[/ ]|-|g')}"
[ -d "$DIR" ] || { echo "stop-hook-latency: нет каталога расшифровок $DIR — не измерено"; exit 2; }
python3 - "$DIR" "${SHL_DAYS:-3}" "${SHL_LIMIT:-10}" <<'PY'
import datetime as dt, glob, json, os, sys
d, days, lim = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
bounds = stalls = 0; finds = []
for f in glob.glob(os.path.join(d, "*.jsonl")):
    if os.path.getmtime(f) < since.timestamp():
        continue
    for line in open(f, errors="replace"):
        if "stop_hook_summary" not in line:
            continue
        try:
            r = json.loads(line)
            t = dt.datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00"))
        except Exception:
            continue
        if r.get("subtype") != "stop_hook_summary" or t < since:
            continue
        hs = [(h.get("command", "").split("/")[-1], (h.get("durationMs") or 0) / 1000)
              for h in (r.get("hookInfos") or []) if isinstance(h, dict)]
        if not hs:
            continue
        bounds += 1
        slow = [x for x in hs if x[1] >= lim]
        if len(slow) * 2 >= len(hs):
            stalls += 1
        else:
            finds += [(t.strftime("%Y-%m-%d %H:%M"), n, s) for n, s in slow]
if bounds == 0:
    print("stop-hook-latency: границ хода за %g дн. нет — не измерено" % days); sys.exit(2)
print("stop-hook-latency: границ %d за %g дн., остановок машины (медленна половина хуков и больше) %d, одиночных "
      "выходов за %g с: %d" % (bounds, days, stalls, lim, len(finds)))
for t, n, s in sorted(finds):
    print("  %s  %s  %.1f с" % (t, n, s))
sys.exit(1 if finds else 0)
PY
