#!/usr/bin/env python3
"""state_archive — архив строк семейств каталога состояния (D1008, решение владельца 29 октября 2026 «архив строк на
семейство»).

Семь семейств, чьё число «за всё время» читают по ВСЕМ посессионным файлам (`scripts/state-prune.sh`, `KEEP_FAMILIES`),
уборка не подрезала вовсе, и каталог рос без предела. Теперь уборка переносит строки файла вне окна в архив семейства
`<state>/archive/<семейство>.tsv` и удаляет файл, а читатели берут строки «архив + живые файлы» отсюда; формула числа
остаётся у прежнего владельца — свёрнутых итогов, второго владельца формулы, нет.

Строка вывода и архива — «имя файла ⇥ mtime файла в секундах ⇥ исходная строка». Имя — то, из чего читатели и прежде
выводили сессию и агента; mtime — время `five-whys` (в его строках времени нет). Архив лежит в подкаталоге: уборка
дросселя (`hooks/throttle-lib.sh`, `find -maxdepth 1 -name '*-fired-*'`) его не видит.

  state_archive.py lines <state> <семейство>             — строки архива, затем живых файлов семейства
  state_archive.py archived <state> <семейство>          — только архив: для читателя, чья маска живых файлов шире
                                                            формы члена (имена без UUID у фикстур `dis_*`)
  state_archive.py archive <state> <семейство> <имя>...   — перенести файлы в архив и удалить; печатает число

Член семейства — файл `<семейство>-<UUID сессии>[.agent-<id>].jsonl|.seen`; снимки `.snap-` уборка подрезает как прочие. Файл,
воссозданный после переноса (запись об истечении в чужой сессии, `hooks/disagreement-lib.sh:333`), — новые строки:
они читаются живыми и уходят в архив следующей уборкой.
"""
import os
import re
import sys

SID = r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'


EXT = {'five-whys': 'seen'}   # прочие семейства — `.jsonl`: расширение то же, что у прежней маски читателя


def member(name, family):
    # Форма имени — та же, что у `session_journals` (журналы настоящих сессий, D1006): резервная копия `.bak.N`, снимок
    # `.snap-…`, файл без UUID (`detection-git-trap.jsonl`) и чужое расширение — не члены.
    ext = re.escape(EXT.get(family, 'jsonl'))
    return re.fullmatch(re.escape(family) + '-' + SID + r'(\.agent-[A-Za-z0-9_-]+)?\.' + ext, name) is not None


def archive_path(state, family):
    return os.path.join(state, 'archive', family + '.tsv')


def _rows(path, name):
    """Строки файла в формате архива; последняя строка без перевода строки — тоже строка. Не прочитался — OSError, а
    не пустота: пустота неотличима от «строк нет» (род B), и перенос удалил бы непрочитанный файл."""
    mtime = int(os.stat(path).st_mtime)
    with open(path, 'rb') as fh:
        data = fh.read()
    if not data:
        return b''
    parts = data.split(b'\n')
    if parts[-1] == b'':
        parts.pop()
    head = name.encode('utf-8') + b'\t' + str(mtime).encode() + b'\t'
    return b''.join(head + p + b'\n' for p in parts)


def archived_rows(state, family):
    """(имя файла, mtime, строка) архива — для читателя на Python: формат разбирается здесь, у владельца. Архива нет —
    пусто; архив есть, а не читается — OSError (читатель считает это непрочитанным журналом, а не «строк нет»)."""
    try:
        with open(archive_path(state, family), 'rb') as fh:
            data = fh.read()
    except FileNotFoundError:
        return []
    rows = []
    for raw in data.decode('utf-8', 'replace').split('\n'):
        if not raw:
            continue
        name, _, rest = raw.partition('\t')
        mt, _, line = rest.partition('\t')
        rows.append((name, int(mt) if mt.isdigit() else 0, line))
    return rows


