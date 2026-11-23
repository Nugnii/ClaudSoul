#!/usr/bin/env python3
"""deny_mark.py — питоновский конец ВЛАДЕЛЬЦА имени состояния «вызов отказан стражем».

Результат: читатель расшифровки на питоне отличает решение стража от упавшей команды,
           спросив ТО ЖЕ выражение, что спрашивают shell-читатели
Проверка результата: bash hooks/tests/test_deny_mark_lib.sh даёт 0

Владелец — `hooks/deny-mark-lib.sh`. Здесь НЕ копия выражения, а его ЧТЕНИЕ: строка
присваивания разбирается из файла владельца либо берётся из окружения, куда её кладёт
shell-потребитель. Копия была бы род K реестра — ровно тот дефект, ради которого владелец
заведён (D421): имя состояния, собранное литералом на каждом конце связи отдельно.

Синтаксис выражения общий для двух движков по решению владельца: `\\A` и `\\s` понимают и
Oniguruma (jq `test`), и питоновский `re`. Поэтому переписывать его здесь не нужно —
и именно поэтому нельзя.

СПРОСИТЬ НЕЧЕМ — НЕ «ОТКАЗОВ НЕТ». Владелец не найден либо его строка не разобрана —
поднимается `DenyMarkUnavailable`, а не подставляется умолчание: молчаливое умолчание
сделало бы сломанный резолв неотличимым от чистого корпуса (род B реестра).
"""
import os
import re

__all__ = ["DenyMarkUnavailable", "deny_re", "is_denial", "result_text"]

# Строка владельца: DENY_MARK_RE="${DENY_MARK_RE:-\A\s*(PreToolUse:[A-Za-z_]+ hook error:\s*)?(⛔|🛑|🚫)}"
_ASSIGN = re.compile(r'^DENY_MARK_RE="\$\{DENY_MARK_RE:-(?P<re>.*)\}"\s*$', re.M)


class DenyMarkUnavailable(RuntimeError):
    """Владельца не спросить: файла нет либо его строка не разобрана."""


def _owner_paths():
    here = os.path.dirname(os.path.abspath(__file__))
    yield os.path.join(here, os.pardir, "deny-mark-lib.sh")      # hooks/lib → hooks/
    repo = os.environ.get("CLAUDSOUL_REPO") or os.environ.get("CLAUDSOUL_ROOT")
    if repo:
        yield os.path.join(repo, "hooks", "deny-mark-lib.sh")
    yield os.path.expanduser("~/.claude/hooks/deny-mark-lib.sh")


_cache = None


def deny_re():
    """Скомпилированное выражение владельца. Бросает DenyMarkUnavailable, если спросить нечем."""
    global _cache
    if _cache is not None:
        return _cache
    src = os.environ.get("DENY_MARK_RE")
    if not src:
        for p in _owner_paths():
            try:
                with open(p, encoding="utf-8") as fh:
                    m = _ASSIGN.search(fh.read())
            except OSError:
                continue
            if m:
                # В двойных кавычках оболочки `\\A` записывает `\A` — разворачиваем обратно.
                src = m.group("re").replace("\\\\", "\\")
                break
    if not src:
        raise DenyMarkUnavailable("deny-mark-lib.sh не найден либо строка DENY_MARK_RE не разобрана")
    try:
        _cache = re.compile(src)
    except re.error as e:                                        # noqa: PERF203
        raise DenyMarkUnavailable(f"выражение владельца не компилируется: {e}") from e
    return _cache


def result_text(block):
    """Текст блока tool_result: харнесс кладёт его строкой либо списком кусков."""
    c = block.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""


def is_denial(text):
    """Текст блока есть РЕШЕНИЕ стража, а не вывод упавшей команды."""
    return bool(deny_re().match(text or ""))
