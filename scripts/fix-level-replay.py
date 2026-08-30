#!/usr/bin/env python3
# fix-level-replay.py — жив ли словарь fix-level-check: прогон по корпусу расшифровок.
#
# Результат: названо число — сколько блоков речи агента словарь ловит на корпусе, и
#            сколько из них гасит глушитель механизмов; по числам видно, что именно
#            держит признак немым
# Проверка результата: python3 scripts/fix-level-replay.py печатает три числа и даёт 0
#
# Зачем (D113). `hooks/fix-level-check.sh` зарегистрирован на четыре события и за 33 дня
# накопления состояния не создал НИ ОДНОГО файла `fix-level-*.jsonl`: словарь
# пост-инцидентных фраз («надо вынести урок», «будем осторожнее») не совпал ни разу.
# Ноль срабатываний не доказывает, что признак мёртв, — но и не даёт считать его живым.
# Замерять по журналу нечего в принципе: при нуле совпадений хук не пишет ничего, и
# «не сработал» неотличимо от «не запускался». Отсюда реплей по корпусу.
#
# ЧТО ПРОВЕРЯЕТ ГИПОТЕЗУ. Хук глушит скан, если в ответе есть любой из маркеров механизма
# («хук», «тест», «скрипт», «механизм», «детектор»…). В проекте про хуки такие слова есть
# почти в каждом ответе — то есть глушитель мог гасить всё ДО сравнения со словарём.
# Реплей считает обе величины отдельно: совпадений словаря всего и из них заглушённых.
#
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ обязателен и идёт ДО замера: если на подложной фикстуре реплей
# даёт ноль, значит сломан он сам, и нули корпуса — поломка, а не данные (образец —
# scripts/ab-authorization-replay.sh).
import json
import pathlib
import re
import sys

HOOK = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "fix-level-check.sh"
PROJECTS = pathlib.Path.home() / ".claude" / "projects"


def extract_list(var_name, text):
    """Достаёт элементы bash-массива вида NAME=( "a" "b" )."""
    m = re.search(rf'{var_name}=\(\s*(.*?)\)', text, re.S)
    if not m:
        return []
    return re.findall(r'"([^"]+)"', m.group(1))


def main():
    if not HOOK.exists():
        print(f"нет {HOOK}")
        return 0
    src = HOOK.read_text(errors="replace")
    phrases = extract_list("FIX_PHRASES", src)
    markers = extract_list("MECHANISM_MARKERS", src)
    if not phrases:
        print("словарь фраз не извлечён — реплей не может быть верным")
        return 2

    def matches(text):
        low = text.lower()
        return [p for p in phrases if p.lower() in low]

    def muffled(text):
        """Прежняя логика: маркер ГДЕ-УГОДНО в ответе гасит скан целиком."""
        low = text.lower()
        return [m for m in markers if m.lower() in low]

    def muffled_in_sentence(text, phrase):
        """Нынешняя логика: маркер должен стоять в ТОМ ЖЕ предложении, что и фраза."""
        low = text.lower()
        for sent in re.split(r'[.!?\n]', low):
            if phrase.lower() in sent:
                if any(m.lower() in sent for m in markers):
                    return True
        return False

    # --- отрицательный контроль ДО замера ---
    fixture_hit = "Понял, надо вынести урок из этого случая."
    fixture_muffled = "Понял, надо вынести урок — заведу хук."
    if not matches(fixture_hit):
        print("ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ПРОВАЛЕН: словарь не ловит собственную фразу")
        return 2
    if not muffled(fixture_muffled):
        print("ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ПРОВАЛЕН: глушитель не видит слова «хук»")
        return 2

    blocks = hits = hits_muffled = hits_muffled_now = 0
    if PROJECTS.is_dir():
        for f in PROJECTS.rglob("*.jsonl"):
            try:
                for line in f.open(errors="replace"):
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    msg = rec.get("message") or {}
                    if (msg.get("role") or rec.get("role")) != "assistant":
                        continue
                    content = msg.get("content") or rec.get("content") or []
                    if isinstance(content, list):
                        text = "\n".join(
                            c.get("text", "") for c in content
                            if isinstance(c, dict) and c.get("type") == "text"
                        )
                    elif isinstance(content, str):
                        text = content
                    else:
                        continue
                    if not text.strip():
                        continue
                    blocks += 1
                    found = matches(text)
                    if found:
                        hits += 1
                        if muffled(text):
                            hits_muffled += 1
                        if all(muffled_in_sentence(text, p) for p in found):
                            hits_muffled_now += 1
            except Exception:
                continue

    print(f"фраз в словаре: {len(phrases)}, маркеров глушителя: {len(markers)}")
    print(f"блоков речи агента в корпусе: {blocks}")
    print(f"совпадений словаря: {hits}")
    print(f"заглушено ПРЕЖНЕЙ логикой (маркер где угодно в ответе): {hits_muffled}")
    print(f"заглушено НЫНЕШНЕЙ логикой (маркер в той же фразе): {hits_muffled_now}")
    if hits:
        was = hits_muffled * 100 // hits
        now = hits_muffled_now * 100 // hits
        print(f"доля заглушённых: было {was}%, стало {now}%")
        print(f"признак доносит до сессии: было {hits - hits_muffled}, стало {hits - hits_muffled_now}")
        if now > 50:
            print("ВЕРДИКТ: глушитель всё ещё съедает больше половины — сузить дальше")
    else:
        print("ВЕРДИКТ: словарь не ловит НИЧЕГО на всём корпусе — дело не в глушителе, "
              "а в самом словаре: перечень форм не описывает предмет")
    # Признак остаётся редким по построению: 6 совпадений на 15005 блоков речи это 0.04%.
    # Это НАЗВАННЫЙ ПРЕДЕЛ словаря, а не его поломка: перечень форм не описывает предмет —
    # пост-инцидентную отписку можно произнести бесконечным числом способов
    # (pattern-subject-checked-by-enumeration, confidence 5).
    # Условие снятия: предел уйдёт, когда признак станет опираться не на перечень фраз, а
    # на наблюдаемое свойство хода — например «после инцидента ход кончился без записи в
    # носитель», что уже умеет журнал исходов контура root-cause.
    return 0


if __name__ == "__main__":
    sys.exit(main())
