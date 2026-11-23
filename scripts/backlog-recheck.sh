#!/usr/bin/env bash
# backlog-recheck.sh — закрытый пункт долга обязан оставаться закрытым.
# Результат: закрытые пункты долга остались закрытыми — воскресших нет
# Проверка результата: bash scripts/backlog-recheck.sh даёт 0
#
#
# Зачем. Закрытия бывают двух видов, и держатся они по-разному:
#
#   · закрытие, за которым стоит ТЕСТ, проверяет себя само — тест гоняется каждый прогон,
#     и регрессия становится красной строкой без чьего-либо участия;
#   · закрытие РАЗОВЫМ ДЕЙСТВИЕМ (лог вычищен, ссылки восстановлены, поле задокументировано)
#     не проверяет себя ничем. Оно может тихо откатиться, и в файле долга пункт останется
#     помеченным «сделано».
#
# Замер на 2026-07-29: из 28 закрытых пунктов 11 держались тестом, 17 — разовым действием.
# Этот скрипт закрывает вторую половину: у каждого проверяемого пункта — свой инвариант
# и своя команда, а не общее «посмотреть глазами».
#
# Что НЕ проверяется и почему. Пункты-решения (записан ADR, вопрос собеседнику отвечен,
# отказ зафиксирован) регрессировать не могут: у них нет состояния, которое портится.
# Их перечисление здесь было бы имитацией проверки.
#
# Запуск: вручную либо из недельного дайджеста. Код возврата 1, если хоть один инвариант
# перестал держаться либо красен без слов пробы (D1147).

set -uo pipefail

# Подстановка в ёлочках пишется ТОЛЬКО как «${var}». Ёлочки многобайтовые, и при `set -u`
# bash читает «$var» как имя переменной вместе с закрывающей кавычкой — «unbound variable».  # mb-ok: строка демонстрирует дефект, а не совершает его
# Тот же класс, что чинился в v1.14.6: многобайтовый символ вплотную к синтаксису оболочки.

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"

if [ ! -f "$REPO/BACKLOG.md" ]; then
    echo "backlog-recheck: не найден $REPO/BACKLOG.md" >&2
    exit 2
fi

# --- D1147: «Проверки» закрытых пунктов архива — исполнитель (`--archive`) ---------
# Восемь инвариантов ниже перечислены руками, а у каждого закрытого пункта архива есть своя
# «Проверка» с объявленным кодом — и после переноса её не исполнял никто: проба закрытого
# D439 краснела с 25 октября 2026 и нашлась случайно (D1114). Замер 31 октября 2026: из 514
# «Проверок» архива 75 расходились с объявленным кодом, и ни одна не была названа.
# ОТДЕЛЬНЫЙ РЕЖИМ, А НЕ ВЕТКА ОБЩЕГО ПРОГОНА. Все «Проверки» архива — 4347 с на три потока
# (замер того же дня), а этот скрипт зовут недельный дайджест и «Проверка» D411. Отчётный канал
# долгую работу не исполняет (`hooks/knowledge-audit-digest.sh`, о `measurement-due.sh check`):
# режим исполняет реестр замеров (`scripts/measurements.tsv`, строка `archive-checks`), его
# вывод бегун кладёт в `measurement-runs/archive-checks.out`, а обычный прогон ниже называет
# оттуда каждый пункт (раздел D1147 перед итогом).
# Исход — по объявлению самой строки («→ N»), корень R6: код совпал — держится; 2, 126/127, срок, кольцо,
# нестабильность, недочитанный вывод — «не измерено» (`?`); иной код со словами пробы — откат (`✗`); иной код,
# а проба промолчала, — `✗ [без слов пробы]`: откат или гнилая проба, по выводу не различить (решение владельца
# 31 октября 2026). Последняя строка вывода команды идёт в строку исхода. Строка без кода не исполняется.
# ПРОМОЛЧАВШАЯ ПОЛУЧАЕТ ПОДСКАЗКУ (D1201, решение владельца 3 ноября 2026; скептик opus того же дня). Красная,
# промолчавшая и в потоке, и в одиночном повторе, после всех подтверждений и в остатке бюджета повторов повторяется
# ещё раз — без глушения `/dev/null` и с трассой (`SHELLOPTS=xtrace` наследуют вложенные пробы и тесты, `PS4` несёт
# файл и строку; трасса пишется в безымянный временный файл, читается хвост 64 КБ и обрезается после последнего
# `exit`). Строка исхода получает приписку «подсказка повтора…» — последнюю строку вывода и хвост трассы
# (`n=1` → `'[' 1 -eq 0 ']'` у D477: носитель остался). Метка «без слов пробы» ОСТАЁТСЯ: её снимают только слова
# первого прогона. Трасса — подсказка читателю, а не вердикт: у команды с кавычками и подстановками в ней всегда есть
# «новое» (раскрытый путь), и как вердикт она переводила шум в «откатилось» (скептик, H1).
# ПРЕДЕЛЫ: под трассой проверка может упасть в другом месте с тем же кодом — тест, ловящий свой `2>&1`, получает
# строки трассы в сравниваемый вывод (D272); снятие глушения внутри `$( )` и кавычек меняет смысл команды (D298,
# D334, D525) — обе беды искажают только подсказку; у встроенного `bash -c` трасса без файла и строки (`⟪:0⟫`).
if [ "${1:-}" = "--archive" ]; then
    # Путь архива — СВОЯ переменная, не `BACKLOG_ARCHIVE`: ту архиватор получает от сборщика
    # (`hooks/session-collector.sh`, архив локального проекта) и передаёт «Проверкам» целиком, и проба
    # D1147 в канале архивации читала бы чужой архив (скептик D1147, круг 1, H3).
    _ARCH="${BACKLOG_RECHECK_ARCHIVE:-$REPO/BACKLOG-archive.md}"
    _BL_LIB="$REPO/hooks/backlog-lib.sh"
    [ -f "$_BL_LIB" ] || _BL_LIB="$HOME/.claude/hooks/backlog-lib.sh"
    # Подмена `mktemp` для «Проверок» (`install_shim`, D1198) — модуль из дерева сверщика, запасной путь — установка.
    _BR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../hooks" 2>/dev/null && pwd)/lib"
    [ -f "$_BR_DIR/bounded_run.py" ] || _BR_DIR="$HOME/.claude/hooks/lib"
    # `--archive --list` — перечень исполнимых «Проверок» тем же разбором, без исполнения (D1283, корень R1): строка
    # «номер ⇥ команда». Отбор после коммита (`scripts/archive-checks-after-commit.sh`) резал архив своим выражением и
    # без границы-заголовка — у D104 «блок» вбирал «Проверки» десятков старых пунктов, D447 выбирался без исполнимой
    # «Проверки». Перечень ничего не исполняет, поэтому маркер вложенности его не касается.
    _AC_LIST=0; [ "${2:-}" = "--list" ] && _AC_LIST=1
    # Маркер вложенности — ответ «не исполнялось», а не «держится»: исполнитель внутри «Проверки»
    # дал бы 4347 с на каждый уровень. Кольцо, снявшее маркер, держит ключ библиотеки (D503).
    if [ "${BACKLOG_CHECKS_NESTED:-0}" = "1" ] && [ "$_AC_LIST" = 0 ]; then
        echo "backlog-recheck --archive: вызван изнутри «Проверки» (BACKLOG_CHECKS_NESTED=1) — архив не исполнялся, исход неизвестен" >&2
        exit 2
    fi
    [ -f "$_ARCH" ] || { echo "backlog-recheck --archive: нет архива $_ARCH" >&2; exit 2; }
    [ -f "$_BL_LIB" ] || { echo "backlog-recheck --archive: нет hooks/backlog-lib.sh — разбирать архив нечем" >&2; exit 2; }
    command -v python3 >/dev/null 2>&1 || { echo "backlog-recheck --archive: нет python3" >&2; exit 2; }
    # shellcheck source=/dev/null
    . "$_BL_LIB"
    backlog_strip_fenced < "$_ARCH" | \
        AC_ITEM_RE="$(backlog_item_re)" AC_DONE_RE="$(backlog_item_re "$BACKLOG_MARK_DONE")" \
        AC_CHECK_RE="$BACKLOG_CHECK_RE" AC_ID_RE="$BACKLOG_ID_TOKEN_RE" \
        AC_LIB="$_BL_LIB" AC_BR_DIR="$_BR_DIR" AC_ARCH="$_ARCH" AC_REPO="$REPO" AC_LIST="$_AC_LIST" AC_PYIOENC="${PYTHONIOENCODING-}" \
        AC_PYIOENC_SET="${PYTHONIOENCODING+1}" PYTHONIOENCODING=utf-8 python3 -c '
