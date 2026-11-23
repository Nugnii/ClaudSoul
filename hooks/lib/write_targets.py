#!/usr/bin/env python3
"""write_targets.py — ПУТИ, с которыми вызов действительно что-то делает, из текста команды.

Вопроса два, и режим выбирает который: `--targets` (по умолчанию) — какой путь вызов
СОЗДАЁТ; `--calls` — какой файл вызов ЗАПУСКАЕТ. Общего у них ровно то, ради чего файл и
заведён: `shell_text` ниже отделяет текст, который исполнит ОБОЛОЧКА, от текста, который
она лишь передаёт другим — телам чужих heredoc и содержимому кавычек.

Предмет расширен 16 сентября 2026 (D424) и объявлен здесь вслух: прежде шапка обещала
только цели создания, а `--calls` сделал бы область файла шире его утверждения — это род L
реестра. Имя файла оставлено: переименование тронуло бы установщик, журнал переносов и
трёх потребителей, то есть перестало бы быть хирургической правкой.
Ещё два вопроса: `--prefix-env` — какая переменная выставлена перед какой командой; `git_calls`
(импортом, без режима) — какие вызовы git исполнит оболочка и в каком каталоге (D526); `--edits` — какой путь
вызов МЕНЯЕТ: создание, удаление, правка на месте, меняющие вызовы git, загрузка `curl`/`wget`, `chmod`,
`find -delete`, `tar -x` — вопрос «вызов пишет» стража разбора (D1160, D1215).

Результат: потребитель получает пути, которые вызов ДЕЙСТВИТЕЛЬНО создаёт или запускает,
           а не слова, похожие на пути, где-то в тексте
Проверка результата: bash hooks/tests/test_skill_name_ascii_guard.sh даёт 0
                     bash hooks/tests/test_undefined_function_guard.sh даёт 0

Зовётся через `executable_write_targets` из hooks/command-scope-lib.sh — владельца сужения
области внутри текста команды. Своей копии разбора у потребителей нет (род K реестра).

ПОЧЕМУ ЭТО НЕ РЕЦИДИВ УДАЛЁННОГО hooks/lib/write-target-lib.sh. Тот разбор целей был снят
целиком: противник нашёл 5 подтверждённых дыр из 6. Различие в КВАНТОРЕ, и оно решает.
Там предикат ОСВОБОЖДАЛ вызов от отказа — одна распознанная приманка снимала защиту, и
цена промаха была «защита не сработала». Здесь предикат ОТКАЗЫВАЕТ: нераспознанная форма
даёт ПРОПУСК, а не ложный отказ. Цена ошибки обратная, поэтому и решение обратное.
Без этой записи следующий заход прочтёт то удаление как запрет на всякий разбор целей.

НАЗВАННЫЙ ПРЕДЕЛ. Разбирается ЛЕКСИКА, а не грамматика оболочки: подстановка команд,
раскрытие скобок и переменные значений до исполнения не имеют. Литеральность судит
ПОТРЕБИТЕЛЬ, потому что зернистость у них разная: страж имени скилла судит сегмент-имя
(`mkdir "$HOME/.claude/skills/Имя"` — имя литеральное, отказ законен), карта связей — путь
целиком. Предикат при этом один, здесь: режим `--literal` отдаёт только цели, известные
целиком (без `_NONLITERAL` и ведущей тильды), — D1037, 23 октября 2026. Первая редакция
отбрасывала нелитеральное в выдаче по умолчанию и онемила отказ стража скилла на путях
через `$HOME`/`$PWD`/`$(…)` (финальный скептик D1037). Названный предел: литерал в кавычках
со знаком `$ [ ] { }` (`'price$.md'`) режим `--literal` теряет — кавычки сняты до суда; в
дереве таких файлов 0. Условие снятия: такой файл появится в дереве.
"""
import posixpath
import re
import shlex
import sys

# Операции, создающие путь. Разделены по тому, ГДЕ у них цель, а не свалены в один список:
# у первых целью может быть каждый аргумент, у вторых — только последний.
ALL_ARGS = {"mkdir", "touch", "tee"}
# Ключи со значением у ALL_ARGS (D1123): значение — не цель записи. `touch -t <время>`, `-d <дата>`, `-r <образец>` (образец
# ЧИТАЕТСЯ), `mkdir -m <режим>`. Прежде целью считалось каждое слово без дефиса, и карта связей внесла узел «202601010000».
# Разбор ключей — тот же, что у git (`_git_opts`): кластеры, `--`, длинные ключи с `=` и без.
_ALL_ARGS_VAL = {"touch": (set("tdrA"), {"--date", "--reference", "--time"}), "mkdir": (set("m"), {"--mode"})}
# `-A` — смещение времени у BSD/macOS touch (D1136). Операнд после `--` — цель, даже если начинается с дефиса: ключи уже
# отделил разбор, и фильтр «не начинается с дефиса» поверх него срезал бы операнд.


def _all_args_paths(head, rest):
    sv, lv = _ALL_ARGS_VAL.get(head, (set(), set()))
    return _git_opts(rest, sv, set(), lv)[1]

LAST_ARG = {"mv", "cp", "install", "rsync", "ln"}
# Правка на месте (режим `--edits`, D1160): ключ `-i` у sed/perl/ruby. У ключа со значением остаток кластера либо следующее
# слово — значение, и `i` там ключом не является: `perl -MTime::HiRes`, `-Ilib`, `sed -f inplace.sed`.
_INPLACE = {"sed": (set("efl"), {"--expression", "--file", "--line-length"}), "perl": (set("eEIMmxdCF"), set()),
            "ruby": (set("eErIxCFK"), set())}
_INPLACE["gsed"] = _INPLACE["sed"]


def _inplace_files(head, rest):
    """Файлы правки на месте либо пусто — ключа `-i` нет. Скрипт не задан ключом (`sed -i s/a/b/ f`) — первое слово
    программа, а не файл. Файлов нет (`xargs sed -i …` берёт их со входа) — «-»: правка есть, путь неизвестен."""
    sv, lv = _INPLACE[head]
    flags, paths = _git_opts(rest, sv, set(), lv)
    if not any(f == "-i" or f.startswith("--in-place") for f in flags):
        return []
    if not any(f in ("-e", "-E", "-f", "--expression", "--file") for f in flags):
        paths = paths[1:]
    return paths or ["-"]
# Оболочки, чьё тело heredoc исполняет ОНА САМА. Тело `python3 - <<EOF` исполняет питон,
# и слова оттуда командами оболочки не являются — ровно этот случай и был дефектом D420.
SHELLS = {"bash", "sh", "zsh"}
# Знаки, при которых путь до исполнения неизвестен: глоб, переменная, раскрытие скобок, подстановка команды.
# Тот же набор, что у `not_literal` (`hooks/skill-name-ascii-guard.sh`).
_NONLITERAL = re.compile(r"[*?\[\]${}`]")

# ПРИЗНАК HEREDOC — ПРОБЕЛ ПЕРЕД ОПЕРАТОРОМ, А НЕ КОНЕЦ СТРОКИ (20 сентября 2026).
# Здесь стояло `\s*$`: метка обязана была замыкать строку, и `cat <<EOF > /dev/null`
# heredoc не считался вовсе — тело уходило в текст оболочки целиком. Замер дерева: таких
# heredoc 50 из 897. Конец строки был выбран ради отрицательного класса — арифметического
# сдвига `$((1<<n))`, которых в дереве 9; их отделяет не конец строки, а то, что там перед
# `<<` стоит операнд, а не пробел. Найдено прогоном, когда потребитель спросил у разбора
# про команду с перенаправлением после метки и получил тело как исполняемый текст.
# МЕТКА — СЛОВО, А НЕ ИМЯ ПЕРЕМЕННОЙ (D1260): `<<\EOF` и метки с `-`/`.` (`<<'a-b'`) образцом не брались, и тело читалось
# командами (67 команд корпуса, ответ менялся у 4).
_HEREDOC = re.compile(r"(?:^|[\s;&|])<<-?\s*\\?[\"']?([A-Za-z_][A-Za-z0-9_.-]*)[\"']?(?=\s|$)")


