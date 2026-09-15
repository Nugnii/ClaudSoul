#!/usr/bin/env python3
# Результат: seed совпадает с рабочей базой — дрейфа нет
# Проверка результата: python3 scripts/regen-seed.py --check даёт 0
#
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
import os
from pathlib import Path

# Предмет сверки объявляется, а не подразумевается местом. `Path.home()` привязывал
# сравнение к каталогу ЗАПУСКАЮЩЕГО, тогда как зовущий (`drift-check`, пара «seed знаний»)
# отчитывается о `$CLAUDE_HOME`. На машине, где они не совпадают, пара честно печатала OK
# про другой объект — и её сравнение вдобавок засчитывалось уликой «установка есть».
WORKING = Path(os.environ.get("LESSONS_DIR")
               or (Path(os.environ.get("CLAUDE_HOME") or (Path.home() / ".claude"))
                   / "global-lessons"))
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
    # provenance_log[].session (с 2026-08-26) — тот же UUID сессии, только в другом носителе.
    # Очистка смотрела в source_session, а идентификаторы переехали в записи провенанса:
    # гейт публикации 30 августа 2026 поймал 19 UUID в 9 паттернах seed
    # (pattern-publication-carrier-mismatch — личное сидит не в том носителе, куда смотрит очистка).
    fm = re.sub(r'^(\s+session:)\s*\S.*$', r'\1 ""', fm, flags=re.M)
    # Абсолютный путь домашнего каталога автора — ТРЕТИЙ носитель того же класса
    # (4 сентября 2026). `trigger_case` в provenance_log хранит полный путь вида
    # /Users/<автор>/.claude/global-lessons/case-….md: у получателя такого файла нет,
    # а `redact.sed` меняет лишь имя и делает путь ПРАВДОПОДОБНЫМ (/Users/user/…), то есть
    # чинит вид, а не смысл. Замер: 6 файлов seed из 42 несли такие пути.
    # Правило, а не перечень полей: перечень — тот самый дефект, из-за которого очистка
    # дважды смотрела не в тот носитель (source_session, потом provenance_log[].session).
    #
    # Правится ЗНАЧЕНИЕ ПОЛЯ, целиком являющееся путём, — и только оно. Первая редакция
    # этого правила била по всему тексту шапки и калечила прозу: в поле `note` фраза
    # «project CLAUDE.md в /Users/<автор>/My Project/ClaudSoul/CLAUDE.md» превращалась в
    # «…в My Project/ClaudSoul/CLAUDE.md», потому что путь с пробелом обрывался на пробеле.
    # Поймано осмотром diff до коммита. Разделение по назначению: поле-путь обязано
    # РАЗРЕШАТЬСЯ у получателя, поэтому становится именем файла; упоминание пути в прозе —
    # это история, её чистит redact.sed при публикации (publish-public.sh так и говорит:
    # «правь исходник, если это дефект, либо redact.sed, если это история»).
    fm = re.sub(r'^(\s*[A-Za-z_][A-Za-z_0-9]*:[ \t]*)(?:/Users|/home)/\S*/([^/\s]+)[ \t]*$',
                r'\1\2', fm, flags=re.M)
    # ЧЕГО ЗДЕСЬ НЕТ НАМЕРЕННО: `source_cases` и `related` НЕ чистятся, хотя все 213 ссылок
    # на `case-*` указывают на файлы, которых в seed нет — кейсы не шипаются по построению.
    # Решение владельца 4 сентября 2026: оставить. Ссылка в никуда здесь дешевле пустоты —
    # она говорит получателю, что у правила есть родословная и сколько случаев за ним стоит,
    # а имя кейса читается как заголовок. Чистка стёрла бы это и ничего не дала бы взамен.
    # Не «забыли»: вопрос поднят, взвешен и закрыт. Прежде чем чистить — спроси владельца.
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


# Перечень режимов ОБЪЯВЛЕН, и всё вне его отбивается кодом 2 ДО любой записи (D320).
# Прежде режим опознавался вхождением строки в argv, и несовпавшее шло в ветку по
# умолчанию — то есть В РАБОТУ: `regen-seed.py --help` печатал «seed пересобран»,
# возвращал 0 и переписывал ВСЕ 40 файлов knowledge/. Содержимое совпало лишь потому,
# что seed был актуален; на расходящемся дереве справка молча перезаписала бы правки.
MODES = {"--check": "сверить seed с рабочей базой, ничего не писать"}


def usage() -> str:
    lines = ["usage: regen-seed.py [--check]", "", "Режимы:"]
    lines += [f"  {k:10} {v}" for k, v in MODES.items()]
    lines += ["  (без аргументов)  пересобрать seed из рабочей базы"]
    return "\n".join(lines)


def main() -> int:
    args = sys.argv[1:]
    if "--help" in args or "-h" in args:
        print(usage())
        return 0
    unknown = [a for a in args if a not in MODES]
    if unknown:
        print(f"неизвестный аргумент: {' '.join(unknown)}", file=sys.stderr)
        print(usage(), file=sys.stderr)
        return 2
    check = "--check" in args
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
