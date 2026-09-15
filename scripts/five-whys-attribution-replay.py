#!/usr/bin/env python3
# five-whys-attribution-replay.py — что изменится, если гейт разбора станет гасить сигналы
# ПОИМЁННО, а не ходом целиком.
#
# Результат: названо число — сколько прежде разрешённых вызовов новое правило отбивает, и
#            сколько из них отбито по делу; без этих двух чисел сужение отказа заводить нельзя
# Проверка результата: python3 scripts/five-whys-attribution-replay.py печатает обе доли и даёт 0
#
# Зачем (7 сентября 2026). `hooks/five-whys-gate.sh:381` выдаёт разрешение по ОДНОМУ вопросу:
# прозвучала ли в ходе хоть какая-нибудь цепочка. Атрибуция «цепочка гасит только сигнал, чей
# предмет виден в тексте» (:400-423) применяется ТОЛЬКО к журналу исходов, а на решение не
# влияет: `exit 0` на :425 стоит внутри `if rc_chain_spoken` безусловно. Починка D227 развела
# предмет и ход в УЧЁТЕ, но не в ГЕЙТЕ.
# Замер живой сессии: сигнал `daily` (класс повторился за сутки трижды) сработал 11 раз и НИ
# РАЗУ не получил собственной цепочки, при этом ни одного отказа не было — в тех же ходах
# разбиралось другое.
#
# ЧТО ЭТОТ РЕПЛЕЙ НЕ УТВЕРЖДАЕТ. Он считает, СКОЛЬКО вызовов новое правило отобьёт, и
# показывает их поимённо. Он НЕ решает, верен ли каждый отказ: это суждение о содержании хода,
# и его выносит человек по предъявленному списку. Число без осмотра — не основание для отказа
# уровня 4 (правило дерева: признак с непроверенной точностью не заводится).
#
# ВЕРДИКТ ПО ПРЕДЪЯВЛЕННОМУ СПИСКУ (8 сентября 2026). Сужение НЕ заводится.
# Прогон по 383 ходам: прежде разрешал 121, новое правило отбивает 70. Прочитаны три —
# ложны все три: ход делал .docx клиенту (84675e9f), ход отвечал про IOD и RODO (b00ed58e),
# ход разбирал ДРУГОЙ дефект по существу (1688a088). Состав отбитых объясняет почему:
# 66 из 70 несут сигнал `daily`, чей предмет — СУТКИ поперёк сессий и проектов, а не ход.
# Доля срабатываний `daily`, где предмет совпал с ходом: 5 из 158 = 3%.
# Отсюда пункт D358: `daily` уходит из гейта хода в очередь, а не ужесточается в нём.
#
# РЕЖИМ `--sample-rework N` (13 сентября 2026, D358 носитель 2). Печатает N случайных напоминаний
# о переработке («повторные заходы на один файл») вместе с файлами из скобок и текстом ответа
# агента в том же ходе — для чтения глазом: настоящий ли это разворот, решает человек, прибор
# лишь предъявляет выборку (seed — `FWG_SAMPLE_SEED`, по умолчанию 13: перемер воспроизводим).
# Показание 13 сентября 2026: разворот 7 из 20; из 13 ложных шесть — файлы учёта и документы,
# после чего `REWORK_EXCLUDE_RE` детектора расширен (202 из 756 срабатываний живых журналов).
#
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ идёт ДО замера и обязателен: на подложном ходе, где предмет НАЗВАН и
# цепочка произнесена, новое правило обязано РАЗРЕШИТЬ. Не разрешило — сломан реплей, и числа
# корпуса ничего не значат (образец — scripts/ab-authorization-replay.sh).
#
# ОПРЕДЕЛЕНИЕ ЦЕПОЧКИ НЕ КОПИРУЕТСЯ. След считает `rc_trace`, вердикт выносит
# `rc_chain_spoken` — обе из `hooks/root-cause-lib.sh`, вызовом. Своя копия формулы разошлась
# бы с оригиналом молча (род K реестра).
import glob
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

