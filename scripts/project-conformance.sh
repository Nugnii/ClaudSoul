#!/usr/bin/env bash
# project-conformance.sh — соответствует ли настройка проекта нынешнему договору.
# Результат: настройка проекта совпадает с нынешним договором — расхождений нет
# Проверка результата: bash scripts/project-conformance.sh даёт 0
#
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

# ── Долг проекта сверяется ЧИТАТЕЛЕМ, а не наличием файла (18 сентября 2026, D416) ──
# Прежде галочка «BACKLOG.md есть — долг проекта виден» стояла на `bl.is_file()`. Пока
# разметка цела, такой вердикт верен СЛУЧАЙНО: сломается формат — сверщик скажет то же
# самое. Повод (15 сентября 2026): на ProjectA_NEW сверщик отчитался «Расхождений нет», а
# архиватор видел там «открытых: 0» при 23 пунктах, потому что у пунктов не было номеров.
# Признак пункта берётся у ВЛАДЕЛЬЦА (`hooks/backlog-lib.sh`), своего счёта здесь нет —
# иначе у факта «сколько открытых пунктов» стало бы два владельца. Образец подключения —
# `scripts/backlog-refresh-readings.sh`.
# ТРИ СОСТОЯНИЯ, А НЕ ДВА: число пунктов; «читателя нет» (библиотека недоступна — тогда
# НЕ ПРОВЕРЕНО, а не «чисто»); «метки есть, пунктов нет» — разметка сломана, и это
# единственное состояние, о котором сверщик обязан кричать.
# Адрес библиотеки — РЯДОМ СО СКРИПТОМ первым делом, и это куплено красным CI 18 сентября
# 2026. Первая редакция брала `$CLAUDSOUL`, а он по умолчанию равен домашнему каталогу
# разработчика; запасной путь вёл в `~/.claude`, которого на раннере тоже нет, потому что
# ClaudSoul там не установлен. Итог: библиотека не найдена, ветка «читателя не спросили»
# сработала честно и добавила расхождение — покраснели и этот сверщик, и два его теста,
# зелёные на macOS. Порядок путей взят у соседа `scripts/backlog-return-check.sh`: сперва
# каталог скрипта, потом установка, потом переменная.
BL_LIB="${BL_LIB:-$(cd "$(dirname "$0")/../hooks" 2>/dev/null && pwd)/backlog-lib.sh}"
[ -f "$BL_LIB" ] || BL_LIB="$HOME/.claude/hooks/backlog-lib.sh"
[ -f "$BL_LIB" ] || BL_LIB="$CLAUDSOUL/hooks/backlog-lib.sh"
BACKLOG_OPEN_N=""; BACKLOG_MARKS_N=""; BACKLOG_DONE_N=""; BACKLOG_BLOCKED_N=""
if [ -f "$BL_LIB" ] && [ -f "$PROJECT/BACKLOG.md" ]; then
    # shellcheck source=/dev/null
    . "$BL_LIB" 2>/dev/null || true
    if command -v backlog_open_items >/dev/null 2>&1; then
        BACKLOG_OPEN_N=$(backlog_open_items "$PROJECT/BACKLOG.md" 2>/dev/null | grep -c . || true)
        # ШИРОКИЙ счёт — по САМИМ символам меток, а не по `backlog_item_re`: первая
        # редакция считала обе стороны одним признаком, и ветка «метки есть, пунктов нет»
        # была недостижима по построению — признак не может разойтись сам с собой.
        # Широкий счёт заведомо БОЛЬШЕ строгого (метки стоят и в легенде, и в образце
        # разметки), поэтому сравнение идёт не «больше ли», а «строгий ноль при непустом
        # широком» — единственное состояние, где долг невидим ВСЕМ читателям.
        BACKLOG_MARKS_N=$({ backlog_read "$PROJECT/BACKLOG.md" 2>/dev/null || cat -- "$PROJECT/BACKLOG.md" 2>/dev/null; } | backlog_strip_fenced 2>/dev/null \
            | grep -cE "$(backlog_marks_alt "$BACKLOG_OPEN_MARKS")" 2>/dev/null || true)
    fi
