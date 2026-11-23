#!/usr/bin/env python3
# Результат: в свидетелях нет ни одного подготовительного вызова, чей отказ нем —
#            у каждого либо читается код, либо отказ назван вслух.
# Проверка результата: python3 scripts/setup-call-guard.py --count даёт 0
"""setup-call-guard.py — реестр носителей класса «отказ подготовки мира молчит».

ПРЕДМЕТ. В свидетеле (hooks/tests/*.sh) мир проверки строится вызовами `cp`, `mkdir`, `git`,
`python3` и подобными. Если у такого вызова код возврата НЕ читается, а вывод выброшен в
/dev/null, то его отказ не говорит ничем: ни кодом, ни текстом. Свидетель продолжает работу
на несобранной фикстуре и судит не то, что объявлено, — а зелёный прогон у него выходит тот
же, что при собранной.

ЧТО ИЗМЕРЕНО (19 сентября 2026). Выборка 40 мест, у каждого вызов сломан подменой первого
слова-команды на `false`, свидетель прогнан целиком, рядом с подменой — маркер достижимости:
  · 21 — МОЛЧИТ (свидетель остался зелёным),
  · 19 — ГОВОРИТ (свидетель покраснел),
  ·  0 — НЕ ИСПОЛНЕНО (строка не достигается).
Точность признака по последствию — 21 из 40, 52,5%. Это ОЧЕРЕДЬ НА РАЗБОР, а не список
дефектов: половина мест краснеет и без стража, потому что несобранная фикстура ломает
проверку ниже по тексту. Отличить одно от другого статически нельзя — только прогоном.

ВАЖНО О ЧИСЛЕ. Замер сделан на признаке ДО сужений: тогда он давал 420 мест. За 19 сентября
2026 область сужалась ПЯТЬ раз, каждый раз по сломанному месту, а не по догадке: многострочное
условие; `$?` в любой форме; перенос строки и фоновый амперсанд в конце; чтение кода
следующей строкой; подстановка.
Каждое сужение снимало ЛОЖНЫЕ срабатывания, поэтому точность от них могла лишь вырасти;
НАСКОЛЬКО — НЕ ИЗМЕРЕНО, перемер стоит новой выборки.

НАЗВАННЫЕ ПРЕДЕЛЫ.
  · Внутри подстановки `$( ... )` прибор МОЛЧИТ: там канал — значение, а не код, и это другое
    устройство. Замер того же дня: из девяти таких мест семь были самим предметом проверки
    (`OUT=$(… bash "$SCRIPT" …)` и следом `assert_contains "$OUT"`), два — настоящей
    подготовкой (`hooks/tests/run_all.sh:367-368`), и те два починены руками. Настоящий
    носитель такого вида в прибор больше не попадёт: роль результата различает человек.
    Условие снятия: появится признак ПОТРЕБИТЕЛЯ захваченного значения — сравнивает ли его
    строка ниже с ожиданием либо пускает в дальнейшую работу.
  · Тела heredoc исключены (там команда — данные), файлы с `set -e` исключены (там код
    читает оболочка).
  · Признак судит ФОРМУ вызова, а последствие — только прогон с подменой. Поэтому «носителей
    N» здесь значит «N мест, где отказ заведомо нем», а не «N дефектов». Что форма РАБОТАЕТ,
    а не просто стоит, проверяет третий контроль пробы `hooks/tests/fixtures/probe_D465.sh`.

Коды возврата: 0 — носителей нет; 1 — носители есть (печатаются); 2 — рамка не собралась.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

# ОБЩИЙ ЗАМОК (род H). `--fix` переписывает свидетелей, которых правят и другие руки —
# параллельная сессия, генератор, человек. Окно read→write открыто по построению. Берётся
# ТОТ ЖЕ протокол, что у соседа по задаче (`scripts/docs-address-drift.py --fix`), а не
# второй свой: у факта «файл правится» один владелец. Заведено 19 сентября 2026, когда
# реестр родов назвал этот файл носителем H сразу после коммита.
_LIB = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "lib"
if not (_LIB / "state_lock.py").exists():
    _LIB = pathlib.Path.home() / ".claude/hooks/lib"
sys.path.insert(0, str(_LIB))
try:
    from state_lock import with_lock
except ImportError:  # библиотеки нет — работаем как прежде: замок улучшает, а не требуется
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False

# Префикс-присваивание и `env` позиции команды не меняют: `HOME=/h bash x >/dev/null`, `env -u X git …` (D1261).
# Значение — слово с кавычками; класс без кавычек, иначе альтернативы пересекаются и перебор взрывается.
BUILD = re.compile(r'''^\s*(?:(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s;"'])*\s+)+|env\s+(?:(?:-u\s+\S+|-i|-|[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s;"'])*)\s+)*)?(cp|mv|mkdir|git|python3|bash|chmod|ln|tar|install)\b''')
# Ключевое слово перед вызовом позицию команды не меняет: `…; do bash x >/dev/null; done` (D1219),
# как и заголовок однострочной функции `f() { git add . >/dev/null; …; }`.
KEYWORD = re.compile(r'^\s*(then|do|else|\{|[A-Za-z_][\w-]*\s*\(\)\s*\{)\s+')
FUNC = re.compile(r'^\s*[A-Za-z_][\w-]*\s*\(\)\s*\{\s')
FUNC_OPEN = re.compile(r'^(\s*)[A-Za-z_][\w-]*\s*\(\)\s*\{\s*(#.*)?$')
# Код ВСЁ-ТАКИ читается: условие, логическая связка, явное присваивание, подстановка.
# `; then` и `; do` — хвост МНОГОСТРОЧНОГО условия: сам вызов стоит строкой ниже `if`, и
# его код читает оболочка. Первая редакция этого не знала и назвала носителем
# `hooks/tests/drift-check.sh:245` — вызов внутри `if`, то есть ложное срабатывание.
# `$?` в любой форме — код читается ЯВНО, как бы ни звалась переменная (`RCA=$?` первая
# редакция пропускала, потому что перечисляла имена rc/RC/_rc, а не предмет).
# Хвостовой `\` — строка НЕ САМОСТОЯТЕЛЬНА: следующая может читать код связкой `&&`.
# Хвостовой `&` — вызов ушёл в фон, кода у него нет по построению: другое устройство.
# Все три заведены 19 сентября 2026, когда первый проход `--fix` сломал синтаксис у четырёх
# свидетелей: `\ || {...}`, `& || {...}` и страж, повисший на присваивании вместо вызова.
READS = re.compile(r'(\|\||&&|;\s*(rc|RC|_rc)=|^\s*(if|while|until|elif)\b|\$\(|`|;\s*(then|do)\b'
                   r'|\$\?|\\\s*$|&\s*$)')
# Открытое многострочное условие: от `if`/`while`/`until` без `then`/`do` в той же строке и
# до первого `then`/`do` — всё внутри читается оболочкой.
# Код читает СЛЕДУЮЩАЯ строка: присваивание из `$?` либо проверка `$?` условием.
NEXT_READS = re.compile(r'\$\?')
OPENS_COND = re.compile(r'^\s*(if|while|until|elif)\b')
CLOSES_COND = re.compile(r'(^|;|\s)(then|do)\b')
MUTE = re.compile(r'>\s*/dev/null|2>\s*/dev/null')
HEREDOC = re.compile(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?")
SET_E = re.compile(r'^\s*set -[a-z]*e', re.M)


def carriers(root: pathlib.Path) -> list[tuple[str, int, str]]:
    base = root / "hooks" / "tests"
    if not base.is_dir():
        return []
    out: list[tuple[str, int, str]] = []
    for path in sorted(base.glob("*.sh")):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as e:
            # Отказ чтения НАЗЫВАЕТСЯ, а не подставляет тишину (род B реестра родов).
            print(f"setup-call-guard: не прочитан {path}: {e}", file=sys.stderr)
            continue
        if SET_E.search(text):
            continue
        in_cond = False
        lines = text.split("\n")
        # ВНУТРИ ПОДСТАНОВКИ КАНАЛ — ЗНАЧЕНИЕ, А НЕ КОД, и это другое устройство. Строка
        # `OUT=$(… bash "$SCRIPT" 2>/dev/null)` с последующим `assert_contains "$OUT"` —
        # не подготовка мира, а САМ ПРЕДМЕТ проверки: её код возврата не читают намеренно.
        # Замер 19 сентября 2026: из девяти таких мест семь были предметом проверки
        # (`test_claudsoul_context_pointer.sh:114,121,128`, `test_docs_family_check.sh:200,223`,
        # `test_contract_line_anchor.sh:52`, `test_backlog_readers_agree_hostile.sh:107`), и лишь
        # два — настоящей подготовкой (`run_all.sh:367-368`, сбор списка правок; у них
        # потребитель захваченного значения — не вердикт, а данные). Те два починены руками:
        # вызовы вынесены из подстановки, каждый со своей проверкой, неполнота названа вслух.
        # Признак сужен по УСТРОЙСТВУ, и ложных в нём было 7 из 9.
        # НАЗВАННЫЙ ПРЕДЕЛ: различает роль результата не прибор, а человек — подготовку от
        # предмета проверки статически не отделить. Внутри подстановки прибор теперь молчит
        # всегда, и настоящий носитель такого вида в него не попадёт.
        # Условие снятия: появится признак ПОТРЕБИТЕЛЯ захваченного значения — сравнивает ли
        # его строка ниже с ожиданием (тогда это предмет проверки) либо пускает в дальнейшую
        # работу (тогда подготовка). Признак этот выводится разбором, а не перечнем имён, и
        # до него правило держится на человеке.
        # Тела heredoc и подстановки — у одного разбора с кавычками (`scan`). Свой поиск heredoc здесь
        # был без кавычек и пропускал терминатор внутри подстановки: у `EXP=$(python3 - <<'EOF'` строка
        # `EOF` терялась, и прибор молчал обо всём ниже (`test_ablation_protocol_claims.sh:135`,
        # `test_merge_root_gate.sh:223`; скептик opus по d319d94e).
        in_subst, in_body = scan(text)
        func = None  # отступ заголовка многострочной функции, внутри которой стоит строка
        for i, line in enumerate(lines, 1):
            if i in in_body or i in in_subst:
                continue
            m = FUNC_OPEN.match(line)
            if m:
                func = m.group(1)
            elif func is not None and line.rstrip() == func + "}":
                func = None
            if in_cond:
                if CLOSES_COND.search(line):
                    in_cond = False
                continue
            if OPENS_COND.match(line) and not CLOSES_COND.search(line):
                in_cond = True
                continue
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            nxt = lines[i] if i < len(lines) else ""
            # Последняя команда многострочного тела функции — её код возврата (`run_bash() {` …
            # `bash "$HOOK" 2>/dev/null` / `}`, `test_knowledge_frontmatter_check.sh:208`).
            if func is not None and nxt.rstrip() == func + "}":
                continue
            for a, b, _tail in carrier_spans(line, nxt):
                out.append((str(path.relative_to(root)), i, line[a:b].strip()[:120]))
    return out


def segments(line: str) -> list[tuple[int, int]]:
    """Границы команд строки: `;` и `;;` вне кавычек, вне `$( … )` и обратных кавычек.

    Судится КАЖДАЯ команда строки, а не начало: до D1219 (6 ноября 2026) признак видел вызов
    только первым словом строки, и `K="$TMP/k"; bash … --install … >/dev/null 2>&1` молчал —
    с ним и строками, которые прятал разбор heredoc без кавычек, — 74 места в 34 свидетелях.
    Хвостовой комментарий в команду не входит: `;` в нём — текст.
    НАЗВАННЫЕ ПРЕДЕЛЫ (скептик opus по d319d94e):
      · последняя команда тела функции считается прочитанной — её код возвращает функция, хотя
        вызывающий может его и не читать;
      · хвост списка `a && cp … 2>/dev/null` не судится — `&&` и `||` команду не делят, хотя код
        хвоста не читает никто: 125 мест, пункт D1262;
      · группа `{ a; b; } >/dev/null` судится по командам: вывод, выброшенный у группы целиком,
        команде не приписывается; подоболочка `( a; b )` судится как строка — страж в ней
        убил бы только подоболочку;
      · `$(` внутри `"…"`, `${…;…}`, `$'…\'…'`, `for ((…;…))` кавычки и подстановки различают
        приближённо — на ответ прибора в корпусе не влияет ни одна (частота 0);
        `bash -n` перед записью ловит сломанный синтаксис, но не стража, вставшего внутрь строки.
    Одиночный `&` верхнего уровня делит команды, как `;`: команда слева ушла в фон, кода у неё в этой строке нет, и
    `carrier_spans` её не судит. До 9 ноября 2026 `&` команды не делил, и `--fix` повесил стража на присваивание за ним —
    `( … bash x >/dev/null 2>&1 ) & pids="$pids $!" || страж` (`hooks/tests/test_state_lock.sh:169`, скептик opus по
    5d465274, D1261 M3): страж не срабатывал никогда.
    """
    spans, start, q, depth, i, n = [], 0, None, 0, 0, len(line)
    while i < n:
        ch = line[i]
        if ch == "\\" and q != "'":
            i += 2
            continue
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif line.startswith("$(", i):
            depth += 1
            i += 1
        elif ch == ")" and depth:
            depth -= 1
        elif ch == "#" and not depth and (i == 0 or line[i - 1].isspace()):
            n = i
            break
        elif ch == ";" and not depth:  # `;;` — два `;`, пустая команда между ними отбрасывается
            spans.append((start, i))
            start = i + 1
        elif (ch == "&" and not depth and line[i - 1:i] not in ("&", ">", "<", "|")
              and line[i + 1:i + 2] not in ("&", ">")):  # не `&&`, `2>&1`, `>&2`, `|&`, `&>`
            spans.append((start, i))
            start = i + 1
        i += 1
    spans.append((start, n))
    return [(a, b) for a, b in spans if line[a:b].strip()]


def list_parts(seg: str) -> list[tuple[int, int]]:
    """Части списка `a && b || c` на верхнем уровне — вне кавычек, подстановок и групп `( … )`/`{ …; }`.

    Код каждой части, кроме последней, читает связка; код ПОСЛЕДНЕЙ не читает никто (D1262): `[ -d x ] && cp a y/
    2>/dev/null` — немой хвост, `cp a y/ 2>/dev/null && echo ok` — нет.
    """
    parts, start, q, depth, i, n = [], 0, None, 0, 0, len(seg)
    while i < n:
        ch = seg[i]
        if ch == "\\" and q != "'":
            i += 2
            continue
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif ch in "({":
            depth += 1
        elif ch in ")}" and depth:
            depth -= 1
        elif not depth and seg.startswith(("&&", "||"), i):
            parts.append((start, i))
            start = i + 2
            i += 2
            continue
        i += 1
    parts.append((start, n))
    return parts


def _closes_outer(s: str) -> bool:
    """В `s` есть `)` или `}` вне кавычек без своей открывающей: часть закрывает группу, открытую раньше."""
    depth, q, i = 0, None, 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and q != "'":
            i += 2
            continue
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif ch in "({":
            depth += 1
        elif ch in ")}":
            depth -= 1
            if depth < 0:
                return True
        i += 1
    return False


def _group_last(seg: str) -> str | None:
    """`( … ) >/dev/null` и `{ …; } >/dev/null`: последняя команда группы, если вывод выброшен у группы целиком."""
    s = seg.lstrip()
    if not s or s[0] not in "({":
        return None
    close = {"(": ")", "{": "}"}[s[0]]
    depth, q, i = 0, None, 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and q != "'":
            i += 2
            continue
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif ch in "({":
            depth += 1
        elif ch in ")}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    rest = s[i + 1:]
    if s[i:i + 1] != close or not MUTE.search(rest) or READS.search(rest):
        return None
    inner = s[1:i]
    cmds = segments(inner)
    if not cmds:
        return None
    a, b = cmds[-1]
    pa, pb = list_parts(inner[a:b])[-1]
    return KEYWORD.sub("", inner[a:b][pa:pb])


def carrier_spans(line: str, nxt: str) -> list[tuple[int, int, bool]]:
    """Команды строки, чей отказ нем: подготовительный вызов, код не читается, вывод выброшен.

    Возвращает (начало, конец, хвост): хвост — последняя часть списка `a && <вызов>`; стража ему ставят ВНУТРЬ
    (`a && { <вызов> || страж; }`), иначе ложное `a` подняло бы стража (D1262).

    СЛЕДУЮЩАЯ КОМАНДА МОЖЕТ ЧИТАТЬ КОД. `rc=$?` и `[ "$?" -eq N ]` стоят следом за вызовом —
    в той же строке после `;` или строкой ниже (`nxt`), — тогда он не носитель, а страж,
    вписанный сюда, ПОДМЕНИЛ БЫ читаемый код своим. Поймано 19 сентября 2026 на
    `hooks/tests/test_instruments_honest.sh:80`, где строка ниже проверяет `-eq 2`.
    """
    spans = segments(line)
    out = []
    for k, (a, b) in enumerate(spans):
        if line[b:b + 1] == "&":  # фоновая команда: код придёт к `wait`, не сюда
            continue
        parts = list_parts(line[a:b])
        pa, pb = parts[-1]
        pa, pb = a + pa, a + pb
        # Хвост, закрывающий скобку группы со строки выше (`( cd x && \` / `&& git … ) >/dev/null`), обёртке не
        # поддаётся: `{ … ) …; }` рвёт группу. Код группы — код её последней команды, и страж встаёт после неё.
        tail = len(parts) > 1 and not _closes_outer(line[pa:pb])
        seg = KEYWORD.sub("", line[pa:pb])
        inner = _group_last(seg)
        if inner is not None:
            if not BUILD.match(inner):
                continue
        elif not BUILD.match(seg) or READS.search(seg) or not MUTE.search(seg):
            continue
        after = line[spans[k + 1][0]:spans[k + 1][1]] if k + 1 < len(spans) else nxt
        # Последняя команда тела функции — её код возврата, его читает вызывающий: `run() { bash x 2>/dev/null`,
        # `rc() { mkdir -p d; bash -c … 2>/dev/null; }` (`test_queued_reply_readers.sh:79`).
        if FUNC.match(line) and (k + 1 == len(spans) or after.strip() == "}"):
            continue
        # `…; then` и `…; do` следом — вызов стоит хвостом условия, его код читает оболочка: ветка
        # READS `;\s*(then|do)` после резки по `;` мертва, и без этой строки условие стало бы `exit 1`.
        if NEXT_READS.search(after) or re.match(r'\s*(then|do)\b', after):
            continue
        # Следующая команда закрывает группу и читает её код связкой (`…; } && ok || bad`): код хвоста — предмет ноги, и
        # страж, вставленный сюда, оборвал бы свидетеля на его собственной регрессии (скептик opus D1262, H1:
        # `test_project_map.sh:298` — 161 проверка из 213 не исполнялась).
        if re.match(r'\s*[)}]\s*(&&|\|\|)', after):
            continue
        out.append((pa, pb, tail))
    return out


def lines_in_substitution(text: str) -> set[int]:
    """Номера строк, попавших внутрь НЕЗАКРЫТОЙ подстановки `$( ... )`.

    Носителями они остаются — кода там не читает никто, — но механический страж им не
    годится: `exit 1` внутри подстановки убивает подоболочку, а не свидетеля, и строка
    вдобавок обычно стоит в группе, отдающей вывод в конвейер. Поймано 19 сентября 2026
    первым же прогоном `--fix`: он вписал стража в `hooks/tests/run_all.sh:367-368`, внутрь
    `$( { … } | sort -u )`. Правка откачена. Предел был назван прозой в шапке этого файла
    с самого начала и не исполнялся ничем — теперь у него есть механизм.
    """
    # Глубина считается РАЗБОРОМ, а не счётом символов: скобка в кавычках (`/[(]чек-лист/`), в
    # комментарии (`D1019)`) и в теле heredoc — данные. Счёт символов прятал куски файлов целиком:
    # `test_merge_root_gate.sh:101-252` «внутри подстановки» из-за `[(]` в awk (скептик opus по d319d94e).
    # `< <( … )` и `>( … )` — тоже подоболочка: страж ef8a65d3 в `test_derived_counts_inventory.sh:82`
    # стоял внутри неё и свидетеля не останавливал (L5).
    return scan(text)[0]


def scan(text: str) -> tuple[set[int], set[int]]:
    """(строки внутри подстановки, строки тел heredoc) — одним разбором с кавычками.

    Тело heredoc — данные; `<<'EOF'` внутри кавычек (`printf '%s\\n' "git commit -F - <<'EOF'"`)
    heredoc не открывает. До D1219 у `carriers()` был свой поиск heredoc без кавычек: такой аргумент
    в `test_merge_root_gate.sh:223` «открывал» тело до конца файла, и прибор молчал о строках ниже.
    """
    out: set[int] = set()
    body: set[int] = set()
    stack: list[str] = []  # «S» — подстановка, «P» — скобка, «"» — двойные кавычки
    sq = False
    term = None
    for i, line in enumerate(text.split("\n"), 1):
        if term is not None:
            body.add(i)
            if line.strip() == term:
                term = None
            if "S" in stack:
                out.add(i)
            continue
        if "S" in stack:
            out.add(i)
        j, n = 0, len(line)
        while j < n:
            ch, top = line[j], (stack[-1] if stack else "")
            if sq:
                sq = ch != "'"
            elif ch == "\\":
                j += 1
            elif top == '"':
                if ch == '"':
                    stack.pop()
                elif line.startswith("$(", j):
                    stack.append("S")
                    j += 1
            elif ch == "'":
                sq = True
            elif ch == '"':
                stack.append('"')
            elif ch == "#" and (j == 0 or line[j - 1] in " \t;"):
                break
            elif line.startswith(("$(", "<(", ">("), j):
                stack.append("S")
                j += 1
            elif ch == "(":
                stack.append("P")
            elif ch == ")" and top in ("S", "P"):
                stack.pop()
            elif line.startswith("<<", j) and not line.startswith("<<<", j):
                m = HEREDOC.match(line, j)
                if m:
                    term = m.group(1)
                j += 1
            j += 1
    return out, body


def guarded(text: str, rel: str, line: int) -> str:
    # Строка — вычислением в момент падения (`$LINENO`), а не числом (D1306): вписанное число жило отдельно от места, и
    # каждая нога, вставленная выше, сдвигала его — 710 сообщений в 190 файлах правились вручную. `line` остаётся в
    # подписи: по нему ставится страж, а не адрес.
    return text + f' || {{ echo "подготовка мира не удалась: {rel}:$LINENO" >&2; exit 1; }}'


def fix(root: pathlib.Path, rows: list[tuple[str, int, str]]) -> tuple[int, list[str]]:
    """Ставит стража носителям. Возвращает (сколько поставлено, что пропущено).

    Страж встаёт в КОНЕЦ КОМАНДЫ-НОСИТЕЛЯ, а не строки: `||` связан с последней командой перед
    ним, и страж в конце строки накрыл бы только её. Хвостовой комментарий в команду не входит,
    поэтому страж встаёт перед ним. Строка внутри подстановки не трогается: `exit 1` там убьёт
    подоболочку, а не свидетеля. Файл, чей синтаксис правка сломала бы, не пишется и назван.
    """
    by_file: dict[str, set[int]] = {}
    for rel, line, _src in rows:
        by_file.setdefault(rel, set()).add(line)
    put, skipped = 0, []
    for rel, nums in by_file.items():
        path = root / rel
        with with_lock(str(path)):
            text = path.read_text(encoding="utf-8")
            subst = lines_in_substitution(text)
            ls = text.split("\n")
            n = 0
            for line in sorted(nums):
                cur = ls[line - 1]
                if line in subst:
                    skipped.append(f"{rel}:{line}\tв-подстановке\t{cur.strip()[:120]}")
                    continue
                for a, b, tail in reversed(carrier_spans(cur, ls[line] if line < len(ls) else "")):
                    end = a + len(cur[a:b].rstrip())
                    if tail:  # `a && <вызов>`: страж внутри, иначе ложное `a` подняло бы его (D1262)
                        beg = a + len(cur[a:b]) - len(cur[a:b].lstrip())
                        cur = cur[:beg] + "{ " + guarded(cur[beg:end], rel, line) + "; }" + cur[end:]
                    else:
                        cur = guarded(cur[:end], rel, line) + cur[end:]
                    n += 1
                ls[line - 1] = cur
            new = "\n".join(ls)
            if subprocess.run(["bash", "-n"], input=new, text=True, capture_output=True).returncode:
                skipped.append(f"{rel}\tправка сломала бы синтаксис\t{n} мест")
                continue
            path.write_text(new, encoding="utf-8")
            put += n
    return put, skipped


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".", help="корень дерева (по умолчанию текущий каталог)")
    ap.add_argument("--count", action="store_true", help="печатать только число носителей")
    ap.add_argument("--fix", action="store_true",
                    help="поставить стража простым носителям; сложные формы называются и не трогаются")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()
    if not (root / "hooks" / "tests").is_dir():
        print(f"setup-call-guard: нет {root}/hooks/tests — судить нечего", file=sys.stderr)
        return 2
    rows = carriers(root)
    if args.fix:
        put, skipped = fix(root, rows)
        print(f"стражей поставлено: {put}")
        if skipped:
            print(f"НЕ ТРОНУТО (нужна ручная разборка): {len(skipped)}", file=sys.stderr)
            for s in skipped:
                print("  " + s, file=sys.stderr)
        return 0 if not skipped else 1
    if args.count:
        print(len(rows))
        return 1 if rows else 0
    for f, i, s in rows:
        print(f"{f}:{i}\t{s}")
    print(f"носителей: {len(rows)}", file=sys.stderr)
    return 1 if rows else 0


if __name__ == "__main__":
    sys.exit(main())
