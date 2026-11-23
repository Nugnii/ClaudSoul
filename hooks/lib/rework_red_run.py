#!/usr/bin/env python3
# rework_red_run.py <расшифровка> <файл> [окно, с] [до, ISO] — был ли КРАСНЫЙ прогон между двумя последними правками
# файла. «До» — повтор на время исхода: записи расшифровки позже него не читаются (повтор подсказки по журналу исходов —
# вместо журнала случаев, снятого 22 ноября 2026, D1303).
# Печатает «red<TAB>улика», если две последние правки файла не дальше «окна» секунд друг от друга и между ними есть
# результат оболочки с ошибкой (флаг `is_error` либо признак провала в тексте); иначе — ничего. Код 0.
#
# Зачем (D1303, 16 ноября 2026, решение владельца — подсказка, а не отказ). Эталонная выборка 25 поводов переработки
# ProjectA (чтение хода): «показалось» ошибочно у 8 из 15 — развороты после упавшего прогона, снятые доводом «правка
# инструмента, не продукта». Признак «красный прогон между заходами не дальше 10 минут» — у 10 из 14 разворотов и у 0 из
# 11 остальных. Выборка мала, поэтому прибор исходов говорит, а не отказывает. Живая выборка 22 ноября 2026 (40 случаев с
# красным прогоном за 14 дней, слепое чтение хода): разворот в 22, шаг плана в 13, шаг протокола в 3 — точность около
# половины, признак остаётся поводом, а не вердиктом.
# Отказ стража — НЕ прогон и НЕ правка (D1303, 22 ноября 2026): вызов не исполнен, а флаг `is_error` харнесс ставит и ему.
# Правкой отказанный вызов тоже не был: в живой выборке у 11 случаев из 40 первая из двух «правок» отказана и повторена
# дословно — без отказа там одна правка. В живом
# журнале подсказок 26 из 50 стояли на тексте отказа, чаще всего самого стража разбора («Правка не пройдёт, пока у повода
# нет названного исхода») — подсказка брала уликой следствие повода, который судит. Имя «вызов отказан стражем» берётся у
# владельца (`deny_mark.py` ← `deny-mark-lib.sh`), а не литералом здесь; спросить нечем — код 2 и тишина: отказы, молча
# сосчитанные прогонами, дали бы ложную подсказку.
# Предел: красный прогон, чей вывод обрезан трубой (`| tail`) до строк без признака и с кодом 0, не виден. Прочие
# неисполненные вызовы (запрет прав, `<tool_use_error>`, отказ пользователем) владельцем не названы и всё ещё считаются
# прогоном с кодом не 0: на 22 ноября 2026 среди подсказок их 0 из 50, в 300 свежих расшифровках — около 130 из 4 200
# ошибочных результатов против 2 980 отказов стражей.
import json
import os
import re
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)   # под `python3 -I` каталог скрипта в путь не входит
from deny_mark import DenyMarkUnavailable, is_denial  # noqa: E402
from write_targets import heads  # noqa: E402

# ПРОГОН — ПО ВЛАДЕЛЬЦУ, А НЕ ВСЯКИЙ РЕЗУЛЬТАТ ОБОЛОЧКИ (D1303, скептик opus 22 ноября 2026, M1). Пропущенный отказ
# отдавал улику следующему результату с признаком провала, а он часто тоже не прогон: `×` из `sed -n … BACKLOG.md`,
# `FAILED` из `git diff`, вывод самого прибора исходов (его подсказка «КРАСНЫЙ прогон (TimeoutError)» и отказ «исход не
# записан», код 3). Что команда — прогон, решает детектор переработки (D1330): слова команд даёт разбор (`heads`), перечень
# читающих программ — строка присваивания в `rework-detector.sh`; здесь её ЧТЕНИЕ, как у `deny_mark.py`, а не копия.
# Прибор исходов прогоном не считается: его вывод — о поводе, а не о работе. Детектор считает его прогоном (перечень судит
# программу, а у `bash scripts/outcome.sh` программа — `bash`); это записано в D1303 пределом детектора.