fi
# Что уехало бы в архив, отвечает сам архиватор (D1263, скептик M1/M2): режим `check` без исполнения команд
# (`BACKLOG_ARCHIVE_RUN_CHECKS=0`, порог возраста как у сборщика) называет выполненные (☑ и ⊘) и поимённо — отказанные
# по форме. Свой счёт по метке ☑ расходился с ним (Jurnalist: 34 против 40) и советовал включить уборку там, где
# архиватор не унёс бы ни одного пункта. Код 2 и выше либо нет архиватора — «не сосчитано», а не «закрытых 0» (род B).
_BL_ARCH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/backlog-archive.sh"
if [ -f "$_BL_ARCH" ] && [ -f "$PROJECT/BACKLOG.md" ]; then
    _bl_tmp=$(mktemp -d 2>/dev/null) && {
        # Маркер вложенности снимается только здесь: команд архиватор не исполняет — кольца нет, а под маркером он
        # отвечает «перенос пропущен» кодом 0, и справка пропадала в любом прогоне из «Проверки» (гейт, архиватор).
        _bl_out=$(cd "$PROJECT" && env -u BACKLOG_CHECKS_NESTED BACKLOG_FILE="$PROJECT/BACKLOG.md" \
            BACKLOG_ARCHIVE="$_bl_tmp/archive.md" BACKLOG_ARCHIVE_RUN_CHECKS=0 BACKLOG_CONTRACT_MIN_ID=0 \
            bash "$_BL_ARCH" check </dev/null 2>&1); _bl_rc=$?
        if [ "$_bl_rc" -le 1 ]; then
            BACKLOG_DONE_N=$(printf '%s\n' "$_bl_out" | sed -n 's/.*выполненных пунктов: \([0-9][0-9]*\).*/\1/p' | head -1)
            [ -n "$BACKLOG_DONE_N" ] && BACKLOG_BLOCKED_N=$(printf '%s\n' "$_bl_out" \
                | sed -n 's/^  · \([^:][^:]*\): .*/\1/p' | sort -u | grep -c . || true)
        fi
        rmdir "$_bl_tmp" 2>/dev/null
    }
fi
python3 - "$PROJECT" "$TEMPLATES" "$PROJECTS_DIR" "$SESSION_STALE_DAYS" "$BACKLOG_OPEN_N" "$BACKLOG_MARKS_N" "$CLAUDSOUL" \
    "$BACKLOG_DONE_N" "$BACKLOG_BLOCKED_N" <<'PY'
import json, os, re, sys, pathlib, time, subprocess

proj, templates, projects_dir, stale_days = (
    pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
    pathlib.Path(sys.argv[3]), int(sys.argv[4]))
# Показания читателя долга приходят аргументами, как и остальное: пустая строка значит
# «читателя не спросили» и отличима от «0 пунктов» (D416).
BACKLOG_OPEN_N = sys.argv[5] if len(sys.argv) > 5 else ""
BACKLOG_MARKS_N = sys.argv[6] if len(sys.argv) > 6 else ""
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
# Требуется только `modules/`: на него завязаны docs-family-check.sh:251,
# claude-md-size-check.sh:58 и auto-scanner.sh:208. Каталоги `sessions/` и `refactoring/`
# инициатор предписывает с самого начала, но в дереве нет НИ ОДНОГО механизма, который их
# создаёт или читает: единственное упоминание `sessions/` — комментарий
# pre-compact-handoff.sh:9, и он врёт, код пишет в `handoff-snapshots`. Требовать их
# значило бы мерить договор, а не работу.
cd = proj / ".claude-docs"
# `docs-family-check.sh:251` принимает ЛИБО `.claude-docs/modules/*.md`, ЛИБО
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
    _open_n = BACKLOG_OPEN_N
    _marks_n = BACKLOG_MARKS_N
    if _open_n == "":
        findings.append(("НЕ ПРОВЕРЕНО", "BACKLOG.md есть, но читателя не спросили",
                         "hooks/backlog-lib.sh недоступна — «файл есть» не значит «пункты видны»; "
                         "это не «чисто», а «проверить нечем»"))
    elif _marks_n not in ("", "0") and _open_n == "0":
        findings.append(("разметка", "BACKLOG.md есть, метки есть, а пунктов читатель НЕ ВИДИТ",
                         "меток %s, опознанных пунктов 0 — долг проекта невидим всем читателям "
                         "(архиватор, completion-gate, session-collector)" % _marks_n))
    else:
        oks.append("BACKLOG.md есть, читатель видит открытых пунктов: %s — долг проекта виден"
                   % _open_n)
