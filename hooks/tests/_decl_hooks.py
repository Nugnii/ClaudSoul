#!/usr/bin/env python3
"""Вспомогательный разбор для test_drift_check.sh (D55).

Два режима:
  _decl_hooks.py <install.sh>            → объявленная конфигурация хуков как JSON
  … | _decl_hooks.py --ghost <имя.sh>    → та же конфигурация плюс призрак регистрации
  … | _decl_hooks.py --drop-tool <имя.sh> → у этого хука из matcher убран ОДИН инструмент
  … | _decl_hooks.py --reorder           → альтернативы каждого matcher переставлены

Вынесено отдельным файлом, а не встроено в тест: вложенные heredoc с python внутри
`case`-веток bash уже дважды в этой сессии дали разбор кавычек не тот, что задуман.
"""
import json
import re
import sys


def declared(path: str) -> dict:
    src = open(path, encoding="utf-8").read()
    m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", src, re.S)
    if not m:
        raise SystemExit(1)
    return json.loads(m.group(1))


def _groups(doc):
    for ev, groups in (doc.get("hooks") or {}).items():
        for g in groups:
            yield ev, g


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "--drop-tool":
        # Дрейф ТОЛЬКО по matcher: файл на месте, событие то же, инструмент выпал (D317).
        doc = json.load(sys.stdin)
        for _ev, g in _groups(doc):
            tools = [x for x in (g.get("matcher") or "").split("|") if x]
            if len(tools) > 1 and any(sys.argv[2] in h.get("command", "")
                                      for h in g.get("hooks", [])):
                g["matcher"] = "|".join(tools[1:])
                break
    elif len(sys.argv) >= 2 and sys.argv[1] == "--reorder":
        # Отрицательный контроль: порядок альтернатив регистрацию не меняет.
        doc = json.load(sys.stdin)
        for _ev, g in _groups(doc):
            tools = [x for x in (g.get("matcher") or "").split("|") if x]
            if len(tools) > 1:
                g["matcher"] = "|".join(reversed(tools))
    elif len(sys.argv) >= 3 and sys.argv[1] == "--ghost":
        doc = json.load(sys.stdin)
        doc.setdefault("hooks", {}).setdefault("SessionEnd", []).append({
            "matcher": "*",
            "hooks": [{"type": "command", "command": f"bash ~/.claude/hooks/{sys.argv[2]}"}],
        })
    else:
        doc = declared(sys.argv[1])
    print(json.dumps(doc, ensure_ascii=False))


if __name__ == "__main__":
    main()
