#!/usr/bin/env python3
"""Вспомогательный разбор для test_drift_check.sh (D55).

Два режима:
  _decl_hooks.py <install.sh>            → объявленная конфигурация хуков как JSON
  … | _decl_hooks.py --ghost <имя.sh>    → та же конфигурация плюс призрак регистрации

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


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "--ghost":
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
