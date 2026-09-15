"""state_lock.py — питоновская половина общего замка (род H).

Единственный источник протокола для питона. Оболочечная половина —
`hooks/state-lock-lib.sh`; обе обязаны совпадать до последней мелочи, иначе замок
перестаёт быть ОБЩИМ и обе стороны спокойно пишут одновременно, каждая считая себя
защищённой. Совпадать должны три вещи: имя каталога (`<путь>.lock`), способ взятия
(`mkdir`, атомарный на всякой POSIX-ФС; `flock` на macOS отсутствует) и пороги
из окружения.

Зачем модуль (5 сентября 2026). Копия этого протокола жила внутри
`hooks/lib/injection-log-rotate.py`, а другим питоновским писателям была недоступна:
имя того файла с дефисом, импортировать нечем. Три носителя рода H —
`scripts/knowledge-independence.py`, `scripts/split-provenance-log.py`,
`mcp-server/ingest/source_store.py` — правят общие файлы (базу знаний и индекс подач),
и та же база пишется хуком `knowledge-link-symmetry.sh` под оболочечным замком.
Две копии взаимного исключения, которые обязаны согласовываться, — опасный вид дубля:
разойдутся молча, и каждая сторона останется «под замком» в одиночку.

ЗАМОК НЕ ЖДЁТ ВЕЧНО. Не взят за отведённые пробы (по умолчанию 100 × 20 мс = 2 с) —
работа идёт БЕЗ него, то есть ровно так, как шла до этой библиотеки. Чужой замок старше
`CLAUDSOUL_LOCK_STALE_S` (30 с) считается брошенным упавшим ходом и срывается: иначе один
убитый ход запирал бы файл навсегда.
"""

import os
import time
from contextlib import contextmanager

LOCK_TRIES = int(os.environ.get("CLAUDSOUL_LOCK_TRIES", "100"))
LOCK_NAP = float(os.environ.get("CLAUDSOUL_LOCK_NAP", "0.02"))
LOCK_STALE_S = float(os.environ.get("CLAUDSOUL_LOCK_STALE_S", "30"))


def lock_acquire(path):
    """Взять замок на путь. Возвращает каталог-замок либо None (не взят)."""
    d = str(path) + ".lock"
    for _ in range(LOCK_TRIES):
        try:
            os.mkdir(d)
            return d
        except FileExistsError:
            try:  # брошенный упавшим ходом — срываем, иначе путь заперт навсегда
                if time.time() - os.stat(d).st_mtime > LOCK_STALE_S:
                    os.rmdir(d)
                    continue
            except OSError:
                pass
        except OSError:
            return None
        time.sleep(LOCK_NAP)
    return None


def lock_release(d):
    if d:
        try:
            os.rmdir(d)
        except OSError:
            pass


@contextmanager
def with_lock(path):
    """Окно read→write под замком. Не взят — тело всё равно исполняется.

    Так же ведёт себя оболочечная половина: замок улучшает, его отсутствие не имеет
    права ронять работу. Ошибка внутри тела замок отпускает.
    """
    d = lock_acquire(path)
    try:
        yield d is not None
    finally:
        lock_release(d)