def _quote_state(s, q=()):
    """Стек кавычек и подстановок, открытых к концу `s` при открытом `q` в начале, — как у bash: `'…'`, `"…"`, `$'…'`
    (там `\\'` — экран), подстановка `$(…)` и обратные кавычки открывают СВОЙ уровень и внутри `"…"`, `\\` вне одинарных
    экранирует, `#` в начале слова вне кавычек — комментарий до конца строки. Нужен `shell_text`: `<<` внутри кавычек
    (`echo "a <<true"`) heredoc не открывает, а внутри `"$(cat <<EOF` — открывает (D1260)."""
    st, i, n = list(q), 0, len(s)
    while i < n:
        c, top = s[i], (st[-1] if st else None)
        if top == "'":
            if c == "'":
                st.pop()
        elif top == "$'":
            if c == "\\":
                i += 1
            elif c == "'":
                st.pop()
        elif c == "\\":
            i += 1
        elif top == '"':
            if c == '"':
                st.pop()
            elif s.startswith("$(", i):
                st.append("(")
                i += 1
            elif c == "`":
                st.append("`")
        elif top == "`" and c == "`":
            st.pop()
        elif c == "'":
            st.append("$'" if i and s[i - 1] == "$" else "'")
        elif c == '"':
            st.append('"')
        elif s.startswith("$(", i) or (c == "(" and top == "("):
            st.append("(")
            i += 0 if c == "(" else 1
        elif c == ")" and top == "(":
            st.pop()
        elif c == "`":
            st.append("`")
        elif c == "#" and (i == 0 or s[i - 1] in " \t;&|()"):
            break
        i += 1
    return tuple(st)


def _in_quotes(st):
    """`<<` в этом месте — внутри кавычек (heredoc не открывает): верх стека — кавычка, а не подстановка."""
    return bool(st) and st[-1] in ("'", '"', "$'")


def shell_text(cmd, group=False):
    """Текст, который исполнит ОБОЛОЧКА: сами команды плюс тела heredoc, открытых оболочкой.
    group — тело в `( … )`: его исполняет ДОЧЕРНЯЯ оболочка, и `cd` в нём наружу не выходит (D1088)."""
    lines = cmd.split("\n")
    out = []
    i = 0
    q = ()                                       # кавычки и подстановки, открытые предыдущими строками
    while i < len(lines):
        line = lines[i]
        m = next((x for x in _HEREDOC.finditer(line) if not _in_quotes(_quote_state(line[:line.index("<<", x.start())], q))),
                 None)
        if not m:
            q = _quote_state(line, q)
            out.append(line)
            i += 1
            continue
        # Хозяин тела — команда, открывшая heredoc (D1160): первое слово СТРОКИ отдавало тело `cd "…" && bash <<'SH'`
        # команде `cd`, и запись в нём не видели ни цели, ни вызовы git (6 таких шапок на 5335 вызовах).
        head = _heredoc_owner(line[:m.start()])
        tag = m.group(1)
        body = []
        i += 1
        while i < len(lines) and lines[i].strip() != tag:
            body.append(lines[i])
            i += 1
        i += 1                                   # сама строка-метка
        q = _quote_state(line, q)
        out.append(_HEREDOC.sub("", line))       # заголовок без открытия heredoc
        if head.split("/")[-1] in SHELLS:
            # Тело оболочки — снова текст оболочки, со своими heredoc (D1160): вложенный `python3 - <<'PY'` иначе читался
            # как команды, и `print(1 > 0)` давал цель «0».
            inner = shell_text("\n".join(body), group).split("\n")
            out.extend(["("] + inner + [")"] if group else inner)
    return "\n".join(out)


