#!/usr/bin/env python3
# question-survival.py — ловит ли признак вопроса живые реплики и переживает ли вопрос стройку.
#
# Результат: названы два числа — сколько реплик собеседника признак `inquiry-gap` считает
#            вопросом на корпусе, и в скольких из этих ходов агент начал править файлы,
#            не произнеся цепочки причин
# Проверка результата: python3 scripts/question-survival.py печатает оба числа и даёт 0
#
# Зачем (D110). Вопрос собеседника стал состоянием сессии 29 августа 2026, у него есть
# потребитель (гейт разбора), связь доказана обрывом в тесте. Второе условие возврата —
# замер «сколько раз состояние пережило начало стройки» — упиралось в то, что мерить
# нечем: за сутки живой работы `question-open-*.jsonl` не создан ни разу, при 249
# срабатываниях прочих поводов. Ноль в состоянии не отличает «вопросов не было» от
# «признак их не ловит», поэтому замер сделан РЕПЛЕЕМ по корпусу расшифровок.
#
# ПОЧЕМУ ЧИСЛИТЕЛЬ НЕ ИЗ ЖУРНАЛА ГЕЙТА. `five-whys-<SID>.seen` пишется ПОСЛЕ проверки
# «цепочка произнесена»: ходы, где разбор состоялся, туда не попадают. Считая по нему,
# получили бы «пережил стройку и разбора не было» вместо «пережил стройку» — предмет
# замера разошёлся бы с утверждением (тот же корень, что чинили в D112).
#
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ идёт ДО замера: если признак не ловит собственную фикстуру,
# значит сломан реплей, и нули корпуса — поломка, а не данные.
import json
import pathlib
import re
import sys

HOOK = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "inquiry-gap.sh"
PROJECTS = pathlib.Path.home() / ".claude" / "projects"
MAX_LEN = 400          # то же ограничение, что в хуке
EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}


def question_words(src):
    """Вопросительные слова из самого хука — чтобы реплей не разошёлся с признаком."""
    m = re.search(r'case "\$LOWER" in\s*\n\s*(\*.*?)\)\s*MATCHED=1', src, re.S)
    if not m:
        return []
    return sorted({w.strip().strip('"').lower()
                   for w in re.findall(r'"([^"]+)"', m.group(1))})


def main():
    if not HOOK.exists():
        print(f"нет {HOOK}")
        return 0
    words = question_words(HOOK.read_text(errors="replace"))
    if not words:
        print("словарь вопросительных слов не извлечён — реплей не может быть верным")
        return 2

    def is_question(text):
        if len(text) > MAX_LEN or "?" not in text:
            return False
        low = text.lower()
        return any(w in low for w in words)

    # --- отрицательный контроль ---
    if not is_question("а почему тут не создаются механизмы?"):
        print("ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ПРОВАЛЕН: признак не ловит собственную фикстуру")
        return 2
    if is_question("сделай вот это"):
        print("ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ПРОВАЛЕН: не-вопрос засчитан вопросом")
        return 2

    user_turns = questions = survived = with_chain = 0
    if PROJECTS.is_dir():
        for f in PROJECTS.rglob("*.jsonl"):
            open_q = False       # вопрос задан и ход ещё не кончился
            chain = 0            # «почему» в ответах после вопроса
            edited = False
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
                        # Результаты инструментов приходят ТОЖЕ как реплики пользователя, но
                        # с содержимым типа tool_result — текста в них нет. Итог хода
                        # подводится только на настоящей реплике: первая редакция считала
                        # каждый tool_result концом хода, и один вопрос закрывался
                        # многократно — доля «пережил стройку» вышла 244%. Число больше
                        # ста процентов и выдало ошибку; будь оно правдоподобным, замер
                        # соврал бы молча.
                        text = content if isinstance(content, str) else "\n".join(
                            c.get("text", "") for c in content
                            if isinstance(c, dict) and c.get("type") == "text")
                        if not text.strip():
                            continue
                        # Ход кончился: подводим итог предыдущего вопроса.
                        if open_q and edited:
                            survived += 1
                            if chain >= 3:
                                with_chain += 1
                        user_turns += 1
                        open_q, chain, edited = is_question(text), 0, False
                        if open_q:
                            questions += 1
                    elif role == "assistant" and open_q and isinstance(content, list):
                        for c in content:
                            if not isinstance(c, dict):
                                continue
                            if c.get("type") == "text":
                                chain += len(re.findall("почему", c.get("text", ""), re.I))
                            elif c.get("type") == "tool_use" and c.get("name") in EDIT_TOOLS:
                                edited = True
                if open_q and edited:
                    survived += 1
                    if chain >= 3:
                        with_chain += 1
            except Exception:
                continue

    print(f"вопросительных слов в признаке: {len(words)}")
    print(f"реплик собеседника в корпусе: {user_turns}")
    print(f"признак считает вопросом: {questions}")
    print(f"из них ход дошёл до правки файлов: {survived}")
    print(f"из них с произнесённой цепочкой (>=3 «почему»): {with_chain}")
    if questions == 0:
        print("ВЕРДИКТ: признак не ловит НИ ОДНОЙ живой реплики — дело в признаке, "
              "а не в отсутствии вопросов; расширять или писать вердикт о невыразимости")
    elif survived == 0:
        print("ВЕРДИКТ: вопрос ни разу не пережил начала стройки — стража на правке "
              "заводить не из чего, состояние достаточно как повод для гейта разбора")
    else:
        share = survived * 100 // questions
        print(f"ВЕРДИКТ: вопрос переживает начало стройки в {share}% случаев; "
              f"из них разбор произносится в {with_chain} — по этим числам и решать, "
              f"нужен ли отдельный страж на правке")
    return 0


if __name__ == "__main__":
    sys.exit(main())
