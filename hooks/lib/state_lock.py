"""state_lock.py — питоновская половина общего замка (род H).

Единственный источник протокола для питона. Оболочечная половина —
`hooks/state-lock-lib.sh`; обе обязаны совпадать до последней мелочи, иначе замок
перестаёт быть ОБЩИМ и обе стороны спокойно пишут одновременно, каждая считая себя
защищённой. Совпадать должны три вещи: имя каталога (`<путь>.lock`), способ взятия
(каталог — вместилище, взят он тем, кто ИСКЛЮЧИТЕЛЬНО создал в нём `owner`; здесь `os.mkdir`
исключителен, но оболочечная половина на uutils — `mkdir` coreutils `ubuntu-26.04` — «создаёт»
тот же каталог в то же окно, D1320; `flock` на macOS отсутствует) и пороги из окружения.

Зачем модуль (5 сентября 2026). Копия этого протокола жила внутри
`hooks/lib/injection-log-rotate.py`, а другим питоновским писателям была недоступна:
имя того файла с дефисом, импортировать нечем. Три носителя рода H —
`scripts/knowledge-independence.py`, `scripts/split-provenance-log.py`,
`mcp-server/ingest/source_store.py` — правят общие файлы (базу знаний и индекс подач),
и та же база пишется хуком `knowledge-link-symmetry.sh` под оболочечным замком.
Две копии взаимного исключения, которые обязаны согласовываться, — опасный вид дубля:
разойдутся молча, и каждая сторона останется «под замком» в одиночку.

ЗАМОК НЕ ЖДЁТ ВЕЧНО. Не взят за отведённые пробы (по умолчанию 100 × 20 мс = 2 с) —
работа идёт БЕЗ него, то есть ровно так, как шла до этой библиотеки. Брошенный замок
срывается, иначе один убитый ход запирал бы файл навсегда.

ЖИВОСТЬ, А НЕ ВОЗРАСТ; СРЫВ АТОМАРЕН; СНИМАЕТСЯ ТОЛЬКО СВОЙ (D500) — то же, что у оболочечной
половины. Взявший пишет `<путь>.lock/owner` («pid токен»). Брошен — владелец мёртв; без владельца
— старше `CLAUDSOUL_LOCK_STALE_S`; старше десяти порогов — всегда (повторно занятый PID). Срыв —
право на срыв — `.break/by`, его создаёт один (D1320), и внутри сверяет, что экземпляр тот же (inode
и строка владельца). Освобождение — по токену.
"""

import os
import random
import shutil
import sys
import time
from contextlib import contextmanager

LOCK_TRIES = int(os.environ.get("CLAUDSOUL_LOCK_TRIES", "100"))
LOCK_NAP = float(os.environ.get("CLAUDSOUL_LOCK_NAP", "0.02"))
LOCK_STALE_S = float(os.environ.get("CLAUDSOUL_LOCK_STALE_S", "30"))
_TOKEN = f"{os.getpid()}.{random.randrange(10**9)}"


def _owner(d):
    """Строка владельца: "" — файла нет, None — файл есть, но не прочитан (живость неизвестна)."""
    try:
        with open(os.path.join(d, "owner"), encoding="utf-8") as f:
            return f.readline().strip()
    except FileNotFoundError:
        return ""
    # ValueError — владелец не в UTF-8 (UnicodeDecodeError): оболочечная половина читает байты и не
    # падает, а здесь исключение вылетало мимо всех зовущих (третий круг финального скептика D1006).
    except (OSError, ValueError) as e:
        print(f"state_lock: владелец замка {d} не прочитан ({e}) — срыв только по потолку", file=sys.stderr)
        return None


def _ino(d):
    try:
        return os.stat(d).st_ino
    except OSError:
        return None


def _age(path):
    try:
        return time.time() - os.stat(path).st_mtime
    except OSError:
        return -1


def _abandoned(d, owner):
    if owner is None:
        return _age(os.path.join(d, "owner")) > LOCK_STALE_S * 10
    parts = owner.split()
    if not parts or not parts[0].isdigit():
        return _age(d) > LOCK_STALE_S
    if _age(os.path.join(d, "owner")) > LOCK_STALE_S * 10:
        return True
    try:
        os.kill(int(parts[0]), 0)
        return False
    except ProcessLookupError:
        return True
    except OSError:
        return False


def lock_acquire(path):
    """Взять замок на путь. Возвращает каталог-замок либо None (не взят)."""
    d = str(path) + ".lock"
    brk = os.path.join(d, ".break")
    by = os.path.join(brk, "by")
    for _ in range(LOCK_TRIES):
        try:
            os.mkdir(d)
        except FileExistsError:
            ino, own = _ino(d), _owner(d)
            if ino is not None and _abandoned(d, own):
                try:
                    os.mkdir(brk)
                    # Право на срыв — исключительное создание `by` (D1320): оболочечная половина на uutils
                    # «создаёт» `.break` и в то же окно, и `os.mkdir` здесь исключителен только против питона.
                    open(by, "x").close()
                    if _ino(d) == ino and _owner(d) == own:
                        shutil.rmtree(d, ignore_errors=True)
                        continue
                    os.remove(by)
                    os.rmdir(brk)
                except FileExistsError:
                    if _age(brk) > LOCK_STALE_S:  # срывавший упал, не доделав
                        for p, rm in ((by, os.remove), (brk, os.rmdir)):
                            try:
                                rm(p)
                            except OSError:
                                pass
                except OSError:
                    pass
        except OSError:
            return None
        else:
            # Захват — исключительное создание `owner` (D1320), как у оболочечной половины: каталог, «созданный» в то же
            # окно оболочкой на uutils, иначе давал двух держателей — `owner` с перезаписью стирал соперника.
            try:
                with open(os.path.join(d, "owner"), "x", encoding="utf-8") as f:
                    f.write(f"{os.getpid()} {_TOKEN}\n")
            except (FileExistsError, FileNotFoundError):
                # Есть — соперник взял первым; нет каталога — соперник взял и уже отпустил в то же окно (скептик opus
                # D1320, H1: FileNotFoundError прежде значил «взят» при отсутствующем каталоге). Оба — ждём.
                time.sleep(LOCK_NAP)
                continue
            except OSError:
                pass
            return d
        time.sleep(LOCK_NAP)
    return None


def lock_release(d):
    if not d:
        return
    # Владелец не прочитан (None) — замок свой, как у оболочечной половины (`state-lock-lib.sh:120-121`:
    # пустой `own` снимается): `None.split()` ронял освобождение мимо `except OSError` зовущих и оставлял
    # каталог на десять порогов (второй круг финального скептика D1006).
    parts = (_owner(d) or "").split()
    if len(parts) >= 2 and parts[1] != _TOKEN:
        return  # наш сорван как брошенный и взят другим — чужой не трогаем
    try:
        os.remove(os.path.join(d, "owner"))
    except OSError:
        pass
    for _ in (0, 1):  # отступающий срывающий мог на миг положить `.break` внутрь
        try:
            os.rmdir(d)
            return
        except OSError:
            time.sleep(0.05)


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
