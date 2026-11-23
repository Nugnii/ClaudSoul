#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/root-cause-lib.sh hooks/fix-level-check.sh hooks/lib/reply-readers.tsv hooks/output-language-check.sh hooks/relative-date-check.sh hooks/accepted-alternative-gap.sh hooks/timestamp-canary-check.sh
# probe_D1153 — служебная запись харнесса `api-request-blob` (роль user, тип другой) ход не делит у читателей широкой
# границы: они зовут ядро «запись user» (`turn_user` в jq, `is_turn_user` в питоне), а не свою проверку роли.
#  · свёртка хода `RC_TURN_STEP`: ход «почини» → текст → blob → текст — `rc_turn_text` отдаёт оба текста; контроль —
#    реплика владельца ход делит;
#  · `fix-level-check`: фраза-фикс, сказанная ДО blob, на Stop записана;
#  · ядро в jq и в питоне отвечают одинаково на формах записи из мира;
#  · ни один читатель реестра (понятия граница, речь, до-текущей) не судит «user» своей копией — по устройству
#    сравнения, а не по написанию (D1156): порчи по формам скептика держит `probe_D1156`; источники (`hook-input-lib.sh`,
#    `transcript_window.py`) судятся тоже, кроме самих определений владельца (D1209, копию в источнике держит `probe_D1209`).
# Красная (1), пока blob делит ход или копия жива; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
for f in hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/root-cause-lib.sh hooks/fix-level-check.sh hooks/lib/reply-readers.tsv; do
    [ -f "$R/$f" ] || exit 2
done
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
rec() { jq -nc "$@"; }
BLOB='{type:"api-request-blob",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"ok"},{type:"text",text:"<system-reminder>\nStop hook additional context: x</system-reminder>"}]}}'
{ rec '{type:"user",message:{role:"user",content:"почини"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"ДО-BLOB: надо вынести урок и не повторять."}]}}'
  rec "$BLOB"
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"после blob"}]}}'
} > "$T/b.jsonl" || exit 2
{ cat "$T/b.jsonl"; rec '{type:"user",message:{role:"user",content:"новая реплика"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"ответ на новую"}]}}'; } > "$T/r.jsonl" || exit 2
turn() { mkdir -p "$T/st-$2"; STATE_DIR="$T/st-$2" bash -c '. "$1/hooks/root-cause-lib.sh"; rc_turn_text "$2"' _ "$R" "$1" 2>/dev/null | tr '\n' '|'; }
case "$(turn "$T/r.jsonl" r)" in *ДО-BLOB*|'') echo "рамка: реплика владельца ход не делит"; exit 2 ;; esac
case "$(turn "$T/b.jsonl" b)" in
    *ДО-BLOB*после\ blob*) ;;
    *) echo "RC_TURN_STEP: blob делит ход — текст до него у стража разбора выпал"; exit 1 ;;
esac
mkdir -p "$T/home/.claude/hooks/state"
jq -nc --arg tp "$T/b.jsonl" '{hook_event_name:"Stop",session_id:"p1153",transcript_path:$tp}' \
    | HOME="$T/home" STATE_DIR="$T/home/.claude/hooks/state" bash "$R/hooks/fix-level-check.sh" >/dev/null 2>&1
grep -q "надо вынести урок" "$T/home/.claude/hooks/state/fix-level-p1153.jsonl" 2>/dev/null || {
    echo "fix-level-check: фраза-фикс до blob не записана — blob делит ход"; exit 1; }
FORMS="$T/forms.jsonl"
{ rec '{type:"user",message:{role:"user",content:"да"}}'; rec "$BLOB"
  rec '{type:"user",isCompactSummary:true,message:{role:"user",content:"sum"}}'
  rec '{type:"user",origin:{kind:"task-notification"},message:{role:"user",content:"<task-notification>"}}'
  rec '{type:"user",message:{role:"user",content:[{type:"tool_result",content:"x"}]}}'
  rec '{type:"user",isMeta:true,message:{role:"user",content:"x"}}'
  rec '{type:"user",isSidechain:true,message:{role:"user",content:[{type:"text",text:"x"}]}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"x"}]}}'
  rec '{type:"user",message:{role:"user",content:[{type:"text",text:5}]}}'; } > "$FORMS" || exit 2
