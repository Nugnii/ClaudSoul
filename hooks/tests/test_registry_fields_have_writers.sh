#!/usr/bin/env bash
# test_registry_fields_have_writers.sh — у каждого поля записи реестра сессий больше одного
# достижимого значения (D258, D278). Поле, объявленное и никем не заполняемое, — описание
# механизма, которого нет: оно выглядит живым в каждой из тысяч записей и всегда пусто.
# Поле-литерал того же рода: оно выглядит заполненным и во всех записях одинаково.
#
# ПОВОДЫ. D258: `commits` был непуст 0 раз за 3622 сессии, `notes` — один (ручной тест
# 2026-04-15); функции `sr_update_commits` и `sr_add_note` не вызывались нигде вне
# библиотеки, а `docs/architecture.md` описывал их как работающий контур. D273/D278:
# `status: "completed"` стоял на финализации 4,5 месяца, и второго значения не принял ни
# разу (`jq -r 'select(has("status"))|.status' ~/.claude/sessions/registry.jsonl | sort |
# uniq -c` → 3 сентября 2026: 3642 `completed`, второго нет; на замере D273 было 3641).
# Этот страж родился зелёным над ним (6b78e56) — универсум кончался heredoc
# регистрации, а правило знало лишь «пусто / непусто». Тот же класс до v1.11 сжёг
# `contradicted_count`: механизм описан, писателя нет, во всех 265 знаниях ноль.
#
# ЧЕМ ЭТОТ ТЕСТ ОТЛИЧАЕТСЯ ОТ ПЕРЕЧНЯ ПОЛЕЙ. Список полей и список писателей он ВЫВОДИТ из
# кода, а не держит своей копией: копия разошлась бы с оригиналом ровно так, как разошлись
# три стража 28 августа. Запись объявляется в ДВУХ местах, и берутся оба: heredoc
# `sr_register_session` и jq-конструктор `. + { … }` в `sr_finalize_session`; соответствие
# «функция → поля» — из jq-программ внутри самой библиотеки, вызовы — поиском по дереву.
#
# ПРАВИЛО, одно для обоих мест. Значение ВЫЧИСЛЯЕТСЯ (подстановка `$var`/`$(…)` в heredoc,
# `$var` или jq-выражение в конструкторе) — заполнено при записи, писатель не нужен.
# Значение — JSON-литерал (`"completed"`, `1`, `true`) — единственное достижимое: FAIL.
# Созданное пустым (`[]`, `0`, `""`) обязано иметь писателя: либо оно вычисляется в
# `sr_finalize_session`, либо его пишет `sr_*`-функция, вызываемая ИЗ ФАЙЛА ВНЕ библиотеки.
# Вызов из текстового шаблона скилла (`skills/**/references/*.md`) писателем НЕ считается:
# это уровень 1 embedded-ness — инструкция агенту, а не механизм, и её пропуск ничем не
# наблюдается. Ключ, объявленный в обоих местах, судится по конструктору: `. +` его
# ПЕРЕЗАПИСЫВАЕТ, heredoc-запись достижимого значения не задаёт.
#
# НАЗВАННЫЙ ПРЕДЕЛ (числа — замер 3 сентября 2026). Правило статическое: переменную,
# которой все вызывающие подают одно и то же значение, оно не видит. `jq -r
# 'select(has("summary")) | if (.summary|tostring)=="" then "empty" else "nonempty" end'
# ~/.claude/sessions/registry.jsonl | sort | uniq -c` → 3620 пустых из 3656 записей;
# второе значение пишет только session-collector. Снимается реестром значений по
# вызывающим — когда появится третий вызывающий finalize.
#
# НАЗВАННЫЙ ПРЕДЕЛ ВТОРОЙ (3 сентября 2026). Универсум перечисляется ДВУМЯ якорями —
# heredoc `sr_register_session` и ПЕРВЫЙ `. + { … }` в `sr_finalize_session`; третий сайт
# объявления снова невидим, ровно как был невидим второй. Проверено мутацией, а не
# рассуждением: второй `. + {flavour: "vanilla"}` в том же теле финализации — страж зелен,
# поле не названо. Сайтов объявления записи в библиотеке сегодня ровно 2 — heredoc в
# `sr_register_session` и конструктор в `sr_finalize_session` (адресами служат ИМЕНА:
# номера строк уплывают от соседних правок, на 3 сентября 2026 их сдвинул D277).
# `sr_update_knowledge` пишет в существующий `.knowledge_delta[]`, а jq в
# `sr_detect_parallel` и `sr_detect_interrupted` строит другие объекты — списки startup
# context, не запись реестра.
# Обход ВСЕХ `. + {` предмета не различает: по широкой регулярке их 9 по дереву, из них 7 —
# отчётные выражения скриптов замеров и один писатель событий (`hooks/lib/backfill-replay-one.sh:90`),
# и отделить их от объявления записи можно было бы только своей копией имён — тем самым,
# чего этот тест не делает. Потому предел называется, а не чинится. Снять при появлении
# третьего сайта объявления в самой библиотеке.
#
# `--count` печатает число полей без писателя либо с единственным значением — строка
# «Показание» пункта D258.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HOOKS_DIR/.." && pwd)"
# Библиотека — вход, а не только собственное расположение: подмена подаётся
# REGISTRY_LIB_OVERRIDE, чтобы проверка вердиктов на формах (test_registry_guard_judges_by_parse.sh)
# не копировала дерево ради каждой формы. Умолчание прежнее; писатели ищутся в НАСТОЯЩЕМ
# дереве ($REPO), потому что писатель поля живёт вне подменяемого файла.
LIB="${REGISTRY_LIB_OVERRIDE:-$HOOKS_DIR/session-registry-lib.sh}"
MODE="${1:-}"

