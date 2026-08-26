#!/usr/bin/env bash
# project-conformance.sh — соответствует ли настройка проекта нынешнему договору.
#
# Повод, названный собеседником: «а если выполнить инициацию в том проекте, где она ранее
# уже была? приведёт ли это к тому, что по-новому перепишется какой-то файл инструкций?
# Было бы неплохо, если бы происходил аудит соответствия актуальной версии взаимодействия
# с проектом».
#
# Что было. `skills/init-project/SKILL.md` написан только на СОЗДАНИЕ: «Create CLAUDE.md»,
# «Create SESSION.md», ни одной проверки на существующий файл и ни одной ветки «если уже
# есть». Перезапись зависела от того, заметит ли агент существующий файл, — уровень 1
# embedded-ness по собственному `principle-knowledge-in-the-world`. И, что важнее, у
# инициатора не было понятия ВЕРСИИ договора: шаблон меняется, а заведённый в апреле проект
# живёт по апрельскому договору, и расхождение не замечает никто.
#
# Замер на момент заведения (5 git-репозиториев под наблюдением): CLAUDE.md возрастом
# 87, 49, 40, 0 дней и один отсутствует вовсе при живых `.claude-docs/`, памяти и git —
# то есть проект наполовину инициализирован. У одного нет CHANGELOG. Сам инициатор при
# этом не заводит ни `VERSION`, ни `CHANGELOG`, хотя глобальные правила называют
# версионирование общесистемным и не опциональным.
#
# Отдельного реестра версий здесь НЕТ намеренно: договор — это шаблоны
# (`templates/CLAUDE.md.tmpl`, `templates/SESSION.md.tmpl`) и глобальные правила. Сравнение
# идёт с ними. Заводить номер версии договора значило бы завести второй источник правды
# о том, что и так записано в шаблоне.
#
# ТОЛЬКО ЧИТАЕТ. Ничего не создаёт и не переписывает: в `CLAUDE.md` живут бизнес-правила,
# написанные руками, и перезапись такого необратима незаметно.
#
# Код возврата: 0 — расхождений нет; 1 — есть.

set -uo pipefail

PROJECT="${1:-$PWD}"
[ -d "$PROJECT" ] || { echo "project-conformance: нет каталога $PROJECT" >&2; exit 2; }
PROJECT=$(cd "$PROJECT" && pwd -P)

CLAUDSOUL="${CLAUDSOUL_ROOT:-$HOME/My Project/ClaudSoul}"
TEMPLATES="${CLAUDSOUL_TEMPLATES:-$HOME/.claude/templates}"
[ -d "$TEMPLATES" ] || TEMPLATES="$CLAUDSOUL/templates"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
SESSION_STALE_DAYS="${SESSION_STALE_DAYS:-14}"   # тот же порог, что у auto-scanner

command -v python3 >/dev/null 2>&1 || { echo "project-conformance: нужен python3" >&2; exit 2; }

python3 - "$PROJECT" "$TEMPLATES" "$PROJECTS_DIR" "$SESSION_STALE_DAYS" <<'PY'
import re, sys, pathlib, time

proj, templates, projects_dir, stale_days = (
    pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
    pathlib.Path(sys.argv[3]), int(sys.argv[4]))
now = time.time()

# Дефектом считается ТОЛЬКО то, что ломает названный механизм. Всё, где отклонение может
# быть осознанным решением, идёт в справку: проверка, объявляющая нарушением любое отличие
# от шаблона, превращается в фон за неделю.
findings = []   # (уровень, что, какой механизм ломается)
notes = []      # справочно, решает человек
oks = []

def age_days(p):
    return (now - p.stat().st_mtime) / 86400

# --- 1. CLAUDE.md есть -------------------------------------------------------
cm = proj / "CLAUDE.md"
if not cm.is_file():
    findings.append(("нет", "CLAUDE.md отсутствует",
                     "правила проекта не загружаются в контекст сессии вообще"))
else:
    oks.append(f"CLAUDE.md есть ({age_days(cm):.0f} дн. с последней правки)")

    # --- 2. разделы против шаблона — СПРАВОЧНО, не дефект --------------------
    # Первая версия сравнивала ЗАГОЛОВКИ как строки и объявила устаревшим сам ClaudSoul:
    # «Стек» против «Стек технологий». Это ровно тот класс, что чинился всю неделю —
    # совпадение с текстом вместо совпадения со смыслом. Отклонение от шаблона к тому же
    # бывает осознанным: у ClaudSoul CLAUDE.md намеренно короткий, потому что грузится
    # каждую сессию целиком. Поэтому сравнение идёт по НОМЕРАМ разделов (устойчивая часть)
    # и попадает в справку, а не в расхождения: решать здесь может только человек.
    tmpl = templates / "CLAUDE.md.tmpl"
    if tmpl.is_file():
        num = lambda t: {int(m) for m in re.findall(r'^## (\d+)\.', t, re.M)}
        want, have = num(tmpl.read_text(errors="replace")), num(cm.read_text(errors="replace"))
        gone = sorted(want - have)
        if gone:
            notes.append(f"CLAUDE.md: {len(have)} нумерованных разделов против {len(want)} "
                         f"в шаблоне (нет №{', №'.join(map(str, gone))}) — "
                         f"проверь, отставание это или осознанное отличие")
        else:
            oks.append(f"нумерация разделов CLAUDE.md совпадает с шаблоном ({len(want)} шт.)")