JQ=$(bash -c '. "$1/hooks/hook-input-lib.sh"; jq -c "$HIL_TURN_USER_JQ turn_user" "$2"' _ "$R" "$FORMS" 2>/dev/null | tr '\n' ' ')
PY=$(python3 -c 'import sys,json; sys.path.insert(0, sys.argv[1] + "/hooks/lib"); from transcript_window import is_turn_user
print(" ".join(str(is_turn_user(json.loads(l))).lower() for l in open(sys.argv[2])))' "$R" "$FORMS" 2>/dev/null)
[ -n "$PY" ] && [ "$JQ" = "$PY " ] || { echo "ядро «запись user»: jq ($JQ) и питон ($PY) отвечают по-разному"; exit 1; }
[ "$PY" = "true false true true false false true false false" ] || { echo "ядро «запись user» судит формы не так: $PY"; exit 1; }
# Своя копия признака «запись user» опознаётся по УСТРОЙСТВУ, а не по написанию (D1156, R3). Первая редакция ловила
# сравнение поля `type`/`role` с "user", и финальный скептик по 5e64dfc3 обошёл её дюжиной форм (константа `USER`,
# параметр функции, `startswith`, `str()`, `operator.eq`, словарь-диспетчер, `frozenset`, срез, `U=user`, `case` в
# строку): перечень сравнений неполон по построению. Поэтому копия — само слово «user» в коде читателя:
#  · питон (разбор `ast`) — литерал "user" где угодно, кроме ключа и значения словаря-записи; словарь, по которому
#    ищут (индекс, `.get`, `in`), — уже сравнение и копия;
#  · оболочка и jq — слово user целиком (в кавычках и без, `\"user\"`, `user)`, `=user`, `--arg u user`) в строке кода
#    после снятия комментария, кроме частей пути и имени (`user-…`, `/user`, `.user`, `$USER`).
# Пределы, каждый с условием снятия:
#  · литерал, собранный по частям (`"us" + "er"`, `startswith("use")`, `u*` в `[[ ]]`), признак не видит. Условие
#    снятия: признак судит значение, а не исходник (вычисленный литерал — у разбора jq `--debug-dump-disasm` и
#    исполнения питонской функции на записях с типом и ролью user);
#  · построение записи `{type:"user"}` в jq и словарь `{"role": "user"}` в питоне внутри `.sh` красят, как копия: в
#    оболочке разбора нет. Условие снятия: jq и питон читателей лежат собранными (файл программы), и их судит разбор;
#  · читатель «не-реплика» изъят целым файлом, и копия, дописанная в него, не видна. Условие снятия: изъятие —
#    строкой с объявленным поводом, а не файлом.
cat > "$T/scan.py" <<'SCAN' || exit 2
import ast, pathlib, re, sys
R = pathlib.Path(sys.argv[1])
def py_hits(src):
    t = ast.parse(src); par = {}
    for n in ast.walk(t):
        for c in ast.iter_child_nodes(n): par[id(c)] = n
    def record_part(n):  # ключ или значение словаря-записи, по которому не ищут
        d = par.get(id(n))
        if not isinstance(d, ast.Dict): return False
        up = par.get(id(d))
        if isinstance(up, ast.Subscript) and up.value is d: return False
        if isinstance(up, ast.Attribute) and up.value is d: return False      # {...}.get(…)
        if isinstance(up, ast.Compare) and d in up.comparators: return False  # x in {...}
        return True
    return [n.lineno for n in ast.walk(t) if isinstance(n, ast.Constant) and n.value == "user" and not record_part(n)]
SH = re.compile(r'(?<![\w$/.])(?<![^:]-)user(?![\w/.-])')
CMT = re.compile(r'(^|\s)#\s.*$')
skip, sources = set(), set()
for line in (R / "hooks/lib/reply-readers.tsv").read_text(encoding="utf-8").splitlines():
    if line and not line.startswith("#"):
        p, c = (line.split("\t") + [""])[:2]
        if c.strip() == "не-реплика": skip.add(p)
        elif c.strip() == "источник": sources.add(p)
# Источник судится тоже (D1209): копия правила рядом с его определением расходится с ним так же. Вычитаются только сами
# определения владельца и строка харнесса «The user just ran» (шаблон вставки, а не проверка роли).
OWN_PY = {"as_reply", "is_turn_user", "is_owner_reply", "is_owner_speech", "_human_kind"}
OWN_SH = ("HIL_AS_REPLY_JQ=", "HIL_TURN_USER_JQ=", "HIL_OWNER_REPLY_JQ=")
def owner_lines(p, src):
    out = set()
    if p.endswith(".py"):
        for n in ast.walk(ast.parse(src)):
            if isinstance(n, ast.FunctionDef) and n.name in OWN_PY: out.update(range(n.lineno, n.end_lineno + 1))
        return out
    ls = src.splitlines(); i = 0
    while i < len(ls):
        if ls[i].startswith(OWN_SH):
            while i < len(ls) and ls[i].strip(): out.add(i + 1); i += 1
        else:
            if '"The user just ran"' in ls[i]: out.add(i + 1)
            i += 1
    return out
left = []
for f in sorted(x for d in ("hooks", "scripts") for x in (R / d).rglob("*") if x.suffix in (".sh", ".py") and x.is_file()):
    p = f.relative_to(R).as_posix()
    if "/tests/" in "/" + p or p in skip: continue
    src = f.read_text(encoding="utf-8", errors="replace")
    try:
        hits = py_hits(src) if p.endswith(".py") else \
            [i for i, l in enumerate(src.splitlines(), 1) if not l.lstrip().startswith("#") and SH.search(CMT.sub("", l))]
    except SyntaxError as e:
        print(f"рамка: {p} не разбирается ({e.msg}, строка {e.lineno})"); sys.exit(2)
    if p in sources:
        own = owner_lines(p, src); hits = [h for h in hits if h not in own]
    left += [f"{p}:{h}" for h in hits]
print(" ".join(left))
SCAN
left=$(python3 "$T/scan.py" "$R"); rc=$?
[ "$rc" -eq 0 ] || { echo "${left:-рамка: распознаватель своей копии вышел кодом $rc}"; exit 2; }
[ -z "$left" ] || { echo "своя проверка роли «user» у читателей: $left"; exit 1; }
# Понятие, а не только blob (скептик D1153, M1). Широкая граница: уведомление задачи ход ДЕЛИТ — так задумано у свёртки
# (`.claude-docs/modules/transcript-window.md`); подмена ядра правилом владельца склеила бы ходы.
{ rec '{type:"user",message:{role:"user",content:"почини"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"ДО-УВЕДОМЛЕНИЯ"}]}}'
  rec '{type:"user",origin:{kind:"task-notification"},message:{role:"user",content:"<task-notification>готово</task-notification>"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"после уведомления"}]}}'; } > "$T/n.jsonl" || exit 2
case "$(turn "$T/n.jsonl" n)" in
    *ДО-УВЕДОМЛЕНИЯ*) echo "RC_TURN_STEP: уведомление задачи не делит ход — широкая граница подменена правилом реплики"; exit 1 ;;
    *после\ уведомления*) ;;
    *) echo "рамка: текст хода после уведомления не получен"; exit 2 ;;
