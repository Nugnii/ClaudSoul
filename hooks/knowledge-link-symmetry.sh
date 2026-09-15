#!/usr/bin/env bash
# knowledge-link-symmetry.sh — PostToolUse[Bash|Write|Edit|MultiEdit]: ссылка кейс → паттерн получает встречную.
# en: PostToolUse on knowledge writes, shell edits included — a case→pattern edge gets its back-reference written.
#
# Результат: у ссылки, объявленной в кейсе (`specializes`/`confirms`/`extends`/`generalizes`),
#            есть встречная запись в `source_cases` паттерна — без участия памяти автора
# Проверка результата: bash hooks/tests/test_knowledge_link_symmetry.sh даёт 0
#
# Зачем (D208). Симметрия — свойство ПАРЫ файлов, а создаётся односторонней записью: автор
# пишет `edges:` в кейсе, паттерн при этом не трогает никто. Закрытие D12 (v1.14.5)
# восстановило 22 ссылки руками и поставило ПРОВЕРКУ (`test_knowledge_link_symmetry.py` в
# наборе mcp), приняв её за поддержание. Замер 29 августа 2026: закрытие не удержалось —
# три односторонние ссылки, две созданы в тот же день, третья в апреле при живом стороже.
# Проверка ловит позже и в другом контуре, поэтому расхождение живёт от прогона до прогона.
#
# ПОЧЕМУ ДОПИСЫВАНИЕ, А НЕ НАПОМИНАНИЕ. Напоминание — уровень 2 укоренённости: замер
# 28 августа показал, что оно читается и не меняет действия. Здесь действие механическое и
# однозначное (добавить имя файла в список), спорных случаев нет — значит его надо делать,
# а не просить.
#
# КОНТРПРИМЕР, объявлен: ссылка на НЕСУЩЕСТВУЮЩИЙ паттерн не дописывается никуда — это
# опечатка или ещё не созданное знание, и молча заводить ему `source_cases` нельзя.
# НАЗВАННЫЙ ПРЕДЕЛ: правится только файл в `~/.claude/global-lessons`. Копия базы в
# `knowledge/` для чистой установки пересобирается `regen-seed.py` и здесь не трогается.
# Условие снятия: предел уйдёт, если seed перестанет быть производным от рабочей базы.
#
# Input  (stdin): {tool_name, tool_input:{file_path}} (PostToolUse JSON)
# Output (stdout): {hookSpecificOutput:{additionalContext}} — что дописано, либо пусто
# Exit:  always 0 (degrade gracefully).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
# Предмет механизма — ИЗМЕНЁННЫЙ ФАЙЛ, а не имя инструмента. Оболочка правит ровно те же
# файлы (heredoc, sed, короткий скрипт), и `file_path` у неё нет: тогда предметом
# становится вся рабочая база. Повод (5 сентября 2026): кейс записан `cat > … <<EOF`,
# хук стоял на `Write|Edit|MultiEdit`, не был вызван ВОВСЕ — и закрытие D12 откатилось.
# Знание об этом роде лежало в базе за два дня до рождения хука
# (`case-2026-08-27-tool-name-detection-blind-to-work-mode.md`, confirmed_count 4).
case "$TOOL" in Write|Edit|MultiEdit|Bash) ;; *) exit 0 ;; esac
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"

# Общий замок (род H): паттерн-родитель правят два хода сразу — этот хук стоит на
# PostToolUse каждой правки знания, и две записи кейсов, ссылающихся на один паттерн,
# приходят параллельно. Замок берётся ПОФАЙЛОВО на родителя (см. ниже) — то же имя,
# что берёт `knowledge-counter-bump.sh:449` через `lock_acquire "$FILE"`, поэтому
# сериализация с ним есть. Здесь до 5 сентября 2026 стояло обратное утверждение
# («bump этого замка не берёт»); оно было опровергнуто чтением bump:449 и снято.
STATE_LOCK_LIB="${STATE_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/state-lock-lib.sh}"
[ -f "$STATE_LOCK_LIB" ] || STATE_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
if [ -f "$STATE_LOCK_LIB" ]; then . "$STATE_LOCK_LIB"; fi

# Предмет — файл кейса В РАБОЧЕЙ БАЗЕ. Копия seed и чужие каталоги не трогаются.
# Названный адрес есть только у Write/Edit/MultiEdit. У оболочки его нет — тогда предметом
# становится вся база, и полный проход стоит ЦЕЛУЮ СЕКУНДУ: 1.1 с замером на живой машине
# (295 кейсов, 168 рёбер, `yaml.safe_load` по родителю на каждое ребро). Первый замер дал
# 43 мс и был НЕ О ТОМ: мерил чтение внутри уже запущенного питона, а не вызов хука целиком
# (`pattern-subject-of-measurement-mismatch`). Секунда на КАЖДУЮ команду оболочки —
# не цена, а поломка, поэтому впереди стоит сторож на самой оболочке: `find` по базе
# стоит 0.00 с и отсекает вызовы, при которых ни один кейс не менялся.
# НАЗВАННЫЙ ПРЕДЕЛ отметки: она общая и берётся без замка. Худший исход — правка, попавшая
# в окно между чтением отметки и её сдвигом, дождётся следующей записи знания; данные при
# этом не портятся, а сверщик (`scripts/backlog-recheck.sh`) остаётся вторым рубежом.
STAMP="${CLAUDSOUL_STATE_DIR:-$HOME/.claude/hooks/state}/link-symmetry-scan.stamp"
if [ -n "$FILE" ]; then
    case "$FILE" in
        "$LESSONS"/case-*.md) ;;
        *) exit 0 ;;
    esac
    [ -f "$FILE" ] || exit 0
