#!/usr/bin/env python3
# Результат: объявленная в ROOTS.md дробь каждого корня совпадает с той, что даёт его
#            проба на нынешнем дереве, а граф корней остаётся деревом (без циклов,
#            ссылок в никуда и сирот).
# Проверка результата: python3 scripts/root-map.py --check даёт 0.
"""root-map.py — карта корней: чей признак живёт ДАННЫМИ, а не кодом.


ЗАЧЕМ. Второй тест остановки разбора — дробь специфичности: «мест со звеном N, из них с
симптомом M». До 9 сентября 2026 она предъявлялась ФРАЗОЙ, и подмена проходила невидимой:
разбор объявил «5 из 5», настоящая была «1 из 65» (D323), а гейт ход пропустил, потому что
формы доктрины были произнесены все. Здесь дробь берётся из КОМАНДЫ: у корня записан
признак, прибор его исполняет и считает носителей сам. Расхождение объявленного с
посчитанным видно машине.

ЧЕМ ОТЛИЧАЕТСЯ ОТ РЕЕСТРА РОДОВ (`scripts/defect-class-carriers.py`). Там признаки зашиты
в код — 2345 строк, и новый род нельзя завести, не правя прибор; за 12 дней его правили
21 раз. Здесь признак — строка в `ROOTS.md`, и новый корень заводится без правки прибора.

ЧТО СЧИТАЕТСЯ ЧЕСТНЫМ ИСХОДОМ. «Команду построить нельзя» — законный ответ, он пишется
словом НЕ ИЗМЕРЕНО и зелёным НЕ считается. Ложная команда хуже отсутствующей: она даёт
число, которому верят.
"""
from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDSOUL_REPO") or Path(__file__).resolve().parent.parent)

# КАРТА БЕРЁТСЯ У ПРОЕКТА СЕССИИ, а корень ClaudSoul остаётся для проб и прочего своего.
#
# Карта объявлена ЛОКАЛЬНОЙ для проекта (CLAUDE.md §5: «общее между проектами ходит
# паттернами базы знаний»), но до 11 сентября 2026 читалась всегда одна — ClaudSoul.
# В ClaudSoul оба пути совпадают, поэтому дефект был невидим; поймали его первым же
# запуском в чужом проекте (ProjectA_NEW): там развернули пустую карту из шаблона, а прибор
# напечатал шесть корней ClaudSoul и выдал их за корни проекта. Дробь корня — основание
# решений о починке, и она пришла бы от другого дерева.
#
# Порядок поиска: явный ROOTS_MAP → ROOTS.md в текущем каталоге → ROOTS.md у корня
# репозитория сессии → карта ClaudSoul. Последнее звено сохранено намеренно: в самом
# ClaudSoul и при вызове из его подкаталога поведение остаётся прежним.
def _find_map() -> Path:
    explicit = os.environ.get("ROOTS_MAP")
    if explicit:
        return Path(explicit)
    # Явно названный корень СИЛЬНЕЕ текущего каталога: `CLAUDSOUL_REPO` задают, когда
    # корень указывают намеренно — так делают тесты на песочнице (test_root_map.sh:52)
    # и вызовы из чужого cwd. Без этой ветки песочница читала бы карту ClaudSoul, потому
    # что прогон идёт из его каталога; поймано прогоном набора в тот же час.
    repo_env = os.environ.get("CLAUDSOUL_REPO")
    if repo_env:
        return Path(repo_env) / "ROOTS.md"
    here = Path.cwd()
    for base in (here, *here.parents):
        cand = base / "ROOTS.md"
        if cand.is_file():
            return cand
        if (base / ".git").exists():
            break          # выше корня репозитория не поднимаемся: там чужие проекты
    return ROOT / "ROOTS.md"


MAP = _find_map()

FIELD = re.compile(r"^\*\*(?P<k>[^.*]+)\.\*\*\s*(?P<v>.*)$")
HEAD = re.compile(r"^##\s+(?P<id>R\d+)\s+—\s+(?P<title>.+)$")
FRAC = re.compile(r"(\d+)\s+из\s+(\d+)")


def parse(text: str) -> list[dict]:
    """Карта → список корней. Разбор по ролям строк, а не по их порядку: перестановка
    полей не должна ломать чтение."""
    roots: list[dict] = []
    cur: dict | None = None
    key: str | None = None
    for line in text.split("\n"):
        h = HEAD.match(line)
        if h:
            cur = {"id": h.group("id"), "title": h.group("title").strip(), "raw": {}}
            roots.append(cur)
            key = None
            continue
        if cur is None:
            continue
        f = FIELD.match(line.strip())
        if f:
            key = f.group("k").strip().lower()
            cur["raw"][key] = f.group("v").strip()
        elif key and line.strip():
            cur["raw"][key] += " " + line.strip()
    return roots


