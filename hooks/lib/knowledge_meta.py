#!/usr/bin/env python3
"""knowledge_meta.py — записи `modification_history` знания, прочитанные разбором шапки, а не построчно.

Результат: у поточной формы `modification_history: [{date: …, kind: …}]` и у блочной формы
           (`- date: …`) один и тот же счёт записей и одна и та же последняя `kind`
Проверка результата: python3 hooks/lib/knowledge_meta.py <файл> печатает по строке «дата<TAB>kind» на запись

Зачем (D339). Починка D315 (5 сентября 2026) научила `_self_dates` в `knowledge-audit-digest.sh`
читать поточную форму `source_cases`, а сосед в том же файле, `_mh_count`, остался построчным:
шаблон `^[[:space:]]*-[[:space:]]*date:` поточной формы не берёт вовсе. Дефект был латентен —
записей поточной формы в базе 0 — и ждал первой. Граница шапки — у `link_symmetry.frontmatter`
(один источник на всех, D312), разбор — PyYAML; без PyYAML модуль отвечает кодом 2, а не нулём:
«не разобрано» и «записей нет» — разные состояния.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def entries(path):
    """Список записей modification_history: [(date, kind)], даты и kind — строками (пусто, если нет)."""
    from link_symmetry import frontmatter  # граница шапки — один источник (D312)
    import yaml
    text = open(path, encoding="utf-8").read()
    fm = frontmatter(text)
    if not fm:
        return []
    data = yaml.safe_load(fm) or {}
    mh = data.get("modification_history") or []
    if not isinstance(mh, list):
        return []
    out = []
    for e in mh:
        if isinstance(e, dict):
            out.append((str(e.get("date", "") or ""), str(e.get("kind", "") or "")))
        else:
            out.append((str(e), ""))
    return out


def main(argv):
    if len(argv) != 2:
        print("применение: knowledge_meta.py <файл-знания>", file=sys.stderr)
        return 2
    try:
        rows = entries(argv[1])
    except ImportError as e:
        print(f"knowledge_meta: нет модуля ({e.name}) — не разобрано", file=sys.stderr)
        return 2
    except (OSError, ValueError) as e:  # yaml.YAMLError — подкласс ValueError у PyYAML
        print(f"knowledge_meta: шапка не разобрана — {e.__class__.__name__}", file=sys.stderr)
        return 2
    for d, k in rows:
        print(f"{d}\t{k}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
