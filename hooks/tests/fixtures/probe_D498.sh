#!/usr/bin/env bash
# СУДИТ: hooks/user-correction-guard.sh hooks/five-whys-gate.sh hooks/throttle-lib.sh hooks/output-language-check.sh hooks/activity-flush-lib.sh hooks/shared-language-lib.sh
# probe_D498.sh — проба пункта D498: цена одного события хука не растёт с накопленным — с длиной расшифровки сессии и с числом файлов каталога состояния.
#
# Предмет — РАЗНОСТЬ цены одного вызова на большом и малом накопленном при ОДНОМ И ТОМ ЖЕ последнем
# ходе. Цена, не растущая с историей, даёт разность около нуля при любой нагрузке машины; растущая —
# сотни миллисекунд и больше. Ноги — по одной на событие, где цена растёт; представители — самые
# дорогие подтверждённые носители разбора wf_8a16e020-af3 (1 октября 2026):
#   L1 вызов инструмента, расшифровка — `user-correction-guard.sh:65` (и на правке файла — L1b,
#      образец «правка, затем реплика» `CONTEXT_HIT`) (jq по всей расшифровке ради
#      последней реплики) и `five-whys-gate.sh:479` (`rc_trace`, `rc_last_block`): 0,26–0,28 с на
#      19 МБ и 0,68 с на 48 МБ, на КАЖДОМ вызове;
#   L2 вызов инструмента, каталог состояния — `throttle_file` (`throttle-lib.sh:127`, `find` по всему
#      каталогу на каждом вызове; зовут 21 хук): 0,24–0,72 с при 73 тыс. файлов под нагрузкой 4–17,
#      28 мс на 30 тыс. при нагрузке 3,7 — близко к шуму замера по времени. Поэтому нога судит не
#      время, а само устройство: старый файл семейства, положенный МЕЖДУ двумя вызовами, второй
#      вызов убирает — значит, каталог обходится на каждом вызове;
#   L4 Stop, сводка по всей сессии — `activity_flush` (`activity-flush-lib.sh:57`, счёт инструментов
#      и правленых файлов всей сессии) и `shlang_candidates` (`shared-language-lib.sh`, кандидаты
#      общего словаря): 1,7 с и 1,0 с на 40 МБ на каждом Stop (2 октября 2026). Окно хода их не
#      лечит — сводке нужно накопление по дописанным байтам;
#   L3 Stop, расшифровка — `output-language-check.sh:70` (`jq -s` по всей расшифровке ради
#      последнего ответа; то же устройство у `relative-date-check.sh:53` и `fix-level-check.sh:88`).
# Размер истории — 40 МБ: наибольшая расшифровка замера была 48 МБ.
# Положительный контроль у L1 и L3: хук на последнем ходе говорит одинаково на малой и большой
# расшифровке — иначе «разность ноль» значила бы «хук ничего не прочёл», а не «цена не растёт».
#
# Коды: 0 — ни одна нога не растёт; 1 — растёт хотя бы одна; 2 — проба не исполнима (нет
# инструментов или хуков, контроль не сошёлся). Метка: судит по времени — разность, а не абсолют,
# но под тяжёлой нагрузкой мерить повторно.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# Проба пункта лежит в fixtures/ и в набор не входит: механизм берётся у CLAUDSOUL_REPO
# (зелёная сторона подменяет дерево) либо у корня этого дерева, на три уровня выше.
HOOKS="${CLAUDSOUL_REPO:-$(cd "$DIR/../../.." && pwd)}/hooks"
command -v jq >/dev/null 2>&1 || { echo "НЕ ИСПОЛНЕНО: jq недоступен"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "НЕ ИСПОЛНЕНО: python3 недоступен"; exit 2; }
for f in user-correction-guard.sh five-whys-gate.sh throttle-lib.sh output-language-check.sh; do
    [ -f "$HOOKS/$f" ] || { echo "НЕ ИСПОЛНЕНО: нет $HOOKS/$f"; exit 2; }