import os, re, shutil, signal, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.environ.get("AC_BR_DIR") or "")
try:
    import bounded_run   # подмена mktemp (D1198); модуля нет — «Проверки» идут без подмены, как прежде
except ImportError:
    bounded_run = None
item_re, done_re = re.compile(os.environ["AC_ITEM_RE"]), re.compile(os.environ["AC_DONE_RE"])
check_re, id_re = re.compile(os.environ["AC_CHECK_RE"], re.M), re.compile(os.environ["AC_ID_RE"])
lib, arch, repo = os.environ["AC_LIB"], os.environ["AC_ARCH"], os.environ["AC_REPO"]
def _int(name, dflt):
    try:
        return max(1, int(os.environ.get(name) or dflt))
    except ValueError:
        return dflt
# Срок одной команды 300 с, а не 120 архиватора: в живом репозитории D220 идёт 242 с, D271 — 223 с.
TO, TOTAL, THREADS = _int("BACKLOG_ARCHIVE_CHECK_TIMEOUT", 300), _int("BACKLOG_ARCHIVE_TOTAL", 3600), _int("BACKLOG_ARCHIVE_THREADS", 3)
# Разбор — по БЛОКУ пункта, как у архиватора: выражение с re.M по тексту блока ловит и многострочную команду
# (построчный разбор её не видел вовсе — живой красный D326, скептик D1147, круг 1, H1). Блок кончается на
# следующем пункте и на заголовке уровня 2–6 — та же граница, что у архиватора (`scripts/backlog-archive.sh`) и
# гейта: строка `# …` с нулевой колонки внутри многострочной команды — комментарий, не заголовок (круг 2, M1). Ключ исхода — место пункта (номер его строки): в архиве 25 повторных
# номеров; одна и та же команда одного номера (копии раздела) исполняется раз (L2).
jobs, undeclared, empty, nocheck, seen, cur, buf = [], [], [], [], set(), None, []
def _flush():
    if not cur:
        return
    text = "".join(buf)
    found = False
    for c in check_re.finditer(text):
        found = True
        e = re.match(r"[ \t]*→[ \t]*([0-9]+)", text[c.end():])
        if (cur[0], c.group(1)) in seen:
            continue
        seen.add((cur[0], c.group(1)))
        if not c.group(1).strip():
            empty.append(cur)
            continue
        (jobs if e else undeclared).append((cur, c.group(1), int(e.group(1)) if e else None))
    if not found:
        nocheck.append(cur)
for no, ln in enumerate(sys.stdin, 1):
    if item_re.match(ln) or re.match(r"#{2,6} ", ln):
        _flush()
        buf, cur = [], None
        m = id_re.search(ln.replace("*", "")) if item_re.match(ln) else None
        if m and done_re.match(ln):   # только ☑: снятый (⊘) не обещал держаться
            cur = (m.group(0), no)
    buf.append(ln)
_flush()
if os.environ.get("AC_LIST") == "1":   # перечень без исполнения (D1283): номер и команда одной строкой
    for (key, cmd, code) in jobs:
        print(key[0] + "\t" + " ".join(cmd.split()))
    sys.exit(0)
ids = {}
for k in [j[0] for j in jobs]:
    ids.setdefault(k[0], set()).add(k[1])
def label(key):   # номер, а при повторе номера — и строка пункта
    return key[0] if len(ids.get(key[0], ())) < 2 else f"{key[0]} (стр. {key[1]})"
# Ограда кольца — правило библиотеки (`backlog_cmd_blocked`/`backlog_cmd_env`), не своя копия.
RING = (". \"$1\" 2>/dev/null && command -v backlog_cmd_blocked >/dev/null 2>&1 || exit 4\n"
        "if why=$(backlog_cmd_blocked \"$2\" check \"$3\" \"$4\"); then printf %s \"$why\"; exit 5; fi\n"
        "backlog_cmd_env \"$2\" check \"$3\" \"$4\"")
T0 = time.monotonic()
REAPF = []   # снятие сессии не состоялось (нет ps) — называется в итоге (скептик D1147, круг 3, L3)
def _reap(sid):
    # Снятие по СЕССИИ, а не по родству (круг 2, M2): команда — вожак своей сессии (start_new_session), а `set -m`
    # даёт потомку новую ГРУППУ, не сессию. Обход `pgrep -P` терял сирот (родитель вышел — родство порвано) и
    # проигрывал гонку с рождающим циклом; номер сессии наследуют и те и другие. Снимается и после штатного
    # выхода: «Проверка» не оставляет живых процессов под следующими. `pkill -s` на macOS нет — обход `ps -A`
    # со сверкой `os.getsid`. НАЗВАННЫЙ ПРЕДЕЛ: потомок, сам вызвавший setsid(), уходит и отсюда.
    for _ in range(5):
        try:
            pids = [int(x) for x in subprocess.run(["ps", "-A", "-o", "pid="], capture_output=True, text=True,
                                                   timeout=10).stdout.split()]
        except Exception:
            REAPF.append(sid)
            return
        hit = 0
        for q in pids:
            if q == os.getpid():
                continue
            try:
                if os.getsid(q) == sid:
                    os.kill(q, signal.SIGKILL)
                    hit += 1
            except OSError:
                pass
        if not hit:
            return
        time.sleep(0.05)