[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }

# Питон вынесен ИЗ подстановки `$( … )`: bash 3.2 (умолчание macOS) разбирает её,
# сканируя до парной скобки с учётом кавычек, и heredoc с питоновскими регулярками
# внутри ломает разбор ещё до исполнения (pattern-shell-portability).
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
TMPJ="$TMPD/report.json"
TMPPY="$TMPD/parse.py"
cat > "$TMPPY" <<'PY'
import os, re, subprocess, json

lib = os.environ["LIB"]
repo = os.environ["REPO"]
src = open(lib, encoding="utf-8").read()

# --- 1. Поля схемы: heredoc внутри sr_register_session -------------------------------
# Схема разбирается как НАСТОЯЩИЙ JSON, а не построчно. Первая редакция считала вложенность
# по строкам и не закрывала объект `knowledge_delta` — из-за чего выдавала несуществующее
# поле `knowledge_delta.files_changed`, а оно получало писателя по совпадению ПРЕФИКСА
# (`.knowledge_delta[` в sr_update_knowledge). Тест был зелёным по неверной причине —
# ровно pattern-detector-wired-to-failure.
m = re.search(r'sr_register_session\(\)\s*\{.*?<<\s*[\'"]?ENDJSON[\'"]?\n(.*?)\nENDJSON',
              src, re.S)
assert m, "не нашёл heredoc схемы в sr_register_session"
schema = m.group(1)

# Подстановки оболочки заменяются НЕПУСТЫМ литералом: `$(...)` и `$VAR` внутри строк —
# значения, известные при создании, и пустыми их считать нельзя.
j = re.sub(r'\$\([^()]*\)', 'SUBST', schema)
j = re.sub(r'\$\{?\w+\}?', 'SUBST', j)
try:
    doc = json.loads(j)
except Exception as e:
    raise SystemExit("схема не разобралась как JSON: %s\n%s" % (e, j))

