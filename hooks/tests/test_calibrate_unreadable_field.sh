#!/usr/bin/env bash
# test_calibrate_unreadable_field.sh — неразобранное поле не входит в замер молча (род B).
#
# Механика. `_as_int()` в scripts/calibrate.py отдавал при отказе разбора 0. Ноль здесь
# не счёт, а ЗАМЕР: «инжект 0 байт» и «поле не разобралось» — разные состояния мира, и
# подставленный ноль тянет вниз min, mean, median и p90 наравне с измеренным.
#
# Замер: stats([1200, 4200, 3300]) → min=1200 mean=2900 p90=4200;
#        stats([1200, "n/a", 3300]) → min=0 mean=1500 p90=3300 при том же n=3.
# Раздел «Рекомендации» решает по этим числам («Оставить `proactive_max=N`: потолок не
# трогается»; emergency-порог из p90/max silence) — то есть одно нечитаемое поле
# превращает «не прочитали» в «данные говорят: порог менять не надо».
#
# Починка — образец hooks/metrics-collector.sh:110-115: отказ считается ОТДЕЛЬНО от
# значения, в выборку не входит, и отчёт называет цену.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

CAL="$REPO/scripts/calibrate.py" python3 - << 'PY'
import importlib.util, os, sys

spec = importlib.util.spec_from_file_location("cal", os.environ["CAL"])
cal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cal)

P = F = 0
def check(cond, label, detail=""):
    global P, F
    if cond:
        P += 1; print(f"PASS [{label}]")
    else:
        F += 1; print(f"FAIL [{label}]: {detail}")

good = cal.stats([1200, 4200, 3300])
check(good["n"] == 3 and good["min"] == 1200 and good["p90"] == 4200
      and good.get("unread") == 0,
      "T0 читаемая выборка считается как раньше", good)
check("НЕ ПРОЧИТАНО" not in cal.fmt_stats(good),
      "T0b на читаемой выборке о непрочитанном молчит", cal.fmt_stats(good))

bad = cal.stats([1200, "n/a", 3300])
check(bad.get("unread") == 1, "T1 отказ разбора посчитан отдельно", bad)
check(bad["n"] == 2, "T2 n говорит, по скольким значениям посчитан итог", bad)
check(bad["min"] == 1200, "T3 подставленный ноль не занизил min", bad)
check(bad["mean"] == 2250.0, "T4 подставленный ноль не занизил mean", bad)
check("НЕ ПРОЧИТАНО 1" in cal.fmt_stats(bad),
      "T5 цена названа рядом с числами", cal.fmt_stats(bad))

# Отказ выражен МАРКЕРОМ вне домена значения, а не числом из него.
check(cal._as_int("n/a") is None and cal._as_int(None) is None
      and cal._as_int("4 200") is None,
      "T6 _as_int отдаёт None, а не 0",
      [cal._as_int("n/a"), cal._as_int(None), cal._as_int("4 200")])
check(cal._as_int("4200") == 4200 and cal._as_int(7) == 7,
      "T7 читаемое поле по-прежнему число")

# Пустая выборка — законный ноль, а не отказ.
empty = cal.stats([])
check(empty["n"] == 0 and empty.get("unread") == 0,
      "T8 пустая выборка отказом не считается", empty)

print(f"test_calibrate_unreadable_field: {P} passed, {F} failed")
sys.exit(1 if F else 0)
PY
exit $?