esac
# Речь: сводка сжатия — не речь собеседника у замера по корпусу; подмена владельца ядром взяла бы её.
mkdir -p "$T/ch/.claude/projects/p"
{ rec '{type:"user",message:{role:"user",content:"Ошибка:\nвот лог"}}'
  rec '{type:"user",isCompactSummary:true,message:{role:"user",content:"Сводка:\nпрошлый разговор"}}'; } > "$T/ch/.claude/projects/p/s.jsonl" || exit 2
out=$(HOME="$T/ch" python3 "$R/scripts/colon-lead-in-count.py" 2>/dev/null)
printf '%s' "$out" | grep -q 'зачином-двоеточием: [0-9]' || { echo "рамка: замер двоеточий не ответил: $(printf '%s' "$out" | head -3)"; exit 2; }
printf '%s' "$out" | grep -q 'зачином-двоеточием: 1\b' || {
    echo "colon-lead-in-count: сводка сжатия принята за речь собеседника — $(printf '%s' "$out" | grep 'двоеточ')"; exit 1; }
# Без библиотеки ввода publish-guard отказывает: сухой прогон прошлого хода не засчитан (запасное `true`, M1).
mkdir -p "$T/pg/hooks" "$T/pgh"; for f in publish-guard.sh command-scope-lib.sh paths-lib.sh; do cp "$R/hooks/$f" "$T/pg/hooks/"; done
{ rec '{type:"user",message:{role:"user",content:"проверь публикацию"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:"bash scripts/publish-public.sh"}}]}}'
  rec '{type:"user",message:{role:"user",content:"теперь публикуй"}}'; } > "$T/pgt.jsonl" || exit 2
jq -nc --arg tp "$T/pgt.jsonl" '{tool_name:"Bash",tool_input:{command:"bash scripts/publish-public.sh --push"},transcript_path:$tp}' \
    | HOME="$T/pgh" bash "$T/pg/hooks/publish-guard.sh" 2>/dev/null | grep -q deny || {
    echo "publish-guard без библиотеки ввода засчитал сухой прогон прошлого хода — публикация пропущена"; exit 1; }
