#!/usr/bin/env python3
# self-repeat-replay.py — агент сам назвал повтор: последовал ли разбор.
#
# Результат: названа доля произнесений маркера повтора в собственной речи («N-й раз», «второй раз
#            подряд», «тот же класс»), после которых в том же ходе не было цепочки разбора, —
#            отдельно до и после 13 сентября 2026, когда маркер стал поводом гейта (D325)
# Проверка результата: python3 scripts/self-repeat-replay.py печатает обе доли и даёт 0; 1 — доля без
#            разбора ПОСЛЕ границы выше половины при десяти и более произнесениях (находка); 2 — корпуса
#            нет либо реплей не прошёл собственный контроль
#
# Зачем (D325, корень R2). Замер 6 сентября 2026 по одной расшифровке: блоков речи 350, с маркером
# повтора 20, настоящих 15, разбор последовал в двух-трёх. Фраза «это пятый раз за день» звучала
# как честность и работала как закрытие темы — потребителя у неё не было. С 13 сентября маркер —
# повод гейта (`hooks/five-whys-gate.sh`, срод `self_repeat`, стоячий). Этот реплей отвечает, что
# изменилось: доля произнесений без разбора ДО границы и ПОСЛЕ неё, по тем же расшифровкам.
#
# СЛОВАРЬ И ОПРЕДЕЛЕНИЕ ЦЕПОЧКИ НЕ КОПИРУЮТСЯ (род K). Маркер — RC_SELF_REPEAT_RE из
# hooks/root-cause-lib.sh, читается источением библиотеки; след считает rc_trace_text, вердикт
# выносит rc_chain_spoken — обе вызовом. Своя копия формулы разошлась бы с оригиналом молча.
#
# ЕДИНИЦА — ПРОИЗНЕСЕНИЕ, а не ход: один ход может назвать повтор дважды. Цепочка ищется от
# произнесения ДО КОНЦА ХОДА (окно до следующей живой реплики владельца): вопрос — «последовал
# ли разбор». Гейт судит шире, по всему окну хода, и это его названный предел; здесь счёт по
# всему ходу давал 19% «без разбора» при ручном замере около 85% — свойство длины хода, а не
# доля. Ход без живой реплики владельца в начале (хвост обрезанной расшифровки) считается с
# начала файла.
#
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ идёт ДО замера и обязателен: подложный ход с маркером и цепочкой обязан
# считаться «с разбором», подложный ход с маркером без цепочки — «без». Не так — реплей сломан,
# и числа корпуса ничего не значат (образец — scripts/ab-authorization-replay.sh).
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. Точность маркера 75% (замер 6 сентября): четверть произнесений — ложные, и
# доля «без разбора» у них по построению высока; реплей их не отличает, поэтому число — верхняя
# граница. Условие снятия: у произнесения появится вердикт о ложности рядом с записью исхода
# (`self_repeat` в журнале outcomes) — тогда доля считается по настоящим.
import glob
import json
import os
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(os.environ.get("CLAUDSOUL_REPO") or pathlib.Path(__file__).resolve().parents[1])
LIB = REPO / "hooks" / "root-cause-lib.sh"
CORPUS = os.environ.get("FWG_REPLAY_CORPUS") or os.path.expanduser("~/.claude/projects/*/*.jsonl")
LIMIT = int(os.environ.get("SELF_REPEAT_TRANSCRIPTS", "80"))
SINCE = os.environ.get("SELF_REPEAT_SINCE", "2026-09-13")
MIN_N = int(os.environ.get("SELF_REPEAT_MIN_N", "10"))


def lib_var(name):
    r = subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1; printf "%s" "${' + name + ':-}"', "_", str(LIB)],
                       capture_output=True, text=True)
    return r.stdout


def chain_spoken(turn_text):
    """Вердикт библиотеки: след rc_trace_text по тексту хода, решение rc_chain_spoken."""
    r = subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1; t=$(rc_trace_text); rc_chain_spoken "$t" "${FIVE_WHYS_MIN:-3}"',
                        "_", str(LIB)], input=turn_text, capture_output=True, text=True)
    return r.returncode == 0


