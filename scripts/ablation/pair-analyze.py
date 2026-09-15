#!/usr/bin/env python3
# Результат: три контраста посчитаны на одном наборе троек, и Δ_structure получает
#            подтверждающее прочтение только при разрешившемся Δ_all.
# Проверка результата: bash hooks/tests/test_ablation_analyze.sh даёт 0
"""pair-analyze.py — анализ теневых троек ablation-замера (протокол §11, D64).

Вход: jsonl, по строке на завершённую тройку:
    {"task_id": "...", "full": 0|1, "core": 0|1, "vanilla": 0|1,
     "stratum_surface": true|false}
(бинаризация по §9: success -> 1; objective_failure/timeout/blocked -> 0;
infrastructure_failure в файл не попадает — тройка аннулируется раньше.)

Три контраста на одном наборе задач (версия 1.4):
    Δ_all       = P(success_full) − P(success_vanilla)   — primary
    Δ_structure = P(success_full) − P(success_core)      — co-primary, гейтится
    Δ_memory    = P(success_core) − P(success_vanilla)   — secondary, описательный

Множественность закрыта ИЕРАРХИЕЙ, а не дроблением alpha: Δ_structure получает
подтверждающее прочтение только если Δ_all разрешился (польза либо вред).
Гейт закрыт — контраст считается и публикуется, но читается как
исследовательский. Так групповая ошибка держится без потери мощности на
primary, и решение о прочтении принято ДО данных, а не после просмотра чисел.

Выход по каждому контрасту: таблица дискордантных пар, Δ̂, 95% CI (Agresti–Min
для разности парных долей: +0.5 к каждой клетке 2x2), двусторонний exact
McNemar (сопутствующая статистика), трёхчастная классификация:
    польза: Δ̂ >= δ  и нижняя граница CI > 0
    вред:   Δ̂ <= -δ и верхняя граница CI < 0
    иначе:  неразрешающий
Параметры δ=0.20 и CI=95% зафиксированы протоколом; менять можно только до первой
РЕГИСТРАЦИИ задачи (§11) — не до принятия в очередь: у policy §6 якорь заморозки
другой и более поздний, разведение объяснено в шапке протокола. Поэтому здесь они
константы, не флаги.

Тройка, в которой нет какого-то плеча, в контраст с этим плечом не входит и
молча не подставляется нулём: объём каждого контраста печатается отдельно.
"""
import json
import math
import sys
from statistics import NormalDist

DELTA = 0.20
# Квота страты would_surface = да (§7): меньше — результат по центральной заявке
# фиксируется как неразрешающий, а не публикуется с интервалом как supportive.
# Заведена 3 сентября 2026 (D283): §7 требовал квоту с 27 августа, а исполнителя у неё не
# было ни одного (grep SURFACE_QUOTA по scripts/ablation и hooks — 0 совпадений), и отчёт
# печатал страту без единого слова о добранности. Число берётся отсюда, а сверяет его с
# документом hooks/tests/test_ablation_protocol_claims.sh — расходятся, тест краснеет.
SURFACE_QUOTA = 8
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