def run(job, solo=False, trace=False):
    iid, raw, exp = job[0][0], job[1], job[2]
    if not solo and time.monotonic() - T0 > TOTAL:
        return job, "total", ""
    try:
        r = subprocess.run(["bash", "-c", RING, "_", lib, arch, iid, raw], capture_output=True, text=True, timeout=30)
    except Exception:
        return job, "ring?", ""
    if r.returncode == 5:
        return job, "ring", r.stdout
    env = dict(os.environ, BACKLOG_CHECKS_NESTED="1")
    env.pop("BACKLOG_RECHECK_ARCHIVE", None)   # путь архива этого прогона «Проверке» не наследуется
    # Кодировку вывода режим ставит СЕБЕ; «Проверке» — та, что была у вызвавшего (круг 2, L2), разметка разбора — нет.
    for k in [k for k in env if k.startswith("AC_")]:
        env.pop(k)
    env.pop("PYTHONIOENCODING", None)
    if os.environ.get("AC_PYIOENC_SET"):
        env["PYTHONIOENCODING"] = os.environ.get("AC_PYIOENC", "")
    if r.returncode == 0:
        env["BACKLOG_CMD_RUNNING"] = r.stdout
    cmd, tracef = raw.strip(), None
    if trace:   # повтор промолчавшей: трасса и во вложенных скриптах, с файлом и строкой (D1201)
        # Глушение в тексте команды съело бы и трассу (она идёт в поток ошибок), а у молчащих красных оно и есть
        # частая форма: `bash probe.sh >/dev/null 2>&1`. Отдельный поток трассы (BASH_XTRACEFD) системный bash 3.2
        # не знает, поэтому в повторе глушение снимается из текста; исход по-прежнему судит первый прогон.
        cmd = re.sub(r"\s*(?:[12]?>|&>)\s*/dev/null(?:\s*2>&1)?", "", cmd)
        env["SHELLOPTS"] = "xtrace"
        env["PS4"] = "+⟪${BASH_SOURCE##*/}:${LINENO}⟫ "
        # Трасса — в безымянный временный файл, читается только хвост: у D269 она 156 МБ (скептик D1201, M1); слова
        # пробы — только поток вывода, без строк-продолжений многострочных значений трассы (M3).
        try:
            tracef = tempfile.TemporaryFile()
        except OSError:
            return job, "start", "файл трассы не создан"
    # Свой TMPDIR на каждую команду (D1198) — как у исполнителя в `hooks/completion-gate.sh`;
    # снимается после команды, в том числе убитой по сроку.
    try:
        tmpd = tempfile.mkdtemp(prefix="rc.")
        env["TMPDIR"] = tmpd
        if bounded_run is not None:
            bounded_run.install_shim(tmpd, env)
    except OSError:
        tmpd = None
    try:
        try:
            p = subprocess.Popen(["bash", "-c", cmd], cwd=repo, env=env, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=tracef or subprocess.STDOUT, start_new_session=True)
        except Exception as ex:
            return job, "start", type(ex).__name__
        try:
            out, _ = p.communicate(timeout=TO)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            # Сама команда вышла, а трубу держит фоновый потомок — исход у команды есть (круг 2, L4).
            done = p.poll()
            _reap(p.pid)
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            # Трубу может держать потомок, ушедший и от сессии: читать её со сроком, а не до конца (круг 1, M2).
            try:
                out, _ = p.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.stdout.close()
                p.wait()
                out = None   # не дочитан: трубу держит потомок, ушедший и из сессии (setsid)
            rc = done if done is not None else "timeout"
        else:
            _reap(p.pid)
    finally:
        if tmpd:
            shutil.rmtree(tmpd, ignore_errors=True)
    if tracef is not None and out is None:
        tracef.close()
    if out is None:
        # Вывод не дочитан — молчала ли проба, неизвестно; красный код без слов не называется молчащим (круг 3, L2).
        if rc == "timeout":
            return job, "timeout", ""   # не вышла — срок, а не «красна» (скептик D1147, круг 4, L2)
        return job, (rc if rc == exp else "lost"), f"код {rc}"
    lines = [x.strip() for x in out.decode("utf-8", "replace").splitlines() if x.strip()]
    if trace:
        # Подсказка, а не слова пробы: исход и метку судит первый прогон (скептик D1201, H1, H2). Одинарных кавычек в
        # этой программе нет и быть не должно: она стоит внутри строки оболочки в одинарных кавычках.
        try:
            tracef.seek(0, 2)
            tracef.seek(max(0, tracef.tell() - 65536))
            tail = tracef.read().decode("utf-8", "replace").splitlines()
        finally:
            tracef.close()
        tr = [re.sub(r"^\++⟪", "⟪", x.strip()) for x in tail if re.match(r"^\++⟪", x.strip())]
        # Строки ловушки EXIT после выхода вытесняли бы значения из хвоста (L3): хвост кончается последним выходом с
        # НЕНУЛЕВЫМ кодом. Нулевой выход вложенного помощника — не конец «Проверки»: живой D474 обрезался на `exit 0`
        # строки 198 прибора, и место падения выпадало (живой прогон 3 ноября 2026).
        ex = [k for k, t in enumerate(tr) if re.match(r"^⟪[^⟫]*⟫ exit [1-9]", t)]
        if ex:
            tr = tr[:ex[-1] + 1]
        parts = ([lines[-1][:140]] if lines else []) + ([" ⏎ ".join(t[:120] for t in tr[-3:])] if tr else [])
        return job, rc, "; трасса: ".join(parts)
    return job, rc, (lines[-1][:140] if lines else "")
with ThreadPoolExecutor(THREADS) as ex:
    results = list(ex.map(run, jobs))
# Красное в потоке подтверждается повтором В ОДИНОЧКУ: тесты со сроками краснеют от соседей (замер 31 октября
# 2026: `test_impact_inject` в три потока — 18 упавших, один — 0). Не подтвердилось — «нестабильна», не откат.
# Повтор идёт мимо общего срока, со своим бюджетом: исчерпанный общий срок иначе отвечал повтору «total», и
# нестабильная оставалась откатом (круг 1, M1). Не исполненный повтор — «не измерено», не откат.
RTOTAL, T1 = _int("BACKLOG_ARCHIVE_RECHECK_TOTAL", 1800), time.monotonic()
quiet = []   # подтверждённые красные, промолчавшие оба раза: им — подсказка повтора с трассой (D1201)
for i, (job, rc, said) in enumerate(results):
    if isinstance(rc, int) and rc != job[2] and rc not in (2, 126, 127):
        if time.monotonic() - T1 > RTOTAL:
            results[i] = (job, "unconfirmed", f"код {rc} в потоке; повтор в одиночку не исполнен — срок повторов {RTOTAL} с (BACKLOG_ARCHIVE_RECHECK_TOTAL)")
            continue
        _, rc2, said2 = run(job, solo=True)
        if rc2 == job[2]:
            results[i] = (job, "flaky", f"код {rc} в потоке, {rc2} в одиночку")
        elif not (isinstance(rc2, int) and rc2 not in (2, 126, 127)):
            results[i] = (job, "unconfirmed", f"код {rc} в потоке, в одиночку — {rc2}")
        elif not said and not said2:
            quiet.append(i)