else
    [ "$TOOL" = "Bash" ] || exit 0
    [ -d "$LESSONS" ] || exit 0
    if [ -f "$STAMP" ]; then
        # Сторож НЕ уже, чем предмет: любой изменённый кейс новее отметки, а именно из
        # изменённого кейса и берётся ссылка (`case-2026-08-22-cheap-prefilter-excludes-its-own-target`).
        _fresh=$(find "$LESSONS" -maxdepth 1 -name 'case-*.md' -newer "$STAMP" -print 2>/dev/null | head -1)
        [ -n "$_fresh" ] || exit 0
    fi
fi

# Замок ПОФАЙЛОВЫЙ, а не каталожный, и это условие работоспособности, а не вкус: взаимное
# исключение живёт на общем ИМЕНИ. `mkdir global-lessons.lock` и `mkdir <файл>.lock` — разные
# каталоги, друг друга не блокируют ни в одну сторону, а обе стороны считают себя защищёнными.
# Замер 5 сентября 2026: у базы знаний было ТРИ имени замка — каталог здесь, файл у
# `knowledge-audit-digest.sh` (через `atomic_filter`), никакого у `knowledge-counter-bump.sh`.
# Сведено к `<файл>.lock`. Имя родителя известно только внутри питона, поэтому замок берётся
# там; питоновская половина протокола — `hooks/lib/state_lock.py`, та же, что у оболочечной.
# Каталог библиотек вычисляет оболочка: питон запускается через stdin (`python3 - …`),
# и `__file__` внутри него не существует — вычислять путь там было бы гаданием.
HOOKS_LIB="${CLAUDSOUL_HOOKS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/lib}"
[ -d "$HOOKS_LIB" ] || HOOKS_LIB="$HOME/.claude/hooks/lib"

