#!/usr/bin/env bash
# replace-uniqueness-guard.sh — PreToolUse[Bash]: замена первого вхождения без счёта вхождений образца отбивается отказом.
# en: PreToolUse[Bash] — a python first-occurrence replace without counting the pattern is denied.
#
# Результат: правка заменой по образцу в python-heredoc доказывает, что легла в ОДНО место.
# Проверка результата: bash hooks/tests/test_replace_uniqueness_guard.sh
#
# Повод (10 октября 2026, ProjectA B272). Помощник `rep()` с `assert o in s` и `s.replace(o, n, 1)`
# поставил перевод отказа в обработчик «Сверки с бухгалтерией»: на странице два одинаковых блока
# `onError`, проверка наличия «одно» от «несколько» не отличает. Тесты зелёные, дефект ушёл на
# прод. Знание об этом лежало в базе с 23 августа (case-2026-08-23-replacement-anchor-taken-from-file,
# pattern-string-replace-must-prove-single-landing) и жило привычкой: встроенная правка уникальность
# проверяет, самописный помощник её обходит.
#
# Почему уровень 4. Признак «`.replace(a, b, 1)` в программе питона, а `count(` в ней нет» несёт одно
# последствие: что образец встречается один раз, не доказано, и при двух местах правка молча ляжет
# в первое — запись файла и код 0 те же. Замер до включения логикой этого файла (11 октября 2026,
# расшифровки пяти проектов): команд Bash со словом `replace` 8249, отказ на 1651; среди команд с
# заменой первого вхождения (3438) — на 1619, 47%. Выборка 14 срабатываний — все настоящие программы
# с заменой без счёта; замена внутри кавычек на своей строке (текст, который питон пишет) — 2 из 1651.
# Худшее время на команде корпуса — 0,6 мс.
# Решение владельца — отказ при этой частоте: цена одного повтора меньше цены правки, ушедшей на прод.
#
# Область — ТОЛЬКО тела heredoc, из которых питон читает ПРОГРАММУ: команда, которой принадлежит
# heredoc, — `python…`/`pypy…` (через `env`, `uv run`, `timeout`, путь, после `if`/`do`) без файла
# скрипта и без `-m` до `-` (`python3`, `python3 -`, `python3 -u - арг`), либо питон стоит дальше в
# конвейере (`cat <<PY | python3 -`). Тело `cat > файл <<EOF`, сообщение коммита, stdin скрипта
# (`python3 render.py <<EOF`) и heredoc внутри чужого тела — данные. Команда определяется по своему
# сегменту строки (после `;`, `&&`, `||`, `|`, `(`), а не по всей строке: слово python в имени папки
# или файла рядом не делает чужой heredoc программой.
# Аргументы `replace` разбираются сканером с кавычками, скобками и комментариями: `"onError("` внутри
# строки и вложенные вызовы не рвут разбор; первое вхождение — ровно три аргумента с третьим `1` либо
# `count=1`; `.replace("yes", 1)` (pandas, два аргумента) — не оно. Незакрытый вызов значит, что
# программа не разобрана (или не запустится), — сканер на нём останавливается: так время линейно.
#
# Питон зовётся с `-I`: без него каталог вызова стоит первым в пути импорта, и `json.py` в рабочей
# папке исполнился бы внутри стража на каждом Bash с `.replace(` (найдено скептиком 11 октября 2026).
#
# НАЗВАННЫЙ ПРЕДЕЛ. `python3 -c '…'` не читается (124 команды корпуса из 3438), в том числе
# `python3 -c "$(cat <<PY …)"`. Строковые литералы в теле не снимаются. `count(` засчитывается на всё
# тело: помощник `rep()` с одним счётом внутри законен, но и посторонний `count(` рядом снимет отказ —
# страж ловит привычку, а не обход. `.replace(a, b, 1)` не на строке (`datetime.replace`,
# `dataclasses.replace(…, count=1)`) получает отказ: тип объекта по тексту не виден. sed/awk/perl не
# судятся (у `sed 's/a/b/'` другая семантика). `re.sub(…, count=1)` и `.sub(…, count=1)` — та же замена первого
# вхождения — не судятся: признак объявлен про `.replace` (решение владельца 18 ноября 2026, D1327; на 13 368 командах
# корпуса таких замен без счёта 77 против 1 499 отказов по `.replace`). Запускатель перед питоном вне перечня
# (`sudo`, `nohup`, `docker exec`, `ssh`), путь питона в кавычках с пробелом, `{ python3 -`, `elif python3 -` — heredoc
# остаётся данными; `.replace(` внутри строки или комментария выше настоящей замены сбивает сканер аргументов —
# на том же корпусе у всех этих форм 0 настоящих пропусков. `<<`, `|` и `(` внутри кавычек на строке-открывателе
# читаются как синтаксис. Сегмент длиннее 4000 символов не разбирается. Условие снятия: правка,
# легшая не туда через непокрытую форму, либо ложный отказ в работе (журнал ниже) — тогда эта форма
# входит в признак.
#
# Input  (stdin): {tool_name, tool_input:{command}, session_id, ...}
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny", ...}} либо пусто
# Exit:  always 0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
# Страж стоит на каждом вызове Bash: без `replace` в команде питон не запускается вовсе.
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
case "$CMD" in *replace*) ;; *) exit 0 ;; esac