# Повтор с трассой идёт ПОСЛЕ всех подтверждений и только в остатке бюджета: подтверждение красного важнее
# подсказки, иначе следующие красные становились «?» (скептик D1201, M2).
HINT = {}
for i in quiet:
    if time.monotonic() - T1 > RTOTAL:
        break
    job, rc, _ = results[i]
    _, rc3, tail = run(job, solo=True, trace=True)
    if tail:
        HINT[i] = ("" if rc3 == rc else f"(код {rc3}) ") + tail
items, order = {}, []
for n_i, ((key, raw, exp), rc, said) in enumerate(results):
    disp = " ".join(raw.split())[:90]
    if rc == exp:
        st, why = 0, ""
    elif rc == "timeout":
        st, why = 1, f"не ответила за {TO} с (BACKLOG_ARCHIVE_CHECK_TIMEOUT) — исход неизвестен"
    elif rc == "total":
        st, why = 1, f"не исполнялась: общий срок {TOTAL} с (BACKLOG_ARCHIVE_TOTAL) истёк — исход неизвестен"
    elif rc == "flaky":
        st, why = 1, f"нестабильна ({said}) — исход неизвестен"
    elif rc == "unconfirmed":
        st, why = 1, f"красное не подтверждено ({said}) — исход неизвестен"
    elif rc in ("ring", "ring?", "start"):
        st, why = 1, f"не исполнялась ({said or rc}) — исход неизвестен"
    elif rc == "lost":
        st, why = 1, f"красна ({said}), но вывод не дочитан — трубу держит потомок вне сессии; исход неизвестен"
    elif rc == 2:
        st, why = 1, "не измерила (код 2: рамка не собралась либо прибор не ответил) — исход неизвестен"
    elif rc in (126, 127):
        st, why = 1, f"не запустилась (код {rc}: команды или пробы нет) — проба гнилая, исход неизвестен"
    else:
        # Молчащая на красном проба от гнилой не отличима ничем, кроме своих слов, — и строка говорит это вслух,
        # а не выдаёт молчание за откат с доказательством (круг 1, H2). Тяжесть: говорящий красный (3) важнее
        # молчащего (2) — у пункта с двумя красными «Проверками» слова пробы не прячутся за молчанием (круг 3, M1).
        st, why = (3, f"красна (код {rc}, объявлен {exp})") if said else \
                  (2, f"красна (код {rc}, объявлен {exp}) — откат от гнилой пробы по её выводу не отличить")
    if key not in items:
        order.append(key)
        items[key] = [0, "", 0, 0]
    it = items[key]
    it[2] += 1
    if st >= 2:   # «не держатся» — только красные; «не измерено» сюда не входит (круг 4, L3)
        it[3] += 1
    if st > it[0]:
        it[0], it[1] = st, f"«Проверка» {why}: `{disp}`" + (f" — вывод: {said}" if said and isinstance(rc, int) else "") \
            + (f" — подсказка повтора без глушения, с трассой: {HINT[n_i]}" if n_i in HINT else "")
red = silent = unk = 0
# Метка `[без слов пробы]` — машинная и стоит СРАЗУ за номером пункта, где слова пробы оказаться не могут: по ней
# пересказ и дайджест разводят «откатилось» и «откат или гнилая проба» (решение владельца 31 октября 2026 по H1
# второго скептика D1147; место метки — круг 3, L1). Строка остаётся `✗`: она красна.
SILENT_TAG = "[без слов пробы]"
verbose = bool(os.environ.get("BACKLOG_RECHECK_VERBOSE"))
print(f"«Проверки» закрытых пунктов архива ({arch})")
for key in order:
    st, txt, n, bad = items[key]
    more = f" [не держатся {bad} из {n}]" if n > 1 and bad > 1 else ""
    if st == 3:
        red += 1
        print(f"  ✗ {label(key):<5} {txt}{more}")
    elif st == 2:
        silent += 1
        print(f"  ✗ {label(key):<5} {SILENT_TAG} {txt}{more}")
    elif st == 1:
        unk += 1
        print(f"  ? {label(key):<5} {txt}{more}")
    elif verbose:
        print(f"  ✓ {label(key):<5} «Проверок» {n}, держатся")
for key, raw, _ in undeclared if verbose else []:
    disp = " ".join(raw.split())[:90]
    print(f"  … {key[0]:<5} «Проверка» не объявляет код («→ 0») — не исполнялась: `{disp}`")
for key in empty if verbose else []:
    print(f"  … {key[0]:<5} «Проверка» пуста — не исполнялась")
ran = sum(1 for _, rc, _ in results if rc not in ("total", "ring", "ring?", "start"))
print(f"Исполнено «Проверок»: {ran} из {len(jobs)} у {len(order)} закрытых пунктов за {int(time.monotonic() - T0)} с; "
      f"откатилось пунктов: {red}, красны без слов пробы: {silent}, не измерено: {unk}, "
      f"строк без объявленного кода: {len(undeclared)}, пустых: {len(empty)}, закрытых пунктов без «Проверки»: {len(nocheck)}"
      + ("; процессы «Проверок» по сессии НЕ СНЯТЫ — нет ps" if REAPF else "") + ".")
sys.exit(1 if (red or silent) else 0)
'
    exit $?
fi

BROKEN=0
SILENT=0
UNPROVEN=0
CHECKED=0

# report СТАТУС ПУНКТ ТЕКСТ
report() {
    CHECKED=$((CHECKED + 1))
    case "$1" in
        ok)     [ -n "${BACKLOG_RECHECK_VERBOSE:-}" ] && printf '  ✓ %-5s %s\n' "$2" "$3" ;;
        broken) BROKEN=$((BROKEN + 1)); printf '  ✗ %-5s %s\n' "$2" "$3" ;;
        # Красна, а проба промолчала: откат или гнилая проба — по выводу не различить (D1147, решение владельца
        # 31 октября 2026). Значок `✗` (красна), метка сразу за номером — её читает дайджест; счёт свой.
        silent) SILENT=$((SILENT + 1)); printf '  ✗ %-5s [без слов пробы] %s\n' "$2" "$3" ;;
        # «Нечем проверить» — ТРЕТЬЕ состояние, а не разновидность нарушения. До 10 сентября
        # 2026 оно шло каналом `broken`, и потребитель (knowledge-audit-digest.sh:465 считает
        # строки `^  ✗ `) объявлял владельцу «закрытие ОТКАТИЛОСЬ, верни пункту ☐». Повод: в
        # чистом окружении launchd нет PyYAML, разбор честно пометил все 341 родителя
        # «не прочитан», и сигнал старта сессии сказал неправду о мире — закрытие держалось.
        # Корень R6 из ROOTS.md: два состояния мира отвечали одним значением канала.
        # Молчать здесь тоже нельзя (род B): отказ прибора не есть чистота.
        unproven) UNPROVEN=$((UNPROVEN + 1)); printf '  ? %-5s %s\n' "$2" "$3" ;;
        skip)   printf '  … %-5s %s\n' "$2" "$3" ;;
    esac
    return 0
}

