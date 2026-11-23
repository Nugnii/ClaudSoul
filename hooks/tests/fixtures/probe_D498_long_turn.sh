#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/user-correction-guard.sh hooks/output-language-check.sh hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D498_long_turn.sh — вторая проба пункта D498 (долгий ход). Тест противника окна хода
# (2 октября 2026), вынесен из набора до починки остатка пункта; прежнее имя —
# test_adv_twin_long_turn_cost.sh. Окно ограничивает цену ХОДОМ, а
# не историей. В долгом автономном ходе («продолжай» и часы работы — обычный режим владельца)
# окно и есть история: каждый вызов инструмента и каждый Stop заново разбирает весь ход
# `jq -s`, и цена события растёт с длиной хода так же, как прежде росла с длиной файла.
# Размер хода — 8 МБ: наибольший последний ход в расшифровках ClaudSoul 8,5 МБ (84af614f),
# по всем проектам 14,6 МБ; ход нынешней сессии к моменту замера 3,9 МБ и растёт.
# Мерка и порог — как у пробы пункта (hooks/tests/fixtures/probe_D498.sh): разность лучшего из
# двух прогонов на большом и малом, предел D498_DELTA_MS (250 мс). Мерится установившаяся цена,
# а не первый холодный вызов: тот же хук сперва вызван на ходе без последней строки (как на
# прошлом вызове инструмента), строка дописана в тот же файл, мерится следующий вызов. Прогрев
# идёт под другим идентификатором сессии: метки «уже сказал» хуки ведут по сессии, кэши
# расшифровки (метка окна, свёртка хода) — по пути файла. До 2 октября 2026 прогревалась одна
# метка окна, вызовом помощника; свёртка хода по дописанным байтам добавила второй кэш.
set -uo pipefail
# Проба лежит в fixtures/ и в набор не входит: механизм берётся у CLAUDSOUL_REPO (зелёная
# сторона подменяет дерево) либо у корня этого дерева, на три уровня выше.
HOOKS="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}/hooks"
command -v jq >/dev/null 2>&1 || { echo "НЕ ИСПОЛНЕНО: нет jq"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "НЕ ИСПОЛНЕНО: нет python3"; exit 2; }
LIMIT_MS="${D498_DELTA_MS:-250}"
TURN_MB="${ADV_TURN_MB:-8}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
SID="adv-long-turn"

# Один и тот же ход владельца: реплика, работа агента, итоговый текст. Малая — работы нет,
# большая — TURN_MB мегабайт вызовов инструмента и их результатов ВНУТРИ этого же хода.
python3 - "$T" "$TURN_MB" <<'PY'
import json, sys
t, mb = sys.argv[1], int(sys.argv[2])
def user(x):  return json.dumps({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def agent(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def tool(i):  return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": f"grep -rn step{i} ."}}]}}, ensure_ascii=False)
def res(i, s): return json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": s}]}}, ensure_ascii=False)
fill = "строка вывода инструмента с путями и числами 12345 " * 40
for name, size in (("small", 0), ("big", mb)):
    with open(f"{t}/{name}.jsonl", "w", encoding="utf-8") as f:
        f.write(user("Посчитай долю переработок в журнале") + "\n")
        f.write(agent("Посчитана доля переработок в журнале: 13 процентов") + "\n")
        f.write(user("Доля переработок посчитана неверно") + "\n")
        i = 0
        while f.tell() < size * 1024 * 1024:
            f.write(tool(i) + "\n"); f.write(res(i, fill) + "\n"); i += 1
        f.write(agent("Сверяю лookup по журналу") + "\n")
PY

# cost <расшифровка> <хук> <событие> → «мс|вывод»: лучший из двух прогонов, каждый в своём
# каталоге состояния, ПРОГРЕТОМ вызовом того же хука на ходе без последней строки.
cost() {
    python3 - "$1" "$2" "$3" "$T" "$SID" <<'PY'
import json, os, subprocess, sys, tempfile, time
tr, hook, ev, t, sid = sys.argv[1:6]
def payload(path, s):
    return json.dumps({"session_id": s, "transcript_path": path, "hook_event_name": ev,
                       "tool_name": "Bash", "tool_input": {"command": "true"}, "stop_hook_active": False}).encode()
lines = open(tr, "rb").read().split(b"\n")[:-1]
head, last = b"".join(x + b"\n" for x in lines[:-1]), lines[-1] + b"\n"
best, out = None, ""
for n in range(2):
    st = tempfile.mkdtemp(dir=t)
    env = dict(os.environ, STATE_DIR=st)
    cp = os.path.join(st, os.path.basename(tr))
    open(cp, "wb").write(head)
    subprocess.run(["bash", hook], input=payload(cp, sid + "-warm"), capture_output=True, env=env, timeout=300)
    open(cp, "ab").write(last)
    s = time.monotonic()
    r = subprocess.run(["bash", hook], input=payload(cp, sid), capture_output=True, env=env, timeout=300)
    ms = int((time.monotonic() - s) * 1000)
    if best is None or ms < best:
        best, out = ms, r.stdout.decode("utf-8", "replace").replace("\n", " ").replace("|", "/")
print(f"{best}|{out[:300]}")
PY
}

judge() {  # judge <хук> <событие> <контроль: out|none>
    local hook="$1" ev="$2" ctl="$3" rs rb ms mb os ob
    rs=$(cost "$T/small.jsonl" "$HOOKS/$hook" "$ev"); rb=$(cost "$T/big.jsonl" "$HOOKS/$hook" "$ev")
    ms="${rs%%|*}"; mb="${rb%%|*}"; os="${rs#*|}"; ob="${rb#*|}"
    if [ "$ctl" = out ] && { [ -z "$os" ] || [ "$os" != "$ob" ]; }; then
        echo "НЕ ИСПОЛНЕНО [$hook]: контроль — вывод на малом и большом обязан совпасть (малая: «${os:0:80}», большая: «${ob:0:80}»)"; exit 2
    fi
    echo "$hook $ev: ход 0 МБ — ${ms} мс, ход ${TURN_MB} МБ — ${mb} мс, разность $((mb - ms)) мс (предел ${LIMIT_MS})"
    [ $((mb - ms)) -le "$LIMIT_MS" ] && ok || bad "$hook" "цена события растёт с длиной хода: +$((mb - ms)) мс на ${TURN_MB} МБ хода"
}

judge user-correction-guard.sh PreToolUse out
judge five-whys-gate.sh PreToolUse none
judge output-language-check.sh Stop none

echo "probe_D498_long_turn: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