REPO = pathlib.Path(os.environ.get("CLAUDSOUL_REPO") or pathlib.Path(__file__).resolve().parents[1])
LIB = REPO / "hooks" / "root-cause-lib.sh"
CORPUS = os.environ.get("FWG_REPLAY_CORPUS") or os.path.expanduser("~/.claude/projects/*/*.jsonl")
REMINDER = "Признак повторяется"

# Сигналы С ЛЕКСИЧЕСКИМ ПРЕДМЕТОМ. streak и question сюда НЕ входят намеренно: у них предмета
# нет по построению, и они гасятся любой цепочкой — это названный предел самого гейта (:394).
LEXICAL = ("повторные заходы", "класс повторился", "внешнее событие", "поправка")
NAME_RE = re.compile(r"\b((?:pattern|case|principle|entity|fact|relation)-[a-z0-9-]{4,})")
FILE_RE = re.compile(r"\b([A-Za-z0-9_.-]+\.(?:sh|py|md|tsv|js|ts|jsonl))\b")


def turn_texts(path):
    """Ходы файла: (тексты агента, тексты напоминаний гейта). Граница — живая реплика владельца."""
    out, cur_a, cur_r, started = [], [], [], False
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return out
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        role = (o.get("message") or {}).get("role") or o.get("role") or ""
        if role == "user" and not o.get("isMeta") and not o.get("isSidechain"):
            c = (o.get("message") or {}).get("content") or []
            txt = "".join(p.get("text", "") for p in c if isinstance(p, dict)) if isinstance(c, list) else str(c)
            if txt.strip():
                if started:
                    out.append((cur_a, cur_r))
                started, cur_a, cur_r = True, [], []
        if role == "assistant" and not o.get("isSidechain"):
            c = (o.get("message") or {}).get("content") or []
            if isinstance(c, list):
                t = "\n".join(p.get("text", "") for p in c if isinstance(p, dict) and p.get("type") == "text")
                if t.strip():
                    cur_a.append(t)
        if o.get("type") == "attachment":
            a = o.get("attachment") or {}
            for s in (a.get("content") or []):
                if isinstance(s, str) and REMINDER in s:
                    cur_r.append(s)
    if started:
        out.append((cur_a, cur_r))
    return out


def trace_of(agent_texts):
    """След хода — вызовом rc_trace, а не своей копией формулы."""
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8") as fh:
        fh.write(json.dumps({"message": {"role": "user", "content": [{"type": "text", "text": "x"}]}}) + "\n")
        for t in agent_texts:
            fh.write(json.dumps({"message": {"role": "assistant",
                                             "content": [{"type": "text", "text": t}]}}) + "\n")
        p = fh.name
    try:
        r = subprocess.run(["bash", "-c", '. "$1"; rc_trace "$2"', "_", str(LIB), p],
                           capture_output=True, text=True, timeout=30)
        return (r.stdout or "").strip()
    finally:
        os.unlink(p)


def chain_spoken(trace_json):
    if not trace_json:
        return False
    r = subprocess.run(["bash", "-c", '. "$1"; rc_chain_spoken "$2" 3', "_", str(LIB), trace_json],
                       capture_output=True, text=True, timeout=30)
    return r.returncode == 0


def subjects(reminder_text):
    """Предметы сигналов С ЛЕКСИЧЕСКИМ ПРЕДМЕТОМ. Пусто — значит гасится любой цепочкой."""
    head = reminder_text.split("\n", 1)[0]
    if not any(k in head for k in LEXICAL):
        return []
    return sorted(set(NAME_RE.findall(head)) | set(FILE_RE.findall(head)))


def decide(agent_texts, reminders):
    trace = trace_of(agent_texts)
    old = chain_spoken(trace)
    if not old:
        return "deny", "deny", []      # прежнее правило и так отбивало
    body = "\n".join(agent_texts)
    unattributed = []
    for rem in reminders:
        for s in subjects(rem):
            if s not in body:
                unattributed.append(s)
    return "allow", ("deny" if unattributed else "allow"), sorted(set(unattributed))