else:
    findings.append(("нет", "BACKLOG.md отсутствует",
                     "session-collector.sh:262 читает локальный долг по cwd — "
                     "читатель есть, файла нет: долг проекта невидим"))

# --- уборка бэклога проекта: признак согласия (D1263) --------------------------
# Сборщик Stop уносит закрытые пункты проекта в архив только по признаку `CG_LOCAL_BACKLOG` — он же граница доверия:
# архиватор исполняет «Проверки» (`hooks/session-collector.sh:654`, D512). Без признака закрытые копятся, и «уборка
# выключена» отвечала тем же молчанием, что «убирать нечего» (R6; повод — blalb, 7 ноября 2026). Включить — решение
# владельца, поэтому справка, а не расхождение. Бэклог самого ClaudSoul сборщик убирает без признака.
BACKLOG_DONE_N = sys.argv[8] if len(sys.argv) > 8 else ""
BACKLOG_BLOCKED_N = sys.argv[9] if len(sys.argv) > 9 else ""
if bl.is_file() and BACKLOG_DONE_N not in ("", "0") and proj.resolve() != pathlib.Path(sys.argv[7]).resolve():
    # Файла настроек нет — признака в нём нет; файл есть, а не читается (битый JSON) — «не смог», и о выключенной уборке
    # тогда не утверждается: называется нечитаемый файл (род B — отказ чтения не подменяется ответом «признака нет»).
    unread = []
    def _flag(p):
        if not p.is_file():
            return ""
        try:
            return (json.load(open(p, encoding="utf-8")).get("env") or {}).get("CG_LOCAL_BACKLOG", "")
        except (OSError, ValueError, AttributeError):
            unread.append(str(p))
            return None
    want = os.path.realpath(bl)
    have = {os.environ.get("CG_LOCAL_BACKLOG", ""), _flag(pathlib.Path.home() / ".claude" / "settings.json")}
    have |= {_flag(proj / ".claude" / n) for n in ("settings.json", "settings.local.json")}
    if want in {os.path.realpath(h) for h in have if h}:
        pass
    elif unread:
        notes.append("уборка бэклога проекта: признак согласия не проверен — не прочитан " + ", ".join(unread))
    else:
        done, blocked = int(BACKLOG_DONE_N), int(BACKLOG_BLOCKED_N or 0)
        movable = max(done - blocked, 0)
        if movable == 0:
            notes.append(f"уборка бэклога проекта выключена, но и включённая не унесла бы ни одного: закрытых {done}, "
                         f"все не в форме договора закрытия (нет «Проверки»/«Результата», у ⊘ — «Вердикта»); сперва "
                         f"дописать строки — пункты называет `scripts/backlog-archive.sh check` в каталоге проекта")
        else:
            notes.append(f"уборка бэклога проекта выключена: в архив уехали бы {movable} из {done} закрытых (по форме, без "
                         f"исполнения «Проверок»; не в форме — {blocked}); включить — в {proj}/.claude/settings.json: "
                         f'"env": {{"CG_LOCAL_BACKLOG": "{want}"}}. Признак делает бэклог доверенным: на каждом Stop '
                         f"архиватор исполняет «Проверки» закрытых пунктов, а гейт — «Проверки» открытых")