def is_live_user(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return bool(c.strip())
    return any(isinstance(x, dict) and x.get("type") == "text" for x in (c or []))


def turns(path):
    """Ходы файла: список (тексты агента с датами). Граница — живая реплика владельца."""
    out, cur = [], []
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return out
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        msg = rec.get("message") or {}
        t = rec.get("type") or msg.get("role")
        if t == "user" and is_live_user(msg):
            if cur:
                out.append(cur)
            cur = []
            continue
        if t == "assistant":
            ts = (rec.get("timestamp") or "")[:10]
            for x in msg.get("content") or []:
                if isinstance(x, dict) and x.get("type") == "text" and x.get("text"):
                    cur.append((ts, x["text"]))
    if cur:
        out.append(cur)
    return out


def main():
    if not LIB.is_file():
        print(f"нет библиотеки {LIB} — не измерено"); return 2
    rx_src = lib_var("RC_SELF_REPEAT_RE")
    if not rx_src:
        print("RC_SELF_REPEAT_RE пуст — словарь маркера не прочитан у владельца, не измерено"); return 2
    rx = re.compile(rx_src, re.IGNORECASE)
    # Отрицательный контроль реплея — ДО чтения корпуса.
    with_chain = ("Это третий раз за день. Почему падает — читается старый индекс (mcp-server/indexer.py:231). "
                  "Почему старый — add шёл после. Почему не поймали — тест брал фикстуру.")
    without = "Это третий раз за день, когда тест падает на той же строке. Чиню."
    if not (rx.search(with_chain.lower()) and rx.search(without.lower())):
        print("КОНТРОЛЬ НЕ ПРОЙДЕН: словарь не узнаёт подложный маркер — реплей сломан"); return 2
    if not chain_spoken(with_chain) or chain_spoken(without):
        print("КОНТРОЛЬ НЕ ПРОЙДЕН: вердикт цепочки не различает подложные ходы — реплей сломан"); return 2
    files = sorted(glob.glob(CORPUS), key=lambda p: os.path.getmtime(p), reverse=True)[:LIMIT]
    if not files:
        print(f"корпуса нет ({CORPUS}) — замерять нечего"); return 2
    before = {"n": 0, "no": 0}
    after = {"n": 0, "no": 0}
    for f in files:
        for turn in turns(f):
            hits = [i for i, (ts, txt) in enumerate(turn) if rx.search(txt.lower())]
            if not hits:
                continue
            for i in hits:
                # Цепочка ищется ПОСЛЕ произнесения, до конца хода: вопрос замера — «последовал ли
                # разбор», а не «был ли он где-то в ходе». Длинный автономный ход почти всегда
                # несёт цепочку о чём-нибудь раньше; счёт по всему ходу давал 19% «без разбора»
                # при ручном 6 сентября около 85% — это была не доля, а свойство длины хода.
                spoken = chain_spoken("\n".join(txt for _, txt in turn[i:]))
                ts = turn[i][0]
                bucket = after if ts and ts >= SINCE else before
                bucket["n"] += 1
                if not spoken:
                    bucket["no"] += 1
    total = before["n"] + after["n"]
    print(f"Маркер повтора в собственной речи (расшифровок {len(files)}, произнесений {total}):")

    def row(label, b):
        share = (b["no"] * 100 // b["n"]) if b["n"] else 0
        print(f"  {label}: произнесений {b['n']}, без разбора в том же ходе {b['no']} ({share}%)")
        return share

    row(f"до {SINCE}", before)
    share_after = row(f"с  {SINCE}", after)
    if total == 0:
        print("  маркеров в корпусе нет — доля не определена"); return 0
    if after["n"] >= MIN_N and after["no"] * 2 > after["n"]:
        print("[замер: находки, не сбой] после того, как маркер стал поводом, больше половины произнесений всё ещё без разбора")
        return 1
    if after["n"] < MIN_N:
        print(f"  после границы мало данных ({after['n']} < {MIN_N}), решения не принимаются")
    return 0


if __name__ == "__main__":
    sys.exit(main())
