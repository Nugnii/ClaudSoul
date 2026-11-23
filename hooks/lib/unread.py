"""unread.py — питоновская половина учёта непрочитанного (род B).

Единственный источник для питона. Оболочечная половина — `hooks/lib/unread-lib.sh`;
обе отвечают на один вопрос: «сколько источников не удалось прочитать и какие», —
чтобы отказ чтения не гасился благоприятным значением и не выдавался за «нарушений нет».

Зачем модуль (6 сентября 2026, род K). Копии этой логики жили в `scripts/dep-index.py` и
`scripts/meta-contamination.py`, причём обе лишь УПОМИНАЛИ `unread-lib.sh` в комментарии, а
источить её не могли: она оболочечная. Копии успели разойтись — у одной формулировка
«не прочитано файлов: N — пути», у другой «не прочитано: N — имена», у одной есть отсечка
списка после пяти имён, у другой нет. Расхождение молчаливое: тест не падает, линтер не
видит, а читатель отчёта получает разные ответы на один вопрос.

ПАРИТЕТ С ОБОЛОЧЕЧНОЙ ПОЛОВИНОЙ. Совпадать обязаны три вещи: что считается отказом
(любая неудача чтения, включая отсутствие файла), формулировка итога («не прочитано: N — …»)
и молчание при нуле отказов — пустая строка, а не «не прочитано: 0».
"""

import os


class Unread:
    """Счётчик непрочитанного. Один на инструмент; список причин хранится в порядке встречи."""

    def __init__(self, max_names: int = 5):
        self.items: list[str] = []
        self.max_names = max_names

    def add(self, path, reason: str) -> None:
        """Записать отказ чтения. `path` — что читали, `reason` — чем объяснила система."""
        self.items.append(f"{path}: {reason}")

    def read_text(self, path, basename_only: bool = False) -> str:
        """Прочитать файл, засчитав отказ вместо исключения. Пустая строка — не «пусто в
        файле», а «прочитать не удалось»; отличить одно от другого позволяет `note()`."""
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                return f.read()
        except FileNotFoundError:
            self.add(os.path.basename(str(path)) if basename_only else path, "файла нет")
            return ""
        except OSError as e:
            self.add(os.path.basename(str(path)) if basename_only else path,
                     e.strerror or str(e))
            return ""

    def note(self) -> str:
        """«не прочитано: N — …» либо ПУСТАЯ строка, если всё прочитано.

        Пустая строка при нуле отказов — часть контракта: вызывающий печатает эту строку
        как есть, и «не прочитано: 0» было бы шумом, который учатся не читать."""
        if not self.items:
            return ""
        names = sorted(set(self.items))
        tail = f" … и ещё {len(names) - self.max_names}" if len(names) > self.max_names else ""
        return (f"не прочитано: {len(names)} — "
                + ", ".join(names[:self.max_names]) + tail)

    def __bool__(self) -> bool:
        """Истинно, когда были отказы, — чтобы `if unread:` читалось как вопрос о них."""
        return bool(self.items)