def archived(state, family, out):
    """Архив целиком. Есть, но не читается — OSError (вызывающий отвечает «не прочитано», а не «строк нет»)."""
    try:
        with open(archive_path(state, family), 'rb') as fh:
            out.write(fh.read())
    except FileNotFoundError:
        pass


def lines(state, family, out):
    """Архив, затем живые члены. Нечитаемый файл — имя в stderr; вернёт число непрочитанных (вывод тогда неполон)."""
    unread = 0
    try:
        archived(state, family, out)
    except OSError as e:
        print(f'state_archive: архив {family} не прочитан: {e}', file=sys.stderr)
        unread += 1
    try:
        names = sorted(os.listdir(state))
    except OSError as e:
        print(f'state_archive: каталог не прочитан: {e}', file=sys.stderr)
        return unread + 1
    for name in names:
        p = os.path.join(state, name)
        if member(name, family) and os.path.isfile(p):
            try:
                out.write(_rows(p, name))
            except OSError as e:
                print(f'state_archive: {name} не прочитан: {e}', file=sys.stderr)
                unread += 1
    return unread


def archive(state, family, names):
    # Все имена сверяются ДО первого переноса: чужое имя посреди списка срывало перенос остатка семейства, когда
    # часть уже перенесена (скептик D1008, L1).
    bad = [n for n in names if not member(n, family)]
    if bad:
        raise ValueError(f'не члены семейства {family}: {" ".join(bad)}')
    tsv = archive_path(state, family)
    os.makedirs(os.path.dirname(tsv), exist_ok=True)
    n, failed = 0, []
    # Сбой одного файла не останавливает остаток: иначе один нечитаемый файл навсегда держал бы семейство на месте
    # (второй скептик D1008, L-1). Сбойные называются в конце, и вызов выходит кодом 2.
    for name in names:
        p = os.path.join(state, name)
        if not os.path.lexists(p):
            continue
        try:
            block = _rows(p, name)   # не прочитался — файл не удаляется (род B)
        except OSError as e:
            failed.append(f'{name} (не прочитан: {e.strerror})')
            continue
        pos = os.path.getsize(tsv) if os.path.exists(tsv) else 0
        if block:
            # ponytail: обрыв ПРОЦЕССА между дописью и удалением повторит строки файла при следующей уборке; окно — миг
            # раз в неделю, журнала перенесённых имён нет: воссозданный файл (см. шапку) он бы спутал с повтором.
            with open(tsv, 'ab') as fh:
                fh.write(block)
                fh.flush()
                os.fsync(fh.fileno())
        try:
            os.unlink(p)
        except FileNotFoundError:
            pass
        except OSError as e:
            # Отказ удаления (EPERM, EACCES) оставил бы файл, и следующая уборка дописала бы его снова — число росло бы
            # на каждой уборке (скептик D1008, M3). Архив возвращается к прежнему размеру.
            os.truncate(tsv, pos)
            failed.append(f'{name} (не удалён: {e.strerror})')
            continue
        n += 1
    return n, failed


def main(argv):
    if len(argv) >= 4 and argv[1] == 'lines':
        return 2 if lines(argv[2], argv[3], sys.stdout.buffer) else 0
    if len(argv) >= 4 and argv[1] == 'archived':
        try:
            archived(argv[2], argv[3], sys.stdout.buffer)
        except OSError as e:
            print(f'state_archive: архив {argv[3]} не прочитан: {e}', file=sys.stderr)
            return 2
        return 0
    if len(argv) >= 4 and argv[1] == 'archive':
        try:
            n, failed = archive(argv[2], argv[3], argv[4:])
        except (ValueError, OSError) as e:
            print(0)
            print(f'state_archive: {e}', file=sys.stderr)
            return 2
        print(n)   # число перенесённых — и при частичном сбое: уборка считает по нему
        if failed:
            print(f'state_archive: не перенесены: {"; ".join(failed)}', file=sys.stderr)
            return 2
        return 0
    print('usage: state_archive.py lines <state> <семейство> | archive <state> <семейство> <имя>...', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