class RunOwnerUnavailable(RuntimeError):
    """Перечень «не прогон» не прочитан: владельца нет либо строка не разобрана."""


_lists = None


def _not_a_run():
    global _lists
    if _lists is not None:
        return _lists
    repo = os.environ.get("CLAUDSOUL_REPO") or os.environ.get("CLAUDSOUL_ROOT")
    for p in [os.path.join(HERE, os.pardir, "rework-detector.sh")] + \
            ([os.path.join(repo, "hooks", "rework-detector.sh")] if repo else []) + \
            [os.path.expanduser("~/.claude/hooks/rework-detector.sh")]:
        try:
            src = open(p, encoding="utf-8").read()
        except OSError:
            continue
        got = []
        for name in ("RW_NOT_A_RUN", "RW_GIT_NOT_A_RUN"):
            m = re.search(r'^%s="((?:[^"\\]|\\\n)*)"' % name, src, re.M)
            got.append(set(m.group(1).replace("\\\n", " ").split()) if m else None)
        if all(got):
            _lists = tuple(got)
            return _lists
    raise RunOwnerUnavailable("перечень «не прогон» у rework-detector.sh не найден либо не разобран")


def is_run(cmd):
    """Команда проверяет результат: есть простая команда не из читающих по перечню детектора и не вызов прибора исходов.
    Разбор не ответил — прогон, как было до D1330 (предел владельца: пусто и «команд нет» у него один ответ)."""
    hs = heads(cmd or "")
    if not hs:
        return True
    not_run, git_not = _not_a_run()
    for h in hs:
        w = h.split("\t")
        if any(os.path.basename(x) == "outcome.sh" for x in w[:2]):
            continue
        prog = os.path.basename(w[0])
        if prog == "git":
            if len(w) < 2 or w[1] not in git_not:
                return True
        elif prog not in not_run:
            return True
    return False

RED = re.compile(r"\bFAIL(?:ED)?\b|✗|×|error TS\d+|TimeoutError|Timeout \d|\b[1-9]\d* failed\b|Traceback \(most recent"
                 r"|AssertionError|упало [1-9]")
WRITE = re.compile(r">|sed -i|perl -i|\btee\b|write_text|open\(")


def ts(e):
    t = e.get("timestamp") or ""
    try:
        return datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""


def red_evidence(body):
    m = RED.search(body)
    return m.group(0) if m else None