done
LIMIT_MS="${D498_DELTA_MS:-250}"
SID="d498-probe"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d) || { echo "НЕ ИСПОЛНЕНО: mktemp"; exit 2; }
trap 'rm -rf "$T"' EXIT

# Расшифровки: малая — только последний ход; большая — 40 МБ истории и тот же последний ход.
# Последний ход взят у положительного контроля стража поправок (нога T0 его теста): слова реплики
# стоят в ходе агента ДО неё — страж говорит. Ответ после реплики несёт слово со смешанным
# алфавитом — его называет страж языка вывода.
python3 - "$T" <<'PY' || { echo "НЕ ИСПОЛНЕНО: расшифровки не собраны"; exit 2; }
import json, sys
t = sys.argv[1]
def user(x):  return json.dumps({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def agent(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
# Ход с вызовом инструмента — сводке активности (L4) есть что считать; читатели текста его не видят.
def agent_tool(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}, {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}]}}, ensure_ascii=False)
last = [user("Посчитай долю переработок в журнале"),
        agent("Посчитана доля переработок в журнале: 13 процентов"),
        user("Доля переработок посчитана неверно"),
        agent_tool("Сверяю лookup по журналу")]
with open(f"{t}/small.jsonl", "w", encoding="utf-8") as f:
    f.write("\n".join(last) + "\n")
fill = "открыл файл, прочитал строки и сверил числа с журналом " * 9
with open(f"{t}/big.jsonl", "w", encoding="utf-8") as f:
    n = 0
    while f.tell() < 40 * 1024 * 1024:
        # Реплика владельца — раз на 100 шагов истории (решение владельца 2 октября 2026). Журнал
        # активности держит все реплики сессии одним блоком и переписывает его на каждом Stop;
        # реплика на КАЖДОМ шаге (33 тыс. на 40 МБ) мерила размер этого блока, а не чтение
        # истории, хотя в настоящих сессиях 12–22 МБ реплик 3–23. Раз на 100 шагов — ~350 на
        # 40 МБ, всё ещё в десять с лишним раз гуще жизни.
        # Латинский токен в речи — сводке словаря (L4) есть что считать: равенство накопленной
        # и холодной выдачи иначе было бы «пусто == пусто». Счёты почти равны — порядок при
        # равных счётах проверяется заодно.
        if n % 100 == 0:
            f.write(user(f"реплика истории {n} про workflow-{n % 9}") + "\n")
        f.write(agent_tool(f"ход истории {n}: {fill}") + "\n")
        n += 1
    f.write("\n".join(last) + "\n")
PY