# --- 3. SESSION.md есть и не протух ------------------------------------------
sm = proj / "SESSION.md"
if not sm.is_file():
    findings.append(("нет", "SESSION.md отсутствует",
                     "контекст между сессиями не переживает истечение окна"))
elif age_days(sm) > stale_days:
    findings.append(("протух", f"SESSION.md не обновлялся {age_days(sm):.0f} дн. "
                               f"(порог {stale_days})",
                     "восстановленный контекст будет описывать не то состояние"))
else:
    oks.append(f"SESSION.md свежий ({age_days(sm):.0f} дн.)")

# --- 4. структура документации -----------------------------------------------
# Требуется только `modules/`: на него завязаны docs-family-check.sh:208,
# claude-md-size-check.sh:58 и auto-scanner.sh:208. Каталоги `sessions/` и `refactoring/`
# инициатор предписывает с самого начала, но в дереве нет НИ ОДНОГО механизма, который их
# создаёт или читает: единственное упоминание `sessions/` — комментарий
# pre-compact-handoff.sh:9, и он врёт, код пишет в `handoff-snapshots`. Требовать их
# значило бы мерить договор, а не работу.
cd = proj / ".claude-docs"
# `docs-family-check.sh:208` принимает ЛИБО `.claude-docs/modules/*.md`, ЛИБО
# `docs/architecture.md` — это одна и та же роль, описание устройства. Требовать именно
# первый путь значило бы быть строже механизма, на который ссылаешься: у самого ClaudSoul
# устройство лежит в `docs/`, и первая версия этой проверки объявила его несоответствующим.
mod_ok = (cd / "modules").is_dir()
arch_ok = (proj / "docs" / "architecture.md").is_file()
if mod_ok or arch_ok:
    oks.append("описание устройства есть (" +
               (".claude-docs/modules/" if mod_ok else "docs/architecture.md") + ")")
else:
    findings.append(("нет", "нет ни .claude-docs/modules/, ни docs/architecture.md",
                     "docs-family-check.sh:208 требует обновлять устройство при правке кода — "
                     "оба принимаемых пути отсутствуют"))
if cd.is_dir():
    # Живые артефакты: появляются по мере работы, отсутствие само по себе не дефект.
    live = [f for f in ("session-activity.md", "narrative.md") if (cd / f).exists()]
    if live:
        oks.append("артефакты работы: " + ", ".join(live))

# --- BACKLOG.md: session-collector.sh:262 читает локальный долг по cwd --------
# Требование обосновано живым читателем (как и остальные проверки): файл без
# писателя-инициатора был невидимым долгом — заведено 2026-08-08 по вопросу
# владельца «почему в новых проектах не заводится бэклог».
bl = proj / "BACKLOG.md"
if bl.is_file():
    oks.append("BACKLOG.md есть — долг проекта виден session-collector")
else:
    findings.append(("нет", "BACKLOG.md отсутствует",
                     "session-collector.sh:262 читает локальный долг по cwd — "
                     "читатель есть, файла нет: долг проекта невидим"))

# --- 5. память проекта --------------------------------------------------------
enc = "-" + str(proj).lstrip("/").replace("/", "-").replace(" ", "-")
mem = projects_dir / enc / "memory"
if not mem.is_dir():
    findings.append(("нет", f"каталог памяти отсутствует ({mem})",
                     "выводы о проекте не переживают сессию"))
elif not (mem / "MEMORY.md").is_file():
    findings.append(("неполно", "в памяти проекта нет MEMORY.md",
                     "индекс не загружается — записи есть, найти их нечем"))
else:
    n = len(list(mem.glob("*.md"))) - 1
    oks.append(f"память проекта есть (записей: {max(n, 0)})")

# --- 6. дисциплина версионирования (только для git-репозиториев с кодом) ------
if (proj / ".git").is_dir():
    has_version = any((proj / f).exists() for f in
                      ("VERSION", "package.json", "pyproject.toml", "Cargo.toml"))
    if not has_version:
        findings.append(("нет", "нет носителя версии (VERSION / package.json / pyproject.toml)",
                         "глобальное правило называет версионирование общесистемным, не опциональным"))
    else:
        oks.append("носитель версии есть")
    if not (proj / "CHANGELOG.md").is_file():
        findings.append(("нет", "нет CHANGELOG.md",
                         "снаружи проекта не видно, что и когда менялось"))
    else:
        oks.append("CHANGELOG.md есть")

# --- вывод --------------------------------------------------------------------
print(f"Соответствие договору: {proj}")
print()
for o in oks:
    print(f"  ✓ {o}")
for n in notes:
    print(f"  · {n}")
if findings:
    print()
    for lvl, what, why in findings:
        print(f"  ✗ [{lvl}] {what}")
        print(f"      → {why}")
    print()
    print(f"Расхождений: {len(findings)}. Ничего не изменено — проверка только читает.")
    print("Что делать с каждым, решать по месту: в CLAUDE.md живут написанные руками")
    print("бизнес-правила, и перезапись такого необратима незаметно.")
else:
    print()
    print("Расхождений нет.")

sys.exit(1 if findings else 0)
PY
