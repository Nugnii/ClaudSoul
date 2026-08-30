#!/usr/bin/env python3
# Результат: ПРИБОР, не инструмент. Взгляд стороны, не знающей про ClaudSoul. Решение, которое оно меняет: где чинить трения по проектам; срок — при обновлении снимка (сейчас разовый, D71)
# Проверка результата: python3 scripts/usage-outcome-audit.py — дата снимка и покрытие разметкой напечатаны
#
"""usage-outcome-audit.py — единственный замер, который смотрит на результат работы,
а не на исправность машинерии.

Повод (2026-08-21). В реестре `scripts/measurements.tsv` на тот момент четырнадцать
замеров, и все меряют систему про саму себя: не разошёлся ли seed, живы ли задания launchd, не пухнет
ли каталог состояния, доходит ли знание до инструмента. Ни один не отвечает на вопрос
«работа стала лучше?». Ответить на него изнутри нельзя в принципе: тот же контур, что
делает работу, ставит себе и оценку.

Отчёт Claude Code Insights (`~/.claude/usage-data/`) даёт оценку снаружи. Разметку ставит
модель, которая про ClaudSoul не знает: на каждую сессию — тип трения, исход, сигналы
удовлетворённости. Это не эталон (размечает модель, не владелец), но независимость от
собственных хуков делает её проверкой на вменяемость внутренних метрик и метрикой исхода
для протокола ablation, у которого своей метрики исхода не было.

ЧТО ЭТОТ ЗАМЕР ПЕЧАТАЕТ ПЕРВЫМ И ПОЧЕМУ ИМЕННО ЭТО. Сам отчёт в шапке пишет «117 сессий,
18.06 → 20.08», а все качественные числа считает по 50 сессиям за 8–20 августа. Из-за
этого «27 случаев битого кода» читается как «за два месяца» — в пять раз мягче, чем есть.
Ровно pattern-subject-of-measurement-mismatch: предмет замера не тот, о котором
утверждение. Поэтому строка про покрытие идёт до любых выводов и печатает оба окна
раздельно — окно разметки и окно всех сессий.

О ТРЕНДЕ ЧЕСТНО. Разбивка по неделям печатается, но кодом возврата не судится: 50 сессий
на 2-3 недели — это единицы точек на неделю, где разница «стало лучше / стало хуже»
неотличима от того, какие задачи попались. Показывать — да, делать вывод — нет.

Данные обновляются не сами: все файлы датируются одним прогоном отчёта. Поэтому замер
краснеет на ВОЗРАСТЕ данных — протухший вход это и есть его находка.

Код возврата: 0 — данные свежие, находок нет; 1 — есть находка (данные устарели, либо
покрытие разметкой упало ниже половины); 2 — не смог отработать (нет входа).
"""

import json
import os
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone

USAGE_DIR = os.environ.get("USAGE_DATA_DIR", os.path.expanduser("~/.claude/usage-data"))
MAX_AGE_DAYS = int(os.environ.get("USAGE_MAX_AGE_DAYS", "14"))
MIN_COVERAGE = float(os.environ.get("USAGE_MIN_COVERAGE", "0.5"))

# Трения делятся на два класса, и лечатся они в разных местах. Замер, который печатает
# одну общую сумму, прячет это различие — а именно оно и есть содержание находки.
INPUT_FRICTION = {
    "wrong_approach", "misunderstood_request", "tone_style_mismatch",
    "communication_mismatch", "unclear_communication", "excessive_changes",
    "user_rejected_action", "unexpected_file_changes",
}
OUTPUT_FRICTION = {
    "buggy_code", "incomplete_solution", "incomplete_verification",
    "incomplete_propagation_of_edits", "incomplete_task", "incomplete_analysis",
    "factual_error", "hallucinated_fact", "hallucinated_or_wrong_claim",
    "incorrect_diagnosis",
}
# Остальное (api_error, tool_failure, environment_issue, permission_blocked,
# usage_limit_interruption, slow_response, missing_feature) — не про качество работы,
# а про среду. Считается отдельно, чтобы не разбавляло два первых класса.