def carriers_of(root: dict) -> tuple[list[str], str | None]:
    """Носители корня — вывод его команды. Возвращает (строки, причина недоступности).

    Отказ команды НЕ выдаётся за «носителей нет»: пустой вывод при ненулевом коде — это
    поломка прибора, и она называется. Иначе сломанный признак читался бы как чистый мир."""
    # Признак — ПУТЬ К ПРОБЕ, а не команда в строке карты: у R3 она в 26 строк, и в строку
    # markdown не влезает. Файл заодно версионируется и правится отдельно от карты.
    cmd = root["raw"].get("признак", "")
    m = re.search(r"`([^`]+)`", cmd)
    if not m:
        return [], "проба не объявлена"
    probe = ROOT / m.group(1).strip()
    if not probe.is_file():
        return [], f"пробы нет: {m.group(1).strip()}"
    try:
        p = subprocess.run(["bash", str(probe)], cwd=ROOT, capture_output=True,
                           text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return [], "команда не уложилась в 120 с"
    except OSError as e:
        return [], f"команда не запустилась: {e.__class__.__name__}"
    out = [l for l in p.stdout.split("\n") if l.strip()]
    # Код 1 у grep при нуле находок — законная пустота, а не поломка (D371).
    if p.returncode not in (0, 1):
        return out, f"команда вернула код {p.returncode}"
    return out, None


def declared(root: dict) -> tuple[int, int] | None:
    m = FRAC.search(root["raw"].get("дробь", ""))
    return (int(m.group(1)), int(m.group(2))) if m else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="код 1, если объявленная дробь разошлась с посчитанной")
    ap.add_argument("--root", help="только этот корень")
    ap.add_argument("--count", action="store_true",
                    help="напечатать ЧИСЛО корней карты и выйти — единственный владелец этого числа")
    ap.add_argument("--declared", metavar="Rn",
                    help="напечатать объявленный в карте ЗНАМЕНАТЕЛЬ дроби корня (носителей по карте) без исполнения проб — единственный владелец этого числа для документов состояния (D397)")
    ap.add_argument("--parse-only", action="store_true",
                    help="разобрать карту и проверить граф, НЕ исполняя пробы корней")
    a = ap.parse_args()

    if not MAP.exists():
        print(f"BROKEN: карты нет — {MAP}", file=sys.stderr)
        return 2
    roots = parse(MAP.read_text(encoding="utf-8"))
    if not roots:
        print("BROKEN: в карте не разобрано ни одного корня — проверь формат", file=sys.stderr)
        return 2

    # Число корней отдаётся ТЕМ ЖЕ разбором карты, каким считаются дроби, — чтобы у факта
    # «сколько корней» был ОДИН владелец (10 сентября 2026). Повод: CLAUDE.md утверждал «три
    # корня», а их стало пять, и утверждение отстало дважды за сутки, потому что сверять его
    # было нечем. Первая редакция починки собиралась считать `grep -c '^## R'` в чужом
    # скрипте — это завело бы вторую реализацию того же знания (корень R1), и поймала это
    # поправка владельца: «при создании механизмов смотреть, чем раньше вопрос решался».
    if a.count:
        print(len(roots))
        return 0
    # Число носителей корня для документов состояния берётся у ОБЪЯВЛЕННОЙ дроби карты, без проб
    # (D397, 13 сентября 2026): пробы дороги (R6 около двух минут), а объявленное число карты и
    # есть то, что документ обязан повторять — верность самого объявления сверяет `--check` по
    # расписанию (реестр `root-map-drift`). Кэша с отметкой свежести здесь нет намеренно: кэш,
    # объявленный свежим, врёт хуже устаревшего числа. Не разобрали дробь — код 2, не «0».
    if a.declared:
        for r in roots:
            if r["id"] == a.declared:
                d = declared(r)
                if d is None:
                    print(f"BROKEN: у {a.declared} дробь не объявлена или не разобрана", file=sys.stderr)
                    return 2
                print(d[1])
                return 0
        print(f"BROKEN: корня {a.declared} в карте нет", file=sys.stderr)
        return 2

    drift = 0
    rows = []
    for r in roots:
        if a.root and r["id"] != a.root:
            continue
        # --parse-only: проба не исполняется. Предмет режима — РАЗБОР и ГРАФ (цикл, ссылка в
        # никуда, сирота), а не число носителей. Повод 11 сентября 2026: нога T10 теста
        # `test_root_map.sh` проверяет ровно «живая карта разбирается, формат не разъехался»,
        # и ради этого гоняла все шесть проб — 108 секунд при 57 миллисекундах у `--count`.
        # Дроби в этом режиме не печатаются вовсе: напечатать их как «0 носителей» значило бы
        # выдать неисполненную пробу за пустой результат — ровно то, что ловит нога T7.
        if a.parse_only:
            cars, why = [], None
        else:
            cars, why = carriers_of(r)
        d = declared(r)
        unmeasured = "НЕ ИЗМЕРЕНО" in r["raw"].get("дробь", "")
        n = len(cars)
        rows.append((r, cars, why, d, unmeasured))

        print(f"\n{r['id']} — {r['title']}")
        print(f"   устройство: {r['raw'].get('устройство','—')[:110]}")
        if why:
            print(f"   ⚠ носители НЕ ПОСЧИТАНЫ: {why}")
        elif unmeasured:
            print(f"   носителей по команде: {n} (дробь объявлена НЕ ИЗМЕРЕНО — зелёным не считается)")
        else:
            print(f"   носителей по команде: {n}" if not a.parse_only
                  else "   носители не считались (--parse-only: предмет режима — разбор и граф)")
        if d and not why and not a.parse_only:
            m, tot = d
            if tot != n:
                print(f"   ✗ РАСХОЖДЕНИЕ: объявлено «{m} из {tot}», команда нашла {n}")
                drift += 1
            else:
                print(f"   ✓ дробь сходится: {m} из {tot}")
        for c in cars[:4]:
            print(f"      · {c[:100]}")
        if n > 4:
            print(f"      … и ещё {n-4}")

    # ГРАФ ЗАВИСИМОСТЕЙ ОБЯЗАН БЫТЬ ДЕРЕВОМ (9 сентября 2026). Связи «держит» пишутся
    # РУКОЙ, и никто не мешает объявить взаимную: «R3 держит R2» вместе с «R2 держит R3».
    # Порядок ремонта при цикле не существует, а прибор до этой правки печатал его молча —
    # проверено на копии карты с двумя узлами. Уверенный ответ на неразрешимый вопрос хуже
    # отказа: по нему пойдут чинить.
    edges = {r["id"]: re.findall(r"R\d+", r["raw"].get("держит", "")) for r in roots}
    known = set(edges)
    cycles, dangling = [], []
    # Имена узлов — `src`/`dst`, а не `a`/`b`: `a` держит разобранные аргументы командной
    # строки, и цикл её затирал. Прибор падал ПОСЛЕ печати порядка ремонта, то есть уже
    # выдав ответ, — отказ, замаскированный правдоподобным выводом.
    for src, outs in edges.items():
        for dst in outs:
            if dst not in known:
                dangling.append(f"{src} → {dst} (такого корня в карте нет)")
            elif src in edges.get(dst, []):
                pair = tuple(sorted((src, dst)))
                if pair not in cycles:
                    cycles.append(pair)
    # Сироты по обе стороны: проба без корня и корень без пробы — тот же класс «у читателя
    # есть писатель», что чинился в контуре разбора этой же сессией.
    probes_dir = ROOT / "scripts" / "probes"
    declared_probes = {Path(re.search(r"`([^`]+)`", r["raw"].get("признак","")).group(1).strip()).name
                       for r in roots if re.search(r"`([^`]+)`", r["raw"].get("признак",""))}
    on_disk = {f.name for f in probes_dir.glob("*.sh")} if probes_dir.is_dir() else set()
    orphan_probe = sorted(on_disk - declared_probes)
    orphan_root = sorted(declared_probes - on_disk)

    if cycles or dangling or orphan_probe or orphan_root:
        print("\n── ГРАФ СЛОМАН ──")
        for a, b in cycles:
            print(f"  ✗ взаимная зависимость {a} ↔ {b}: порядок ремонта не существует")
        for d in dangling:
            print(f"  ✗ ссылка в никуда: {d}")
        for o in orphan_probe:
            print(f"  ✗ проба без корня: scripts/probes/{o}")
        for o in orphan_root:
            print(f"  ✗ корень без пробы: {o}")
        print("  Порядок ремонта не печатается: он был бы уверенным ответом на неразрешимое.")
        return 2

    # ПОРЯДОК РЕМОНТА. Раньше чинится тот, у кого больше носителей и от кого зависят
    # другие: починка корня-опоры меняет землю под остальными, и делать её последней
    # значит переделывать уже сделанное.
    print("\n── ПОРЯДОК РЕМОНТА ──")
    def weight(t):
        r, cars, why, d, unm = t
        deps = len([x for x in re.findall(r"R\d+", r["raw"].get("держит", ""))])
        return (deps * 100 + len(cars), r["id"])
    for i, t in enumerate(sorted(rows, key=weight, reverse=True), 1):
        r, cars, why, d, unm = t
        deps = re.findall(r"R\d+", r["raw"].get("держит", ""))
        mark = "НЕ ИЗМЕРЕНО" if (why or unm) else f"{len(cars)} носителей"
        dep = f", держит {', '.join(deps)}" if deps else ""
        print(f"  {i}. {r['id']} — {mark}{dep}")

    if a.check:
        if drift:
            print(f"\n[замер: находки, не сбой] расхождений объявленного с посчитанным: {drift}")
            return 1
        print("\nобъявленные дроби совпадают с посчитанными")
    return 0


if __name__ == "__main__":
    sys.exit(main())