fields = {}
def walk(o, prefix=()):
    for k, v in o.items():
        # ПУСТОЙ объект — лист, а не узел: рекурсия в него не даёт ни одного поля, и
        # `"x": {}` исчезало из универсума целиком (D297). Пустой объект — ровно тот
        # случай, ради которого страж писан: значение одно и оно пустое.
        if isinstance(v, dict) and v:
            walk(v, prefix + (k,))
        else:
            fields[".".join(prefix + (k,))] = v
walk(doc)
assert fields, "схема разобралась пустой"

# --- 1b. Поля, дописываемые на ФИНАЛИЗАЦИИ: jq-конструктор `. + { … }` в sr_finalize_session.
# Второе место объявления записи. Без него поле, добавленное при закрытии, стражу невидимо
# в принципе: `status: "completed"` (D273) прожил под зелёным стражем, рождённым над ним.
# Строка конструктора, не разобравшаяся как `ключ: значение`, — громкий отказ, не пропуск.
fm = re.search(r"sr_finalize_session\(\)\s*\{.*?'\.\s*\+\s*\{(.*?)\}\s*'", src, re.S)
assert fm, "не нашёл конструктор `. + { … }` в sr_finalize_session"
# Единица разбора — ЭЛЕМЕНТ jq-объекта (до запятой верхнего уровня), а не строка текста.
# Построчная регулярка стоила двух ложных вердиктов и одного падения на здоровом коде:
# второе поле на строке (`a: $x, status: "completed"`) в универсум не попадало вовсе, а
# значение, занявшее две строки, роняло разбор с AssertionError (D297).
def _balanced(t):
    depth, quote, esc = 0, None, False
    for ch in t:
        if esc:
            esc = False
            continue
        if quote:
            if ch == "\\":
                esc = True
            elif ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0 and quote is None

def split_top_level(text):
    parts, buf, depth, quote, esc = [], [], 0, None, False
    for ch in text:
        if esc:
            buf.append(ch); esc = False; continue
        if quote:
            buf.append(ch)
            if ch == "\\":
                esc = True
            elif ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch; buf.append(ch); continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(buf)); buf = []; continue
        buf.append(ch)
    parts.append("".join(buf))
    return [p for p in (x.strip() for x in parts) if p]

final_fields = {}
for frag in split_top_level(fm.group(1)):
    mm = re.match(r'"?([A-Za-z_]\w*)"?\s*:\s*(.+)$', frag, re.S)
    assert mm, "элемент конструктора финализации не разобрался: %r" % frag
    final_fields[mm.group(1)] = mm.group(2).strip()
assert final_fields, "конструктор финализации разобрался пустым"
# `. + {…}` ПЕРЕЗАПИСЫВАЕТ ключ: поле, объявленное в обоих местах, достижимое значение
# получает на финализации, heredoc-запись отбрасывается (на 6b78e56 так стоял files_changed).
for k in final_fields:
    fields.pop(k, None)

def json_value(raw):
    """(значение, True) для выражения с ОДНИМ достижимым значением; (None, False) —
    для вычисляемого. Внешние парные скобки снимаются: `("only")` — то же одно
    значение, что и `"only"`, а прежняя проверка звала его вычислением (D297).
    `$var`, `$(…)` и настоящие jq-выражения JSON-ом не разбираются."""
    t = raw.strip().rstrip(",").strip()
    while len(t) > 1 and t[0] == "(" and t[-1] == ")" and _balanced(t[1:-1]):
        t = t[1:-1].strip()
    try:
        return json.loads(t), True
    except Exception:
        return None, False

def is_empty(v):
    return v == [] or v == 0 or v == "" or v == {}

