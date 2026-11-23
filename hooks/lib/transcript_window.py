#!/usr/bin/env python3
"""Начало текущего хода в расшифровке сессии: байтовое смещение последней реплики владельца.

Использование: transcript_window.py <расшифровка> [--state <каталог>] [--range [--before N | --from-agent | --reply | --around-reply]]
               (--reply — только строка реплики; --around-reply — от последнего текста агента до конца реплики;
               --emit вместо --range — строка «ok» и сами байты окна)
               transcript_window.py <расшифровка> --context-hit <путь файла>   → 1 / 0
Без --range печатает смещение начала строки последней реплики владельца; 0 — реплики нет (ход —
весь файл). С --range печатает «начало конец» окна в байтах: от реплики (с --before N — до N байт
раньше, с ближайшего начала строки: читателю, которому нужен текст агента ДО реплики) до конца
последней ПОЛНОЙ строки — недописанная строка уронила бы `jq -s` целиком. Сами байты режет
вызывающий (`tail -c` и `head -c`), поэтому сбой помощника не может напечатать окно дважды.

Зачем (D498). Читатели «что сказано в этом ходе» брали расшифровку целиком на каждом вызове,
и цена события росла с жизнью сессии: 0,68 с на 48 МБ на каждый вызов инструмента. Предмет
события — текущий ход, поэтому файл читается С КОНЦА до последней реплики владельца, а с меткой
в каталоге состояния следующий вызов досматривает только дописанные байты.

Реплика владельца — то же определение, что у `transcript_user_texts` (hook-input-lib.sh):
type и role user, не isMeta, не isCompactSummary, не isSidechain, origin.kind человек или не
задан, текст непустой. Окно от неё безопасно для читателя с более широкой границей (любая
запись user — rc_turn_key, канарейка): его граница лежит в окне или позже. Какое понятие нужно каждому
читателю (граница, речь, реплика до текущей) — `reply-readers.tsv` рядом (D1145): правку признака сверяй с ним.

Названный предел: метка верит паре «inode + размер» — файл, переписанный на месте тем же
inode и не короче прежнего, даст устаревшее смещение. Расшифровку харнесс только дописывает.
Условие снятия: харнесс начнёт переписывать расшифровку на месте — тогда метке нужен отпечаток содержимого.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

CHUNK = 1 << 18
# Служебная копия запроса (D1346): клиент пишет в расшифровку копии сообщений запроса записью вида `api-request-blob`;
# `message.role` у неё тот же, что у настоящей записи, и читатель по роли видел каждый вызов дважды, а копию последнего
# ответа прошлого хода — уже в следующем ходе (в 120 расшифровках 79 блоков; `rc_outcome_observed` засчитывал прошлую
# правку бэклога исходом нынешнего хода). Окно и свёртка таких строк читателю не отдают. Признак — сырой текст ключа: в
# тексте сообщения он стоит с экранированными кавычками. ponytail: вложенный объект с тем же ключом и значением без
# экранирования уронит и свою строку — в расшифровках не встречен; встретится — разбирать вид записи через json.
COPY_WORD = b"api-request-blob"
COPY_MARK = re.compile(rb'"type"\s*:\s*"api-request-blob"')   # клиент пишет слитно, прочие писатели — с пробелом


def drop_copies(data):
    """Байты расшифровки без строк-копий запроса; строки делит только перевод строки."""
    if COPY_WORD not in data:
        return data
    return b"\n".join(l for l in data.split(b"\n") if COPY_WORD not in l or not COPY_MARK.search(l))


def _text(rec):
    msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
    c = msg.get("content", rec.get("content"))
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        # Текст блока — только строка: нестроковый `text` ядро не роняет (скептик D1153, L1).
        return "\n".join(x.get("text") if isinstance(x.get("text"), str) else "" for x in c
                         if isinstance(x, dict) and x.get("type") == "text")
    return ""


def _human_kind(kind):
    """Автор — человек: поле отсутствует (null), ложно (false) или "human" — как `(.kind // "human") == "human"` в jq: `//`
    подставляет значение и на null, и на false. Одно правило для питонских судей автора (`as_reply`, `is_owner_reply`;
    через них — `is_owner_speech` и `_is_reply_any`, D1209), которые расходились с jq-двойниками на пограничных формах
    (скептики D1142, D1150)."""
    return kind is None or kind is False or kind == "human"


def as_reply(rec):
    """Реплика владельца, набранная посреди хода (D1142, корень R3), приводится к виду реплики: харнесс кладёт её
    записью `attachment` вида `queued_command` (текст — `attachment.prompt`, автор — `attachment.origin.kind`), и хук
    подачи реплики на ней срабатывает. Дальше судят прежние условия. Уведомления задач (`commandMode`
    task-notification) и отчёты субагентов (`origin.kind` peer) остаются вложениями. Та же приводилка в jq —
    `HIL_AS_REPLY_JQ` (`hooks/hook-input-lib.sh`).
    ГРАНИЦУ ХОДА она не двигает: вложение приходит посреди хода, ход до Stop продолжается, и сканеры речи на Stop
    (`output-language-check`, `relative-date-check`, …) судят его целиком — окно, начатое с вложения, оставило бы
    текст агента до него без суда. Поэтому граница хода — `is_owner_reply` (запись user), а последняя реплика —
    `is_owner_speech`. Корпус (27 октября 2026): в 523 из 559 случаев Stop между прежней репликой и вложением нет;
    в 34 ход после Stop разбудило уведомление задачи, в 2 — реплика без текста, и граница стоит на прежней реплике,
    как и до D1142."""
    if not isinstance(rec, dict) or rec.get("type") != "attachment" or not isinstance(rec.get("attachment"), dict):
        return rec
    a = rec["attachment"]
    # Автор — `_human_kind`, как в jq (`HIL_AS_REPLY_JQ`): поля нет, null или false — человек; пустая строка, 0 — не
    # человек (скептик D1142, L3; D1150, четвёртый круг, L2). Предел: `attachment.origin` не объектом (null, false) питон
    # не приводит, а jq на null приводит и на false падает — в мире таких записей 0 (скептик D1150, четвёртый круг, L5).
    origin = a.get("origin", {})
    if not isinstance(origin, dict):
        return rec
    kind = origin.get("kind")
    if a.get("type") != "queued_command" or a.get("commandMode") != "prompt" or not _human_kind(kind):
        return rec
    return dict(rec, type="user", origin=origin, message={"role": "user", "content": a.get("prompt")})


def is_turn_user(rec):
    """Запись user для читателей ШИРОКОЙ границы (D1153): тип и роль user, не isMeta, текст непустой. Уведомление задачи и
    сводка сжатия ход здесь делят — так задумано у стражей Stop и свёртки хода; служебная запись `api-request-blob` (роль
    user, тип другой) — нет. Двойник в jq — `HIL_TURN_USER_JQ` (`hooks/hook-input-lib.sh`)."""
    if not isinstance(rec, dict) or rec.get("type") != "user":
        return False
    msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
    if (msg.get("role") or rec.get("role") or "") != "user":
        return False
    if rec.get("isMeta"):
        return False
    return len(_text(rec)) > 0


def _jq_false(v):
    """Ложь в смысле jq `(x // false) | not`: только null и false — 0 и пустая строка в jq истинны."""
    return v is None or v is False


def is_turn_user_no_summary(rec):
    """Запись user для читателей границы «без сводки» (`reply-readers.tsv`, канарейка `real_user`): уведомление задачи ход
    делит, сводка сжатия и боковая ветка — нет. Исключение — по истинности jq (`_jq_false`): признак не шире jq-двойника,
    и окно не начнётся позже границы читателя."""
    return is_turn_user(rec) and _jq_false(rec.get("isCompactSummary")) and _jq_false(rec.get("isSidechain"))


def is_owner_reply(rec):
    if not is_turn_user(rec) or rec.get("isCompactSummary") or rec.get("isSidechain"):
        return False
    origin = rec.get("origin") if isinstance(rec.get("origin"), dict) else {}
    # Пустой автор — не человек, null и false — человек, как у jq-двойника (D1150, L1).
    return _human_kind(origin.get("kind"))


def is_owner_speech(rec):
    """Последняя реплика владельца для читателей РЕЧИ (D1142): реплика хода либо реплика, набранная посреди него."""
    return is_owner_reply(as_reply(rec))


def is_agent_text(rec):
    return isinstance(rec, dict) and rec.get("type") == "assistant" and len(_text(rec)) > 0


def _end_bound(path):
    """Граница файла от зовущего (D1250, корень R6): фоновый хук Stop судит ход, закончившийся на СВОЁМ Stop, а к
    моменту чтения в файле бывает уже начало следующего (сессия 62cb88c6: через 0,3 с после Stop). Граница —
    `TRANSCRIPT_END_BYTES`, байтовый конец строки итога хода (`--stop-end`), и действует она только на свой файл
    `TRANSCRIPT_END_FILE`: смещение без файла урезало бы любой другой файл, прочитанный тем же процессом."""
    v, own = os.environ.get("TRANSCRIPT_END_BYTES", ""), os.environ.get("TRANSCRIPT_END_FILE", "")
    if not v.isdigit() or not own or not path:
        return None
    try:
        return int(v) if os.path.samefile(own, path) else None
    except OSError:
        return None


def _complete_end(f, size):
    """Конец последней ПОЛНОЙ строки: недописанный хвост не читается, его дочитает следующий вызов."""
    b = _end_bound(getattr(f, "name", None))
    if b is not None and b < size:
        size = b
    pos = size
    while pos > 0:
        start = max(0, pos - CHUNK)
        f.seek(start)
        i = f.read(pos - start).rfind(b"\n")
        if i >= 0:
            return start + i + 1
        pos = start
    return 0


def scan_back(f, end, floor, pred=is_owner_reply):
    """Смещение последней строки с `pred` среди полных строк [floor, end); None — нет."""
    pos, carry = end, b""
    while pos > floor:
        start = max(floor, pos - CHUNK)
        f.seek(start)
        data = f.read(pos - start) + carry
        if start > floor:
            nl = data.find(b"\n")
            if nl < 0:
                carry, pos = data, start
                continue
            head, body, body_start = data[:nl + 1], data[nl + 1:], start + nl + 1
        else:
            head, body, body_start = b"", data, start
        starts, off = [], body_start
        for line in body.split(b"\n")[:-1]:
            starts.append((off, line))
            off += len(line) + 1
        for off, line in reversed(starts):
            try:
                if pred(json.loads(line)):
                    return off
            except ValueError:
                continue
        carry, pos = head, start
    return None


def stop_end(path, text):
    """Байтовый конец строки итога хода: последняя запись агента, чей текст без краевых пробелов равен полю Stop
    `last_assistant_message`. Ищется в последних STOP_SCAN байтах; итог пуст — конец последней полной строки сейчас.
    Итога в файле ещё нет — файл не догнал Stop (D1159: 12 из 109 тревог канарейки на этой гонке), и граница на нынешнем
    конце выбросила бы сам итог из суда (скептик D1250, H1): итог ждётся до STOP_WAIT секунд, не дождался — None,
    границы нет, читатели судят файл, как до D1250."""
    want = (text or "").strip()
    deadline = time.time() + STOP_WAIT
    while True:
        with open(path, "rb") as f:
            size = os.fstat(f.fileno()).st_size
            pos = size
            while pos > 0:   # конец последней полной строки без границы зовущего — её здесь и ставят
                start = max(0, pos - CHUNK)
                f.seek(start)
                i = f.read(pos - start).rfind(b"\n")
                if i >= 0:
                    pos = start + i + 1
                    break
                pos = start
            if not want:
                return pos
            hit = scan_back(f, pos, max(0, pos - STOP_SCAN),
                            lambda r: is_agent_text(r) and _text(r).strip() == want)
            if hit is not None:
                f.seek(hit)
                return hit + len(f.readline())
        if time.time() >= deadline:
            return None
        time.sleep(0.1)


STOP_SCAN = 8 << 20
STOP_WAIT = float(os.environ.get("TRANSCRIPT_STOP_WAIT", "3"))


PRUNE_AGE = 3 * 86400
PRUNE_EVERY = 3600


def _prune(state):
    """Уборка своих файлов в каталоге состояния: метки окна и состояния свёртки, не тронутые
    трое суток. Без неё их число росло бы с числом расшифровок вечно — тот же род, что каталог
    из 73 тыс. файлов в D498. Срок — календарь, как у уборки `throttle_file`: предмет — жива ли
    сессия, а возобновлённая после трёх суток платит один холодный проход, верность не страдает.
    Не чаще раза в час, по метке `.transcript-prune.stamp`; двое одновременных проходят оба."""
    stamp, now = os.path.join(state, ".transcript-prune.stamp"), time.time()
    try:
        if now - os.stat(stamp).st_mtime < PRUNE_EVERY:
            return
    except OSError:
        pass
    try:
        with open(stamp, "a"):
            pass
        os.utime(stamp, None)
        with os.scandir(state) as it:
            for e in it:
                if e.name.startswith(("transcript-turn-", "transcript-fold-")):
                    try:
                        if now - e.stat().st_mtime > PRUNE_AGE:
                            os.unlink(e.path)
                    except OSError:
                        pass
    except OSError:
        pass


def turn_offset(path, state=None, pred=is_owner_reply, tag="turn"):
    """(смещение последней строки с `pred` — по умолчанию начала хода, конец последней полной строки).
    У каждого признака своя метка (`tag`): точка «последняя речь» дальше точки «начало хода», и одна
    метка на двоих отдавала бы одному из них чужую."""
    if state:
        _prune(state)
    st = os.stat(path)
    with open(path, "rb") as f:
        end = _complete_end(f, st.st_size)
        mark = None
        if state:
            key = hashlib.sha1(os.path.abspath(path).encode()).hexdigest()[:16]
            mark = os.path.join(state, f"transcript-{tag}-{key}")
        floor, prev = 0, 0
        if mark:
            try:
                with open(mark, encoding="utf-8") as m:
                    ino, size, off = (int(x) for x in m.read().split()[:3])
                if ino == st.st_ino and size > end:
                    # Сосед ушёл дальше моего снимка (противник свёртки, раунд 2): файл только
                    # дописывается — снимок догоняется, а точка соседа не отбрасывается. Файл,
                    # переписанный короче точки, и после догона короче — метка удаляется (_drop).
                    end = _complete_end(f, os.fstat(f.fileno()).st_size)
                    if size > end:
                        # Устарели точки ВСЕХ признаков этого файла, а не только своего: иначе метка
                        # речи пережила бы сжатие, замеченное окном хода, и после дорастания файла
                        # отдала бы прежнюю речь (скептик D1142, круг 3, L1).
                        # При границе зовущего (D1250) сосед прочёл дальше неё законно: его метку не берём и не сносим.
                        if _end_bound(path) is None:
                            for t in ("turn", "turn-speech", "turn-wide", "turn-nosum"):
                                _drop(os.path.join(state, f"transcript-{t}-{key}"))
                if ino == st.st_ino and size <= end:
                    floor, prev = size, off
            except (OSError, ValueError):
                pass
        found = scan_back(f, end, floor, pred)
        off = found if found is not None else prev
    if mark:
        _write_mark(mark, st.st_ino, end, off)
    return off, end


def _under_lock(path, put):
    """`put` под общим замком (род H). Замка нет или он не взят — `put` всё равно исполняется:
    кэш улучшает работу, а не держит её."""
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from state_lock import with_lock
    except ImportError:
        put()
        return
    with with_lock(path):
        put()


def _drop(path):
    """Удалить метку или состояние, доказанно устаревшие: точка дальше файла и после догона
    снимка — файл переписан на месте короче. Отказ при чтении мира не меняет, а запись «только
    вперёд» берегла бы такую точку как «более продвинутую», и после дорастания файла устаревшее
    принималось снова (противник свёртки, раунд 3, атака 3). Под общим замком (род H)."""
    def rm():
        try:
            os.unlink(path)
        except OSError:
            pass
    _under_lock(path, rm)


def _write_mark(mark, ino, end, off):
    """Метка обновляется только ВПЕРЁД и под общим замком (род H): соседний вызов мог уже
    записать более продвинутую точку — её не затирать. Каждая тройка верна про свою часть
    файла, поэтому потеря записи стоила бы лишь повторного досмотра; сериализация снимает и её."""

    def put():
        try:
            with open(mark, encoding="utf-8") as m:
                cur = [int(x) for x in m.read().split()[:3]]
            if len(cur) == 3 and cur[0] == ino and cur[1] >= end:
                return
        except (OSError, ValueError):
            pass
        tmp = f"{mark}.{os.getpid()}"
        try:
            with open(tmp, "w", encoding="utf-8") as m:
                m.write(f"{ino} {end} {off}\n")
            os.replace(tmp, mark)
        except OSError:
            pass

    _under_lock(mark, put)


def fold(path, state, name, cmd, turn=False):
    """Свёртка расшифровки по дописанным байтам (D498): цена события — дописанное, а не прожитое.

    `cmd` — шаг свёртки: на stdin получает полные строки, дописанные с прошлого вызова, последним
    аргументом — путь файла с прежним накопленным (пустой — с нуля), печатает новое накопленное.
    Определение шага живёт у потребителя (jq), здесь только «докуда дочитано»: файл состояния
    `transcript-fold-<имя>-<ключ>` — строка «inode конец подпись начало» и накопленное.
    `turn` — свёртка текущего хода: помощник начинает её с последней реплики владельца
    (`turn_offset`) ради цены, а шаг ОБЯЗАН сам сбрасываться на реплике (его граница не уже
    реплики): запасной путь без помощника отдаёт шагу весь файл (противник, раунд 3). Подпись —
    хеш команды: поменялся шаг (правка кода) — накопленное не годится, свёртка идёт с начала.
    Запись только ВПЕРЁД под общим замком (род H): соседний вызов мог продвинуться дальше.
    Вывод — строка «ok» и накопленное, как у `--emit`: успех читается по метке, а не по коду
    возврата — помощник прежнего выпуска, не знающий `--fold`, тоже выходит с 0 и печатает
    смещение хода, которое без метки принималось за накопленное (противник свёртки, атака 1:
    оболочка и помощник доставляются в установку порознь).
    Коды: 0 — накопленное напечатано; 4 — шаг отказал (состояние не тронуто); 1 — сбой помощника.
    """
    # Подпись несёт и редакцию ВХОДА шага (скептик D1346, L1): накопленное прежней редакцией считало копии запроса,
    # и продолжать его дельтой без копий значило оставить завышение до конца сессии (19 состояний из 19, на 5–77%).
    sig = hashlib.sha1(("без-копий-запроса\0" + "\0".join(cmd)).encode()).hexdigest()[:16]
    if state and not turn:
        _prune(state)
    origin, end = turn_offset(path, state) if turn else (0, None)
    ino = os.stat(path).st_ino
    with open(path, "rb") as f:
        if end is None:
            end = _complete_end(f, os.fstat(f.fileno()).st_size)
        sfile, base, acc, warm = None, None, b"", False
        if state:
            key = hashlib.sha1(os.path.abspath(path).encode()).hexdigest()[:16]
            sfile = os.path.join(state, f"transcript-fold-{name}-{key}")
            try:
                with open(sfile, "rb") as s:
                    head, _, body = s.read().partition(b"\n")
                h = head.decode().split()
                if len(h) == 4 and int(h[0]) == ino and h[2] == sig and int(h[1]) > end:
                    # Сосед свернул дальше моего снимка: снимок догоняется (у хода — заново и
                    # начало хода), а не идёт холодная свёртка всего хода (противник, раунд 2).
                    if turn:
                        origin, end = turn_offset(path, state)
                    else:
                        end = _complete_end(f, os.fstat(f.fileno()).st_size)
                    if int(h[1]) > end:
                        if _end_bound(path) is None:   # при границе (D1250) свёртка соседа дальше неё — законна
                            _drop(sfile)
                if (len(h) == 4 and int(h[0]) == ino and h[2] == sig and int(h[3]) == origin
                        and origin <= int(h[1]) <= end):
                    base, acc, warm = int(h[1]), body, True
            except (OSError, ValueError):
                pass
        if base is None:
            # Начало — от ОКОНЧАТЕЛЬНОГО начала хода, после догона снимка: выведенное до догона
            # отдавало шагу хвост прошлого хода (противник свёртки, раунд 3, атака 1).
            base = origin
        if warm and base == end:
            sys.stdout.buffer.write(b"ok\n" + acc)
            return 0
        f.seek(base)
        delta = drop_copies(f.read(end - base))
    fd, accp = tempfile.mkstemp(prefix="transcript-fold-")
    try:
        with os.fdopen(fd, "wb") as a:
            a.write(acc)
        r = subprocess.run(cmd + [accp], input=delta, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    finally:
        os.unlink(accp)
    if r.returncode != 0:
        return 4
    if sfile:
        def put():
            try:
                with open(sfile, "rb") as s:
                    h = s.readline().decode().split()
                if len(h) == 4 and int(h[0]) == ino and h[2] == sig and int(h[1]) >= end:
                    return
            except (OSError, ValueError):
                pass
            tmp = f"{sfile}.{os.getpid()}"
            try:
                with open(tmp, "wb") as s:
                    s.write(f"{ino} {end} {sig} {origin}\n".encode() + r.stdout)
                os.replace(tmp, sfile)
            except OSError:
                pass
        _under_lock(sfile, put)
    sys.stdout.buffer.write(b"ok\n" + r.stdout)
    return 0


def _is_reply_any(rec):
    """Реплика в смысле `CONTEXT_HIT` стража поправок — реплика ВЛАДЕЛЬЦА (D1138, корень R3): type и role user с
    текстом, не служебная запись (`isMeta`, сводка сжатия, боковая ветка) и `origin.kind` human. Прежде здесь
    стояла одна форма, и ею были уведомления о фоновых задачах и отчёты субагентов: правка файла, уведомление, вторая
    правка того же файла давали образец «правка, затем реплика», и последняя настоящая реплика («продолжай с D1137»)
    ложилась в журнал поправок через 1 ч 41 мин после того, как была сказана. Правило — владельца, `is_owner_speech`
    (D1209, R3): своя копия перечня полей здесь не требовала роли user и не брала текст рядом с результатом инструмента, и
    быстрый путь стража расходился с запасным (`hooks/user-correction-guard.sh`, `owner_reply` в jq). Реплика посреди
    хода (`queued_command`) — реплика тоже (D1142, `as_reply`)."""
    return is_owner_speech(rec)


def _edits_file(rec, fp):
    if not isinstance(rec, dict) or rec.get("type") != "assistant":
        return False
    msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
    for x in msg.get("content") or []:
        if (isinstance(x, dict) and x.get("type") == "tool_use"
                and x.get("name") in ("Edit", "Write", "MultiEdit")
                and ((x.get("input") or {}).get("file_path") or "") == fp):
            return True
    return False


def edit_then_reply(path, fp):
    """1 — в расшифровке есть правка файла `fp`, за которой следует реплика; 0 — нет.

    Образец «правка, затем реплика» (строка «EH» стража поправок) существует тогда и только
    тогда, когда ПЕРВАЯ правка файла стоит раньше ПОСЛЕДНЕЙ реплики. Поэтому последняя
    реплика ищется с конца, а правка до неё — поиском подстроки пути (скорость memchr);
    JSON разбирают только строки-кандидаты. Цена — чтение байтов, а не разбор всей сессии.
    Названный предел: область до реплики читается в память целиком — десятки МБ.
    Условие снятия: расшифровки вырастут настолько, что чтение области целиком станет заметно в цене
    хука, — тогда чтение блоками.
    """
    needles = {json.dumps(fp, ensure_ascii=False).encode(), json.dumps(fp).encode()}
    with open(path, "rb") as f:
        end = _complete_end(f, os.fstat(f.fileno()).st_size)
        last_h = scan_back(f, end, 0, _is_reply_any)
        if last_h is None:
            return 0
        f.seek(0)
        buf = f.read(last_h)
    for n in needles:
        i = buf.find(n)
        while i >= 0:
            ls, le = buf.rfind(b"\n", 0, i) + 1, buf.find(b"\n", i)
            le = len(buf) if le < 0 else le
            try:
                if _edits_file(json.loads(buf[ls:le]), fp):
                    return 1
            except ValueError:
                pass
            i = buf.find(n, le)
    return 0


def window_start(path, off, before=0):
    """Начало окна: до `before` байт раньше реплики, выровнено на начало строки."""
    start = max(0, off - before)
    if 0 < start < off:
        with open(path, "rb") as f:
            f.seek(start - 1)
            start += f.read(off - start + 1).find(b"\n")   # ≤ off: реплика сама начинает строку
    return start


def main(argv):
    if len(argv) < 2:
        print("использование: transcript_window.py <расшифровка> [--state <каталог>]", file=sys.stderr)
        return 2
    if "--stop-end" in argv[:-1]:
        # transcript_window.py <расшифровка> --stop-end <файл с текстом итога>   → байтовый конец строки итога
        try:
            with open(argv[argv.index("--stop-end") + 1], encoding="utf-8", errors="replace") as t:
                b = stop_end(argv[1], t.read())
                print("" if b is None else b)   # пусто — итог не дождались, границы нет (D1250, H1)
            return 0
        except OSError as e:
            print(f"transcript_window: {e}", file=sys.stderr)
            return 1
    if "--fold" in argv and "--" in argv:
        # transcript_window.py <расшифровка> --fold <имя> [--turn] [--state <каталог>] -- <шаг...>
        opts, cmd = argv[:argv.index("--")], argv[argv.index("--") + 1:]
        st = opts[opts.index("--state") + 1] if "--state" in opts[:-1] else None
        try:
            return fold(argv[1], st, opts[opts.index("--fold") + 1], cmd, "--turn" in opts)
        except (OSError, ValueError, IndexError) as e:
            print(f"transcript_window: {e}", file=sys.stderr)
            return 1
    state = argv[argv.index("--state") + 1] if "--state" in argv[:-1] else None
    try:
        if "--context-hit" in argv[:-1]:
            print(edit_then_reply(argv[1], argv[argv.index("--context-hit") + 1]))
            return 0
        before = int(argv[argv.index("--before") + 1]) if "--before" in argv[:-1] else 0
        # Окно от границы ЧИТАТЕЛЯ (D1235, корень R6): читатель широкой границы получал окно от реплики владельца и сам
        # искал в нём свою — в пакетном ходе владелец молчит часами, и каждый Stop разбирал всё с его реплики (88–107 МБ:
        # канарейка 30–81 с). Широкая граница не раньше узкой, поэтому суждение то же, а цена — от последней подачи.
        if "--wide" in argv:
            off, end = turn_offset(argv[1], state, is_turn_user, "turn-wide")
        elif "--no-summary" in argv:
            off, end = turn_offset(argv[1], state, is_turn_user_no_summary, "turn-nosum")
        else:
            off, end = turn_offset(argv[1], state)
        start = window_start(argv[1], off, before)
        if "--from-agent" in argv and off > 0:
            # Окно с последнего текста агента ДО реплики: цена — расстояние до него, а не
            # фиксированный захват; текста нет — с начала файла (первая реплика сессии).
            with open(argv[1], "rb") as f:
                found = scan_back(f, off, 0, is_agent_text)
            start = found if found is not None else 0
        if "--reply" in argv or "--around-reply" in argv:
            # Читателю нужна сама реплика (и текст агента перед ней), а не весь ход: цена
            # не растёт с длиной хода. Реплики нет — весь файл, как было. Реплика — последняя
            # РЕЧЬ владельца в ходе (D1142): набранная посреди хода стоит позже начала хода. Её
            # точка тоже тёплая, своей меткой: поиск от конца до начала хода разбирал весь ход на
            # каждом вызове (+2,3 с у стража поправок на ходе 127 МБ, скептик D1142). Начало хода —
            # тоже речь, поэтому точка речи не раньше его; `max` держит и холодный «речи нет» (0).
            said, _ = turn_offset(argv[1], state, is_owner_speech, "turn-speech")
            off = max(off, said)
            with open(argv[1], "rb") as f:
                f.seek(off)
                line = f.readline()
                try:
                    is_reply = is_owner_speech(json.loads(line))
                except ValueError:
                    is_reply = False
                if not is_reply:
                    start = 0
                else:
                    end = off + len(line)
                    if "--around-reply" in argv:
                        found = scan_back(f, off, 0, is_agent_text) if off > 0 else None
                        start = found if found is not None else 0
                    else:
                        start = off
        if "--emit" in argv:
            # Байты окна отдаёт сам помощник, за строкой «ok»: системный `tail -c +N` на macOS
            # копирует ~30 МБ/с — 0,2–0,3 с на каждые 8 МБ окна, и цена росла с длиной хода
            # (D498, 2 октября 2026). Строка «ok» пишется только после открытия файла: нет её —
            # вызывающий берёт файл целиком, и окно не печатается дважды.
            with open(argv[1], "rb") as f:
                f.seek(start)
                out, left = sys.stdout.buffer, end - start
                out.write(b"ok\n")
                carry = b""                      # неполная строка на стыке кусков — копию судят по целой строке
                while left > 0:
                    chunk = f.read(min(CHUNK * 4, left))
                    if not chunk:
                        break
                    left -= len(chunk)
                    buf = carry + chunk
                    cut = buf.rfind(b"\n") + 1
                    carry = buf[cut:]
                    out.write(drop_copies(buf[:cut]))
                out.write(drop_copies(carry))
                out.flush()
        elif "--range" in argv:
            print(start, end)
        else:
            print(off)
    except BrokenPipeError:
        # Читатель закрыл канал раньше конца окна — ему больше не нужно; молча.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 1
    except (OSError, ValueError) as e:
        print(f"transcript_window: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