# cost <payload> <хук> → «мс|вывод|файлы состояния»: наименьшее время из двух прогонов, каждый в
# СВОЁМ каталоге состояния — иначе второй прогон мерил бы путь дедупа, а не путь чтения.
cost() {
    python3 - "$1" "$2" "$T" <<'PY'
import os, subprocess, sys, tempfile, time
payload, hook, t = sys.argv[1].encode(), sys.argv[2], sys.argv[3]
best, out, files = None, "", ""
for _ in range(2):
    st = tempfile.mkdtemp(dir=t)
    env = dict(os.environ, STATE_DIR=st)
    s = time.monotonic()
    r = subprocess.run(["bash", hook], input=payload, capture_output=True, env=env, timeout=120)
    ms = int((time.monotonic() - s) * 1000)
    if best is None or ms < best:
        best = ms
    out = r.stdout.decode("utf-8", "replace").strip()
    files = " ".join(sorted(n for n in os.listdir(st) if os.path.getsize(os.path.join(st, n)) > 0))
print(f"{best}|{out[:400]}|{files}")
PY
}
payload() { jq -cn --arg s "$SID" --arg p "$1" --arg e "$2" --arg t "${3:-Bash}" \
    'if $t == "Edit" then {session_id:$s, transcript_path:$p, hook_event_name:$e, tool_name:"Edit", tool_input:{file_path:"/tmp/probe-d498.txt", old_string:"a", new_string:"b"}}
     else {session_id:$s, transcript_path:$p, hook_event_name:$e, tool_name:"Bash", tool_input:{command:"true"}, stop_hook_active:false} end'; }

judge() {  # judge <нога> <хук> <событие> <контроль: out|state|none> [инструмент: Bash|Edit]
    local leg="$1" hook="$2" ev="$3" ctl="$4" tool="${5:-Bash}" rs rb ms mb os ob fs fb
    rs=$(cost "$(payload "$T/small.jsonl" "$ev" "$tool")" "$HOOKS/$hook")
    rb=$(cost "$(payload "$T/big.jsonl" "$ev" "$tool")" "$HOOKS/$hook")
    ms="${rs%%|*}"; mb="${rb%%|*}"
    os="${rs#*|}"; os="${os%|*}"; ob="${rb#*|}"; ob="${ob%|*}"
    fs="${rs##*|}"; fb="${rb##*|}"
    case "$ctl" in
        out)   { [ -n "$os" ] && [ "$os" = "$ob" ]; } \
                   || { echo "НЕ ИСПОЛНЕНО [$leg $hook]: контроль — хук обязан сказать на последнем ходе одинаково на обеих расшифровках (малая: «${os:0:80}», большая: «${ob:0:80}»)"; exit 2; } ;;
        state) { grep -q "output-violations-$SID" <<< "$fs" && grep -q "output-violations-$SID" <<< "$fb"; } \
                   || { echo "НЕ ИСПОЛНЕНО [$leg $hook]: контроль — запись нарушения в состоянии на обеих расшифровках (малая: «${fs}», большая: «${fb}»)"; exit 2; } ;;
    esac
    echo "$leg $hook: малая ${ms} мс, большая ${mb} мс, разность $((mb - ms)) мс (предел ${LIMIT_MS})"
    if [ $((mb - ms)) -le "$LIMIT_MS" ]; then ok
    else bad "$leg" "$hook: цена вызова растёт с длиной расшифровки — разность $((mb - ms)) мс на 40 МБ истории при одном и том же последнем ходе"; fi
}

judge L1 user-correction-guard.sh PreToolUse out
# L1b — тот же страж на правке файла: образец «правка, затем реплика» (`CONTEXT_HIT`) читал
# всю расшифровку только на Edit/Write, и нога на вызове Bash его не касалась.
judge L1b user-correction-guard.sh PreToolUse out Edit
judge L1 five-whys-gate.sh PreToolUse none
judge L3 output-language-check.sh Stop state

# L2 — каталог состояния: обходит ли `throttle_file` весь каталог на КАЖДОМ вызове. Старый файл
# чужого семейства кладётся до первого вызова (его уборка — положительный контроль: обход вообще
# есть) и второй — между вызовами; убран второй — второй вызов снова обошёл каталог.
D="$T/dir"; mkdir -p "$D"
tf() { bash -c '. "$1"; throttle_file "$2" probe "$3" >/dev/null' _ "$HOOKS/throttle-lib.sh" "$D" d498 2>/dev/null; }
touch -t 202001010000 "$D/probe498a-fired-x.jsonl"
tf
if [ -e "$D/probe498a-fired-x.jsonl" ]; then
    echo "L2 throttle_file: каталог не обходится и на первом вызове"; ok
else
    touch -t 202001010000 "$D/probe498b-fired-x.jsonl"
    tf
    if [ -e "$D/probe498b-fired-x.jsonl" ]; then
        echo "L2 throttle_file: второй вызов каталог не обходит"; ok
    else
        bad L2 "throttle_file обходит весь каталог состояния на КАЖДОМ вызове: старый файл, положенный между двумя вызовами, убран вторым — цена вызова растёт с числом файлов каталога"
    fi
fi