# --- 2. Соответствие «sr_*-функция → какие поля она пишет» ----------------------------
func_fields = {}
for fm in re.finditer(r'^(sr_[a-z_]+)\(\)\s*\{', src, re.M):
    name = fm.group(1)
    start = fm.end()
    depth, i = 1, start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    body = src[start:i]
    touched = set()
    for f in list(fields) + [k for k in final_fields if k not in fields]:
        leaf = f.split(".")[-1]
        head = f.split(".")[0]
        # jq-присваивание/добавление к полю: `.field +=`, `.field |=`, `.field =`,
        # `.a[$x] +=`, ключ в heredoc `"field":` либо ГОЛЫЙ ключ в jq-конструкторе
        # объекта `field: $var` — последнее чуть не пропустило sr_finalize_session,
        # где `summary: $summary` пишется без кавычек.
        if re.search(r'\.%s\s*(\+=|\|=|=)' % re.escape(head), body) \
           or re.search(r'\.%s\[' % re.escape(head), body) \
           or re.search(r'"%s"\s*:' % re.escape(leaf), body) \
           or re.search(r'(?m)^\s*%s\s*:' % re.escape(leaf), body):
            touched.add(f)
    func_fields[name] = touched

# --- 3. Кто зовёт эти функции ВНЕ библиотеки (и не из текстового шаблона) -------------
def callers(fn):
    # `except: return []` и непроверенный код возврата стояли здесь до 5 сентября 2026 и
    # были родом B: сломавшийся `grep` (нет двоичного файла, чужой диалект, код ≥2) отдаёт
    # тот же пустой вывод, что честное «не нашёл ни одного», и поле получало вердикт
    # «ПИСАТЕЛЯ НЕТ» — красный тест по причине, которой нет в мире. У `grep` код 1 значит
    # «не нашёл», ≥2 значит «сломался»; ветка `except`/пустая строка сливала их в один.
    try:
        r = subprocess.run(
            ["grep", "-rl", "--include=*.sh", "--include=*.py", fn,
             os.path.join(repo, "hooks"), os.path.join(repo, "scripts")],
            capture_output=True, text=True)
    except Exception as e:                       # noqa: BLE001 — отказ обязан быть НАЗВАН
        raise SystemExit("НЕ ПРОВЕРЕНО: поиск писателей не запустился (%r) — "
                         "вердикты о полях не выносятся" % (e,))
    if r.returncode >= 2:
        # Код 2 у `grep` покрывает и полный отказ, и ЧАСТИЧНУЮ ошибку при состоявшемся
        # поиске (один файл исчез или нечитаем). Различить их кодом нельзя, и оба
        # означают одно: перечень писателей НЕПОЛОН, а вердикт «писателя нет» на неполном
        # перечне — утверждение о мире по части. Поэтому останавливаемся в обоих случаях,
        # но говорим именно это, а не «поиск не работает».
        raise SystemExit("НЕ ПРОВЕРЕНО: поиск писателей неполон (код %d: %s) — перечень "
                         "мог не охватить часть дерева, вердикты о полях не выносятся"
                         % (r.returncode, r.stderr.strip()[:200]))
    out = r.stdout
    # Сам этот тест — не писатель: он называет функции, разбирая их. Без исключения
    # hooks/tests/ он засчитал бы себя и любой файл, лишь упомянувший имя.
    return [p for p in out.split("\n")
            if p and os.path.basename(p) != os.path.basename(lib)
            and os.sep + "tests" + os.sep not in p]

writerless, ok = [], []
for f, val in sorted(fields.items()):
    if not is_empty(val):
        # Подстановка (SUBST) — значение известно при создании. Всё прочее непустое — литерал,
        # у поля одно достижимое значение: тот же дефект, что у поля без писателя.
        if isinstance(val, str) and "SUBST" in val:
            ok.append((f, "заполнено при создании"))
        else:
            writerless.append((f, "ЕДИНСТВЕННОЕ ДОСТИЖИМОЕ ЗНАЧЕНИЕ: литерал %s"
                               % json.dumps(val, ensure_ascii=False)))
        continue
    why = None
    if f in func_fields.get("sr_finalize_session", set()):
        why = "вычисляется в sr_finalize_session"
    else:
        for fn, ff in func_fields.items():
            if fn in ("sr_register_session", "sr_finalize_session") or f not in ff:
                continue
            cs = callers(fn)
            if cs:
                why = "%s ← %s" % (fn, ", ".join(os.path.relpath(c, repo) for c in cs))
                break
    (ok if why else writerless).append((f, why or "ПИСАТЕЛЯ НЕТ"))

