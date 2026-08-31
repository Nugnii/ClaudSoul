#!/usr/bin/env python3
# injection-log-rotate.py — ротация журнала подач по последним K уникальным сессиям.
# Вызов: python3 injection-log-rotate.py <log> <archive> <keep_sessions>
# Вынесен из heredoc в knowledge-activator.sh (D236): вызываемый файл тестируется
# напрямую, и копия блока в test_state_hygiene T14 больше не нужна.
#
# Контракт:
#   · живой лог хранит строки последних K уникальных session_id (порядок первого
#     появления); строки старых сессий и строки без session_id уезжают в архив;
#   · битые строки остаются в живом логе — их считает отдельная метрика;
#   · дешёвый гейт: файл меньше INJECTION_LOG_MIN_BYTES (512К) не разбирается.
#
# АТОМАРНОСТЬ ПРОТИВ КОНКУРЕНТНОГО АППЕНДА (D236). Прежняя форма read_text →
# write_text теряла строки, дописанные параллельной сессией между чтением и
# записью, — замер теста: 14082 потерянных из 44172 (32%). Теперь:
#   1) лог атомарно ПЕРЕИМЕНОВЫВАЕТСЯ в *.rot.<pid>.<ms>: конкурентные `>>`
#      с этого мгновения создают свежий живой лог и не теряются;
#   2) переименованный файл разбирается без спешки, старое уезжает в архив;
#   3) оставляемые строки ВОЗВРАЩАЮТСЯ в живой лог ОДНИМ os.write в O_APPEND —
#      однострочные аппенды соседей не рвутся (write() сериализуется ядром);
#   4) упавшая посередине ротация оставляет *.rot*-сироту; следующий запуск
#      возвращает её содержимое в живой лог (заявка через os.replace — двум
#      процессам одна сирота не достанется). Свежие чужие *.rot (моложе 120 с)
#      не трогаются: это, возможно, живая ротация соседа.
# Цена: порядок строк после ротации перемешивается (свежие аппенды оказываются
# раньше возвращённых) — все потребители журнала порядко-независимы (пары по
# session_id, окна по датам, счёт по строкам); «первое появление» сессии для
# следующей ротации может сдвинуться — буфер K=200 против окон 20-30 это гасит.
import json, os, pathlib, sys, time

log = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
keep_sessions = int(sys.argv[3])
logdir = log.parent


def append_atomic(path, data):
    # Единый write() в O_APPEND: пока пишется один буфер, однострочные `>>` соседей
    # не вклиниваются внутрь строки. Частичная запись write() на локальной ФС —
    # экзотика (сигнал/ENOSPC); дописываем остаток циклом, принимая, что в этом
    # крайнем случае на стыке кусков возможна чужая строка МЕЖДУ (не внутри) наших.
    if not data:
        return
    fd = os.open(str(path), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        view = memoryview(data)
        while view:
            n = os.write(fd, view)
            view = view[n:]
    finally:
        os.close(fd)


# --- 1. Сироты прежних ротаций: вернуть их строки в живой лог -----------------
now = time.time()
for orphan in sorted(logdir.glob(log.name + ".rot*")):
    try:
        st = orphan.stat()
    except OSError:
        continue
    if (now - st.st_mtime) < 120:
        continue    # возможно, живая ротация соседа — не трогаем
    claim = logdir / f"{log.name}.rot.claim.{os.getpid()}.{int(now * 1000)}"
    try:
        os.replace(orphan, claim)   # атомарная заявка: сирота достанется одному
    except OSError:
        continue
    try:
        append_atomic(log, claim.read_bytes())
        claim.unlink()
    except OSError:
        # заявка осталась *.rot*-файлом — её подберёт следующий запуск
        pass

# --- 2. Собственно ротация ----------------------------------------------------
try:
    if log.stat().st_size < int(os.environ.get("INJECTION_LOG_MIN_BYTES", "524288")):
        raise SystemExit
except FileNotFoundError:
    raise SystemExit

rot = logdir / f"{log.name}.rot.{os.getpid()}.{int(time.time() * 1000)}"
try:
    os.replace(log, rot)            # с этого мгновения аппенды идут в свежий лог
except FileNotFoundError:
    raise SystemExit                # лог увёл параллельный ротатор

lines = rot.read_text(errors="replace").splitlines(True)
sids, order, seen = [], [], set()
for line in lines:
    try:
        sid = json.loads(line).get("session_id") or None
    except Exception:
        sid = "?"   # битую строку не выбрасываем: её считает отдельная метрика
    sids.append(sid)
    if sid and sid != "?" and sid not in seen:
        seen.add(sid)
        order.append(sid)
keep_ids = set(order[-keep_sessions:])
keep, old = [], []
for line, sid in zip(lines, sids):
    (keep if sid == "?" or sid in keep_ids else old).append(line)

if old:
    append_atomic(archive, "".join(old).encode("utf-8"))
append_atomic(log, "".join(keep).encode("utf-8"))
rot.unlink()
