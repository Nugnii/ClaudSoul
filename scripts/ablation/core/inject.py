#!/usr/bin/env python3
"""inject.py — инжектор контрольного плеча Core (протокол §2, §6, §12).

Core представляет «простой слой памяти»: та же база знаний, что у Full,
извлечение top-k по лексической близости, инъекция как есть. Больше ничего —
ни ранжирования по confidence/priority, ни blocker-tier, ни аналогий из
соседних доменов, ни FSRS-decay, ни мостов, ни скиллов, ни глобальных правил.
Плечо отвечает на вопрос «а если просто retrieval?», поэтому оно намеренно
сделано настолько хорошим, насколько простой слой памяти может быть, и ни на
шаг структурнее.

Близость лексическая, а не семантическая — решение, не упрощение:
преregistration требует, чтобы решение сэмплера и состав инъекции
воспроизводились через год, а эмбеддинги дрейфуют между версиями модели.
Ограничение названо в §12 протокола и не скрывается в анализе.

Python, а не shell: база знаний русскоязычная, приведение кириллицы к нижнему
регистру через tr/awk на BSD побайтовое (pattern-shell-portability, conf 5).

Живёт в обвязке замера, а не в измеряемой системе: код Core не является частью
ClaudSoul и не замораживается вместе с policy (§6).
"""
import json
import os
import re
import sys
from pathlib import Path

TOP_K = int(os.environ.get("CORE_INJECT_K", "5"))
MIN_TERM_LEN = 4
WORD = re.compile(r"\w+", re.UNICODE)


def query_terms(prompt: str) -> set:
    """Уникальные термины запроса длиной >= 4, приведённые к нижнему регистру."""
    return {w.casefold() for w in WORD.findall(prompt) if len(w) >= MIN_TERM_LEN}


def head_fields(text: str) -> tuple:
    """name и description из YAML-шапки; пусто — если шапки нет."""
    name = desc = ""
    for line in text.split("\n", 40)[:40]:
        if not name and line.startswith("name:"):
            name = line[5:].strip()
        elif not desc and line.startswith("description:"):
            desc = line[12:].strip()
        if name and desc:
            break
    return name, desc


def score(files: list, terms: set) -> list:
    """Покрытие: сколько РАЗНЫХ терминов запроса встретилось в файле.

    Ничьи разрешаются именем файла — решение обязано быть воспроизводимым.
    """
    ranked = []
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        low = text.casefold()
        hits = sum(1 for t in terms if t in low)
        if hits:
            ranked.append((hits, path, text))
    ranked.sort(key=lambda r: (-r[0], r[1].name))
    return ranked[:TOP_K]


def main() -> None:
    lessons = Path(os.environ.get("CORE_LESSONS_DIR",
                                  Path.home() / ".claude" / "global-lessons"))
    if not lessons.is_dir():
        return
    try:
        prompt = json.load(sys.stdin).get("prompt", "")
    except (json.JSONDecodeError, ValueError):
        return
    terms = query_terms(prompt or "")
    if not terms:
        return

    files = sorted(lessons.glob("*.md"))
    top = score(files, terms)
    if not top:
        return

    out = ["📎 Записи из базы, похожие на запрос "
           f"({len(top)} из {len(files)}, по лексической близости):", ""]
    for i, (_hits, path, text) in enumerate(top, 1):
        name, desc = head_fields(text)
        out.append(f"{i}. {name or path.stem}")
        if desc:
            out.append(f"   {desc}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
