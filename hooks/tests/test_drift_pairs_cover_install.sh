#!/usr/bin/env bash
# test_drift_pairs_cover_install.sh — у каждого приёмника install.sh есть пара в drift-check.
#
# Результат: приёмника, который install.sh наполняет, а drift-check не сравнивает, нет.
# Проверка результата: bash hooks/tests/test_drift_pairs_cover_install.sh даёт 0
#
# Зачем (D105). `drift-check.sh` держал семь ПОИМЕННО написанных пар. Каталог, который
# install.sh раскладывает, но для которого пары не завели, не сравнивался никогда, и его
# расхождение давало не DRIFT и не BROKEN, а молчание — неотличимое от OK. Тот же класс,
# что маска мест в module-doc-check и область обхода в docs-inventory (28 августа 2026):
# предмет проверки задан тем, ГДЕ его нашли.
#
# Сводить семь пар к одному сравнению нельзя: у каждой своя семантика (побайтовая копия,
# область между маркерами, сгенерированный seed, регистрация в настройках). Правилом
# выражается не сравнение, а ПОКРЫТИЕ — и это то, что проверяет здешний тест.
#
# Замер на 28 августа 2026 до правки: приёмников 7, пар 7, непокрытых 2 (templates,
# statusline). Расхождения на диске не было — щель была тихой, а не сработавшей.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$REPO/install.sh"
DRIFT="$REPO/hooks/tests/drift-check.sh"
for f in "$INSTALL" "$DRIFT"; do
    [ -f "$f" ] || { echo "FAIL: $f не найден"; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

python3 - "$INSTALL" "$DRIFT" <<'PY'
import re, sys, pathlib

install = pathlib.Path(sys.argv[1]).read_text(errors="replace")
drift = pathlib.Path(sys.argv[2]).read_text(errors="replace")

# 1. Переменные-назначения, ведущие внутрь ~/.claude. Берём из самого install.sh, а не
#    из списка в голове: приёмник, заведённый завтра новой переменной, попадёт сюда сам.
env = {"CLAUDE_HOME": "$CLAUDE_HOME"}
# Значения переменной копим СПИСКОМ: переопределённая ниже по файлу переменная не должна
# затирать своё прежнее значение, иначе приёмник, доставленный через первое, исчезает.
env_multi = {}
for m in re.finditer(r'^([A-Za-z_]+)="(\$(?:CLAUDE_HOME|HOME)/[^"]*)"', install, re.M):
    val = m.group(2).replace("$HOME/.claude", "$CLAUDE_HOME")
    env.setdefault(m.group(1), val)
    env_multi.setdefault(m.group(1), []).append(val)
# Локальные переменные цикла скиллов: target_dir="$SKILLS_DIR/$skill_name"
for m in re.finditer(r'^\s*([a-z_]+)="(\$[A-Z_]+/[^"]*)"', install, re.M):
    env[m.group(1)] = m.group(2)

def expand(path, depth=0):
    if depth > 5:
        return path
    m = re.match(r"\$([A-Za-z_]+)(/.*)?$", path)
    if m and m.group(1) in env:
        return expand(env[m.group(1)] + (m.group(2) or ""), depth + 1)
    return path

# 2. Приёмники: назначение КАЖДОЙ доставки, приведённое к пути внутри ~/.claude.
#    Форм доставки много (`cp`, `cp -r/-a/-R`, `install -m`, `ln -s`, перенаправление,
#    `tee`), и перечислять их — та же ошибка, что этот тест ловит. Правило: берём ЛЮБОЙ
#    путь внутри `$CLAUDE_HOME`, встреченный как аргумент назначения или цель записи, а
#    строку, которую не смогли разобрать, НАЗЫВАЕМ вслух вместо молчания.
DELIVERY = re.compile(
    r'^\s*(?:cp|install|ln|mv|rsync)\b[^\n]*?"([^"]+)"\s*$'   # последний аргумент — назначение
    r'|^\s*(?:cat|tee|printf|echo|jq)\b[^\n]*?>\|?\s*"([^"]+)"'  # перенаправление в файл
    r'|^\s*>\s*"([^"]+)"', re.M)

# Приёмник — только тот, у кого ЕСТЬ источник в репозитории: пара сравнивает
# «репозиторий ↔ установленное», и файлу, порождённому на месте, сравнивать не с чем.
# Так честно отпадают `~/.claude/claudsoul-repo` (в нём путь ЭТОЙ машины, пишется `echo`)
# и `settings.json` (собирается `jq`); их состояние стережёт пара «регистрация хуков»,
# которая сверяет не байты, а факт регистрации. Это правило, а не список исключений:
# появится завтра ещё один порождаемый файл — отпадёт сам.
# Подстановки команд гасим ДО разбора: `cp "$x" "$T/$(basename "$x")"` несёт кавычки
# внутри кавычек, и без этого шага назначение из строки не извлекается вовсе — три
# настоящих приёмника (хуки, библиотеки, шаблоны) уезжали в «не разобрано».
SUBST = re.compile(r'\$\([^()]*\)')
install_flat = SUBST.sub("SUBST", install)
# Три написания одного каталога сводим к одному ДО разбора: `~/.claude`, `$HOME/.claude`
# и `${HOME}/.claude` — тот же приёмник, и различать их значит перечислять формы.
for _form in (r'\$\{HOME\}/\.claude', r'\$HOME/\.claude', r'(?<![\w/])~/\.claude'):
    install_flat = re.sub(_form, "$CLAUDE_HOME", install_flat)

def _from_repo(line):
    """Строка берёт источник ИЗ РЕПОЗИТОРИЯ.

    Косая после имени переменной бывает и внутри кавычек (`"$CLAUDSOUL_DIR/bin/x.sh"`), и
    сразу за закрывающей (`"$CLAUDSOUL_DIR"/hooks/*.sh`) — второй формой написаны шесть
    настоящих доставок install.sh, и требование косой внутри кавычек выбрасывало их разом
    из обоих проходов: ни приёмника, ни строки «не разобрано».
    """
    return bool(re.search(r'\$(?:CLAUDSOUL_DIR|REPO)"?/', line)
                or re.search(r'\$(?:hook_script|lib_file|tmpl|skill_dir|f)\b', line))

receivers = {}
unparsed = []
for m in DELIVERY.finditer(install_flat):
    raw = m.group(1) or m.group(2) or m.group(3)
    line = m.group(0)
    # Источник — ФАЙЛ репозитория, а не значение переменной: `echo "$CLAUDSOUL_DIR" >
    # "$REPO_POINTER"` кладёт путь ЭТОЙ машины, и сравнивать его с репозиторием нечем.
    # Отсюда обязательная косая после имени переменной.
    if not _from_repo(line):
        continue
    dst = expand(raw)
    if not dst.startswith("$CLAUDE_HOME/"):
        continue
    rel = dst[len("$CLAUDE_HOME/"):]
    # Состояние — не зеркало репозитория: baseline пишется один раз и живёт своей жизнью.
    if rel.startswith("hooks/state/"):
        continue
    parts = rel.split("/")
    # Приёмник — каталог (первые компоненты) либо одиночный файл в корне ~/.claude.
    key = parts[0] if len(parts) == 1 else "/".join(parts[:2] if parts[0] == "hooks" and parts[1] == "lib" else parts[:1])
    receivers.setdefault(key, m.group(1))

# Правило вместо эвристики формы: ЛЮБАЯ незакомментированная строка, называющая путь
# внутри ~/.claude и содержащая команду записи, обязана либо дать приёмник, либо быть
# названной неразобранной. Перечислять формы доставки нельзя — это ровно та ошибка,
# которую ловит сам этот тест (`cp -a`, `install -m`, `tee`, цикл в одну строку).
WRITERS = re.compile(r'\b(?:cp|install|ln|mv|rsync|cat|tee|printf|echo|jq)\b')
for line in install_flat.splitlines():
    s = line.strip()
    if s.startswith("#") or not WRITERS.search(s):
        continue
    for m2 in re.finditer(r'"([^"]*\$(?:CLAUDE_HOME|GLOBAL_LESSONS|SKILLS_DIR|HOOKS_TARGET|TEMPLATES_TARGET)[^"]*)"', s):
        dst2 = expand(m2.group(1))
        if not dst2.startswith("$CLAUDE_HOME/"):
            continue
        rel2 = dst2[len("$CLAUDE_HOME/"):]
        if rel2.startswith("hooks/state/"):
            continue
        head = rel2.split("/")[0]
        if head in receivers:
            continue
        if not _from_repo(s):
            continue          # источник не из репозитория — сравнивать нечего
        unparsed.append(s[:100])
        break

# 3. Покрытие: приёмник обязан реально СРАВНИВАТЬСЯ, а не упоминаться.
# Покрытие засчитывается только по строке, которая ДЕЙСТВИТЕЛЬНО сравнивает: вызов
# `_cmp_tree` либо `cmp`/`diff` с этим путём. Упоминание в тексте сообщения («не
# установлено: $CLAUDE_HOME/bin») и в комментарии парой не является — а прежняя версия
# засчитывала оба, то есть держала зелёным ровно то состояние, в котором пару правят.
# Отбрасываем комментарии и тексты сообщений `_emit`: путь живёт в файле не только в
# сравнениях, но и в «не установлено: $CLAUDE_HOME/bin». Прежняя версия засчитывала оба,
# то есть держала зелёным состояние «сравнение закомментировано, а покрытие числится».
comparing = "\n".join(
    l for l in drift.splitlines()
    if not l.lstrip().startswith("#") and not re.match(r'\s*_emit\b', l)
)

# Граница пути точная: `templates` не засчитывается сравнением `templates-old` — в
# регулярке `\b` перед дефисом совпадает, а каталог другой.
#
# НАЗВАННЫЙ ПРЕДЕЛ. Здесь проверяется, что путь приёмника встречается в ИСПОЛНЯЕМОМ коде
# детектора (не в комментарии и не в тексте сообщения `_emit`). Этого достаточно против
# «пару закомментировали» и «сравнивают соседний каталог», и НЕ достаточно против двух
# случаев: вызов, стоящий в заведомо ложной ветке, и путь, только присвоенный переменной
# без последующего сравнения. Отличить их текстом нельзя — нужна модель потока управления;
# поведенческую проверку каждой пары (подмени приёмник — вывод обязан измениться) держит
# отдельный тест `test_drift_pair_actually_compares.sh`.
#
# Условие снятия: предел держится, пока «действительно ли сравнивается» решается по
# ТЕКСТУ. Появится разбор потока управления оболочки (или переезд сравнения в код, где
# вызов виден статически) — предел снимается, и текстовый страж покрывает все случаи.
uncovered = []
for key, sample in sorted(receivers.items()):
    if re.search(r'\$CLAUDE_HOME/' + re.escape(key) + r'(?![\w.-])', comparing):
        continue
    uncovered.append((key, sample))

print(f"приёмников install.sh: {len(receivers)}, непокрытых пар: {len(uncovered)}")
for key, sample in uncovered:
    print(f"  · {key}   (например: {sample})")
if uncovered:
    print("  Заведи пару в hooks/tests/drift-check.sh: у приёмника без пары расхождение")
    print("  даёт молчание, неотличимое от OK.")
if unparsed:
    print(f"  строк доставки, которые НЕ РАЗОБРАЛИСЬ ({len(unparsed)}) — покрытие по ним неизвестно:")
    for line in unparsed:
        print(f"  · {line}")
sys.exit(1 if (uncovered or unparsed) else 0)
PY