# L4 — сводки по всей сессии на Stop: цена растёт с историей, если каждый Stop перечитывает всё.
# Мерится УСТАНОВИВШАЯСЯ цена (2 октября 2026, вместе со свёрткой по дописанным байтам): Stop
# бывает на каждом ходе, и прошлый Stop уже прочёл историю. Поэтому прогон — как в жизни: сводка
# по истории без последнего хода (не мерится), дописать последний ход в тот же файл, мерить вызов.
# Первый Stop после потери состояния платит за всю историю один раз — это вне ноги.
# Положительный контроль: `activity_flush` пишет журнал активности на обеих расшифровках. Равенство:
# накопленная сводка совпадает с холодной по всему файлу — журнал без строки заголовка, кандидаты
# словаря; расхождение — дефект накопления, а не цена (нога L4c).
lcost() {  # lcost <расшифровка> <функция: flush|shlang> → «мс записано равно»: наименьшее из двух
    python3 - "$HOOKS" "$1" "$2" "$T" <<'PY2'
import os, subprocess, sys, tempfile, time
hooks, tr, fn, t = sys.argv[1:5]
voc = os.path.join(t, "vocab.md")
open(voc, "w").write("# словарь\n\n- **окно хода** — от реплики\n")
if fn == "flush":
    cmd = '[ -f "$1/paths-lib.sh" ] && . "$1/paths-lib.sh"; . "$1/activity-flush-lib.sh" && activity_flush sid-d498 "$2" "$3"'
else:
    cmd = '[ -f "$1/paths-lib.sh" ] && . "$1/paths-lib.sh"; . "$1/shared-language-lib.sh" && shlang_candidates "$2" "$4" 1'
lines = open(tr, "rb").read().split(b"\n")[:-1]
head = b"".join(x + b"\n" for x in lines[:-4])
last = b"".join(x + b"\n" for x in lines[-4:])
def call(path, cwd, st):
    r = subprocess.run(["bash", "-c", cmd, "_", hooks, path, cwd, voc], capture_output=True, timeout=300,
                       env=dict(os.environ, STATE_DIR=st))
    if fn == "flush":
        try:
            with open(os.path.join(cwd, ".claude-docs", "session-activity.md"), encoding="utf-8") as j:
                return "".join(x for x in j if not x.startswith("## "))
        except OSError:
            return None
    return r.stdout.decode("utf-8", "replace")
cold = call(tr, tempfile.mkdtemp(dir=t), tempfile.mkdtemp(dir=t))
best, out = None, None
for n in range(2):
    cwd, st = tempfile.mkdtemp(dir=t), tempfile.mkdtemp(dir=t)
    cp = os.path.join(t, f"run-{fn}-{n}-{os.path.basename(tr)}")
    open(cp, "wb").write(head)
    call(cp, cwd, st)
    open(cp, "ab").write(last)
    s = time.monotonic()
    out = call(cp, cwd, st)
    ms = int((time.monotonic() - s) * 1000)
    best = ms if best is None or ms < best else best
print(best, int(out is not None and cold is not None), int(out == cold))
PY2
}
for fn in flush shlang; do
    [ -f "$HOOKS/activity-flush-lib.sh" ] && [ -f "$HOOKS/shared-language-lib.sh" ] \
        || { echo "НЕ ИСПОЛНЕНО [L4]: нет библиотек сводки"; exit 2; }
    read -r ls lw le <<< "$(lcost "$T/small.jsonl" "$fn")"
    read -r lb bw be <<< "$(lcost "$T/big.jsonl" "$fn")"
    if [ "$fn" = flush ] && { [ "$lw" != 1 ] || [ "$bw" != 1 ]; }; then
        echo "НЕ ИСПОЛНЕНО [L4 flush]: контроль — журнал активности не записан (малая: ${lw}, большая: ${bw})"; exit 2
    fi
    if [ "$le" = 1 ] && [ "$be" = 1 ]; then ok
    else bad L4c "${fn}: накопленная сводка расходится с холодной по всему файлу (малая: ${le}, большая: ${be})"; fi
    echo "L4 ${fn}: малая ${ls} мс, большая ${lb} мс, разность $((lb - ls)) мс (предел ${LIMIT_MS})"
    if [ $((lb - ls)) -le "$LIMIT_MS" ]; then ok
    else bad L4 "${fn}: сводка по сессии на Stop перечитывает всю историю — разность $((lb - ls)) мс на 40 МБ"; fi
done

echo "probe_D498: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
