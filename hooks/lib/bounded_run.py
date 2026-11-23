"""bounded_run.py — исполнение чужой команды со сроком: одно правило для питонских исполнителей.

Результат: команда (`bash -c`), не уложившаяся в срок или прерванная (Ctrl-C, сигнал исполнителя), снимается вместе
           со всеми потомками, а её TMPDIR — после них; у всех исполнителей одним правилом, а не копиями
Проверка результата: bash hooks/tests/fixtures/probe_D1199.sh даёт 0

Зовут: `hooks/completion-gate.sh` («Проверки» на Stop), `scripts/backlog-archive.sh` (закрытые при переносе),
`scripts/backlog-refresh-readings.sh` («Показания»), `scripts/named-limits.py` («Проверки снятия»), `scripts/root-map.py`
(пробы корней) и `scripts/docs-refresh-claims.sh` (источники чисел документов, D1239). До D1199 у первых
трёх стояло по копии шести строк (D1180), у четвёртого — `subprocess.run(…, timeout=)`, снимавший только `bash -c`:
копии разошлись, и внуки «Проверки снятия» жили после срока.
Устройство — у сверщика `scripts/backlog-recheck.sh`: команда — вожак своей сессии, снимается её группа. Свой TMPDIR
на каждую команду — D1198: пробы создают каталоги и не убирают, а исполнители идут на каждом Stop.
НАЗВАННЫЙ ПРЕДЕЛ: потомок, сам ушедший в свою группу (`set -m`) или сессию (`setsid`), группой не снимается, и после
штатного выхода команды живые потомки не снимаются (D1180, M2 и L2: в «Проверках» таких форм 0 и 1 из 542). Сверщик
снимает и их — обходом `ps -A` по номеру сессии; здесь этого нет.
Условие снятия: в «Проверках» или «Показаниях» появится форма `set -m`/`setsid` либо фоновый потомок без `wait`.
"""
import os
import shutil
import signal
import subprocess
import tempfile


def trap_signals():
    """SIGTERM и SIGHUP исполнителя — выход исключением, и `run_bounded` успевает снять группу команды: у неё своя сессия, сигнал
    группы исполнителя до неё не доходит (D1180, H1 скептика). Зовётся исполнителем один раз, до первой команды."""
    def _exit(n, f):
        raise SystemExit(128 + n)
    for s in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, _exit)


def install_shim(tmpd, env):
    """Подмена `mktemp` в каталоге команды (D1198): на macOS голая форма `mktemp [-d]` и `-t` берут системный каталог
    при любом TMPDIR. Копия `mktemp-shim.sh` рядом с модулем → `<tmpd>/.bin/mktemp`, каталог первым в PATH; файла нет —
    команда идёт как прежде. Оболочечная половина — `cmd_tmpdir_shim` в `hooks/timeout-lib.sh`, файл подмены один."""
    b = os.path.join(tmpd, ".bin")
    try:
        os.mkdir(b)
        shutil.copyfile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "mktemp-shim.sh"), os.path.join(b, "mktemp"))
        os.chmod(os.path.join(b, "mktemp"), 0o755)
    except OSError:
        return
    env["PATH"] = b + os.pathsep + env.get("PATH", "")


def run_bounded(cmd, timeout, *, cwd, env, prefix, capture=False, errors=None):
    """`bash -c cmd` со сроком → CompletedProcess (stdout/stderr — текст при capture, иначе None).

    Срок истёк — TimeoutExpired, как у `subprocess.run`; ветки исполнителей не меняются. Любое исключение (срок,
    KeyboardInterrupt, SystemExit из обработчика сигнала) сперва снимает группу команды, потом уходит выше. Каталог
    TMPDIR не создался — команда идёт с унаследованным, как шла до D1198.
    """
    env = dict(env)
    try:
        tmpd = tempfile.mkdtemp(prefix=prefix)
        env["TMPDIR"] = tmpd
        install_shim(tmpd, env)
    except OSError:
        tmpd = None
    out = subprocess.PIPE if capture else subprocess.DEVNULL
    try:
        # `errors` — у захваченного текста (D1239: пробы корней грепают файлы не в UTF-8, `errors="replace"`).
        p = subprocess.Popen(["bash", "-c", cmd], cwd=cwd, env=env, stdout=out, stderr=out,
                             text=capture, errors=errors if capture else None, start_new_session=True)
        try:
            o, e = p.communicate(timeout=timeout)
        except BaseException:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            p.wait()
            for f in (p.stdout, p.stderr):
                if f:
                    f.close()
            raise
        return subprocess.CompletedProcess(p.args, p.returncode, o, e)
    finally:
        if tmpd:
            shutil.rmtree(tmpd, ignore_errors=True)
