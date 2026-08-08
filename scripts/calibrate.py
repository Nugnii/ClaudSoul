#!/usr/bin/env python3
"""
scripts/calibrate.py — Pretzel plan Phase 3 step 3.3.

Анализ накопленной истории intrusiveness-tracker для калибровки constants v1.4.0.

Вход:
  ~/.claude/hooks/state/intrusiveness-history.jsonl (ITR_HISTORY override)
Выход:
  markdown draft с распределениями acceptance/ignore per axis, state distribution,
  cost peaks, рекомендации по изменению budgets/thresholds.

Usage:
    python3 scripts/calibrate.py                      # stdout
    python3 scripts/calibrate.py -o docs/calibration-v1.4.md
    ITR_HISTORY=/path/to/history.jsonl python3 scripts/calibrate.py

Формат valid chunk (v1.3.8+): boundary ∈ {stop, precompact} AND gate-events>0.
Legacy chunks (без boundary) пропускаются — они до v1.3.8 chunk boundary.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path
from statistics import mean, median

DEFAULT_HIST = Path.home() / ".claude" / "hooks" / "state" / "intrusiveness-history.jsonl"


def load_history(path: str) -> list[dict]:
    chunks: list[dict] = []
    malformed = 0
    with open(path, "r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                chunks.append(json.loads(raw))
            except json.JSONDecodeError:
                malformed += 1
    if malformed:
        print(f"⚠️  {malformed} malformed lines skipped in {path}", file=sys.stderr)
    return chunks


def is_valid_chunk(c: dict) -> bool:
    if c.get("boundary") not in ("stop", "precompact"):
        return False
    m = c.get("metrics") or {}
    gate_events = (
        m.get("gentle_accepted", 0)
        + m.get("gentle_ignored", 0)
        + m.get("proactive_events", 0)
    )
    return gate_events > 0


def pct(n: int, total: int) -> float:
    return 100.0 * n / total if total else 0.0


def _as_int(v) -> int:
    """Число из поля, которое бывает строкой.

    В живом `intrusiveness-history.jsonl` `injection_bytes_max` приходит строкой в 1619
    записях из 2923 — писатель пишет через оболочку, где всё текст. `sorted()` над смесью
    str и int падает с TypeError, то есть голый `python3 scripts/calibrate.py` (ровно тот
    вызов, который предлагает `session-start.sh:194`) не работал вовсе.
    """
    try:
        return int(str(v).strip() or 0)
    except (TypeError, ValueError):
        return 0


def stats(values: list) -> dict:
    # Приведение к числу — ЗДЕСЬ, а не в восьми местах вызова: поля приходят из оболочки,
    # где всё текст, и смешанный список рушит `sorted()` с TypeError. В живом
    # `intrusiveness-history.jsonl` таких 1619 записей из 2923; голый
    # `python3 scripts/calibrate.py` (ровно тот вызов, что предлагает session-start.sh:194)
    # падал целиком, а не терял одно поле.
    values = [_as_int(v) for v in values]
    if not values:
        return {"n": 0, "min": 0, "max": 0, "mean": 0.0, "median": 0, "p90": 0, "sum": 0}
    s = sorted(values)
    p90_idx = min(len(s) - 1, int(0.9 * len(s)))
    return {
        "n": len(values),
        "min": s[0],
        "max": s[-1],
        "mean": round(mean(values), 2),
        "median": median(values),
        "p90": s[p90_idx],
        "sum": sum(values),
    }


def histogram_block(values: list[int], width: int = 40) -> str:
    if not values:
        return "_нет данных_"
    counter = Counter(values)
    max_count = max(counter.values())
    rows = []
    for key in sorted(counter):
        bar_len = max(1, int(width * counter[key] / max_count))
        rows.append(f"    {key:>4}  {'█' * bar_len} {counter[key]}")
    return "```\n" + "\n".join(rows) + "\n```"


def fmt_stats(s: dict) -> str:
    return (
        f"n={s['n']} min={s['min']} max={s['max']} "
        f"mean={s['mean']} median={s['median']} p90={s['p90']} sum={s['sum']}"
    )


def fold_by_session(chunks: list[dict]) -> list[dict]:
    """Одна запись на сессию — последняя по времени.

    Без свёртки сессии взвешиваются по болтливости: в живом файле 2923 записи на 216
    сессий, у одной 156 записей. Решение уже принято для метрик вмешательства
    (`metrics-collector.sh:247-262`: «2879 строк это 213 сессий… метрика показывала 0%
    там, где честный счёт даёт 19%») и здесь просто не было применено.
    """
    by_sid: dict = {}
    for c in chunks:
        sid = c.get("session_id")
        if sid is None:
            by_sid[id(c)] = c        # без идентификатора — считаем отдельной записью
            continue
        prev = by_sid.get(sid)
        if prev is None or str(c.get("closed_at") or c.get("created_at") or "") >= str(
            prev.get("closed_at") or prev.get("created_at") or ""
        ):
            by_sid[sid] = c
    return list(by_sid.values())


def analyze(chunks: list[dict]) -> dict:
    chunks = fold_by_session(chunks)
    valid = [c for c in chunks if is_valid_chunk(c)]
    legacy = [c for c in chunks if c.get("boundary") not in ("stop", "precompact")]
    boundary_noevent = [
        c for c in chunks
        if c.get("boundary") in ("stop", "precompact") and not is_valid_chunk(c)
    ]

    gentle_used = [c.get("budget", {}).get("gentle_used", 0) for c in valid]
    proactive_used = [c.get("budget", {}).get("proactive_used", 0) for c in valid]
    shrink = [c.get("budget", {}).get("shrink_events", 0) for c in valid]

    # Константа берётся из МАКСИМУМА по корпусу, а не из первого попавшегося отрезка.
    #
    # `gentle_max` в истории — не константа, а УЖЕ УСОХШЕЕ значение: библиотека уменьшает
    # его на единицу за каждое проигнорированное мягкое вмешательство
    # (`intrusiveness-state-lib.sh:204-207`). Доказательство совпадением: по корпусу
    # `shrink_events sum` = 100 и `gentle ignored` = 100, ровно.
    #
    # Прежний `next(...)` брал значение первого валидного отрезка, поэтому отчёт зависел
    # от ПОРЯДКА СТРОК в логе: попадись первым отрезок с двумя усыханиями — «max» вышел бы
    # 3, и рекомендация ниже исчезла бы или сменилась на противоположную.
    gentle_max = max((c.get("budget", {}).get("gentle_max", 0) for c in valid), default=5) or 5
    proactive_max = max((c.get("budget", {}).get("proactive_max", 0) for c in valid), default=3) or 3

    gentle_accepted = sum(c.get("metrics", {}).get("gentle_accepted", 0) for c in valid)
    gentle_ignored = sum(c.get("metrics", {}).get("gentle_ignored", 0) for c in valid)
    proactive_total = sum(c.get("metrics", {}).get("proactive_events", 0) for c in valid)
    override_total = sum(c.get("metrics", {}).get("override_events", 0) for c in valid)
    silence_surfaced = sum(c.get("metrics", {}).get("silence_debt_surfaced", 0) for c in valid)

    # State distribution — sum counts across all valid chunks
    state_totals: Counter = Counter()
    for c in valid:
        for state, count in (c.get("state_distribution") or {}).items():
            state_totals[state] += count
    state_grand = sum(state_totals.values())

    # Sessions hitting budget ceiling
    gentle_ceiling_hits = sum(1 for v in gentle_used if v >= gentle_max)
    proactive_ceiling_hits = sum(1 for v in proactive_used if v >= proactive_max)

    cost = {
        "timing": stats([c.get("cost_peaks", {}).get("timing_max", 0) for c in valid]),
        "silence": stats([c.get("cost_peaks", {}).get("silence_max", 0) for c in valid]),
        "injection_bytes": stats([c.get("cost_peaks", {}).get("injection_bytes_max", 0) for c in valid]),
    }

    backward = [c.get("cascading", {}).get("backward_count", 0) for c in valid]
    debt_pending = [c.get("debt", {}).get("pending", 0) for c in valid]

    return {
        "counts": {
            "total_lines": len(chunks),
            "valid": len(valid),
            "legacy_no_boundary": len(legacy),
            "boundary_no_events": len(boundary_noevent),
        },
        "sessions": len({c.get("session_id") for c in valid}),
        "date_range": (
            min((c["date"] for c in valid if c.get("date")), default="—"),
            max((c["date"] for c in valid if c.get("date")), default="—"),
        ),
        "budget": {
            "gentle_used_stats": stats(gentle_used),
            "gentle_used_hist": gentle_used,
            "gentle_max": gentle_max,
            "gentle_ceiling_hits": gentle_ceiling_hits,
            "proactive_used_stats": stats(proactive_used),
            "proactive_used_hist": proactive_used,
            "proactive_max": proactive_max,
            "proactive_ceiling_hits": proactive_ceiling_hits,
            "shrink_stats": stats(shrink),
        },
        "gate_events": {
            "gentle_accepted": gentle_accepted,
            "gentle_ignored": gentle_ignored,
            "gentle_total": gentle_accepted + gentle_ignored,
            "acceptance_rate": pct(gentle_accepted, gentle_accepted + gentle_ignored),
            "proactive_total": proactive_total,
            "override_total": override_total,
            "silence_surfaced": silence_surfaced,
        },
        "states": {"totals": dict(state_totals), "grand_total": state_grand},
        "cost": cost,
        "cascading": stats(backward),
        "debt_pending": stats(debt_pending),
    }


def render_recommendations(a: dict) -> list[str]:
    """Generate recommendations based on distributions."""
    recs: list[str] = []
    b = a["budget"]
    g = a["gate_events"]

    # Budget ceiling analysis
    valid_n = a["counts"]["valid"]
    gc_rate = pct(b["gentle_ceiling_hits"], valid_n)
    pc_rate = pct(b["proactive_ceiling_hits"], valid_n)

    if gc_rate >= 20:
        recs.append(
            f"- **Поднять `gentle_max`**: {b['gentle_ceiling_hits']}/{valid_n} "
            f"({gc_rate:.0f}%) chunks упёрлись в потолок {b['gentle_max']}. "
            "Кандидат → 6-7 (зависит от acceptance rate в тех же chunks)."
        )
    else:
        # Рекомендации «опустить gentle_max» здесь НЕТ намеренно, и это вывод разбора
        # 2026-08-01, а не упущение.
        #
        # Прежняя версия сравнивала p90 счётчика `gentle_used` с потолком `gentle_max`.
        # Это две РАЗНЫЕ величины: `gentle_used` растёт только на НЕигнорированных
        # вмешательствах (`intrusiveness-state-lib.sh:195-197`), тогда как потолок
        # расходуют именно игнорированные. По корпусу: `gentle_used sum` = 22 = число
        # принятых, а из 122 мягких событий 100 (82%) в этот счётчик не попали вовсе.
        # Вывод «запас неиспользуем» из такого сравнения не следует.
        #
        # Что потолок расходуется — видно по распределению записанного `gentle_max`:
        # 5→1807, 4→396, 3→261, 2→196, 1→85, 0→82. Восемьдесят две записи дошли до нуля.
        recs.append(
            f"- **`gentle_max` не трогать по этим данным.** p90 счётчика `gentle_used`="
            f"{b['gentle_used_stats']['p90']} НЕ сопоставим с потолком {b['gentle_max']}: "
            "счётчик растёт на принятых, потолок расходуют игнорированные "
            "(shrink_events = число игнорирований, совпадает до единицы). "
            "Калибровать здесь имеет смысл ШАГ УСЫХАНИЯ, а не начальное значение."
        )

    if pc_rate >= 20:
        recs.append(
            f"- **Поднять `proactive_max`**: {b['proactive_ceiling_hits']}/{valid_n} "
            f"({pc_rate:.0f}%) chunks упёрлись в {b['proactive_max']}. "
            f"Кандидат → {b['proactive_used_stats']['median'] + 1} (медиана+1); "
            f"p90={b['proactive_used_stats']['p90']}, max={b['proactive_used_stats']['max']}. "
            "ОГОВОРКА: поднятие 2→3 в v1.7.0 превышений не убрало — прежде чем поднимать "
            "снова, проверь, что потолок вообще является регулятором: `itr_remaining_budget` "
            "читают только печать и её тест, ни один хук на нём не блокирует."
        )
    elif b["proactive_used_stats"]["p90"] < b["proactive_max"]:
        recs.append(
            f"- **Оставить `proactive_max={b['proactive_max']}`**: p90="
            f"{b['proactive_used_stats']['p90']}, потолок не трогается."
        )

    # Acceptance rate
    if g["gentle_total"] >= 20:
        if g["acceptance_rate"] < 30:
            recs.append(
                f"- **Снизить gentle частоту**: acceptance_rate="
                f"{g['acceptance_rate']:.0f}% ({g['gentle_accepted']}/{g['gentle_total']}). "
                "Большинство gentle игнорируются — порог value (или silence_cost) "
                "слишком низкий, нужны более селективные триггеры."
            )
        elif g["acceptance_rate"] >= 70:
            recs.append(
                f"- **Повысить gentle частоту**: acceptance_rate="
                f"{g['acceptance_rate']:.0f}% — интервенции релевантны, "
                "можно расширить gate (понизить value threshold или повысить silence_cost weight)."
            )

    # State distribution
    st = a["states"]["totals"]
    st_grand = a["states"]["grand_total"]
    if st_grand:
        focus_pct = pct(st.get("focus", 0), st_grand)
        stuck_pct = pct(st.get("stuck", 0), st_grand)
        idle_pct = pct(st.get("idle", 0), st_grand)
        if stuck_pct > 30:
            recs.append(
                f"- **State classifier: stuck {stuck_pct:.0f}%** — слишком "
                "много stuck классификаций. Пересмотреть сигналы (error_count threshold, "
                "repetition детектор) — возможно `stuck > 2 errors` дет-true, вместо "
                "более узкого `stuck > 2 same-error`."
            )
        if "distressed" not in st:
            recs.append(
                "- **`distressed` state не наблюдался** в накопленной истории v1.5.7+ — "
                "либо сигналы слишком строгие (R10 требует 2+ классов), либо реальных "
                "distress-эпизодов не было. Ждать ≥1 срабатывания перед калибровкой порогов AP2."
            )

    # Silence debt
    debt_max = a["debt_pending"]["max"]
    if debt_max >= 3:
        recs.append(
            f"- **Silence debt pending max={debt_max}** — есть хронические несказанные. "
            "Проверить декаи/expire логику `silence_debt.pending_topics` — "
            "топики накапливаются, не разрешаются."
        )

    # Cost peaks
    si = a["cost"]["silence"]
    if si["max"] >= 4:
        recs.append(
            f"- **silence_max p90={si['p90']}, max={si['max']}** — emergency "
            "override (silence_cost≥4) срабатывал. Если override_events/valid >= 10% — "
            "это индикатор что gate слишком подавляющий; пересмотреть baseline."
        )

    if not recs:
        recs.append("- _Нет автоматически выявленных аномалий в распределениях._")

    return recs


def render(a: dict) -> str:
    c = a["counts"]
    b = a["budget"]
    g = a["gate_events"]
    st = a["states"]

    lines: list[str] = []
    lines.append("# Calibration v1.4.0 — Draft Report")
    lines.append("")
    lines.append(
        "Автоматический отчёт `scripts/calibrate.py` (pretzel plan шаг 3.3). "
        "Чтение `intrusiveness-history.jsonl` + фильтр valid chunks "
        "(boundary ∈ {stop,precompact} AND gate-events>0). "
        "Базис для ручной корректировки constants в шаге 3.4."
    )
    lines.append("")
    lines.append("## Dataset")
    lines.append("")
    lines.append(f"- Всего записей: **{c['total_lines']}**")
    lines.append(f"- Valid chunks (v1.3.8+): **{c['valid']}**")
    lines.append(f"- Legacy (без boundary, до v1.3.8): {c['legacy_no_boundary']}")
    lines.append(f"- Boundary-set но без gate-событий: {c['boundary_no_events']}")
    lines.append(f"- Уникальных сессий: {a['sessions']}")
    lines.append(f"- Диапазон дат: {a['date_range'][0]} → {a['date_range'][1]}")
    lines.append("")
    lines.append(
        f"**Threshold pretzel plan = 30 valid.** Текущее: **{c['valid']}** — "
        f"{'✅ порог пройден' if c['valid'] >= 30 else '⚠️ порог не пройден'}."
    )
    lines.append("")
    lines.append("## Budget usage")
    lines.append("")
    lines.append(f"**`gentle_max` = {b['gentle_max']}**, `gentle_used` по chunks:")
    lines.append("")
    lines.append(f"- {fmt_stats(b['gentle_used_stats'])}")
    lines.append(
        f"- Упирание в потолок: "
        f"{b['gentle_ceiling_hits']}/{c['valid']} ({pct(b['gentle_ceiling_hits'], c['valid']):.0f}%)"
    )
    lines.append("")
    lines.append(histogram_block(b["gentle_used_hist"]))
    lines.append("")
    lines.append(f"**`proactive_max` = {b['proactive_max']}**, `proactive_used` по chunks:")
    lines.append("")
    lines.append(f"- {fmt_stats(b['proactive_used_stats'])}")
    lines.append(
        f"- Упирание в потолок: "
        f"{b['proactive_ceiling_hits']}/{c['valid']} ({pct(b['proactive_ceiling_hits'], c['valid']):.0f}%)"
    )
    lines.append("")
    lines.append(histogram_block(b["proactive_used_hist"]))
    lines.append("")
    lines.append(f"**`shrink_events`**: {fmt_stats(b['shrink_stats'])}")
    lines.append("")
    lines.append("## Gate events")
    lines.append("")
    lines.append(f"- Gentle accepted: **{g['gentle_accepted']}**")
    lines.append(f"- Gentle ignored:  **{g['gentle_ignored']}**")
    lines.append(
        f"- Gentle acceptance rate: **{g['acceptance_rate']:.1f}%** "
        f"({g['gentle_accepted']}/{g['gentle_total']})"
    )
    lines.append(f"- Proactive events: **{g['proactive_total']}**")
    lines.append(f"- Override events:  **{g['override_total']}**")
    lines.append(f"- Silence debt surfaced: **{g['silence_surfaced']}**")
    lines.append("")
    lines.append("## State distribution")
    lines.append("")
    if st["grand_total"] == 0:
        lines.append("_Нет state-событий в valid chunks._")
    else:
        expected_states = ["focus", "stuck", "exploration", "idle", "distressed"]
        observed = st["totals"]
        lines.append("| State | События | % |")
        lines.append("|-------|---------|---|")
        for s in expected_states:
            n = observed.get(s, 0)
            marker = "" if s in observed else " _(не наблюдался)_"
            lines.append(f"| {s} | {n}{marker} | {pct(n, st['grand_total']):.1f}% |")
        extra = [s for s in observed if s not in expected_states]
        for s in extra:
            lines.append(
                f"| {s} _(unexpected)_ | {observed[s]} | {pct(observed[s], st['grand_total']):.1f}% |"
            )
    lines.append("")
    lines.append("## Cost peaks")
    lines.append("")
    lines.append(f"- `timing_max`: {fmt_stats(a['cost']['timing'])}")
    lines.append(f"- `silence_max`: {fmt_stats(a['cost']['silence'])}")
    lines.append(f"- `injection_bytes_max`: {fmt_stats(a['cost']['injection_bytes'])}")
    lines.append("")
    lines.append("## Cascading & debt")
    lines.append("")
    lines.append(f"- `cascading.backward_count`: {fmt_stats(a['cascading'])}")
    lines.append(f"- `debt.pending` per chunk: {fmt_stats(a['debt_pending'])}")
    lines.append("")
    lines.append("## Рекомендации (автоматические — требуют ручной верификации)")
    lines.append("")
    lines.extend(render_recommendations(a))
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append(
        "**Следующий шаг (3.4):** на основе этих распределений обновить constants в "
        "`hooks/intrusiveness-state-lib.sh` (budgets) и `hooks/intrusiveness-tracker.sh` "
        "(state cutoffs). Каждое изменение — в отдельном коммите + тесты зелёные."
    )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Calibrate intrusiveness constants from history.")
    ap.add_argument("-o", "--output", default=None, help="write to file instead of stdout")
    ap.add_argument(
        "--history",
        default=os.environ.get("ITR_HISTORY", str(DEFAULT_HIST)),
        help="path to intrusiveness-history.jsonl",
    )
    args = ap.parse_args()

    hist_path = Path(args.history)
    if not hist_path.exists():
        print(f"history file not found: {hist_path}", file=sys.stderr)
        return 1

    chunks = load_history(str(hist_path))
    analysis = analyze(chunks)
    md = render(analysis)

    if args.output:
        Path(args.output).write_text(md, encoding="utf-8")
        print(f"wrote {args.output} ({len(md)} bytes, {analysis['counts']['valid']} valid chunks)", file=sys.stderr)
    else:
        sys.stdout.write(md)

    # Ноль валидных фрагментов — это отказ разбора, а не пустая выборка (D52).
    # Найдено собственным прогоном: файл СОБЫТИЙ (`intrusiveness-backfill-history.jsonl`)
    # вместо файла ФРАГМЕНТОВ (`-digest.jsonl`) дал «wrote ... (0 valid chunks)» и код 0.
    # Отчёт при этом писался — полный, связный и построенный ни на чём. Отличить его от
    # честного «данных пока нет» было нечем.
    if analysis["counts"]["valid"] == 0:
        print(
            "calibrate: 0 valid chunks — вероятно подан не тот файл.\n"
            "  Нужен агрегат по сессиям (поля boundary/budget/metrics), а не журнал событий.\n"
            f"  Прочитано записей: {analysis['counts'].get('total', len(chunks))}.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
