#!/usr/bin/env python3
"""ClaudSoul — регенерация seed-базы знаний (knowledge/) из рабочей базы.

Чистая установка получает ВСЮ универсальную мудрость: все принципы
(универсальны по определению — case→pattern→principle = cross-domain) плюс
паттерны со `scope: universal`. Личные кейсы (case-*), сущности
(entity-/fact-/relation-) и коммуникативные знания (scope: per-speaker) НЕ
шипаются.

Пользовательские счётчики сбрасываются к базовым (confirmed_count: 1,
contradicted_count: 0) — новый агент не «наследует» чужую историю
подтверждений. confidence/impact сохраняются: это сила правила, её и шипаем.

Замена счётчиков — точечная, ТОЛЬКО внутри frontmatter-блока (между первыми
двумя `---`); остальной текст, включая YAML-комментарии и тело, сохраняется
байт-в-байт (обычный YAML parse→dump уничтожил бы комментарии вроде
`# Контекстные якоря`).

Использование:
    scripts/regen-seed.py            # пересобрать knowledge/ из рабочей базы
    scripts/regen-seed.py --check    # не писать; exit 1 если seed расходится
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

WORKING = Path.home() / ".claude" / "global-lessons"
SEED = Path(__file__).resolve().parents[1] / "knowledge"

_FM = re.compile(r"^(---\n.*?\n---\n)", re.S)
_SCOPE = re.compile(r"^scope:\s*(\S+)", re.M)


def _frontmatter(text: str) -> str:
    m = _FM.match(text)
    return m.group(1) if m else ""


def _scope(text: str):
    m = _SCOPE.search(_frontmatter(text))
    return m.group(1).strip() if m else None


def should_ship(name: str, text: str) -> bool:
    """Принципы — все, кроме явных per-speaker/mixed (универсальны по
    определению). Паттерны — только scope: universal."""
    scope = _scope(text)
    if name.startswith("principle-"):
        return scope not in ("per-speaker", "mixed")
    if name.startswith("pattern-"):
        return scope == "universal"
    return False


def reset_counters(text: str) -> str:
    m = _FM.match(text)
    if not m:
        return text  # нет frontmatter — оставить как есть
    fm, body = m.group(1), text[m.end():]
    fm = re.sub(r"^confirmed_count:.*$", "confirmed_count: 1", fm, count=1, flags=re.M)
    fm = re.sub(r"^contradicted_count:.*$", "contradicted_count: 0", fm, count=1, flags=re.M)
    # source_session (v1.11) — UUID сессии автора. Frontmatter копируется байт-в-байт,
    # так что без этой строки идентификаторы уехали бы в публикуемый seed. Публичный
    # релиз v1.10.0 уже отложен из-за утечки личных данных (DEFER-1) — второй раз не надо.
    fm = re.sub(r'^source_session:.*$', 'source_session: ""', fm, count=1, flags=re.M)
    return fm + body


def build() -> dict:
    """Имя файла → содержимое seed-версии (только принципы и universal-паттерны)."""
    out = {}
    for path in sorted(WORKING.glob("*.md")):
        name = path.name
        if not (name.startswith("principle-") or name.startswith("pattern-")):
            continue
        text = path.read_text(encoding="utf-8")
        if should_ship(name, text):
            out[name] = reset_counters(text)
    return out


def current_seed() -> dict:
    out = {}
    for path in sorted(SEED.glob("*.md")):
        if path.name.startswith("principle-") or path.name.startswith("pattern-"):
            out[path.name] = path.read_text(encoding="utf-8")
    return out


def main() -> int:
    check = "--check" in sys.argv[1:]
    if not WORKING.is_dir():
        print(f"рабочая база не найдена: {WORKING}", file=sys.stderr)
        return 2

    target = build()
    existing = current_seed()
    stale = [n for n, c in target.items() if existing.get(n) != c]
    removed = [n for n in existing if n not in target]

    n_pr = sum(1 for n in target if n.startswith("principle-"))
    n_pt = sum(1 for n in target if n.startswith("pattern-"))

    if check:
        if stale or removed:
            for n in sorted(stale):
                print(f"расходится: {n}")
            for n in sorted(removed):
                print(f"лишний в seed (не universal): {n}")
            print("\nЗапусти scripts/regen-seed.py для пересборки.", file=sys.stderr)
            return 1
        print(f"seed актуален: {len(target)} файлов ({n_pr} принципов + {n_pt} universal-паттернов)")
        return 0

    for name, content in target.items():
        (SEED / name).write_text(content, encoding="utf-8")
    for name in removed:
        (SEED / name).unlink()
    print(f"seed пересобран: {len(target)} файлов ({n_pr} принципов + {n_pt} universal-паттернов)")
    if removed:
        print(f"удалено (больше не universal): {', '.join(sorted(removed))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