def parse(tr):
    """ОДИН проход по расшифровке — события без привязки к файлу повода: вызовы, правки оболочкой, отказы, красные
    результаты прогонов. Повтор по журналу исходов (`--batch`) спрашивает про все поводы сессии по одному проходу:
    расшифровки ProjectA за 14 дней — 821 МБ, разбор каждой на каждый повод не уложился бы в срок «Проверки»."""
    lines = open(tr, encoding="utf-8", errors="replace").read().splitlines()
    stamps = []   # (порядок, время записи) — для среза
    evs = []      # (порядок, время, вид, id, данные)
    uses = {}
    cmds = {}
    for k, raw in enumerate(lines):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        t = ts(e)
        stamps.append((k, t))
        content = (e.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        if e.get("type") == "assistant":
            for x in content:
                if not isinstance(x, dict) or x.get("type") != "tool_use":
                    continue
                name, inp = x.get("name"), x.get("input") or {}
                uses[x.get("id")] = name
                cmd = (inp.get("command") or "") if name == "Bash" else ""
                if name == "Bash":
                    cmds[x.get("id")] = cmd
                evs.append((k, t, "use", x.get("id"), (name, inp.get("file_path"), cmd)))
        elif e.get("type") == "user":
            r = e.get("toolUseResult")
            if isinstance(r, dict) and isinstance(r.get("bashEditDiff"), dict):
                files = [f.get("filePath") for f in r["bashEditDiff"].get("files") or [] if isinstance(f, dict)]
                evs.append((k, t, "bed", None, files + list(r["bashEditDiff"].get("changedFiles") or [])))
            for x in content:
                if not isinstance(x, dict) or x.get("type") != "tool_result":
                    continue
                body = text_of(x.get("content"))
                if x.get("is_error") and is_denial(body):
                    evs.append((k, t, "deny", x.get("tool_use_id"), None))  # не исполнен — ни правка, ни прогон
                    continue
                if uses.get(x.get("tool_use_id")) != "Bash":
                    continue
                ev = red_evidence(body)
                if (x.get("is_error") or ev) and is_run(cmds.get(x.get("tool_use_id"), "")):
                    ev = ev or (body.strip().splitlines() or ["код не 0"])[0][:80]
                    evs.append((k, t, "red", x.get("tool_use_id"), ev))
    return stamps, evs


def judge(stamps, evs, path, win=600.0, cut=None):
    """«red<TAB>улика» либо пусто — для файла повода, по записям не позже среза."""
    stop = float("inf")
    if cut is not None:
        # Расшифровка дописывается по времени: дальше первой записи позже среза не читается (предел L1 скептика D1303).
        stop = next((k for k, t in stamps if (t or 0) > cut), stop)
    edits, denied, results = [], set(), []
    for k, t, kind, i, d in evs:
        if k >= stop:
            break
        if kind == "use":
            name, fp, cmd = d
            if name in ("Edit", "Write", "MultiEdit") and fp == path:
                edits.append((k, t, i))
            elif name == "Bash" and path in cmd and WRITE.search(cmd):
                # Прогон спеки тоже называет путь файла — правкой считается только команда с признаком записи.
                edits.append((k, t, i))
        elif kind == "bed":
            if path in d:
                edits.append((k, t, None))
        elif kind == "deny":
            denied.add(i)
        elif kind == "red":
            results.append((k, t, d))
    edits = sorted((k, t) for k, t, i in edits if i is None or i not in denied)
    if len(edits) < 2:
        return ""
    (a, ta), (b, tb) = edits[-2], edits[-1]
    # Окно — промежуток МЕЖДУ ПРАВКАМИ, как в эталонной выборке («две правки не дальше 10 минут друг от друга и красный
    # прогон между ними»), а не давность прогона до второй правки: первая редакция брала второе, и в живой сессии правки
    # seed с промежутком 3,5 часа получили подсказку по чужому FAIL набора тестов за полчаса до второй правки.
    if ta is not None and tb is not None and tb - ta > win:
        return ""
    for k, t, ev in results:
        if a < k < b:
            return "red\t" + ev.replace("\t", " ").replace("\n", " ")
    return ""


def main():
    # --batch <расшифровка> [окно]: на вход строки «файл<TAB>срез», на выход по строке ответа на каждую (пустая — нет).
    if len(sys.argv) > 2 and sys.argv[1] == "--batch":
        win = float(sys.argv[3]) if len(sys.argv) > 3 else 600.0
        try:
            stamps, evs = parse(sys.argv[2])
        except OSError:
            stamps, evs = [], []
        out = []
        for q in sys.stdin.read().splitlines():
            path, _, c = q.partition("\t")
            out.append(judge(stamps, evs, path, win, ts({"timestamp": c}) if c else None))
        sys.stdout.write("".join(x + "\n" for x in out))
        return 0
    if len(sys.argv) < 3:
        return 0
    tr, path = sys.argv[1], sys.argv[2]
    win = float(sys.argv[3]) if len(sys.argv) > 3 else 600.0
    cut = ts({"timestamp": sys.argv[4]}) if len(sys.argv) > 4 else None
    try:
        stamps, evs = parse(tr)
    except OSError:
        return 0
    r = judge(stamps, evs, path, win, cut)
    if r:
        print(r)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (DenyMarkUnavailable, RunOwnerUnavailable) as e:
        print("rework_red_run: не измерено — %s" % e, file=sys.stderr)
        sys.exit(2)