echo "Перепроверка закрытых пунктов долга"

# --- D7: лог инжектов без нечитаемых строк ------------------------------------
# Закрыт разовой чисткой (8508 → 8335). Писатель чинён отдельно, но регрессия санитизации
# вернула бы битые строки молча — счётчик в metrics.md увидит их только при следующем Stop.
LOG="$STATE/injection-log.jsonl"
if [ ! -f "$LOG" ]; then
    report skip "D7" "лога инжектов нет — проверять нечего"
elif ! command -v jq >/dev/null 2>&1; then
    report skip "D7" "нет jq"
else
    _total=$(grep -c '' "$LOG" 2>/dev/null) || _total=0
    _valid=$({ jq -rR 'fromjson? // empty | 1' "$LOG" 2>/dev/null || true; } | grep -c '' || true)
    _bad=$(( _total - _valid ))
    if [ "$_bad" -eq 0 ]; then
        report ok "D7" "лог инжектов: $_total строк, все разбираются"
    else
        report broken "D7" "в логе инжектов снова $_bad нечитаемых строк из $_total"
    fi
fi

# --- D12: двусторонние ссылки кейс ↔ паттерн ----------------------------------
# Закрыт восстановлением 22 ссылок. Держится тестом test_knowledge_link_symmetry.py,
# но тот гоняется только вместе с набором mcp — здесь дешёвая независимая проверка.
if [ ! -d "$LESSONS" ]; then
    report skip "D12" "базы знаний нет"