def load(subdir):
    path = os.path.join(USAGE_DIR, subdir)
    if not os.path.isdir(path):
        return {}, 0
    out, newest = {}, 0
    for name in os.listdir(path):
        if not name.endswith(".json"):
            continue
        full = os.path.join(path, name)
        try:
            with open(full, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        sid = d.get("session_id") or name[:-5]
        out[sid] = d
        newest = max(newest, os.path.getmtime(full))
    return out, newest


def day(meta):
    return (meta.get("start_time") or "")[:10]


def week(meta):
    s = meta.get("start_time") or ""
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return "?"
    y, w, _ = dt.isocalendar()
    return f"{y}-н{w:02d}"


def main():
    facets, f_mtime = load("facets")
    meta, m_mtime = load("session-meta")

    if not meta:
        print(f"usage-outcome-audit: нет данных отчёта в {USAGE_DIR}", file=sys.stderr)
        print("Отчёт Claude Code Insights ещё не собирался на этой машине.", file=sys.stderr)
        return 2

    findings = []

    # --- 1. Покрытие. До любых выводов, двумя окнами раздельно.
    labelled_days = sorted(day(meta[s]) for s in facets if s in meta)
    all_days = sorted(day(m) for m in meta.values() if day(m))
    cov = len(labelled_days) / len(meta) if meta else 0.0

    # Сторож для периода «по событию» (D71, решение владельца 2026-08-28). Отчёт Claude
    # Code Insights из CLI не запускается — способ не найден, и все файлы датируются одним
    # прогоном. Пока замер стоял на недельном периоде, он каждую неделю печатал одно и то
    # же число, подавая замороженный снимок как показание периода. Дата снимка печатается
    # ПЕРВОЙ строкой, чтобы одномоментность выводов была видна раньше самих выводов.
    try:
        snap = max(os.path.getmtime(os.path.join(USAGE_DIR, d))
                   for d in ("facets", "session-meta")
                   if os.path.isdir(os.path.join(USAGE_DIR, d)))
        import datetime as _dt
        stamp = _dt.datetime.fromtimestamp(snap).strftime("%Y-%m-%d %H:%M")
        print(f"СНИМОК ДАННЫХ: {stamp} — разовый выгруз, не расписание.")
        print("Всё ниже относится к этому моменту, а не к сегодняшнему дню.\n")
    except (OSError, ValueError):
        print("СНИМОК ДАННЫХ: дату определить не удалось\n")

    print("ПОКРЫТИЕ РАЗМЕТКОЙ")
    print(f"  всего сессий в отчёте : {len(meta):3d}   окно {all_days[0]} → {all_days[-1]}")
    if labelled_days:
        print(f"  из них размечено      : {len(labelled_days):3d}   окно {labelled_days[0]} → {labelled_days[-1]}")
        print(f"  доля                  : {cov:.0%}")
        print("  Выводы ниже относятся ТОЛЬКО ко второму окну. Первое окно — техническое"
              " (число сессий, инструменты), качественных оценок в нём нет.")
    else:
        print("  размеченных сессий нет — качественная часть отчёта пуста")

    age_days = int((time.time() - max(f_mtime, m_mtime)) / 86400) if (f_mtime or m_mtime) else 999
    print(f"  возраст данных        : {age_days} дн. (порог {MAX_AGE_DAYS})")
    if age_days >= MAX_AGE_DAYS:
        findings.append(
            f"данные отчёта старше {MAX_AGE_DAYS} дн. ({age_days}) — пересобрать отчёт, "
            "иначе замер описывает прошлое"
        )
    if labelled_days and cov < MIN_COVERAGE:
        findings.append(
            f"размечена меньшая часть сессий ({cov:.0%} < {MIN_COVERAGE:.0%}) — "
            "выводы держатся на хвосте выборки, а не на всём периоде"
        )
    if not facets:
        findings.append("качественной разметки нет вовсе — мерить исход нечем")

    if not facets:
        if findings:
            print("[замер: находки, не сбой] — ненулевой код здесь — вердикт замера, а не сбой (D95)")
        return 1 if findings else 0

    # --- 2. По проектам: вход, выход, среда — раздельно.
    proj = defaultdict(lambda: {"n": 0, "in": 0, "out": 0, "env": 0,
                                "diss": 0, "sat": 0, "top": Counter()})
    for sid, f in facets.items():
        m = meta.get(sid)
        if not m:
            continue
        p = os.path.basename(m.get("project_path", "?")) or "?"
        b = proj[p]
        b["n"] += 1
        for k, v in (f.get("friction_counts") or {}).items():
            b["top"][k] += v
            if k in INPUT_FRICTION:
                b["in"] += v
            elif k in OUTPUT_FRICTION:
                b["out"] += v
            else:
                b["env"] += v
        sc = f.get("user_satisfaction_counts") or {}
        b["diss"] += sc.get("dissatisfied", 0) + sc.get("frustrated", 0)
        b["sat"] += sc.get("likely_satisfied", 0) + sc.get("satisfied", 0) + sc.get("happy", 0)

    print()
    print("ТРЕНИЯ ПО ПРОЕКТАМ (на сессию; вход = не понял рамку, выход = сказал готово без проверки)")
    print(f"  {'проект':24} {'сес':>4} {'вход':>6} {'выход':>6} {'среда':>6} {'-/+':>9}  чаще всего")
    for p, b in sorted(proj.items(), key=lambda x: -(x[1]["in"] + x[1]["out"]) / max(x[1]["n"], 1)):
        n = b["n"]
        top = ", ".join(f"{k} {v}" for k, v in b["top"].most_common(2)) or "—"
        print(f"  {p:24} {n:4d} {b['in']/n:6.2f} {b['out']/n:6.2f} {b['env']/n:6.2f} "
              f"{b['diss']:4d}/{b['sat']:<4d}  {top}")

    # Перекос между входом и выходом — это и есть указание, ГДЕ чинить. Порог 2:1 при
    # трёх и более сессиях: ниже этого выборка ничего не различает.
    for p, b in proj.items():
        if b["n"] < 3:
            continue
        i, o = b["in"], b["out"]
        if i >= 2 * max(o, 1) and i / b["n"] >= 1.0:
            findings.append(f"{p}: трение на входе ({i}) вдвое перевешивает выход ({o}) — "
                            "чинить формулировку рамки до начала работы, не проверку после")
        elif o >= 2 * max(i, 1) and o / b["n"] >= 1.0:
            findings.append(f"{p}: трение на выходе ({o}) вдвое перевешивает вход ({i}) — "
                            "чинить проверку до заявления «готово», не постановку задачи")

    # --- 3. По неделям. Печатается, но не судится.
    wk = defaultdict(lambda: {"n": 0, "fr": 0})
    for sid, f in facets.items():
        m = meta.get(sid)
        if not m:
            continue
        b = wk[week(m)]
        b["n"] += 1
        b["fr"] += sum((f.get("friction_counts") or {}).values())
    print()
    print("ПО НЕДЕЛЯМ (справочно — точек мало, вывода о тренде отсюда не делать)")
    for w in sorted(wk):
        b = wk[w]
        print(f"  {w}  сессий {b['n']:3d}  трений {b['fr']:3d}  на сессию {b['fr']/b['n']:.2f}")

    # --- 4. Исходы.
    out = Counter(f.get("outcome") for f in facets.values())
    print()
    print("ИСХОДЫ: " + ", ".join(f"{k} {v}" for k, v in out.most_common() if k))

    print()
    if findings:
        print("НАХОДКИ:")
        for f in findings:
            print(f"  ⚠️ {f}")
        print("[замер: находки, не сбой] — ненулевой код здесь — вердикт замера, а не сбой (D95)")
        return 1
    print("Находок нет.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