def _heredoc_owner(prefix):
    """Хозяин тела heredoc по тексту строки до `<<`: голова последней простой команды — тем же лексером и `_cmd_pos`,
    что у остальных ответов (перенаправления `2>&1`, обёртки с ключами, `then`/`do`/`{`). Своё выражение по сырому тексту
    резало `2>&1` и `$(` и теряло тело `bash 2>&1 <<X` (скептик D1160, круг 2, M1). Heredoc внутри `<(`/`$(` кормит
    текстом внешнюю команду: у `bash <(cat <<X` хозяин тела — `bash`; кавычка без пары (`bash -c "$(cat <<X`) — первое
    слово строки, как до D1160."""
    try:
        lex = shlex.shlex(_shell_words_text(prefix), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        toks = list(lex)
    except ValueError:
        w = prefix.split()
        return w[0].split("/")[-1] if w else ""
    segs, seg = [], []
    for t in toks:
        if _is_sep(t):
            segs.append((seg, t))
            seg = []
        else:
            seg.append(t)
    segs.append((seg, ""))

    def head(sg):
        w = _strip_redirs(sg)
        k = _cmd_pos(w)
        return w[k].split("/")[-1] if k < len(w) else ""

    if len(segs) > 1:
        ps, psep = segs[-2]
        if psep.endswith("<(") or (psep.endswith("(") and ps[-1:] and ps[-1].endswith("$")):
            if head(ps) in SHELLS:
                return head(ps)
    return head(segs[-1][0])


def _substs(text):
    """Тексты подстановок, которые лексер оставляет внутри слова: `$(…)` в двойных кавычках и обратные апострофы вне
    одинарных — их команды исполнит оболочка (режим `--edits`, скептик D1160, круг 2, M2: `echo "$(rm f)"`, `` `rm f` ``).
    Подстановку без кавычек лексер и так режет на команды."""
    out, q, i, n = [], None, 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\" and q != "'":
            i += 2
            continue
        if q == "'":
            q = None if c == "'" else q
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                break
            out.append(text[i + 1:j])
            i = j + 1
            continue
        elif q == '"' and text.startswith("$(", i) and not text.startswith("$((", i):
            j = _subst_end(text, i)
            out.append(text[i + 2:j - 1])
            i = j
            continue
        elif c == '"':
            q = None if q == '"' else '"'
        elif c == "'" and q is None:
            q = "'"
        i += 1
    return out


def _blank_backticks(text):
    """Спаны обратных кавычек вне одинарных — заглушкой: их тела разбирает `_substs`, а внешний лексер иначе склеивал
    кавычку с соседним словом (D1277). Граница спана — та же, что у `_substs`."""
    out, q, i, n = [], None, 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\" and q != "'":
            out.append(text[i:i + 2])
            i += 2
            continue
        if q == "'":
            q = None if c == "'" else q
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                out.append(text[i:])
                break
            out.append("$__subst__")   # знак `$` — «до исполнения неизвестно» для каждого читателя признака (D1280)
            i = j + 1
            continue
        elif c == '"':
            q = None if q == '"' else '"'
        elif c == "'" and q is None:
            q = "'"
        out.append(c)
        i += 1
    return "".join(out)


def _join(base, t):
    """Цель относительно каталога, куда команда перешла раньше (D1088). Каталог или цель, неизвестные до исполнения
    (`~`, `$X`, глоб), не нормализуются: `normpath("$X/../f")` — литеральное `f`, и карта приклеила бы его к каталогу
    запроса (скептик D1088, находка 6)."""
    if not base or t.startswith(("/", "~", "$")):
        return t
    if _NONLITERAL.search(base + t):
        return base.rstrip("/") + "/" + t
    if base == "~" or base.startswith("~/"):
        # `~` неизвестен, но неизменен: хвост после него нормализуется, пока `..` не выходит за `~`. Без этого
        # `cd ~/.claude/skills/x && cd .. && mkdir Имя` давал `~/.claude/skills/x/../Имя`, и страж читал имя `x`
        # (скептик D1088, раунд 2, находка 6).
        tail = posixpath.normpath(posixpath.join(base[2:], t))
        return base.rstrip("/") + "/" + t if tail.startswith("..") else "~/" + tail
    return posixpath.normpath(posixpath.join(base, t))


def _cd_dest(base, prev, dirs, head, rest):
    """(новый каталог, прежний) после `cd`/`pushd`/`popd`. Голый `cd` — `~`; `cd -` меняет местами с прежним;
    `popd` без стека — каталог, неизвестный до исполнения."""
    if head == "popd":
        return (dirs.pop() if dirs else "$OLDPWD"), base
    d = next((a for a in rest if a == "-" or not a.startswith("-")), "~")
    if d == "-":
        return prev, base
    if head == "pushd":
        dirs.append(base)
    return (d if d.startswith(("/", "~", "$")) or not base else _join(base, d)), base


def targets(cmd, literal=False, edits=False):
    """Пути, которые вызов создаёт: аргументы операций создания и файлы перенаправлений.
    literal — только известные до исполнения целиком (режим `--literal`).
    edits — ещё и пути, которые вызов МЕНЯЕТ, не создавая (режим `--edits`, вопрос «вызов пишет», D1160): `rm`/`unlink`,
    правка на месте (`sed -i`, `perl -pi`, `ruby -i`) и меняющие вызовы git (`_git_writes`) — их целью отдаётся `.git`;
    с D1215 — формы `_edit_targets`: файлы `curl -o`/`-c`/`-D` и `wget -O`, пути `chmod`, корни `find … -delete`, каталог `tar -x -C`,
    а «-» там, где путь разбор не выделил (`curl -O`, `wget` без `-O`, `tar -x` без `-C`, `chmod -x f`); `find … -exec`
    начинает команду. Позиция команды та же, что у создания: `command -v tee`, `grep -rn rm` правкой не считаются, тело `bash <<X`
    и `bash -c '…'` — считаются.
    edits="content" — только пути, чьё СОДЕРЖИМОЕ вызов пишет сам (режим `--content`, D1330): перенаправление, `tee`,
    правка на месте, файл `curl -o`/`wget -O`. Без `mkdir`/`touch`, `rm`, `chmod`, git, `find`, `tar`: смена режима и
    времени файла, удаление и каталог — не правка содержимого (у `rework-detector` `chmod +x тест` перед прогоном
    считался бы правкой теста: 202 команды из 8 889 с целью записи). Без приёмника `cp`/`mv`/`install`/`rsync`/`ln`
    (скептик D1330, L3): копия — не авторская правка, и раскладка установленной копии между прогонами росла бы своей
    цепочкой (1 078 команд из 6 224 с целью содержимого, 106 из них — в `~/.claude`); копию в репозитории называет
    мир. ponytail: команду, которую лексер не разобрал, запасной разбор судит как `--edits` — 61 из 35 737; сузить там
    же, если встретится в журналах детектора.

    Относительная цель отдаётся с каталогом `cd` той же команды до неё (D1088): без него потребитель приклеивал её к
    каталогу запроса — карта вносила узел-призрак, а страж имени скилла пропускал `cd ~/.claude/skills && mkdir "Имя"`.
    Слова и границы команд — те же, что у `git_calls` (лексер с пунктуацией, `_is_sep`, `_cmd_pos`): первая редакция
    резала сырой текст выражением, и `cd` из кавычек (`git commit -m "a; cd /tmp"`) двигал каталог, а `cd` в `( … )` не
    виден был вовсе (скептик D1088, 359 таких команд в корпусе). Подоболочка `( … )` и тело `bash <<X` — свой каталог;
    `cd` в конвейере и в фоне на нашу оболочку не действует; правая часть `||` после `cd` судится по прежнему каталогу.
    Голый `cd` — `~`, `cd -` — прежний, `popd` без стека — неизвестный: режим `--literal` такие цели отбрасывает.
    `bash -c '<скрипт>'` разбирается рекурсией: его цели — от каталога запуска, его `cd` наружу не выходит.
    НАЗВАННЫЙ ПРЕДЕЛ (скептик D1088, раунды 1–2; каждая форма — нога, обязанная расходиться, в
    `test_write_targets_cd_oracle.sh`): условное исполнение иначе не моделируется — `false && cd X; …` (`eval cd X`
    раскрывается с D1160: `eval` — обёртка); `)` шаблона `case … in a)` закрывает подоболочку; `cd` в группе или цикле, стоящих в конвейере
    (`{ cd X; } | …`), выходит наружу; `cd` из тела функции применяется при определении; правая часть `cd X || { … }`
    судится по новому каталогу; подстановка без кавычек (`cd $(…)/x`) делится лексером. Команду, которую лексер не
    разобрал (61 из 35 737 в корпусе, из них с `cd` и целью 24), судит прежний разбор без каталога — как на HEAD.
    Условие снятия: форма встретится в корпусе команд с целью записи в каталоге скиллов либо узлом-призраком карты."""
    found = []
    st = shell_text(cmd, group=True)
    # Тела подстановок исполнит оболочка — их цели берутся в ЛЮБОМ режиме (D1277: прежде только для `--edits`, и
    # `x="$(echo a > f)"` не давал режиму целей создания ничего), а внешнему лексеру обратные кавычки не отдаются: он
    # оставлял кавычку частью слова, и цель приходила как `` f` ``.
    for sub in _substs(st):
        found += targets(sub, edits=edits)
    try:
        lex = shlex.shlex(_shell_words_text(_blank_backticks(st)), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""                          # комментарии сняты в _shell_words_text — с учётом кавычек
        toks = list(lex)
    except ValueError:
        # Лексер не разобрал команду — чаще всего метка heredoc в кавычках (предел `shell_text`, тот же у
        # `git_calls`): текст до «метки» съеден, кавычки остались без пары. Прежний разбор по кускам находит часть
        # целей и тут; каталога `cd` он не знает. Без него у таких команд терялись цели, которые HEAD видел.
        return _filter_literal(found + _targets_by_parts(cmd, edits), literal)
    items, seg = [], []
    for t in toks:
        if _is_sep(t) or (edits and t in ("-exec", "-execdir")):
            items.append((seg, t))
            seg = []
        else:
            seg.append(t)
    items.append((seg, ""))
    base, prev, dirs, stack, pending, before = "", "$OLDPWD", [], [], None, ""
    for seg, sep in items:
        core = sep.replace("(", "").replace(")", "")
        now, pending = pending, None
        for j, w in enumerate(seg[:-1]):             # перенаправление в файл — тоже создание
            if w in (">", ">>", ">|", "&>", "&>>"):
                found.append(_join(base, seg[j + 1]))
        words = _strip_redirs(seg)
        i = _cmd_pos(words)
        head = words[i].split("/")[-1] if i < len(words) else ""
        rest = words[i + 1:]
        for script in _nested_scripts(words):        # `bash -c '<скрипт>'`, `eval '<скрипт>'` — команды дочерней оболочки
            found += [_join(base, t) for t in targets(script, edits=edits)]
        if head in ("cd", "pushd", "popd"):
            if before not in ("|", "|&") and core not in ("|", "&", "|&"):
                dest = _cd_dest(base, prev, dirs, head, rest)
                if core == "||":
                    pending = dest
                else:
                    base, prev = dest
        elif head == "git" and rest[:1] == ["mv"]:
            found += [_join(base, a) for a in [a for a in rest[1:] if not a.startswith("-")][-1:]]
        elif head in ALL_ARGS:
            if edits != "content" or head == "tee":
                found += [_join(base, a) for a in _all_args_paths(head, rest)]
        elif head in LAST_ARG:
            if edits != "content":
                found += [_join(base, a) for a in [a for a in rest if not a.startswith("-")][-1:]]
        elif edits is True and head in ("rm", "unlink"):
            found += [_join(base, a) for a in _git_opts(rest, set(), set(), set())[1] or ["-"]]   # `xargs rm` — со входа
        elif edits and head in _INPLACE:
            found += [_join(base, a) for a in _inplace_files(head, rest)]
        elif edits and head in _EDIT_HEADS and (edits is True or head in ("curl", "wget")):
            found += [a if a == "-" else _join(base, a) for a in _edit_targets(head, words, rest)]
        if now:
            base, prev = now
        for ch in sep:                               # подоболочка: каталог внутри наружу не выходит
            if ch == "(":
                stack.append((base, prev))
            elif ch == ")" and stack:
                base, prev = stack.pop()
        before = core
    return _filter_literal(found, literal)


# Подкоманды git, меняющие дерево, индекс или хранилище (режим `--edits`; D1215 — формы двух корпусов расшифровок):
# `stash` кроме `list`/`show`, `worktree add|move|remove|prune`, `apply` без ключей одного осмотра.
# ponytail: перечень, а не наблюдение изменения (R3); `checkout --`, `restore`, `reset --hard`, `am` — предел в шапке
# `is_write_command`.
_GIT_APPLY_LOOK = {"--check", "--stat", "--numstat", "--summary"}


def stash_changes(g):
    """Вызов git (`git_calls`) меняет рабочую копию через `stash` — любая форма, кроме `list` и `show`. Одно правило
    двух потребителей: `git-stash-guard.sh` (отказ всегда) и признак «вызов пишет» (`_git_writes`, D1215); прежде оно
    жило строкой внутри стража."""
    return g["sub"] == "stash" and (g["args"][:1] or [""])[0] not in ("list", "show")


def _git_writes(c):
    sub, args = c["sub"], c["args"]
    if sub in ("commit", "rm", "restore") or stash_changes(c):   # `git rm` — дерево и индекс; `restore` — сброс правок
        return True
    if sub == "checkout":                            # `checkout -- <пути>` сбрасывает правки; ветку без `--` — предел
        return "--" in args
    if sub == "worktree":
        return bool(args) and args[0] in ("add", "move", "remove", "prune")
    if sub == "apply":
        return not _GIT_APPLY_LOOK & set(args)
    return False


_EDIT_HEADS = {"git", "curl", "wget", "chmod", "find", "tar"}


def _edit_targets(head, words, rest):
    """Цели формы D1215 по слову команды; «-» — путь до исполнения не выделен. Одно правило основного разбора и
    запасного (`_targets_by_parts`): у запасного была своя копия перечня, и формы D1215 мимо него шли (скептик D1215)."""
    if head == "git":
        g = []
        _git_in_segment(words, [], g)
        return [".git"] if g and _git_writes(g[0]) else []
    if head == "curl":
        return _curl_writes(rest)
    if head == "wget":                               # без `-O` пишет файл с именем из адреса; `-O -` — поток
        out = _opt_vals(rest, "O", {"--output-document"})
        return [v for v in out if v != "-"] if out else ([] if "--spider" in rest else ["-"])
    if head == "chmod":                              # первое слово — режим, дальше пути; `chmod -x f` — режим ключом
        return _git_opts(rest, set(), set(), set())[1][1:] or ["-"]
    if head == "find" and "-delete" in rest:         # корни — до первого выражения; `_` — скобка `\(` или `'('`
        return rest[:next((j for j, a in enumerate(rest) if a[:1] in "-(!" or a == "_"), len(rest))] or ["-"]
    if head == "tar" and _tar_extracts(rest):        # извлечение пишет в `-C <каталог>` либо в текущий
        return _opt_vals(rest, "C", {"--directory"}) or ["-"]
    return []


# Короткие ключи `curl` со значением: в кластере значение — остаток слова либо следующее слово (`-XPOST`, `-H'…'`).
_CURL_VAL = set("AbcCdDEeFHKmoPQrTtUuwXxYyz")
_CURL_FILE = {"o": "--output", "c": "--cookie-jar", "D": "--dump-header"}


def _curl_writes(rest):
    """Файлы, которые пишет `curl`: `-o`, `-c` (cookie), `-D` (заголовки), «-» — `-O`/`--remote-name` (имя из
    адреса); значение «-» — поток, не файл. Кластер читается по ключам: до D1215, круг скептика, выражение `-…O` ловило
    значение `-XPOST`, а слитное значение с буквой o (`-H'Accept: application/json'`) читалось как `-o`."""
    out, remote, i, longs = [], False, 0, set(_CURL_FILE.values())
    while i < len(rest):
        a = rest[i]
        i += 1
        if a == "--":
            break
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            remote = remote or name in ("--remote-name", "--remote-name-all")
            if name in longs:
                if not eq and i < len(rest):
                    val, i = rest[i], i + 1
                out.append(val)
            continue
        for k, ch in enumerate(a[1:] if a.startswith("-") else "", 1):
            remote = remote or ch == "O"
            if ch in _CURL_VAL:
                val = a[k + 1:]
                if not val and i < len(rest):
                    val, i = rest[i], i + 1
                if ch in _CURL_FILE:
                    out.append(val)
                break
    return [v for v in out if v not in ("-", "")] + (["-"] if remote else [])


def _tar_extracts(rest):
    """`tar` извлекает: `--extract`/`--get`, `x` в кластере коротких ключей либо в первом слове старой формы
    (`tar xzf a.tgz`). ponytail: ключ со значением раньше `x` в кластере (`-fx`) — у корпуса не встречен."""
    if {"--extract", "--get"} & set(rest):
        return True
    if rest and not rest[0].startswith("-") and "x" in rest[0]:
        return True
    return any(re.match(r"^-[a-zA-Z]*x", a) for a in rest)


def _opt_vals(args, short, longs):
    """Значения ключа: `-o f`, `-of`, `-sSo f`, `--output f`, `--output=f`. Ключ — последний в кластере либо со значением
    слитно. ponytail: ключ со значением, стоящий в кластере раньше (`-Ho …`), съест остаток — у `wget`/`tar` не встречен (`curl` читает кластер по ключам)."""
    out, i = [], 0
    while i < len(args):
        a = args[i]
        i += 1
        if a == "--":
            break
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            if name in longs:
                if eq:
                    out.append(val)
                elif i < len(args):
                    out.append(args[i])
                    i += 1
        elif a.startswith("-") and short in a[1:]:
            k = a.index(short, 1)
            if k < len(a) - 1:
                out.append(a[k + 1:])
            elif i < len(args):
                out.append(args[i])
                i += 1
    return out


def _targets_by_parts(cmd, edits=False):
    """Прежний разбор (до D1088): куски по разделителям в сыром тексте, слова — `shlex.split` каждого куска. Только
    запасной путь для команды, которую не разобрал лексер; каталога `cd` не знает."""
    found = []
    for part in re.split(r"[\n;]|&&|\|\||[|&]", shell_text(cmd)):
        try:
            words = shlex.split(part)
        except ValueError:
            continue
        k = 0
        while k < len(words) and _ASSIGN.match(words[k]):
            k += 1
        if k >= len(words):
            continue
        head, rest = words[k].split("/")[-1], words[k + 1:]
        if head == "git" and rest[:1] == ["mv"]:
            args = [a for a in rest[1:] if not a.startswith("-")][-1:]
        elif head in ALL_ARGS:
            found += _all_args_paths(head, rest)
            args = []
        elif head in LAST_ARG:
            args = [a for a in rest if not a.startswith("-")][-1:]
        elif edits and head in ("rm", "unlink"):
            found += _git_opts(rest, set(), set(), set())[1] or ["-"]
            args = []
        elif edits and head in _INPLACE:
            found += _inplace_files(head, rest)
            args = []
        elif edits and head in _EDIT_HEADS:
            found += _edit_targets(head, words, rest)
            args = []
        else:
            args = []
        found += [a for a in args if not a.startswith("-")]
        found += [words[j + 1] for j, w in enumerate(words[:-1]) if w in (">", ">>")]
        found += [w.lstrip(">") for w in words if re.match(r"^>>?[^>&]", w)]
    return found


def _filter_literal(found, literal):
    if not literal:
        return found
    # Цель с глобом, переменной, подстановкой или тильдой целиком до исполнения неизвестна (D1037).
    return [t for t in found if not (_NONLITERAL.search(t) or t.startswith("~"))]


# Разделители, после которых начинается НОВАЯ команда. Позиция команды СЧИТАЕТСЯ, а не
# угадывается по форме: shlex с punctuation_chars отдаёт разделители отдельными токенами,
# а кавыченный аргумент оставляет ОДНИМ токеном — потому `bash x.sh` внутри чужой кавычки
# токеном команды не становится.
_SEP = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}
_KEYWORD = {"if", "while", "until", "then", "else", "elif", "do", "done", "fi", "!", "time"}
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def calls(cmd):
    """Файлы, которые оболочка ЗАПУСКАЕТ: `bash x.sh`, а не слово «bash» в аргументе.

    ПОЧЕМУ РАЗБОР, А НЕ `executable_part` (D424, замерено 16 сентября 2026 на корпусе
    35 622 вызовов Bash). Вырезание кавычек убирает ложное срабатывание, но вместе с ним
    стирает и настоящую ЦЕЛЬ: `bash "hooks/tests/x.sh"` превращается в `bash  ` — таких
    195 в корпусе. Об этом предупреждает сам владелец библиотеки (command-scope-lib.sh:33):
    «вырезание применяется ТОЛЬКО к поиску сигнатуры; цель извлекается из ИСХОДНОЙ строки».
    Здесь предмет — именно цель, поэтому кавычки СНИМАЮТСЯ РАЗБОРОМ, как у `targets`.

    НАЗВАННЫЙ ПРЕДЕЛ: `bash -c <код>` и `bash -s` файла не запускают, и клауза ниже их
    отсекает — без неё разбор объявлял вызовом весь код, стоящий после `-c` (поймано
    замером по корпусу на собственной первой редакции, а не рассуждением).
    Разбор не удался (незакрытая кавычка) — возвращается пусто: промах даёт ПРОПУСК, а не
    ложную тревогу, и это верный знак для потребителя, который инжектит текст, а не
    отказывает.
    """
    out, buf = [], ""
    for line in shell_text(cmd).split("\n"):
        buf = buf + "\n" + line if buf else line
        try:
            lex = shlex.shlex(buf, posix=True, punctuation_chars=True)
            lex.whitespace_split = True
            toks = list(lex)
        except ValueError:
            continue                             # кавычка не закрыта — строка продолжается
        out += _calls_in_line(toks)
        for body in _substs(buf):             # D1253: подстановки в кавычках — у владельца, `_substs`
            out += calls(body)
        buf = ""
    return out


def _calls_in_line(toks):
    """Вызовы в ОДНОЙ строке: её начало — позиция команды, дальше её двигают разделители.

    Граница команды берётся у СТРОКИ, а не у `lex.lineno`: тот показывает, где остановился
    лексер, а не где стоит токен, и съезжает на соседа — `cd hooks\nbash x.sh` помечал
    границей аргумент `cd`, а не `bash`. Проверено прогоном 16 сентября 2026.
    """
    out, at_cmd, i = [], True, 0
    while i < len(toks):
        t = toks[i]
        if t in _SEP or t in _KEYWORD:
            at_cmd = True
            i += 1
            continue
        if at_cmd and _ASSIGN.match(t):          # префикс окружения: FOO=bar bash x.sh
            i += 1
            continue
        if at_cmd and t.split("/")[-1] in SHELLS:
            j, inline = i + 1, False
            while j < len(toks) and toks[j].startswith("-"):
                if toks[j] == "-" or set("cs") & set(toks[j][1:]):
                    inline = True                # код в аргументе либо stdin — файла нет
                j += 1
            if not inline and j < len(toks) and toks[j] not in _SEP:
                out.append(toks[j])
        at_cmd = False
        i += 1
    return out


def prefix_env(cmd):
    r"""Присваивания в ПОЗИЦИИ КОМАНДЫ: `NAME=VALUE <имя команды>` по строке на сегмент.

    Третий вопрос того же разбора (20 сентября 2026): не «какой путь вызов создаёт» и не
    «какой файл запускает», а «какая переменная выставлена ПЕРЕД какой командой». Заведён
    для `git-add-sweep-guard`, чей осознанный обход пишется присваиванием в самой команде:
    на PreToolUse команда ещё не исполнена, и в окружении хука такой переменной нет — в
    отличие от соседа `publish-guard`, читающего свой ключ прямо из среды.

    ПОЧЕМУ ЗДЕСЬ, А НЕ У ПОТРЕБИТЕЛЯ. У стража 19-20 сентября 2026 стояла СВОЯ копия
    разбора — `sed` снимал комментарии и кавычки, `awk` тела heredoc. Противник пробил её
    шестью способами за прогон, в обе стороны: heredoc с кавычками в метке (604 таких в
    дереве против 230 без), односложная строка в теле, экранированная кавычка, решётка
    внутри кавычек, метка с цифрой, арифметический сдвиг. Все шесть — формы, которые
    `shell_text` и `shlex` здесь уже разбирают верно. Копия была родом K реестра, и
    комментарий `command-scope-lib.sh:330` («разбирать кавычки надо РАЗБОРОМ, а не
    вырезанием») указывал на этого владельца ещё до того, как копия появилась.

    Слова — те же, что у `git_calls` (лексер с пунктуацией, `_strip_redirs`, ключевые слова перед присваиванием): до
    D1216 сегменты резало выражение по сырому тексту, и шаблон `grep -E 'a|B=1 git|c'` давал «присваивание» `B=1` перед
    `git`, а `X='a;b' git` терял настоящее. Границы — `_value_segments`: значение присваивания — одно слово, как у
    оболочки, с подстановкой без кавычек, массивом и приклеенным хвостом (скептик opus по 1abe8aa3: голые `_is_sep`
    отрывали `A=1` от `git` в `A=1 X=$(dirname $(pwd)) git` и давали ключ из `echo { K=1 git }`, `arr=(K=1 git)`,
    `K=1 D=$(pwd)/git`).

    НАЗВАННЫЙ ПРЕДЕЛ, общий со всем файлом: разбирается ЛЕКСИКА, а не грамматика. Значение
    присваивания берётся как написано, подстановка до исполнения не раскрывается. Имя
    команды — первое слово ПОСЛЕ присваиваний; сегмент без них молчит. `export NAME=1` сюда
    не попадает намеренно: это не позиция команды, а отдельный вызов. Лексер не разобрал
    команду (кавычка без пары) — пусто: промах снимает обход, а не ставит его. Код в кавычках
    (`bash -c '…'`, `sh -c "…"`) не раскрывается: прежнее деление сырого текста находило там
    присваивания вперемешку с ложными. Значение с подстановкой без кавычек отдаётся до `$`
    (`X=$(pwd)` — `X=$`). Образец `case` внутри подстановки (`X=$(case y in y) …`) закрывает её
    раньше времени, тело функции (`f() { K=1 git; }`) читается как команда — частота обоих на
    корпусе 0. Формы общего лексера, которые путают и прочие ответы (строка `$'…\'…'`,
    `\;`/`\|`, heredoc `<<\EOF`), — D1260. На 275 807 командах (6 ноября 2026) против редакции до
    D1216 ответ сменился у 24 937, ключ `CLAUDSOUL_ALLOW_ADD_SWEEP=1` перед `git` — 1 → 0 (тот был
    строкой списка `for c in '…'`), лексер не разобрал 156 команд.
    """
    out = []
    try:
        text = _shell_words_text(shell_text(cmd))
        toks = _toks_at(text)
    except (ValueError, RecursionError):         # кавычка без пары; ~1200 вложенных `"$(` (скептик D1216, L3)
        return out
    for words in _value_segments(text, toks):
        while words and words[0] in _KEYWORD:     # `then X=1 git` — как `_cmd_pos` у `git_calls` (скептик D1216, L2)
            words = words[1:]
        assigns = []
        for w in words:
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
                assigns.append(w)
                continue
            break
        if not assigns:
            continue
        rest = words[len(assigns):]
        head = rest[0].split("/")[-1] if rest else ""
        for a in assigns:
            out.append(f"{a}\t{head}")
    return out


def _toks_at(text):
    """Токены лексера с позицией конца в тексте: по ней видно, приклеено ли следующее слово (`D=$(pwd)/git`)."""
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""                          # комментарии сняты в _shell_words_text — с учётом кавычек
    out = []
    while True:
        t = lex.get_token()
        if t is None:
            return out
        end = lex.instream.tell() - len(lex._pushback_chars)
        if end and text[end - 1].isspace():      # пробел за токеном лексер съедает, а не возвращает
            end -= 1
        # `))`, `);`, `)&&` — закрытие по одной скобке: вложенная подстановка закрывается вместе с внешней.
        while t.startswith(")") and len(t) > 1 and set(t) <= _PUNCT:
            out.append((")", end - len(t) + 1))
            t = t[1:]
        out.append((t, end))


_ARRAY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=$")


def _value_segments(text, toks):
    """Простые команды по словам лексера, где значение присваивания — одно слово, как у оболочки (D1216, скептик opus):
    подстановка без кавычек в нём (`A=1 X=$(pwd) git`) — свои сегменты, а присваивания до неё ждут закрывающей скобки;
    хвост, приклеенный к `)` (`D=$(pwd)/git`, `$(a)$(b)`), — часть значения, а не голова; массив `NAME=(…)` — значение,
    а не подоболочка; `{`/`}` после первого слова — аргумент, а не группа."""
    segs, seg, held, arr, tail, prev = [], [], [], 0, False, ""
    n = len(text)
    for k, (t, end) in enumerate(toks + [(";", n)]):
        glued = k > 0 and toks[k - 1][1] < n and not text[toks[k - 1][1]].isspace()
        punct = bool(t) and set(t) <= _PUNCT
        if arr:                                  # внутри `NAME=(…)`
            if punct:
                arr += t.count("(") - t.count(")")
            tail = arr <= 0
            arr = max(arr, 0)
            prev = t
            continue
        if t == "(" and glued and (prev.endswith("$") and (tail or (seg and _ASSIGN.match(seg[-1])))):
            held.append([seg, 1])                # подстановка в значении присваивания
            seg, tail, prev = [], False, t
            continue
        if t == "(" and glued and seg and _ARRAY.match(seg[-1]):
            arr, tail, prev = 1, False, t
            continue
        if tail and glued and not punct:         # хвост значения после `)`
            prev = t
            continue
        tail, prev = False, t
        if not punct and not (t in ("{", "}") and not seg) or (punct and not _is_sep(t)):
            seg.append(t)                        # слово либо перенаправление
            continue
        segs.append(_strip_redirs(seg))
        seg = []
        if held:
            held[-1][1] += t.count("(") - t.count(")")
            if held[-1][1] <= 0:
                seg, tail = held.pop()[0], True
    segs.append(_strip_redirs(seg))
    return segs


# Глобальные опции git ДО подкоманды: со значением и без. Перечень поимённый, как у
# `is_git_subcommand` (command-scope-lib.sh): «любое -слово» съело бы подкоманду.
_GIT_OPT_VAL = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
_GIT_OPT_FLAG = {"--no-pager", "-P", "-p", "--paginate", "--bare", "--no-replace-objects",
                 "--literal-pathspecs", "--no-optional-locks", "--glob-pathspecs", "--noglob-pathspecs",
                 "--no-advice"}
_CMD_PREFIX = {"command", "builtin", "exec", "nice", "nohup", "sudo", "env", "xargs", "timeout", "time", "caffeinate",
               "eval", "parallel", "watch", "stdbuf"}
# Опции обёрток со ОТДЕЛЬНЫМ значением: `nice -n 5`, `sudo -u x`, `env -u VAR`, `xargs -n 1`.
_PREFIX_OPT_VAL = {"-n", "-u", "-g", "-s", "-P", "-I", "-L", "-k"}
# То же по обёртке (скептик D1160, круг 2, M2): общий перечень не знал `xargs -J %`, `env -C dir`, `sudo -D dir`,
# `caffeinate -t 60` — значение съедалось как имя команды, — а `sudo -s` (оболочка, без значения) съедал команду.
# Обёртка вне таблицы — общий перечень.
_PREFIX_OPT_VAL_BY = {
    "xargs": {"-n", "-I", "-J", "-L", "-E", "-d", "-s", "-P", "-a", "-R", "-S"},
    "sudo": {"-u", "-g", "-D", "-C", "-h", "-p", "-r", "-t", "-U", "-T"},
    "env": {"-u", "-C", "-S", "-P"},
    "caffeinate": {"-t", "-w"},
    "nice": {"-n"}, "timeout": {"-s", "-k"}, "watch": {"-n"}, "stdbuf": {"-i", "-o", "-e"}, "parallel": {"-j", "-S", "-a"},
}
_PUNCT = set(";&|()<>")


_REDIR = re.compile(r"^(?:[<>]{1,3}&?|&>>?|>\|)$")


def _is_sep(t):
    """Разделитель команд, в том числе СКЛЕЕННЫЙ лексером: `);`, `)&&`, `|&`, `((`, `<(` (раунд 2
    противника D525, N1). Оператор перенаправления (`>&`, `&>`, `>>`, `<<<`) — не разделитель."""
    if _REDIR.match(t):
        return False
    return t in _SEP or (bool(t) and set(t) <= _PUNCT and bool(set(t) & set(";&|()")))


def _strip_redirs(seg):
    """Перенаправления вырезаются вместе с целью и номером потока: `2>&1`, `>>out`, `<<<"x"` стоят
    где угодно — перед командой, между `git` и подкомандой, среди аргументов (раунд 3, находка 4)."""
    out, i = [], 0
    while i < len(seg):
        t = seg[i]
        if re.match(r"^[0-9]+$", t) and i + 1 < len(seg) and _REDIR.match(seg[i + 1]):
            i += 1
        elif _REDIR.match(t):
            i += 2
        else:
            out.append(t)
            i += 1
    return out


def _arith_end(text, i):
    """Конец арифметики `((…))` / `$((…))` с позиции i либо 0 — это подоболочки `((cd a); (cd b))`: у арифметики
    внутренняя скобка закрывается вплотную перед внешней, у подоболочек — раньше; так различает и bash (D1160).
    НАЗВАННЫЙ ПРЕДЕЛ (скептик D1160, круг 2, L2): незакрытое `((` сканируется до конца текста, и их ряд квадратичен —
    20 000 «(» подряд разбираются 19 с; на 7110 командах корпусов худшая — 4,4 мс. Условие снятия: команда длиннее
    30 КБ с такими скобками в расшифровке — тогда карта скобок одним проходом."""
    j, d = text.index("((", i) + 2, 2
    while j < len(text):
        d += {"(": 1, ")": -1}.get(text[j], 0)
        if d == 1:
            return j + 2 if text.startswith(")", j + 1) else 0
        j += 1
    return 0


def _cond_end(text, i):
    """Конец условия `[[ … ]]` с позиции i — первая `]]` вне кавычек; конца нет — длина текста (D1160)."""
    j, q, n = i + 2, None, len(text)
    while j < n:
        ch = text[j]
        if ch == "\\" and q != "'":
            j += 2
            continue
        if q:
            q = None if ch == q else q
        elif ch in "'\"":
            q = ch
        elif text.startswith("]]", j):
            return j + 2
        j += 1
    return n


def _subst_end(text, i):
    """Конец подстановки `$(…)` с позиции i — с её собственными кавычками и вложенными подстановками; конца нет — длина
    текста (D1160)."""
    j, d, n = i + 2, 1, len(text)
    while j < n:
        ch = text[j]
        if ch == "\\":
            j += 2
            continue
        if ch == "'":
            k = text.find("'", j + 1)
            j = n if k < 0 else k + 1
            continue
        if ch == '"':
            j += 1
            while j < n and text[j] != '"':
                j = j + 2 if text[j] == "\\" else (_subst_end(text, j) if text.startswith("$(", j) else j + 1)
            j += 1
            continue
        d += {"(": 1, ")": -1}.get(ch, 0)
        if d == 0:
            return j + 1
        j += 1
    return n


def _neutral(out, qs):
    """Строка в кавычках из одних знаков оператора (`'>'`, `">>"`, `'|'`) — аргумент (D1160): лексер снимает кавычки и
    отдал бы её тем же словом, что настоящий `>` или `|`. Заменяется нейтральным словом."""
    if qs < len(out) and set("".join(out[qs:])) <= _PUNCT:
        out[qs:] = ["_"]


def _shell_words_text(text):
    r"""Сырой текст → текст для ОДНОГО прохода лексера. Комментарий (`#` в начале слова вне
    кавычек), перенос строки `\` и граница команды (перевод строки вне кавычек) определяются
    здесь, с учётом кавычек, — как у bash, в том же проходе. Раунд 3 противника D525: при
    отрезании комментария ПОСЛЕ снятия кавычек `git commit -m "#123"; git stash pop` терял
    `stash pop`, а апостроф в настоящем комментарии глотал все следующие строки; разбор по
    строкам с повтором буфера был кубическим на многострочных аргументах."""
    out, q, i, n, start, qs = [], None, 0, len(text), True, 0
    while i < n:
        c = text[i]
        if q == "'":
            if c == "'":
                _neutral(out, qs)
                q = None
            out.append(c)
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            if text[i + 1] == "\n":
                i += 2
                continue
            # `\>` и `\<` вне кавычек — литерал, а не перенаправление (`[ a \> b ]`): лексер отдал бы его словом «>» (D1160).
            # Отдельное слово `\(`/`\)` (`find . \( -name a -o -name b \) -delete`) — тоже литерал: лексер отдал бы его
            # словом «(», и граница команды отрезала бы `-delete` от `find` (скептик D1215, M1). Внутри слова (`a\(1\)`)
            # скобка остаётся: она часть пути.
            lone = text[i + 1] in "()" and (not out or out[-1][-1:].isspace()) and (i + 2 >= n or text[i + 2].isspace())
            # `\;`, `\|`, `\&` словом из одних знаков оператора (`find … \;`, `echo a \; X=1 git`) — литерал: лексер отдал бы
            # его тем же словом, что настоящий `;` (D1260). Внутри слова (`a\|b`) знак остаётся: он часть слова.
            pv, nx = (out[-1][-1:] if out else ""), (text[i + 2] if i + 2 < n else "")
            bare = text[i + 1] in ";|&" and not (pv and not pv.isspace() and pv not in _PUNCT) \
                and not (nx and not nx.isspace() and nx not in _PUNCT and nx != "\\")
            out.append("_" if q is None and (text[i + 1] in "<>" or lone or bare) else text[i:i + 2])
            i += 2
            start = False
            continue
        if q == '"':
            if c == '"':
                _neutral(out, qs)
                q = None
            elif text.startswith("$(", i) and not text.startswith("$((", i):
                # Подстановка в двойных кавычках — со своими кавычками (D1160): `"$(printf "a>b")"` лексер читал тремя
                # кусками и «>» из середины принимал за перенаправление. Её `"` и `\` экранируются — лексер вернёт текст
                # подстановки дословно, внутри того же слова.
                j = _subst_end(text, i)
                out.append(text[i:j].replace("\\", "\\\\").replace('"', '\\"'))
                i = j
                continue
            out.append(c)
            i += 1
            continue
        if c == "'" and out and out[-1] == "$":
            # Строка `$'…'` (D1260): `\'` внутри — экранированная кавычка, а не конец; лексер, закрыв строку на ней,
            # читал хвост командами. Строка отдаётся одним словом в одинарных кавычках, экраны — литералом.
            j = i + 1
            while j < n and text[j] != "'":
                j += 2 if text[j] == "\\" else 1
            if j < n:
                out.append("'" + text[i + 1:j].replace("'", "_") + "'")
                i = j + 1
                start = False
                continue
        if c in "'\"":
            q = c
            out.append(c)
            qs = len(out)
            start = False
        elif start and text.startswith("[[", i):
            # Условие `[[ … ]]` — одним словом (D1160): «>» там сравнение, а не перенаправление. Конец ищется вне кавычек:
            # `[[ "$x" == "]]" ]]` кончался внутри строки.
            out.append("true")
            i = _cond_end(text, i)
            start = False
            continue
        elif (text.startswith("$((", i) or (start and text.startswith("((", i))) and _arith_end(text, i):
            # Арифметика — одним словом (D1160): `$(( n > 100 ))` отдавал целью «100». Слово без пробелов, чтобы
            # `x=$((a+1)) cmd` не сдвинул позицию команды; `((cd a); (cd b))` — подоболочки, их отделяет `_arith_end`.
            # НАЗВАННЫЙ ПРЕДЕЛ: запись внутри подстановки в арифметике и в `[[ … ]]` не видна (`[[ $(touch f) ]]`).
            out.append("0")
            i = _arith_end(text, i)
            start = False
            continue
        elif c == "#" and start:
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif c == "\n":
            out.append(" ; ")
            start = True
        else:
            out.append(c)
            start = c in " \t;&|()<>"
        i += 1
    return "".join(out)


def git_calls(cmd):
    """Вызовы git, которые исполнит оболочка: подкоманда, её аргументы и каталог (D526).

    Четвёртый вопрос того же разбора: не «что создаёт / запускает / выставляет», а «какой
    `git <подкоманда>` и в каком каталоге». Каталог — пути `cd <путь>` в той же команде до
    вызова (по порядку) и `-C <путь>` самого вызова; относительные складывает потребитель.
    Заведён для `denied-branch-commit-guard`: его первая редакция искала создание ветки
    регулярным выражением по тексту с вырезанными кавычками, и противник пробил её в обе
    стороны — флаг между `switch` и `-c` (`git switch -q -c X`, сам повод пункта), путь
    `-C "<с пробелом>"` (вырезался вместе с кавычками, `-C` съедал подкоманду), мусор в имени
    (`fix/r>/dev/null`). Здесь кавычки снимает `shlex`, перенаправления — отдельные токены.

    Вызов засчитывается только в ПОЗИЦИИ КОМАНДЫ (после разделителя, ключевого слова,
    присваивания или `command`/`env`/…): `echo git switch -c X` вызовом не является.
    Подстановки в кавычках (`"$(git …)"`, обратные апострофы), `bash -c '…'` и `eval '…'` раскрываются
    (D1323): их тела исполнит оболочка; каталог `cd` внутри них наружу не выходит.
    НАЗВАННЫЙ ПРЕДЕЛ: `cd` внутри подоболочки `( … )` считается и после неё; чужие интерпретаторы
    (`python3 -c`, `xargs sh`) не раскрываются; метка heredoc внутри кавычек или комментария не отличается от настоящей;
    глобальная опция git с отдельным значением вне перечня (`--attr-source <tree>`) съест
    подкоманду. Разбор не удался — пусто (промах = пропуск).
    """
    out, cds = [], []
    st = shell_text(cmd)
    for sub in _substs(st):          # тела подстановок в кавычках и обратных апострофов — у владельца, `_substs`
        out += git_calls(sub)
    try:
        lex = shlex.shlex(_shell_words_text(_blank_backticks(st)), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""          # комментарии сняты в _shell_words_text — с учётом кавычек
        toks = list(lex)
    except ValueError:
        return out                   # незакрытая кавычка — пропуск, а не ложная тревога
    seg = []
    for t in toks + [";"]:
        if _is_sep(t) or t in ("-exec", "-execdir"):
            words = _strip_redirs(seg)
            for script in _nested_scripts(words):
                out += git_calls(script)
            _git_in_segment(words, cds, out)
            seg = []
        else:
            seg.append(t)
    return out


def heads(cmd):
    """Простые команды, которые исполнит оболочка: слова от слова-команды через табуляцию, по строке на команду (D1330).

    Пятый вопрос того же разбора: не «что создаёт / запускает / какой git», а «КАКИЕ ПРОГРАММЫ зовёт команда и с какими
    словами». Заведён для `rework-detector`: тот узнавал прогон и его предмет образцом по всему тексту, и строка в
    кавычках (`grep 'bash tests/x.sh'`) или в теле heredoc читалась запуском. Слово-команда — после ключевых слов,
    присваиваний и обёрток (`_cmd_pos`); у git строка нормализована — `git`, подкоманда, её аргументы (глобальные ключи
    сняты `_git_in_segment`). Тела `bash -c`, `eval`, подстановок и `find -exec` раскрываются, как у `git_calls`.
    Перевод строки внутри слова заменён пробелом, табуляция тоже: строка — одна команда, поле — одно слово.
    НАЗВАННЫЙ ПРЕДЕЛ: те же, что у `git_calls`; разбор не удался — пусто, и потребитель обязан отличать «пусто» от
    «команд нет» сам (ответ на пустую и на неразобранную команду одинаков).
    Условие снятия: разбор начнёт возвращать признак «не разобрано» отдельным кодом.
    """
    out = []
    st = shell_text(cmd)
    for sub in _substs(st):
        out += heads(sub)
    try:
        lex = shlex.shlex(_shell_words_text(_blank_backticks(st)), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        toks = list(lex)
    except ValueError:
        return out
    seg = []
    for t in toks + [";"]:
        if _is_sep(t) or t in ("-exec", "-execdir"):
            words = _strip_redirs(seg)
            for script in _nested_scripts(words):
                out += heads(script)
            i = _cmd_pos(words)
            if i < len(words):
                g = []
                _git_in_segment(words, [], g)
                line = ["git", g[0]["sub"]] + g[0]["args"] if g else words[i:]
                out.append("\t".join(re.sub(r"[\t\n]", " ", w) for w in line))
            seg = []
        else:
            seg.append(t)
    return out


def commit_dirs(cmd):
    """Каталог каждого `git commit` команды (D1278): `cd` до вызова и `-C` самого вызова, сложенные по порядку, — `.`
    без них; относительный складывает потребитель от папки вызова. Каталог через переменную или подстановку до
    исполнения неизвестен — `?`: потребитель судит, как без разбора."""
    out = []
    for g in git_calls(cmd):
        if g["sub"] != "commit":
            continue
        parts = g["cd"] + g["C"]
        if any("$" in p or "`" in p or "__subst__" in p for p in parts):
            out.append("?")
            continue
        d = "."
        for p in parts:
            d = posixpath.join(d, posixpath.expanduser(p))
        out.append(posixpath.normpath(d))
    return out


def _cmd_pos(seg):
    """Индекс слова-команды простой команды: после ключевых слов, присваиваний и обёрток с их опциями. Один на
    `git_calls` и `targets` (D1088): копия у второго была бы род K."""
    i = 0
    while i < len(seg):
        t = seg[i]
        if t in _KEYWORD or _ASSIGN.match(t):
            i += 1
        elif t.split("/")[-1] in _CMD_PREFIX:
            if t == "command" and i + 1 < len(seg) and re.match(r"^-[pvV]*[vV][pvV]*$", seg[i + 1]):
                return len(seg)                              # `command -v x`, `-pv` ищет имя, а не зовёт его (D1160)
            vals = _PREFIX_OPT_VAL_BY.get(t.split("/")[-1], _PREFIX_OPT_VAL)
            i += 1
            while i < len(seg) and seg[i].startswith("-"):     # опции обёртки
                i += 2 if seg[i] in vals and i + 1 < len(seg) else 1
            if t == "timeout" and i < len(seg) and re.match(r"^[0-9.]+[smhd]?$", seg[i]):
                i += 1                                            # длительность `timeout 5`
        else:
            break
    return i


def _nested_scripts(seg):
    """Скрипты, которые простая команда отдаёт оболочке ТЕКСТОМ: `bash -c '<скрипт>'` и `eval '<скрипт>'`. Один на
    `targets` и `git_calls` (D1323): прежде `-c` раскрывал только первый, `eval` со скриптом в кавычках — никто."""
    i = _cmd_pos(seg)
    j = next((k for k in range(min(i, len(seg)) - 1, -1, -1) if seg[k].split("/")[-1] == "eval"), None)
    if j is not None:
        # `eval cd X` — обёртка, её разбирает вызывающий; скрипт — когда в слове есть то, что оболочка разберёт заново.
        # Слова берутся от САМОГО `eval`: слово-присваивание (`eval 'x=$(…)'`) позиция команды уже перешагнула.
        return [" ".join(seg[j + 1:])] if any(re.search(r"[\s;&|<>]", w) for w in seg[j + 1:]) else []
    if i >= len(seg):
        return []
    if seg[i].split("/")[-1] in SHELLS:
        rest = seg[i + 1:]
        k = next((j for j, a in enumerate(rest) if re.match(r"^-[a-zA-Z]*c[a-zA-Z]*$", a)), None)
        # Скрипт — первое слово после `-c`, не являющееся ключом: `bash -c -- '…'`, `bash -c -e '…'` (раунд 2, №5).
        script = next((a for a in rest[k + 1:] if not a.startswith("-")), None) if k is not None else None
        return [script] if script is not None else []
    return []


def _git_in_segment(seg, cds, out):
    i = _cmd_pos(seg)
    if i >= len(seg):
        return
    if seg[i] == "cd":
        if i + 1 < len(seg) and not seg[i + 1].startswith("-"):
            cds.append(seg[i + 1])
        return
    if seg[i].split("/")[-1] != "git":
        return
    i += 1
    cdir = []
    while i < len(seg):
        t = seg[i]
        if t in _GIT_OPT_VAL and i + 1 < len(seg):
            if t == "-C":
                cdir.append(seg[i + 1])
            i += 2
        elif t.startswith("-"):
            i += 1           # подкоманда git не начинается с `-`: незнакомая опция — флаг (N5)
        else:
            break
    if i < len(seg):
        out.append({"cd": list(cds), "C": cdir, "sub": seg[i], "args": seg[i + 1:]})


# Ключи `git commit` и `git add`, берущие ЗНАЧЕНИЕ, — по `git commit -h` и `git add -h` (git 2.54): слово за ними не флаг
# и не путь. У короткого значение — остаток кластера либо следующее слово (`-am x`: `a`, затем `m` со значением `x`;
# `-ma` — сообщение «a»). `-S` и `-u` коммита берут значение только слитно.
_COMMIT_SHORT_VAL, _COMMIT_SHORT_STUCK = set("mFcCtU"), set("Su")
_COMMIT_LONG_VAL = {"--message", "--file", "--author", "--date", "--reedit-message", "--reuse-message", "--fixup",
                    "--squash", "--trailer", "--template", "--cleanup", "--unified", "--inter-hunk-context",
                    "--pathspec-from-file"}
_ADD_LONG_VAL = {"--unified", "--inter-hunk-context", "--chmod", "--pathspec-from-file"}
# Ключи, при которых `add` ничего не ставит сам (пробный прогон, выбор кусков) и `commit` не уносит правки молча.
_ADD_NOT_SWEEP = {"-n", "--dry-run", "-p", "--patch", "-i", "--interactive", "-e", "--edit", "--refresh"}
_COMMIT_NOT_SWEEP = {"-p", "--patch", "--interactive", "--dry-run"}
_WHOLE_TREE = {".", "./", ":/", ":/."}


def _git_opts(args, short_val, short_stuck, long_val):
    """Слова вызова → (ключи, пути): кластеры коротких ключей раскрыты, значения пропущены, `--` кончает ключи."""
    flags, paths, i = [], [], 0
    while i < len(args):
        a = args[i]
        i += 1
        if a == "--":
            paths += args[i:]
            break
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            flags.append(name)
            if "=" not in a and name in long_val:
                i += 1
        elif a.startswith("-") and len(a) > 1:
            for k, ch in enumerate(a[1:], 1):
                flags.append("-" + ch)
                if ch in short_val:
                    i += k == len(a) - 1          # значение — следующее слово, если кластер кончился ключом
                    break
                if ch in short_stuck:
                    break
        else:
            paths.append(a)
    return flags, paths


def commit_adds(cmd):
    """Что команда САМА положит в индекс к своему коммиту (D1087): `all` — всё изменённое, с неотслеживаемым
    (`git add -A|--all` без путей, `git add .|:/`); `tracked` — только отслеживаемое (`git add -u|--update` без путей,
    `git commit -a|--all`); пусто — ни то ни другое. Судятся вызовы до первого `git commit` и он сам.

    Прежде ответ держали четыре потребителя — свои выражения по тексту, проверенные примерами; три раунда скептика
    подряд находили регрессию прежней починки (D1084–D1086). Здесь слова даёт `git_calls`, а ключи разбираются так,
    как их разбирает git; эталон — `hooks/tests/test_commit_adds_oracle.sh`: таблица форм исполняется настоящими
    bash и git, и вердикт сверяется с тем, что вошло в коммит.
    НАЗВАННЫЙ ПРЕДЕЛ: `.` считается всем деревом и тогда, когда команда стоит в подкаталоге; глоб (`git add *`),
    алиасы git, сокращённые длинные ключи (`--al`) и условное исполнение (`false && git add -A`) не разбираются.
    Условие снятия: форма появится в корпусе команд, и эталон её покажет.
    """
    res = ""
    for g in git_calls(cmd):
        if g["sub"] in ("add", "stage"):
            flags, paths = _git_opts(g["args"], set("U"), set(), _ADD_LONG_VAL)
            if _ADD_NOT_SWEEP & set(flags) or (paths and not set(paths) <= _WHOLE_TREE):
                continue
            addremove, update = False, False
            for f in flags:
                if f in ("-A", "--all"):
                    addremove = True
                elif f in ("--no-all", "--ignore-removal"):
                    addremove = False
                elif f in ("-u", "--update"):
                    update = True
                elif f == "--no-update":
                    update = False
            if update:
                res = res or "tracked"
            elif paths or addremove:
                res = "all"
        elif g["sub"] == "commit":
            flags, _ = _git_opts(g["args"], _COMMIT_SHORT_VAL, _COMMIT_SHORT_STUCK, _COMMIT_LONG_VAL)
            sweep = False
            for f in flags:
                if f in ("-a", "--all"):
                    sweep = True
                elif f == "--no-all":
                    sweep = False
            if sweep and not _COMMIT_NOT_SWEEP & set(flags):
                res = res or "tracked"
            break
    return [res] if res else []


if __name__ == "__main__":
    if "--content" in sys.argv[1:] and "--heads" in sys.argv[1:]:
        # Два ответа одним запуском (скептик D1330, M2): потребитель, которому нужны оба, платил бы за интерпретатор
        # дважды на каждой команде. Строка — «T⇥путь» либо «H⇥слова команды».
        _text = sys.stdin.read()
        for t in targets(_text, edits="content"):
            print("T\t" + t)
        for h in heads(_text):
            print("H\t" + h)
        sys.exit(0)
    if "--prefix-env" in sys.argv[1:]:
        _fn = prefix_env
    elif "--calls" in sys.argv[1:]:
        _fn = calls
    elif "--commit-adds" in sys.argv[1:]:
        _fn = commit_adds
    elif "--commit-dirs" in sys.argv[1:]:
        _fn = commit_dirs
    elif "--git-subs" in sys.argv[1:]:               # подкоманды git, которые исполнит оболочка (D1326)
        _fn = lambda c: [g["sub"] for g in git_calls(c)]
    elif "--heads" in sys.argv[1:]:
        _fn = heads
    elif "--edits" in sys.argv[1:]:
        _fn = lambda c: targets(c, edits=True)
    elif "--content" in sys.argv[1:]:
        _fn = lambda c: targets(c, edits="content")
    elif "--literal" in sys.argv[1:]:
        _fn = lambda c: targets(c, literal=True)
    else:
        _fn = targets
    for t in _fn(sys.stdin.read()):
        print(t)