else
    # Считает РАЗБОРОМ поля `source_cases`, а не вхождением имени в текст родителя
    # (D312). Прежний способ спрашивал `c.name not in par[tgt]`, а имя кейса лежит в
    # файле родителя и помимо `source_cases` — в `provenance_log.trigger_case`, в
    # `related`, в прозе. Замер 5 сентября 2026: подстрока давала 1 нарушение там, где
    # разбор даёт 18. Инвариант вынесен в `hooks/lib/link_symmetry.py`, чтобы у писателя
    # и у приборов был ОДИН ответ: две прежние копии совпадали дословно и ошибались
    # согласованно, то есть их независимость была мнимой.
    # Библиотека ищется там, где она бывает: в репозитории, рядом со скриптом и в
    # установке. Её ОТСУТСТВИЕ — не «чисто», а «не проверено»: неспособность прибора
    # ответить на свой вопрос выдавать за зелёный нельзя (D205, род B).
    _LS_LIB=""
    for _d in "$REPO/hooks/lib" "$(dirname "$0")/../hooks/lib" "$HOME/.claude/hooks/lib"; do
        if [ -f "$_d/link_symmetry.py" ]; then _LS_LIB="$_d"; break; fi
    done
    _asym=$(LIB_DIR="$_LS_LIB" python3 - "$LESSONS" <<'PY' 2>/dev/null || echo "?"
import os, sys
sys.path.insert(0, os.environ["LIB_DIR"])
import link_symmetry as ls
bad, unread = ls.asymmetric(sys.argv[1])
# «Не прочитано» называется отдельно и НЕ выдаётся за чистоту (род B).
print(f"{len(bad)} {len(unread)}")
PY
)
    _asym_bad=${_asym%% *}
    _asym_unread=${_asym##* }
    if [ -z "$_LS_LIB" ]; then
        report unproven "D12" "нет hooks/lib/link_symmetry.py — инвариант НЕ ПРОВЕРЕН"
    elif [ "$_asym" = "?" ]; then
        report skip "D12" "нет python3 или PyYAML — разобрать поле нечем"
    elif [ "$_asym_bad" != "0" ]; then
        report broken "D12" "снова $_asym_bad односторонних ссылок кейс → паттерн"
    elif [ "$_asym_unread" != "0" ]; then
        report unproven "D12" "$_asym_unread родителей не разобрать — чистота НЕ ПОДТВЕРЖДЕНА"
    else
        report ok "D12" "односторонних ссылок нет"
    fi
fi

# --- D27 / D14: поля origin и preceded_artifact описаны в спецификации ---------
# Закрыты правкой META.md. Регрессия возможна: install.sh перезаписывает рабочую копию
# из репозитория, и правка не в том направлении молча пропадает.
META="$REPO/knowledge/META.md"
if [ ! -f "$META" ]; then
    report broken "D27" "нет $META"
else
    _miss=""
    grep -q '^origin:' "$META" || _miss="$_miss origin"
    grep -q '^preceded_artifact:' "$META" || _miss="$_miss preceded_artifact"
    if [ -z "$_miss" ]; then
        report ok "D27" "origin и preceded_artifact описаны в META"
    else
        report broken "D27" "в META снова не описано:$_miss"
    fi
    # Расхождение судится по НАПРАВЛЕНИЮ (D1098, корень R6). Установка кладёт META из
    # репозитория, поэтому копия, не правленная после переноса, просто ждёт переноса и при
    # установке получит правку, а не потеряет её. Пропадёт только правка, сделанная в самой
    # рабочей базе. Это суждение уже имеет владельца — журнал переносов (`lib/carry-log.sh`,
    # `carry_diverged`, ADR-019), им и судим; приёмник, о котором журнал не знает, судить
    # нечем — «не проверено», а не откат. До починки оба состояния шли одним «✗», и сигнал
    # старта 24 и 25 октября 2026 велел вернуть D27 пункту ☐, когда копия отставала на
    # непереносённый коммит.
    if [ -f "$LESSONS/META.md" ] && ! cmp -s "$META" "$LESSONS/META.md"; then
        # shellcheck source=../lib/carry-log.sh
        [ -f "$REPO/lib/carry-log.sh" ] && . "$REPO/lib/carry-log.sh"
        if ! command -v carry_last_hash >/dev/null 2>&1 || [ -z "$(carry_last_hash "$LESSONS/META.md")" ]; then
            report unproven "D27" "META в репозитории и в рабочей базе разошлись, журнал переносов о ней не знает — направление НЕ ПРОВЕРЕНО"
        elif carry_diverged "$META" "$LESSONS/META.md"; then
            report broken "D27" "META в рабочей базе правлена после переноса — правка откатится при установке"
        else
            report ok "D27" "рабочая копия META не правлена после переноса — ждёт переноса, не откат"
        fi
    else
        report ok "D27" "META синхронизирован с рабочей базой"
    fi
fi

# --- D8: у скиллов на месте фразы автовызова ----------------------------------
# Закрыт возвратом фраз. Регрессия вероятна: их снова вырежут при подгонке под длину.
for pair in "entity:что ты знаешь о" "ingest:добавь в базу знаний"; do
    _sk="${pair%%:*}"; _needle="${pair#*:}"
    _f="$REPO/skills/$_sk/SKILL.md"
    if [ ! -f "$_f" ]; then
        report skip "D8" "нет $_f"
    elif grep -qF "$_needle" "$_f"; then
        report ok "D8" "$_sk: фраза автовызова на месте"
    else
        report broken "D8" "$_sk: из описания снова пропала фраза «${_needle}»"
    fi
done

# --- D411: спайка по рёбрам ДАННЫХ не даёт спирали правок ----------------------
# Закрыт вердиктом: спайка из 17 узлов ЗАКОННА по устройству — общий журнал с несколькими
# писателями и читателями, а ребро «читает» идёт от журнала к механизму по потоку данных.
# Вердикт держится числом, а не словом: правка одного механизма спайки не должна тянуть
# ОТВЕТНУЮ правку соседа в ближайших трёх коммитах. Замер при закрытии: состав спайки 14
# файлов дерева, тронуты в 16 коммитах из 300, кандидат в спираль один, и осмотр показал
# разные предметы — настоящих спиралей ноль. Порог: больше одного кандидата.
# ПРОГРАММА ВЫНЕСЕНА ИЗ ПОДСТАНОВКИ. Heredoc внутри `$( … )` bash 5 разбирает иначе, чем
# bash 3.2: на раннере CI он потерял закрывающую скобку («command substitution: … ` || echo
# "?")'») и следом убил скрипт под `set -u` — «_SPIRAL: unbound variable», а с ним три
# соседних инварианта (прогон 34872897131, 14 сентября 2026). Локально дефект невоспроизводим:
# на этой машине bash 3.2. Форма ниже от версии оболочки не зависит.
_SPIRAL_PY=$(mktemp 2>/dev/null) || _SPIRAL_PY=""
if [ -n "$_SPIRAL_PY" ]; then
    cat > "$_SPIRAL_PY" <<'PYSPIRAL'
import json, os, re, subprocess, sys
# СОСТАВ СПАЙКИ ВЫВОДИТСЯ ИЗ КАРТЫ, а не перечисляется: перечень устарел бы в тот же день,
# когда спайка изменится, и инвариант молча судил бы вчерашний набор (род F). Берём самый
# большой кусок и оставляем в нём файлы дерева — журналы правками не двигают.
DATA = "mcp-server/visualization/project-graph-data.json"
try:
    g = json.load(open(DATA, encoding="utf-8"))
except OSError:
    print("NO_MAP")
    sys.exit(0)
except ValueError:
    print("MAP_UNREADABLE")
    sys.exit(0)
# Виды рёбер — ТЕ ЖЕ, что берёт режим --scc прибора карты: исполнение и данные. Первая
# редакция брала ВСЕ виды (пункт, описывает, знание) и выводила спайку из 70 файлов —
# предмет иной, и число вышло про другое (19 из 70 против 0 из 11).
KIND = ("зовёт", "использует", "пишет", "читает", "проверяет")
# РАЗБОР СНИМКА ЦЕЛИКОМ ПОД ОДНИМ ОТКАЗОМ. Ловится не частный `KeyError` одной строки,
# а ЛЮБОЙ отказ разбора: снимок бывает сломан не одним способом, и первая редакция знала
# ровно один — висячее ребро В ЦИКЛЕ. Одностороннее висячее ребро, отсутствующий ключ
# `edges`, ребро без `source`, узел без `id`, `nodes` не списком уходили наружу как «нет
# python3 либо git» (находка скептика 19 сентября 2026). Сам факт, что ЭТОТ КОД
# ИСПОЛНЯЕТСЯ, и есть доказательство того, что инструменты на месте.
try:
    adj, radj = {}, {}
    for e in g["edges"]:
        if not str(e.get("type", "")).startswith(KIND):
            continue
        adj.setdefault(e["source"], set()).add(e["target"])
        radj.setdefault(e["target"], set()).add(e["source"])
    idx = {n["id"]: n for n in g["nodes"]}
    seen, best = set(), set()
    for start in idx:
        if start in seen:
            continue
        fwd, stack = {start}, [start]
        while stack:
            x = stack.pop()
            for y in adj.get(x, ()):
                if y not in fwd:
                    fwd.add(y); stack.append(y)
        back, stack = {start}, [start]
        while stack:
            x = stack.pop()
            for y in radj.get(x, ()):
                if y not in back:
                    back.add(y); stack.append(y)
        comp = fwd & back
        seen |= comp
        if len(comp) > len(best):
            best = comp
    names = {idx[x]["key"] for x in best
             if idx[x].get("key") and os.path.exists(idx[x]["key"])}
except Exception as e:
    # Имя класса — не украшение: читателю решать, пересобирать карту или чинить снимок.
    print("MAP_BROKEN " + type(e).__name__)
    sys.exit(0)
if not names:
    print("EMPTY_COMPONENT")
    sys.exit(0)
log = subprocess.run(["git", "log", "--format=\x1e%H %s", "-n", "300", "--name-only"],
                     capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
commits, hashes, items, cur = [], [], [], None
# `split("\n")`, не `splitlines()`: тот режет и по разделителю записи \x1e, и заголовок коммита терялся.
for line in log.split("\n"):
    if line.startswith("\x1e"):
        cur = set(); commits.append(cur); hashes.append(line[1:41])
        items.append(set(re.findall(r"\bD(\d+)\b", line[42:])))
    elif line.strip() and cur is not None:
        cur.add(line.strip())
touched = sum(1 for c in commits if c & names)
# ОТВЕТ СВЯЗАН С ПРАВКОЙ ПО ДАННЫМ, А НЕ ПО ПОЗИЦИИ (27 октября 2026, D1146). Окно трёх коммитов
# ловит и перемежение независимых серий: e5bd0c4e (D1126) > 74b26847 (D1132) > be37f162 (D1133)
# дали два кандидата, а пункты пар друг на друга не ссылаются — настоящий ответ D1133 («Регресс
# D1126») правит тот же файл, что D1126. Связь «правка вызвана правкой» записана в тексте пункта,
# поэтому пара считается, когда у коммитов общий пункт либо блок пункта одного называет пункт другого
# ИЛИ ЕГО КОММИТ — короткий хеш: ответ здесь чаще всего рождает «Повод (… скептик по <хеш> …)», и без
# хеша 10 причинных пар из 42 в окне уходили в «законна» (скептик D1146, H1).
# НАЗВАННЫЕ ПРЕДЕЛЫ: коммит без номера пункта в заголовке (хоть один из пары) судится позицией, как
# прежде; диапазон «D1142–D1144» в заголовке даёт только крайние номера; связь, записанная словами
# без номера и хеша, не видна.
blocks = {}
for _bf in ("BACKLOG.md", "BACKLOG-archive.md"):
    try:
        _bt = open(_bf, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    _hs = list(re.finditer(r"^- [☐◐☑⊘] \*\*D(\d+)\*\*", _bt, re.M))
    for _k, _m in enumerate(_hs):
        _end = _hs[_k + 1].start() if _k + 1 < len(_hs) else len(_bt)
        blocks[_m.group(1)] = blocks.get(_m.group(1), "") + _bt[_m.start():_end]
def names_other(p, q, h):
    b = blocks.get(p, "")
    return re.search(r"\bD%s\b" % q, b) is not None or h[:7] in b
def related(i, j):
    x, y = items[i], items[j]
    if not x or not y or x & y:
        return True
    return any(names_other(p, q, hashes[j]) for p in x for q in y) \
        or any(names_other(q, p, hashes[i]) for p in x for q in y)
# ОТВЕТ — ПРАВКА СОСЕДА, А НЕ ПРОДОЛЖЕНИЕ РАБОТЫ НАД ТЕМ ЖЕ ФАЙЛОМ (5 октября 2026, D411).
# Прежнее условие `b != a` считало ответом любой следующий коммит с ИНЫМ набором файлов
# спайки, в том числе тот, что правит тот же файл вместе с его тестом либо с соседом по
# своему поводу. Серия починок 4 октября 2026 дала так четыре кандидата при пороге один, и
# осмотр показал: у трёх «ответ» включает исходный файл (five-whys-gate.sh и его тест;
# session-collector.sh и completion-gate.sh как два носителя одного дефекта). Спираль, о
# которой пункт, — сосед вынужден меняться ВСЛЕД, сам исходный файл при этом не трогают.
# НАЗВАННЫЙ ПРЕДЕЛ: ответ, правящий и соседа, и исходный файл разом, в счёт не входит.
# Условие снятия: осмотр назовёт хотя бы одну настоящую спираль такой формы — тогда ответ
# судится по соседу отдельно от исходного файла, и отсечка снимается.
spiral, pairs = 0, []
for i, c in enumerate(commits):
    a = c & names
    if len(a) != 1:
        continue
    for j in range(max(0, i - 3), i):
        b = commits[j] & names
        if b and not (b & a) and related(i, j):
            spiral += 1
            pairs.append(hashes[i][:8] + ">" + hashes[j][:8])
            break
# Первое и последнее слово — числа (их читает оболочка), между ними — пары «правка>ответ»:
# отказ обязан называть кандидатов, иначе осмотр начинается с переписывания этого счёта руками.
print(" ".join([str(spiral)] + pairs + [str(touched)]))
PYSPIRAL
    # НАЛИЧИЕ ИНСТРУМЕНТОВ РЕШАЕТ ОБОЛОЧКА, И РЕШАЕТ ДО ЗАПУСКА. Прежде «инструмента нет»
    # и «инструмент отработал и сказал об отказе» приходили одним значением `"?"`: снаружи
    # упавший интерпретатор неотличим от отсутствующего. Спрашивать надо у того, кто знает,
    # — у `command -v`, а не у кода возврата чужого процесса.
    if ! command -v python3 >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
        _SPIRAL="NO_TOOLS"
    else
        _SPIRAL=$( (cd "$REPO" 2>/dev/null && python3 "$_SPIRAL_PY" 2>/dev/null) || echo "PY_FAILED" )
        [ -n "$_SPIRAL" ] || _SPIRAL="PY_SILENT"
    fi
    rm -f "$_SPIRAL_PY"
else
    _SPIRAL="NO_TMP"
fi
case "$_SPIRAL" in
MAP_BROKEN*)
    report broken "D411" "снимок карты РАЗБИРАЕТСЯ, но НЕ ЦЕЛ (${_SPIRAL#MAP_BROKEN }) — спираль правок посчитана быть не может; пересобери mcp-server/visualization/project-graph-data.json" ;;
NO_MAP)
    report unproven "D411" "снимка карты НЕТ (mcp-server/visualization/project-graph-data.json не собран — обычное состояние свежего клона) — спираль правок НЕ ИЗМЕРЕНА" ;;
MAP_UNREADABLE)
    report broken "D411" "снимок карты НЕ РАЗБИРАЕТСЯ (повреждён JSON) — спираль правок посчитана быть не может" ;;