def analyze(rows: list, a: str, b_arm: str, *, verdict: bool) -> dict:
    """Контраст a − b_arm на тройках, где присутствуют ОБА плеча.

    `verdict` — есть ли у ЭТОГО контраста правило решения (§8.1 протокола).
    Аргумент обязателен и именован намеренно: вердикт есть свойство контраста, а не
    вычисления, и до 2 сентября 2026 его не было в модели данных вовсе — `classify()`
    ложился на результат безусловно, и описательному Δ_memory печаталось
    «польза»/«вред»/«неразрешающий» при том, что протокол (§8.1: «описательный, без
    правила решения»; §11: «без тестов и без заявлений о значимости») его запрещает.
    Забытый аргумент роняет вызов TypeError — новый контраст обязан назвать свою роль.
    """
    usable = [r for r in rows if a in r and b_arm in r]
    n = len(usable)
    b = sum(1 for r in usable if r[a] == 1 and r[b_arm] == 0)
    c = sum(1 for r in usable if r[a] == 0 and r[b_arm] == 1)
    d_hat = (b - c) / n if n else 0.0
    lo, hi = agresti_min_ci(b, c, n) if n else (0.0, 0.0)
    out = {
        "contrast": f"{a} − {b_arm}",
        "pairs": n,
        "discordant": {f"{a}_plus_{b_arm}_minus": b, f"{a}_minus_{b_arm}_plus": c},
        "delta_hat": round(d_hat, 4),
        "ci95": [round(lo, 4), round(hi, 4)],
        "mcnemar_exact_p": round(mcnemar_exact_p(b, c), 6),
    }
    if verdict:
        out["outcome"] = classify(d_hat, lo, hi) if n else "нет данных"
    return out


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: pair-analyze.py <pairs.jsonl>")
    rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
    # Primary — только набор (§13): строки с enrolled == "extension" добраны ради квоты страты
    # (§7) и в primary не входят. Строка без поля (записана до 12 сентября 2026) считается
    # набором и называется числом в отчёте, а не молчит (D299).
    enrolled = [r for r in rows if r.get("enrolled", "primary") != "extension"]
    legacy = sum(1 for r in rows if "enrolled" not in r)
    surface = [r for r in rows if r.get("stratum_surface")]

    primary = analyze(enrolled, "full", "vanilla", verdict=True)
    primary["enrollment"] = {"rows_total": len(rows), "primary": len(enrolled),
                             "extension": len(rows) - len(enrolled), "legacy_without_field": legacy}
    structure = analyze(enrolled, "full", "core", verdict=True)
    gate_open = primary["outcome"] in ("польза", "вред")
    structure["gate"] = "открыт" if gate_open else "закрыт"
    structure["reading"] = "подтверждающее" if gate_open else "исследовательское"

    surface_report = analyze(surface, "full", "vanilla", verdict=False)
    surface_report["quota"] = {"required": SURFACE_QUOTA, "have": len(surface),
                               "met": len(surface) >= SURFACE_QUOTA}
    # «Нет данных» и «страта не добрана» — разные состояния мира, и до 3 сентября 2026
    # второе печаталось на месте первого: при НУЛЕ завершённых троек отчёт объявлял
    # центральную заявку неразрешающей, то есть выносил чтение там, где нет ни одного
    # наблюдения. Ветка та же, что у analyze() на n == 0, и по той же причине: вердикт
    # без наблюдений — не вердикт. Поймано прожаркой 3 сентября, дефект внесён правкой
    # того же дня (на 186f1c1 полей quota и reading не было вовсе).
    if not surface_report["pairs"]:
        surface_report["reading"] = "нет данных"
    elif len(surface) >= SURFACE_QUOTA:
        surface_report["reading"] = "supportive"
    else:
        surface_report["reading"] = "неразрешающий: страта не добрана (§7)"
    report = {
        "delta": DELTA,
        "primary_all": primary,
        "co_primary_structure": structure,
        # Оба описательные (§8.1): Δ_memory — «без правила решения», Δ_surface — «без
        # отдельного подтверждающего решения и поправки на множественность». Поля outcome
        # у них нет вовсе: печатать «неразрешающий» значило бы объявить решение там, где
        # протокол его запретил.
        "secondary_memory": analyze(rows, "core", "vanilla", verdict=False),
        "key_secondary_surface": surface_report,
        "note": "правило решения — классификация по Δ̂ и CI; p-value — сопутствующая "
                "статистика (§11); Δ_structure читается подтверждающе только при "
                "разрешившемся Δ_all (иерархия, §11); у описательных контрастов "
                "(secondary_memory, key_secondary_surface) поля outcome нет — §8.1",
    }
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