# Окно хода — из библиотеки ввода (третий и четвёртый круги). Файла библиотеки нет — помощника окна нет, и ни один из
# четырёх хуков не судит: окном был бы весь файл, и фразы ПРОШЛОГО хода судились бы заново. Старая редакция (помощник
# окна есть, ядра нет) судит текущий ход и не судит прошлый, как до D1153: окно начинается с последней реплики владельца
# (скептик третьего круга, M1 — охрана по ядру глушила этот суд). Старая редакция строится из нынешней библиотеки
# снятием ядра и правила реплики. Контроль: с библиотекой фразы текущего хода находят все четыре.
hd="$R/hooks"; mkdir -p "$T/nf/hooks/lib" "$T/ol/hooks/lib"
for f in "$hd"/*.sh; do [ "${f##*/}" = hook-input-lib.sh ] || cp "$f" "$T/nf/hooks/"; done; cp "$hd"/lib/* "$T/nf/hooks/lib/" 2>/dev/null
cp "$T"/nf/hooks/*.sh "$T/ol/hooks/"; cp "$T"/nf/hooks/lib/* "$T/ol/hooks/lib/" 2>/dev/null
{ cat "$hd/hook-input-lib.sh"; printf '%s\n' "unset HIL_TURN_USER_JQ HIL_OWNER_REPLY_JQ"; } > "$T/ol/hooks/hook-input-lib.sh" || exit 2
bash -c '. "$1"; command -v transcript_turn_window >/dev/null && [ -z "${HIL_TURN_USER_JQ:-}" ]' _ "$T/ol/hooks/hook-input-lib.sh" \
    || { echo "рамка: фикстура старой редакции не та (окна нет либо ядро осталось)"; exit 2; }
PH='Ошибка моя. Надо вынести урок и не повторять. Слово trёх. Вчера сломалось. Твой вариант лучше.'
U1='{type:"user",message:{role:"user",content:"первый"},timestamp:"2026-10-27T10:00:00Z"}'
U2='{type:"user",message:{role:"user",content:"второй"},timestamp:"2026-10-27T10:05:00Z"}'
A0='{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Готово."}]}}'
AP='{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
{ rec "$U1"; rec "$A0"; rec "$U2"; rec --arg t "$PH" "$AP"; } > "$T/cur.jsonl" || exit 2
{ rec "$U1"; rec --arg t "$PH" "$AP"; rec "$U2"; rec "$A0"; } > "$T/past.jsonl" || exit 2
# judged <каталог хуков> <расшифровка> <метка> → кто из четырёх судил фразы хода: «fix lang date aag»
judged() {
    local h="$1" tp="$2" st="$T/st4-$3" out="" k
    mkdir -p "$st/h"
    for k in fix-level-check output-language-check relative-date-check; do
        jq -nc --arg tp "$tp" '{hook_event_name:"Stop",session_id:"s4",transcript_path:$tp}' \
            | HOME="$st/h" STATE_DIR="$st" bash "$h/$k.sh" >/dev/null 2>&1
    done
    grep -q 'надо вынести урок' "$st/fix-level-s4.jsonl" 2>/dev/null && out="$out fix"
    grep -q 'trёх' "$st/output-violations-s4.jsonl" 2>/dev/null && out="$out lang"
    [ -s "$st/relative-date-findings-s4.jsonl" ] && out="$out date"
    jq -nc --arg tp "$tp" '{hook_event_name:"Stop",session_id:"s4",transcript_path:$tp}' \
        | HOME="$st/h" STATE_DIR="$st" bash "$h/accepted-alternative-gap.sh" 2>/dev/null | grep -q . && out="$out aag"
    printf '%s' "${out# }"
}
v=$(judged "$hd" "$T/cur.jsonl" ok); [ "$v" = "fix lang date aag" ] || { echo "рамка: с библиотекой фразы текущего хода нашли не все: «${v}»"; exit 2; }
v=$(judged "$T/ol/hooks" "$T/cur.jsonl" olc)
[ "$v" = "fix lang date aag" ] || { echo "со старой редакцией библиотеки текущий ход судят не все четыре: «${v}»"; exit 1; }
v=$(judged "$T/ol/hooks" "$T/past.jsonl" olp); [ -z "$v" ] || { echo "со старой редакцией библиотеки судится прошлый ход: «${v}»"; exit 1; }
v=$(judged "$T/nf/hooks" "$T/past.jsonl" nfp); [ -z "$v" ] || { echo "без библиотеки ввода судится прошлый ход: «${v}» — охраны нет"; exit 1; }
# У каждого хука широкой границы с запасным `false` — охрана по окну хода, без запасного окна «весь файл»; названные
# исключения: библиотека свёртки (выйти не может) и declared-problem-recorded (без ядра молчит сам).
noguard=""
for f in "$hd"/*.sh; do
    case "${f##*/}" in root-cause-lib.sh|declared-problem-recorded.sh|hook-input-lib.sh) continue ;; esac
    grep -q 'HIL_TURN_USER_JQ:-def turn_user: false;' "$f" || continue
    grep -qE '^[[:space:]]*command -v transcript_turn_window >/dev/null 2>&1 \|\| (exit|return) 0$' "$f" \
        && ! grep -q 'transcript_turn_window() {' "$f" || noguard="$noguard ${f##*/}"
done
[ -z "$noguard" ] || { echo "без охраны по окну хода либо с запасным окном «весь файл»:$noguard"; exit 1; }
echo "blob ход не делит; читатели широкой границы зовут ядро «запись user»"
exit 0