EMPTY_COMPONENT)
    report unproven "D411" "в наибольшей спайке нет ни одного существующего файла — измерять нечего" ;;
NO_TMP)
    report broken "D411" "не создался временный файл — вложенный разбор карты НЕ ЗАПУСКАЛСЯ" ;;
NO_TOOLS)
    report unproven "D411" "нет python3 либо git — спираль правок НЕ ИЗМЕРЕНА" ;;
PY_FAILED|PY_SILENT)
    report broken "D411" "вложенный разбор карты ОТРАБОТАЛ НЕ ДО КОНЦА (${_SPIRAL}) — исход неизвестен, «чисто» отсюда не следует" ;;
*)
    _sp_n=${_SPIRAL%% *}; _sp_t=${_SPIRAL##* }
    _sp_who=""
    [ "$_SPIRAL" = "$_sp_n $_sp_t" ] || { _sp_who=${_SPIRAL#* }; _sp_who=${_sp_who% *}; }
    if [ "${_sp_t:-0}" -eq 0 ]; then
        report unproven "D411" "спайку не трогали ни разу за 300 коммитов — измерять нечего"
    elif [ "${_sp_n:-0}" -gt 1 ]; then
        report broken "D411" "ответных правок внутри спайки снова $_sp_n из $_sp_t — спираль появилась; кандидаты (правка>ответ): ${_sp_who:-не названы}"
    else
        report ok "D411" "спайка данных законна: ответных правок $_sp_n из $_sp_t коммитов"
    fi ;;
esac

# --- D13: блокер-уровень с проверяемыми сигналами -----------------------------
# Закрыт поднятием pattern-shell-portability. Регрессия: сигналы сотрут или сломают JSON,
# и блокер станет украшением в frontmatter.
_sp="$LESSONS/pattern-shell-portability.md"
if [ ! -f "$_sp" ]; then
    report skip "D13" "знания нет в рабочей базе"
elif ! grep -q '^blocker: true' "$_sp"; then
    report broken "D13" "pattern-shell-portability больше не блокер-уровня"
else
    _sig=$(python3 - "$_sp" <<'PY' 2>/dev/null || echo "?"
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r"detection_signals: \|\n((?:  .*\n)+)", t)
if not m:
    print("0"); raise SystemExit
try:
    print(len(json.loads("".join(l[2:] for l in m.group(1).splitlines(True)))))
except Exception:
    print("bad")
PY
)
    case "$_sig" in
        0)   report broken "D13" "у блокера пустые detection_signals — срабатывать нечему" ;;
        bad) report broken "D13" "detection_signals не разбираются как JSON" ;;
        "?") report skip   "D13" "нет python3" ;;
        *)   report ok     "D13" "блокер жив, сигналов: $_sig" ;;
    esac
