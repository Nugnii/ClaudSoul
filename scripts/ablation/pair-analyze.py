#!/usr/bin/env python3
"""pair-analyze.py — парный анализ ablation-замера (протокол §11, D64).

Вход: jsonl пар, по строке на завершённую пару:
    {"task_id": "...", "full": 0|1, "vanilla": 0|1, "stratum_surface": true|false}
(бинаризация по §9: success -> 1; objective_failure/timeout/blocked -> 0;
infrastructure_failure в файл пар не попадает — пара аннулируется раньше.)

Выход: таблица дискордантных пар, Δ̂, 95% CI (Agresti–Min для разности парных
долей: +0.5 к каждой клетке 2x2), двусторонний exact McNemar (сопутствующая
статистика), трёхчастная классификация по Δ̂ и CI (правило решения):
    польза: Δ̂ >= δ  и нижняя граница CI > 0
    вред:   Δ̂ <= -δ и верхняя граница CI < 0
    иначе:  неразрешающий
Параметры δ=0.20 и CI=95% зафиксированы протоколом; менять можно только до
первой регистрации задачи (§11), поэтому здесь они константы, не флаги.

Отчёт считается для primary Δ_all и отдельно для straты would_surface
(key secondary, supportive — без отдельного подтверждающего решения).
"""
import json
import math
import sys
from statistics import NormalDist

DELTA = 0.20
Z = NormalDist().inv_cdf(0.975)


def mcnemar_exact_p(b: int, c: int) -> float:
    """Двусторонний exact McNemar по дискордантным парам: X ~ Bin(b+c, 1/2)."""
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    tail = sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, 2 * tail)


def agresti_min_ci(b: int, c: int, n: int):
    """95% CI разности парных долей (Agresti & Min 2005: +0.5 к каждой клетке)."""
    bp, cp, np_ = b + 0.5, c + 0.5, n + 2
    d = (bp - cp) / np_
    se = math.sqrt((bp + cp) - (bp - cp) ** 2 / np_) / np_
    return d - Z * se, d + Z * se


def classify(d_hat: float, lo: float, hi: float) -> str:
    if d_hat >= DELTA and lo > 0:
        return "польза"
    if d_hat <= -DELTA and hi < 0:
        return "вред"
    return "неразрешающий"


def analyze(pairs: list) -> dict:
    n = len(pairs)
    b = sum(1 for p in pairs if p["full"] == 1 and p["vanilla"] == 0)  # Full+/Vanilla-
    c = sum(1 for p in pairs if p["full"] == 0 and p["vanilla"] == 1)  # Full-/Vanilla+
    d_hat = (b - c) / n if n else 0.0
    lo, hi = agresti_min_ci(b, c, n) if n else (0.0, 0.0)
    return {
        "pairs": n,
        "discordant": {"full_plus_vanilla_minus": b, "full_minus_vanilla_plus": c},
        "delta_hat": round(d_hat, 4),
        "ci95": [round(lo, 4), round(hi, 4)],
        "mcnemar_exact_p": round(mcnemar_exact_p(b, c), 6),
        "outcome": classify(d_hat, lo, hi) if n else "нет данных",
    }


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: pair-analyze.py <pairs.jsonl>")
    pairs = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
    report = {
        "delta": DELTA,
        "primary_all": analyze(pairs),
        "key_secondary_surface": analyze([p for p in pairs if p.get("stratum_surface")]),
        "note": "правило решения — классификация по Δ̂ и CI; p-value — сопутствующая статистика (§11)",
    }
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