PY=$(cat <<'PY'
import bisect, json, re, sys
cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command") or ""
if not isinstance(cmd, str):
    sys.exit(0)
OPEN = re.compile(r"(?<!<)<<(-?)(?!<)\s*\\?(['\"]?)([A-Za-z_][\w.-]*)\2")
ARITH = re.compile(r"\$\(\((?:[^()]|\([^()]*\))*\)\)")
# Подстановка команды, закрытая на той же строке, — значение, а не граница команды (D1327): `X=$(cat f) python3 - <<PY`
# резался по её скобке, и сегмент начинался с `cat f) …` — питон владельцем heredoc не признавался (2 команды корпуса).
SUBST = re.compile(r"\$\((?!\()(?:[^()]|\([^()]*\))*\)")
SEP = re.compile(r"&&|\|\||[;|(]")
CUT = re.compile(r"&&|\|\||;")
PYRUN = re.compile(
    r"\s*(?:(?:do|then|else|if|while|until|!)\s+)*(?:\w+=\S*\s+)*"
    # программа дочерней оболочки: `bash -c 'python3 - <<"PY"` — питон стоит сразу за открывающей кавычкой (D1327)
    r"(?:(?:\S*/)?(?:ba|z|da)?sh\s+(?:-\w+\s+)*-\w*c\s+['\"]\s*)?"
    r"(?:(?:\S*/)?(?:env|exec|time|nice|timeout|(?:uv|poetry|pipenv)\s+run)"
    r"(?:\s+(?:\w+=\S*|\d+[smhd]?|--?[\w-]+(?:=\S*)?(?:\s+(?!(?:\S*/)?(?:python|pypy))[^-\s]\S*)?))*\s+)*"
    r"(?:\S*/)?(?:python|pypy)[0-9.]*(?=\s|$)")

def reads_program(seg):
    # питон читает ПРОГРАММУ со stdin, если до `-` или до конца нет файла скрипта и нет -m/-c
    if len(seg) > 4000:
        return False
    m = PYRUN.match(seg)
    if not m:
        return False
    toks, k = seg[m.end():].split(), 0
    while k < len(toks):
        tok, k = toks[k], k + 1
        if tok == "-":
            return True
        if re.fullmatch(r"\d*(?:[<>]+|>&|<&)", tok) or tok in ("-W", "-X"):
            k += 1                      # оператор перенаправления или опция со значением — значение следом
        elif re.match(r"\d*[<>]", tok):
            continue                    # перенаправление со слитной целью
        elif re.match(r"-[mc]", tok) or not tok.startswith("-"):
            return False                # модуль, строка программы или файл скрипта — stdin это данные
    return True

def first_replace(prog):
    # `.replace(a, b, 1)` / `.replace(a, b, count=1)`: аргументы — сканером с кавычками, скобками, комментариями
    for m in re.finditer(r"\.\s*replace\s*\(", prog):
        args, cur, depth, q, j = [], "", 0, None, m.end()
        while j < len(prog):
            c = prog[j]
            if q:
                if c == "\\":
                    cur += prog[j:j + 2]
                    j += 2
                    continue
                if c == q:
                    q = None
            elif c in "'\"":
                q = c
            elif c == "#":
                nl = prog.find("\n", j)
                j = len(prog) if nl < 0 else nl
                continue
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif c == "," and depth == 0:
                args.append(cur.strip())
                cur, j = "", j + 1
                continue
            cur += c
            j += 1
        if j >= len(prog):
            return None                 # незакрытый вызов: программа не разобрана — дальше не сканируем
        args.append(cur.strip())
        if args and args[-1] == "":
            args.pop()
        if len(args) == 3 and re.sub(r"\s", "", args[2]) in ("1", "count=1"):
            return prog[m.start():j + 1]
    return None

lines = cmd.split("\n")
i = 0
while i < len(lines):
    scan = ARITH.sub(lambda a: " " * len(a.group(0)), lines[i])
    scan = SUBST.sub(lambda a: "_" * len(a.group(0)), scan)
    i += 1
    opens = list(OPEN.finditer(scan))
    if not opens:
        continue
    sep_ends = [x.end() for x in SEP.finditer(scan)]
    cut_starts = [x.start() for x in CUT.finditer(scan)]
    for n, m in enumerate(opens):
        dash, marker, body = m.group(1) == "-", m.group(3), []
        while i < len(lines) and (lines[i].lstrip("\t") if dash else lines[i]) != marker:
            body.append(lines[i])
            i += 1
        i += 1
        k = bisect.bisect_right(sep_ends, m.start())
        seg = scan[sep_ends[k - 1] if k else 0:m.start()]
        c = bisect.bisect_left(cut_starts, m.end())
        stop = min(cut_starts[c] if c < len(cut_starts) else len(scan),
                   opens[n + 1].start() if n + 1 < len(opens) else len(scan))
        pipe = scan[m.end():stop].split("|")[1:]
        if not (reads_program(seg) or any(reads_program(p) for p in pipe)):
            continue
        prog = "\n".join(body)
        hit = None if "count(" in prog else first_replace(prog)
        if hit:
            print(" ".join(hit.split())[:80])
            sys.exit(0)
PY
)
HIT=$(printf '%s' "$INPUT" | python3 -I -c "$PY" 2>/dev/null)
[ -n "$HIT" ] || exit 0

# Журнал `state/replace-uniqueness-fired-<SID>.jsonl` — семейство `*-fired-*`, читатель у него есть
# (`scripts/signal-precision.sh`). Без журнала точность отказа измерена бы один раз, при заведении (корень R5).
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosid"' 2>/dev/null)
STATE_DIR="${STATE_DIR:-${HOME:-}/.claude/hooks/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cmd "$HIT" '{ts:$ts,key:"replace-first-no-count",cmd:$cmd}' \
    >> "$STATE_DIR/replace-uniqueness-fired-${SID}.jsonl" 2>/dev/null

jq -n --arg hit "$HIT" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:
    ("🚫 Замена первого вхождения `" + $hit + "` без счёта вхождений образца: при двух одинаковых местах правка молча ляжет в первое, а запись файла и код 0 будут те же (D522, ProjectA B272). Перед заменой докажи единственность: `assert s.count(o) == 1, o` — проверка `o in s` отличает «нет» от «есть», но не «одно» от «несколько». Замена всех вхождений — `assert s.count(o) == N`; намеренная замена по одной в цикле — `for _ in range(s.count(o)): s = s.replace(o, n, 1)`.")}}'
exit 0