for f, raw in sorted(final_fields.items()):
    val, is_json = json_value(raw)
    if not is_json:
        ok.append((f, "вычисляется в sr_finalize_session"))
    elif is_empty(val):
        # Созданное ПУСТЫМ на финализации — тот же случай, что пустое поле heredoc, и
        # судится тем же правилом: писателем обязана быть sr_*-функция с вызывающим ВНЕ
        # библиотеки. Сам конструктор писателем не считается — он это поле и создал
        # пустым; прежняя редакция звала его «вычисляется в sr_finalize_session» и
        # выдавала полю `commits: []` ложное свидетельство (D297).
        why = None
        for fn, ff in func_fields.items():
            if fn in ("sr_register_session", "sr_finalize_session") or f not in ff:
                continue
            cs = callers(fn)
            if cs:
                why = "%s ← %s" % (fn, ", ".join(os.path.relpath(c, repo) for c in cs))
                break
        (ok if why else writerless).append((f, why or "ПИСАТЕЛЯ НЕТ (создано пустым на финализации)"))
    else:
        writerless.append((f, "ЕДИНСТВЕННОЕ ДОСТИЖИМОЕ ЗНАЧЕНИЕ: литерал %s на финализации" % raw))

print(json.dumps({"ok": ok, "writerless": writerless}, ensure_ascii=False))
PY
REPO="$REPO" LIB="$LIB" python3 "$TMPPY" > "$TMPJ" 2>"$TMPD/err"
[ -s "$TMPJ" ] || { echo "FAIL: разбор схемы упал"; cat "$TMPD/err"; exit 1; }
REPORT=$(cat "$TMPJ")

# --- ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: доказать, что проверка СПОСОБНА покраснеть ---------------
# Тест из одних зелёных утверждений доказывает лишь, что он молчит; он молчал бы и будучи
# пустым файлом (правило hooks/tests/test_guards_provable.sh). Здесь это особенно нужно:
# первая редакция была зелёной по НЕВЕРНОЙ причине — ломался разбор вложенности, и
# несуществующее поле получало писателя по совпадению префикса.
# В копию библиотеки подсаживается поле, которого никто не пишет; если проверка его не
# назовёт, зелёное на живой библиотеке ничего не значит.
MUT="$TMPD/session-registry-lib.sh"
sed 's/^  "knowledge_delta": {$/  "phantom_never_written": [],\
  "knowledge_delta": {/' "$LIB" > "$MUT"
grep -q 'phantom_never_written' "$MUT" || { echo "FAIL: подсадное поле не вставилось — контроль недействителен"; exit 1; }
CTRL=$(REPO="$REPO" LIB="$MUT" python3 "$TMPPY" 2>/dev/null \
       | python3 -c 'import json,sys; d=json.load(sys.stdin); print(",".join(f for f,_ in d["writerless"]))' 2>/dev/null)
case "$CTRL" in
    *phantom_never_written*) ;;
    *) echo "FAIL: отрицательный контроль не сработал — проверка не способна покраснеть (нашла: '$CTRL')"; exit 1 ;;
esac