fi

# --- D1147: «Проверки» закрытых пунктов архива — итог замера archive-checks ---------
# Исполняет их режим `--archive` (шапка выше) из реестра замеров; здесь — только чтение его
# последнего вывода, и каждый пункт оттуда называется своей строкой: дайджест считает `✗` и
# берёт имена. Итога нет либо он неполон — «не проверено», а не «держится» (род B).
_AC_OUT="$STATE/measurement-runs/archive-checks.out"
if [ ! -f "$REPO/BACKLOG-archive.md" ]; then
    report skip "D1147" "архива нет — «Проверки» закрытых исполнять нечего"
elif [ "${BACKLOG_CHECKS_NESTED:-0}" = "1" ]; then
    # Внутри «Проверки» пересказ чужих закрытий не судится: «Проверка» D202 (этот же скрипт → 0), исполненная
    # режимом `--archive`, краснела от прошлого итога чужих пунктов (скептик D1147, круг 1, M3).
    report skip "D1147" "внутри «Проверки» пересказ «Проверок» архива не судится"
elif [ ! -s "$_AC_OUT" ]; then
    report unproven "D1147" "«Проверки» архива не исполнялись: нет итога замера archive-checks ($_AC_OUT) — исход закрытий в архиве НЕИЗВЕСТЕН"
elif ! grep -q '^Исполнено «Проверок»' "$_AC_OUT"; then
    report unproven "D1147" "итог замера archive-checks неполон (прогон идёт либо оборвался) — исход закрытий в архиве НЕИЗВЕСТЕН"
elif ! grep -qE '^Исполнено «Проверок»: [0-9]+ из [0-9]+ .*красны без слов пробы: ' "$_AC_OUT"; then
    # Итог старого формата — молчащие в нём не размечены (либо метка не на своём месте), и пересказ назвал бы каждую
    # «откатилось» (скептик D1147, круг 3, H1: живой снимок круга 1 дал бы 43 «откатилось» при 12 говорящих). Признак
    # нового формата — счёт «красны без слов пробы:», которого до круга 4 не печатал никто (круг 4, L1).
    report unproven "D1147" "итог замера archive-checks старого формата (молчащие пробы не размечены) — перемерь: bash scripts/backlog-recheck.sh --archive, итог — на место $_AC_OUT"
else
    _ac_when=$(date -r "$_AC_OUT" +%F 2>/dev/null) || _ac_when="дата неизвестна"
    _ac_n=0
    while IFS= read -r _ac_l; do
        _ac_n=$((_ac_n + 1))
        # Значок снимается литералом в кавычках: `?` без кавычек — шаблон одного символа, а ✗ под
        # локалью C — три байта.
        case "$_ac_l" in
            "  ✗ "*) _ac_kind=broken;   _ac_rest=${_ac_l#"  ✗ "} ;;
            *)       _ac_kind=unproven; _ac_rest=${_ac_l#"  ? "} ;;
        esac
        _ac_id=${_ac_rest%% *}
        _ac_txt=${_ac_rest#"$_ac_id"}
        _ac_txt=${_ac_txt#"${_ac_txt%%[![:space:]]*}"}
        # Повтор номера несёт «(стр. N)» до метки; метка — только на своём месте, не в словах пробы.
        _ac_pre=""
        case "$_ac_txt" in "(стр. "*) _ac_pre="${_ac_txt%%)*}) "; _ac_txt=${_ac_txt#"$_ac_pre"} ;; esac
        if [ "$_ac_kind" = broken ]; then
            case "$_ac_txt" in "[без слов пробы] "*) _ac_kind=silent; _ac_txt=${_ac_txt#"[без слов пробы] "} ;; esac
        fi
        report "$_ac_kind" "$_ac_id" "${_ac_pre}архив, прогон ${_ac_when}: ${_ac_txt}"
    done < <(grep -E '^  (✗|\?) ' "$_AC_OUT")
    [ "$_ac_n" -eq 0 ] && report ok "D1147" "«Проверки» закрытых пунктов архива держатся (прогон ${_ac_when})"
    # Счёт исполненного и неисполнимого называется всегда: строки без кода и закрытые без «Проверки» молча
    # шли бы держащимися (круг 1, L4).
    report skip "D1147" "архив, прогон ${_ac_when}: $(grep -m1 '^Исполнено «Проверок»' "$_AC_OUT")"
fi

# --- Итог ---------------------------------------------------------------------
echo ""
# «Не проверено» называется ВСЕГДА и отдельной строкой — и при зелёном итоге тоже:
# невысказанная непроверенность читается как чистота (род B).
[ "${UNPROVEN:-0}" -gt 0 ] && \
    echo "Не проверено: $UNPROVEN — прибор не смог ответить на свой вопрос (это НЕ откат закрытия)."
# Красные без слов пробы — своей строкой и не «перестали держаться»: откат или гнилая проба, по выводу не различить
# (D1147, решение владельца 31 октября 2026; скептик, круг 3, M2). Повода `resurrected` они не заводят: его читают
# как провал контрмеры (`hooks/disagreement-lib.sh`), а здесь провал не доказан. Код выхода красный при любом красном.
[ "${SILENT:-0}" -gt 0 ] && \
    echo "Красны без слов пробы: $SILENT — откат или гнилая проба, по выводу не различить; разбери по самой «Проверке» (гнилую — починкой пробы, откат — новым пунктом со ссылкой на прежний)."
if [ "$BROKEN" -eq 0 ] && [ "${SILENT:-0}" -gt 0 ]; then
    echo "Инвариантов проверено: $CHECKED, откатов со словами пробы нет."
elif [ "$BROKEN" -eq 0 ]; then
    echo "Инвариантов проверено: $CHECKED, все держатся."
else
    echo "Инвариантов проверено: $CHECKED, ПЕРЕСТАЛИ ДЕРЖАТЬСЯ: $BROKEN."
    echo "Пункт, чей инвариант сломан, снова открыт — верни ему ☐ в BACKLOG.md (пункт архива — новым пунктом со ссылкой на прежний)."
    # Воскресшее закрытие — повод разбора (D202). Повторение дефекта ПОСЛЕ контрмеры есть
    # провал самой контрмеры, то есть сильнейший из поводов; прежде он проходил строкой
    # отчёта, и разбора «почему закрытие не удержалось» не требовалось ни от кого.
    _RC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../hooks" 2>/dev/null && pwd)/root-cause-lib.sh"
    [ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
    if [ -f "$_RC_LIB" ]; then
        # shellcheck source=/dev/null
        . "$_RC_LIB"
        rc_note_event "${STATE_DIR:-$HOME/.claude/hooks/state}" "resurrected" \
            "инвариантов перестало держаться: $BROKEN"
    fi
fi
[ "$BROKEN" -eq 0 ] && [ "${SILENT:-0}" -eq 0 ]