# --- 5. память проекта --------------------------------------------------------
# Слаг каталога памяти НЕ угадывается перечислением символов: Claude Code схлопывает
# в дефис и «_», которого в списке не было, — и проверка объявляла отсутствующей живую
# память ProjectA_NEW (49 записей). Формула-перечисление промахивается на первом же символе
# вне списка; брат того же корня — knowledge-activator.sh:915 (там заменяется только «/»,
# поэтому мимо летит любой путь с пробелом, и молча). Поэтому: сперва точное имя, затем
# сопоставление с точностью до небуквенных — так работает любой разделитель.
enc = "-" + str(proj).lstrip("/").replace("/", "-").replace(" ", "-")
mem = projects_dir / enc / "memory"
if not mem.is_dir() and projects_dir.is_dir():
    import re as _re
    _norm = lambda s: _re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    _want = _norm(str(proj))
    for _d in sorted(projects_dir.iterdir()):
        if _d.is_dir() and _norm(_d.name) == _want:
            mem = _d / "memory"
            break
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
    # Носитель версии живёт и в подкаталоге: у ProjectA_NEW код в web/, package.json там
    # же (2.105.1), а проверка «только корень» объявляла его отсутствующим. Допущение
    # «код лежит в корне» ложно для любого монорепо — смотрим корень и первый уровень.
    _carriers = ("VERSION", "package.json", "pyproject.toml", "Cargo.toml")
    has_version = any((proj / f).exists() for f in _carriers) or any(
        (sub / f).exists()
        for sub in proj.iterdir()
        if sub.is_dir() and not sub.name.startswith(".") and sub.name != "node_modules"
        for f in _carriers)
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

# --- 7. карта связей проекта (шаг 1д) -----------------------------------------
# Карта нужна только git-дереву: подсказка и хук коммита молчат без неё. Инструменты — ClaudSoul (не код проекта).
claudsoul = pathlib.Path(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] else None
pm_json = proj / ".claude-docs" / "project-map.json"
if (proj / ".git").is_dir() and claudsoul:
    dep = claudsoul / "scripts" / "dep-index.py"
    if not pm_json.is_file():
        # Справка, не дефект: отсутствие карты — не-сделанное/осознанное (как knowledge/), её заводит /init-project.
        # Жёстким расхождением оно объявило бы несоответствующим всякий ещё не промигрированный проект.
        notes.append("карты связей нет (.claude-docs/project-map.json) — подсказка перед правкой и хук коммита "
                     "молчат; /init-project заведёт описание, учёт и карту")
    elif dep.is_file():
        # Чьё дерево судить — называем прибору (--repo); CLAUDSOUL_REPO снимаем, чтобы он не взял чужой корень из среды.
        _env = {k: v for k, v in os.environ.items() if k != "CLAUDSOUL_REPO"}
        r = subprocess.run(["python3", str(dep), "--repo", str(proj), "--check"],
                           capture_output=True, text=True, env=_env)
        if r.returncode == 0:
            oks.append("описание устройства проекта есть, учёт зависимостей свеж")
        elif r.returncode == 2:
            notes.append("учёт зависимостей: прибор не смог проверить — " + (r.stderr.strip()[:100] or "код 2"))
        else:
            findings.append(("не свеж", "учёт зависимостей разошёлся с деревом",
                             "пересобери: python3 " + str(dep) + " --repo . --all"))
        # Виды файлов, которых описание не знает: файлы с расширением кода, не покрытые образцами `code` — числом.
        try:
            sys.path.insert(0, str(claudsoul / "hooks" / "lib"))
            import project_map as _pm
            _m = _pm.load(str(proj))
            _code_ext = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts",
                         ".go", ".rs", ".rb", ".java", ".kt", ".php", ".c", ".cpp", ".cs", ".swift")
            _out = _pm.git(str(proj), "ls-files", "-z")   # обёртка, не голый git: не исполнять программы настроек чужого дерева (D1089)
            _unknown = {f.rsplit(".", 1)[-1] for f in _out.stdout.split("\0")
                        if f and f.endswith(_code_ext) and not _pm.is_code(_m, f) and not _pm.is_test(_m, f)}
            if _unknown:
                notes.append("виды файлов, которых описание не знает (расширения кода вне `code`): "
                             + str(len(_unknown)) + " — " + ", ".join(sorted(_unknown)))
        except Exception:
            pass

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