# --- ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ №2 (D278): литерал в обоих местах и переменная рядом ----------
# В копию библиотеки подсаживаются ПЯТЬ полей: литерал на финализации (ровно то, чем был
# `status: "completed"`), литерал в heredoc, ПЕРЕМЕННАЯ на финализации, ВЫЧИСЛЯЕМОЕ
# jq-выражение на финализации и поле, объявленное в ОБОИХ местах — пустым в heredoc и
# литералом на финализации. Три литерала обязаны быть названы, переменная и выражение —
# нет. Без переменной контроль проходим белым списком имён: страж, не знающий ключа,
# неотличим от стража, понявшего литерал. Без поля в обоих местах проходима дедупликация
# в сторону heredoc: `. +` перезаписывает, судить надо по нему. Без вычисляемого выражения
# (добавлено 3 сентября 2026) контроль проходит подмена `json_value` текстовым
# `not raw.startswith("$")` — она даёт rc=0 на четырёх подсадных и ложно краснит законное
# `tag: ($ended | ascii_upcase)`; после архивации D278 внешней «Проверки» не останется, и
# этот контроль — единственный сторож правила «литерал против вычисления».
MUT2="$TMPD/session-registry-lib-literal.sh"
awk '{print}
     /^ *ended_at: \$ended,$/ {print "            phantom_final_literal: \"only_value\","; print "            phantom_final_variable: $ended,"; print "            phantom_final_computed: ($ended + \"only_value\"),"; print "            phantom_both: \"only_value\","}
     /^  "started_at": "\$started_at",$/ {print "  \"phantom_heredoc_literal\": \"only_value\","; print "  \"phantom_both\": 0,"}' "$LIB" > "$MUT2"
for p in phantom_final_literal phantom_final_variable phantom_final_computed phantom_heredoc_literal phantom_both; do
    grep -q "$p" "$MUT2" || { echo "FAIL: подсадное поле $p не вставилось — контроль №2 недействителен"; exit 1; }
done
CTRL2=$(REPO="$REPO" LIB="$MUT2" python3 "$TMPPY" 2>/dev/null \
       | python3 -c 'import json,sys; d=json.load(sys.stdin); print(",".join(f for f,_ in d["writerless"]))' 2>/dev/null)
case ",$CTRL2," in
    *,phantom_final_literal,*) ;;
    *) echo "FAIL: контроль №2 — литерал на финализации не назван, универсум кончается heredoc (нашла: '$CTRL2')"; exit 1 ;;
esac
case ",$CTRL2," in
    *,phantom_heredoc_literal,*) ;;
    *) echo "FAIL: контроль №2 — литерал в heredoc не назван, правило знает лишь пусто/непусто (нашла: '$CTRL2')"; exit 1 ;;
esac
case ",$CTRL2," in
    *,phantom_final_variable,*) echo "FAIL: контроль №2 — переменная на финализации названа литералом (нашла: '$CTRL2')"; exit 1 ;;
esac
case ",$CTRL2," in
    *,phantom_final_computed,*) echo "FAIL: контроль №2 — вычисляемое выражение названо литералом (нашла: '$CTRL2')"; exit 1 ;;
esac
case ",$CTRL2," in
    *,phantom_both,*) ;;
    *) echo "FAIL: контроль №2 — поле в обоих местах судится по heredoc, а не по конструктору (нашла: '$CTRL2')"; exit 1 ;;
esac

COUNT=$(printf '%s' "$REPORT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["writerless"]))')

if [ "$MODE" = "--count" ]; then
    printf '%s\n' "$COUNT"
    exit 0
fi

printf '%s' "$REPORT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for f, why in d["ok"]:
    print(f"  ok   {f:34s} {why}")
for f, why in d["writerless"]:
    print(f"  FAIL {f:34s} {why}")
'

if [ "$COUNT" -ne 0 ]; then
    echo "registry fields have writers: $COUNT поле(й) записи без писателя либо с единственным достижимым значением"
    echo "  Исход из закрытого списка: подключить писателя-механизм ЛИБО убрать поле из записи"
    echo "  и из описания в docs/architecture.md. «Убрать» — законный исход, он честнее пустого поля."
    exit 1
fi
echo "registry fields have writers: у всех полей записи больше одного достижимого значения"
exit 0