ADDED=$(env LESSONS_DIR="$LESSONS" CLAUDSOUL_HOOKS_LIB="$HOOKS_LIB" python3 - "${FILE:-}" <<'PY'
import re, sys, pathlib, os

for _c in (pathlib.Path(os.environ["CLAUDSOUL_HOOKS_LIB"]) if os.environ.get("CLAUDSOUL_HOOKS_LIB")
           else None, pathlib.Path.home() / ".claude/hooks/lib"):
    if _c and (_c / "state_lock.py").exists():
        sys.path.insert(0, str(_c))
        break
try:
    from state_lock import with_lock
except ImportError:  # библиотеки нет — работаем как прежде: замок улучшает, а не требуется
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False

# Инвариант «перечислен ли кейс в source_cases» — ОДИН на писателя и на приборы
# (`hooks/lib/link_symmetry.py`, D312). Своя копия здесь была третьей, и именно
# расхождение копий стоило 18 незамеченных асимметрий. Библиотека обязательна: без неё
# писать нельзя, потому что единственная альтернатива — слабое правило по подстроке,
# от которого и уходили. Отказ называется, а не заменяется тихой работой.
for _c in (os.environ.get("CLAUDSOUL_HOOKS_LIB"), str(pathlib.Path.home() / ".claude/hooks/lib")):
    if _c and (pathlib.Path(_c) / "link_symmetry.py").exists():
        sys.path.insert(0, _c)
        break
try:
    import link_symmetry as _ls
except ImportError:
    print("knowledge-link-symmetry: нет hooks/lib/link_symmetry.py — встречные ссылки НЕ дописаны",
          file=sys.stderr)
    print("")
    raise SystemExit(0)

_ld = os.environ.get("LESSONS_DIR") or str(pathlib.Path.home() / ".claude/global-lessons")
lessons = pathlib.Path(_ld)

# Адрес назван — правим один кейс; не назван (оболочка) — проходим базу целиком.
arg = sys.argv[1] if len(sys.argv) > 1 else ""
targets = [pathlib.Path(arg)] if arg else sorted(lessons.glob("case-*.md"))


added = []
for case in targets:
    if not case.name.startswith("case-") or not case.exists():
        continue
    text = case.read_text(errors="replace")
    # Снятое с учёта знание встречной ссылки не требует — так же считает и сверщик
    # (`scripts/backlog-recheck.sh:90`), иначе проход завёл бы связи, которых он не ждёт.
    if "DEPRECATED" in text[:2000]:
        continue
    # `parent_edges` отдаёт только рёбра на ПАРЕНТОВ: ребро кейс → кейс законно, но
    # `source_cases` в кейсе значит другое. Проверки рода здесь не было вовсе, и первый
    # же полный проход предложил испортить 7 кейсов (сухой прогон 5 сентября 2026).
    _edges = _ls.parent_edges(text)
    if _edges is None:
        # Симметрично отказу по стороне РОДИТЕЛЯ восемью строками ниже: молчание здесь
        # неотличимо от «рёбер нет», а писатель — единственный механизм, создающий
        # встречные ссылки. Молчащий писатель означает, что связи не пишутся, при зелёном
        # инварианте: он проверяет записанное и не спрашивает, почему записей нет (D333).
        print("knowledge-link-symmetry: " + case.name +
              " — edges не разобрать, встречные ссылки НЕ дописаны", file=sys.stderr)
        continue
    for _kind, target in _edges:
        parent = lessons / target
        # Контрпример: несуществующий паттерн не заводим — это опечатка либо ещё не созданное.
        if not parent.exists():
            continue
        # Всё окно read→write по родителю ПОД ЕГО замком, и чтение тоже внутри: прочитанное
        # до чужой записи легло бы поверх неё, и встречная ссылка соседа исчезла бы молча —
        # при том что хук напечатал бы «ссылка дописана».
        with with_lock(str(parent)):
            ptext = parent.read_text(errors="replace")
            fm = _ls.frontmatter(ptext)
            hi = 0 if fm is None else 3 + len(fm)
            if fm is None:
                # Родитель без frontmatter: места вставки нет, и определить его нечем.
                # Молчать здесь нельзя — молчание неотличимо от «дописывать было нечего»
                # (род B реестра дефектов). В рабочей базе таких родителей 0 из 50
                # (замер 5 сентября 2026), но отказ обязан быть слышен, если появится.
                print("knowledge-link-symmetry: " + parent.name +
                      " — frontmatter не найден, встречная ссылка НЕ дописана", file=sys.stderr)
                continue
            seen = _ls.listed(ptext, case.name)
            if seen is None:
                print("knowledge-link-symmetry: " + parent.name +
                      " — source_cases не разобрать, ссылка НЕ дописана", file=sys.stderr)
                continue
            if seen:
                continue
            m = re.search(r"^source_cases:(.*)$", ptext[:hi], re.M)
            if m:
                val = m.group(1)
                s = val.strip()
                if s == "":
                    # Блочный список: элемент строкой ниже.
                    ptext = ptext[:m.end()] + "\n  - " + case.name + ptext[m.end():]
                elif s.startswith("["):
                    if "]" not in val:
                        # Поточный список, НЕ закрытый в строке: построчная правка потеряла
                        # бы прежние кейсы. Молчаливая порча хуже отказа — не трогаем.
                        # Тот же контрпример объявлен у соседа (counter-bump:382-390).
                        continue
                    # Поточный список: дописываем ВНУТРЬ скобок, СОХРАНЯЯ форму. Иначе
                    # завёлся бы второй ключ `source_cases`; YAML при этом валиден,
                    # `yaml.safe_load` берёт ПОСЛЕДНИЙ и молчит — прежние кейсы исчезают
                    # из графа. Ровно это случилось 5 сентября 2026 с
                    # `pattern-marker-matches-form-not-role.md`: из 4 объявленных кейсов
                    # честному парсеру стал виден 1. Род был закрыт у соседа-писателя
                    # (counter-bump:511-518) за 12 ч 34 мин ДО того, как этот хук внёс
                    # его заново — класс, закрытый в одном механизме и оставленный в
                    # соседнем, возвращается тем же днём.
                    p_open = m.start(1) + val.index("[")
                    p_close = m.start(1) + val.rindex("]")
                    inside = ptext[p_open + 1:p_close]
                    ins = case.name if inside.strip() == "" else ", " + case.name
                    ptext = ptext[:p_close] + ins + ptext[p_close:]
                else:
                    # Скаляр вместо списка — форма вне договора `knowledge/META.md`.
                    # Не гадаем: правка вслепую здесь стоила бы данных.
                    continue
            else:
                # Поля нет — заводим его перед `related:`/`edges:`, то есть внутри frontmatter,
                # а не в конце файла: иначе YAML сломается и знание перестанет читаться.
                m2 = re.search(r"^(related:|edges:)", ptext[:hi], re.M)
                if not m2:
                    continue
                ptext = ptext[:m2.start()] + "source_cases:\n  - " + case.name + "\n" + ptext[m2.start():]
            parent.write_text(ptext)
        added.append(case.name + " → " + target)

print("\n".join(added))
PY
) || exit 0

# Отметка сдвигается и когда дописывать было нечего: «прошёл и не нашёл» — тоже результат
# прохода, и без сдвига сторож пропускал бы полный проход на каждой команде после правки.
if [ -z "$FILE" ]; then
    mkdir -p "$(dirname "$STAMP")" 2>/dev/null && : > "$STAMP" 2>/dev/null || true
fi

[ -n "${ADDED// /}" ] || exit 0

MSG="🔗 Встречная ссылка дописана автоматически:
${ADDED}
Симметрия — свойство пары файлов; проверка её ловила, но не создавала (D208)."
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}' 2>/dev/null || true
exit 0
