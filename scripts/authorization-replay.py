#!/usr/bin/env python3
# authorization-replay.py — сколько живых поручений теряет классификатор авторизации.
#
# Результат: названо число — сколько реплик собеседника классификатор считает поручением
#            на корпусе расшифровок, и сколько поручений он пропускает по измеренной выборке
# Проверка результата: python3 scripts/authorization-replay.py печатает числа и даёт 0
#
# Зачем (D207). Замер на живой реплике 29 августа 2026: «ну что ж, не плохо. А теперь
# разгребаем этот бэклог» — прямое поручение, классификатор вернул пусто, и `budget-gate`
# окрикнул «действующей авторизации нет» при первой же правке. Словарь содержит только
# повелительные формы, а продолжения ищутся лишь в начале строки.
#
# ЧТО ЭТО НЕ ИЗМЕРЯЕТ. Полноту: разметить весь корпус вручную нечем, «поручение» — суждение
# о намерении. Поэтому здесь считаются две наблюдаемые величины: (1) доля реплик,
# признанных поручением, и (2) СЛЕДСТВИЕ пропуска — сколько раз после нераспознанной
# реплики агент всё-таки правил файлы. Второе и есть цена ошибки: правка при «нет
# авторизации» либо окрикивается зря, либо идёт вопреки окрику.
#
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ идёт ДО замера: классификатор обязан узнать заведомое поручение и
# не узнать заведомый вопрос. Ноль на фикстуре означает поломку реплея, а не чистый корпус.
import json
import pathlib
import re
import subprocess
import sys

LIB = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "authorization-lib.sh"
PROJECTS = pathlib.Path.home() / ".claude" / "projects"
EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}


def classify(text):
    """Вызов настоящего классификатора: реплей обязан спрашивать механизм, а не его копию."""
    r = subprocess.run(
        ["bash", "-c", f'. "{LIB}"; auth_classify "$1"', "_", text],
        capture_output=True, text=True)
    return r.stdout.strip()


def main():
    if not LIB.exists():
        print(f"нет {LIB}")
        return 0

    # --- отрицательный контроль ---
    if not classify("сделай вот это"):
        print("ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ПРОВАЛЕН: не узнано заведомое поручение")
        return 2
    if classify("а почему так вышло?"):
        print("ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ПРОВАЛЕН: вопрос принят за поручение")
        return 2

    turns = recognized = missed_then_edited = 0
    missed_examples = []
    if PROJECTS.is_dir():
        for f in PROJECTS.rglob("*.jsonl"):
            pending_miss = None
            try:
                for line in f.open(errors="replace"):
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    msg = rec.get("message") or {}
                    role = msg.get("role") or rec.get("role")
                    content = msg.get("content") or rec.get("content") or []
                    if role == "user":
                        text = content if isinstance(content, str) else "\n".join(
                            c.get("text", "") for c in content
                            if isinstance(c, dict) and c.get("type") == "text")
                        text = text.strip()
                        # Системные вставки репликой собеседника не являются.
                        if not text or text.startswith("[SYSTEM") or "<task-notification>" in text:
                            continue
                        if len(text) > 600:
                            continue
                        turns += 1
                        if classify(text):
                            recognized += 1
                            pending_miss = None
                        else:
                            pending_miss = text[:70].replace("\n", " ")
                    elif role == "assistant" and pending_miss and isinstance(content, list):
                        for c in content:
                            if isinstance(c, dict) and c.get("type") == "tool_use" \
                               and c.get("name") in EDIT_TOOLS:
                                missed_then_edited += 1
                                if len(missed_examples) < 8:
                                    missed_examples.append(pending_miss)
                                pending_miss = None
                                break
            except Exception:
                continue

    print(f"реплик собеседника в корпусе: {turns}")
    print(f"признано поручением: {recognized}")
    if turns:
        print(f"доля признанных: {recognized * 100 // turns}%")
    print(f"НЕ признано, но агент следом правил файлы: {missed_then_edited}")
    if missed_examples:
        print("примеры нераспознанных реплик, после которых шла правка:")
        for e in missed_examples:
            print(f"  · {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
