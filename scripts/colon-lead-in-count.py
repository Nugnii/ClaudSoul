#!/usr/bin/env python3
# Результат: ПРИБОР, не инструмент. Число реплик с зачином-двоеточием. Решение, которое оно меняет: порог длины у классификатора состояния (D92, закрыт 2026-08-28); срок — при росте доли пересылок
# Проверка результата: python3 scripts/colon-lead-in-count.py — счёт напечатан
#
"""Счёт реплик собеседника с зачином-двоеточием — замер под BACKLOG D92.

D92: реплика вида «вот вывод:» с приложенным чужим логом короче 500 символов проходит
классификатор состояния целиком, и слова из чужого лога дают `stuck`. Решение отложено до
выборки в десять таких реплик: на трёх наблюдениях доля пересылок среди них — догадка.

Пункт предписывал добавить счёт «одной строкой» в scripts/meta-contamination.py. Проверка
27 августа 2026: тот скрипт читает документы репозитория и до транскриптов не доходит
вовсе — назначенный замер структурно не мог дать это число. Отсюда отдельный файл.

Признак зачина: первая непустая строка реплики короче 80 символов, кончается двоеточием,
и после неё есть ещё содержимое. Признак наблюдаемый, суждения не требует.

Запуск: python3 scripts/colon-lead-in-count.py [--verbose]
Вывод: число реплик; при --verbose — первые строки найденных.
"""
import glob, json, os, sys

# Реплика владельца, набранная посреди хода, — вложение `queued_command`; `as_reply` приводит её к виду реплики, как у
# хуков (D1142, D1143): живой классификатор идёт на подаче реплики, а она бывает и вложением. Помощника нет — тождественна.
_TW_LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "hooks", "lib")
if not os.path.exists(os.path.join(_TW_LIB, "transcript_window.py")):
    _TW_LIB = os.path.expanduser("~/.claude/hooks/lib")
sys.path.insert(0, _TW_LIB)
try:
    from transcript_window import as_reply
except ImportError:
    def as_reply(rec):
        return rec
# Реплика — правилом владельца (D1153): своя проверка роли брала и служебную запись `api-request-blob` (роль user,
# `<system-reminder>`). Помощника нет — замер не идёт: судить реплику нечем.
try:
    from transcript_window import is_owner_reply
except ImportError as _tw_e:
    # Владельца признака нет — замер не идёт кодом 2 «не измерено», а не трассой с кодом 1: единица — «находка» у
    # реестра замеров, у свода на Stop и у «Проверок» бэклога (D1157, R6).
    print(f"нет владельца признака transcript_window ({_tw_e}) — не измерено"); sys.exit(2)

ROOT = os.path.expanduser("~/.claude/projects")
LEAD_MAX = 80


def user_texts(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                rec = as_reply(json.loads(line))
            except ValueError:
                continue
            msg = rec.get("message") or rec
            if not is_owner_reply(rec):
                continue
            c = msg.get("content") or rec.get("content") or []
            if isinstance(c, str):
                yield c
            elif isinstance(c, list):
                t = "\n".join(p.get("text", "") for p in c
                              if isinstance(p, dict) and p.get("type") == "text")
                if t:
                    yield t


def main():
    verbose = "--verbose" in sys.argv
    found = []
    for path in glob.glob(os.path.join(ROOT, "*", "*.jsonl")):
        for text in user_texts(path):
            lines = [l for l in text.split("\n") if l.strip()]
            if len(lines) < 2:
                continue
            head = lines[0].strip()
            if len(head) < LEAD_MAX and head.endswith(":"):
                found.append(head)
    print(f"реплик с зачином-двоеточием: {len(found)}   (порог D92: 10)")
    if verbose:
        for h in found[:20]:
            print(f"  · {h}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