def negative_control():
    """Предмет НАЗВАН и цепочка произнесена — новое правило обязано разрешить."""
    rem = "🔁 Признак повторяется (один класс повторился за сутки трижды и больше, а именно pattern-proba-kontrolnaya), а разбора причин в этом ходе не было."
    body = ("Почему сломалось? ← первое. Почему? ← второе. Почему? ← третье. "
            "Это pattern-proba-kontrolnaya, и корень назван.")
    o, n, un = decide([body], [rem])
    return o == "allow" and n == "allow" and not un


def sample_rework(n):
    """Выборка напоминаний о переработке с текстом хода — для чтения глазом (точность rework, D358).
    Прибор печатает случаи; настоящий ли разворот — решает человек по тексту (как в adversary-replay)."""
    import random
    random.seed(int(os.environ.get("FWG_SAMPLE_SEED", "13")))
    pairs = []
    for f in sorted(glob.glob(CORPUS)):
        for agent_texts, reminders in turn_texts(f):
            for r in reminders:
                head = r.split("\n", 1)[0]
                if "повторные заходы" in head:
                    m = re.search(r"повторные заходы на один файл[^()]*\(([^)]*)\)", head)
                    pairs.append((os.path.basename(f)[:8], (m.group(1) if m else "")[:160], re.sub(r"\s+", " ", "\n".join(agent_texts))[:520]))
    print("напоминаний о переработке в корпусе: %d; выборка %d (seed %s)" % (len(pairs), min(n, len(pairs)), os.environ.get("FWG_SAMPLE_SEED", "13")))
    for i, (sid, files, txt) in enumerate(random.sample(pairs, min(n, len(pairs))), 1):
        print("\n#%d [%s] файлы: %s\n   ТЕКСТ: %s" % (i, sid, files or "—", txt))
    print("\nВЕРДИКТ — ЧТЕНИЕМ: разворот ли это (второй заход на тот же файл, потому что результат не устроил), решает человек; число ложных пишется в пункт с датой и seed.")
    return 0


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--sample-rework":
        return sample_rework(int(sys.argv[2]))
    if not LIB.exists():
        print("НЕ ИЗМЕРЕНО: нет %s" % LIB, file=sys.stderr)
        return 2
    if not negative_control():
        print("НЕ ИЗМЕРЕНО: отрицательный контроль не прошёл — сломан сам реплей, "
              "числа корпуса ничего не значат", file=sys.stderr)
        return 2

    files = sorted(glob.glob(CORPUS))
    if not files:
        print("НЕ ИЗМЕРЕНО: корпус пуст (%s)" % CORPUS, file=sys.stderr)
        return 2

    seen = allowed_before = newly_denied = 0
    cases = []
    for f in files:
        for agent_texts, reminders in turn_texts(f):
            if not reminders or not agent_texts:
                continue
            seen += 1
            old, new, un = decide(agent_texts, reminders)
            if old != "allow":
                continue
            allowed_before += 1
            if new == "deny":
                newly_denied += 1
                cases.append((os.path.basename(f)[:8], un[:3]))

    print("ходов с напоминанием и ответом агента: %d" % seen)
    print("из них прежнее правило РАЗРЕШАЛО:       %d" % allowed_before)
    print("новое правило ОТБИВАЕТ:                 %d (%.0f%% прежде разрешённых)"
          % (newly_denied, 100.0 * newly_denied / max(allowed_before, 1)))
    print()
    print("отбитые поимённо (сессия → неразобранный предмет), первые 15:")
    for s, un in cases[:15]:
        print("   %s  %s" % (s, ", ".join(un) if un else "—"))
    if len(cases) > 15:
        print("   … и ещё %d" % (len(cases) - 15))
    print()
    print("ЧИСЛО — НЕ ВЕРДИКТ. Верность каждого отказа решается осмотром списка выше;")
    print("сужение отказа заводится только после того, как ложные названы поимённо.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
