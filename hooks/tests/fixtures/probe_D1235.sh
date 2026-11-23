#!/usr/bin/env bash
set -u
# СУДИТ: install.sh scripts/stop-hook-latency.sh scripts/measurements.tsv hooks/lib/transcript_window.py hooks/hook-input-lib.sh hooks/timestamp-canary-check.sh hooks/accepted-alternative-gap.sh hooks/fix-level-check.sh hooks/output-language-check.sh hooks/relative-date-check.sh
# probe_D1235 — синхронный хук Stop не держит ответ дольше 10 с своей ценой: `declared-problem-recorded.sh` и
#   `carrier-growth-check.sh` зарегистрированы фоновыми (`"async": true` в install.sh), у цены есть строка замера
#   `stop-hook-latency` с прибором, его свидетель зелен, и живой замер за три дня не называет одиночных выходов за 10 с.
#   Живая часть зеленеет только по границам на новой регистрации — после переноса в установку и трёх дней работы.
# Цена синхронного хука не растёт с молчанием владельца (10 ноября 2026, корень R6). Читатели широкой границы хода
#   (уведомление задачи делит ход — `hooks/lib/reply-readers.tsv`) получали окно от последней РЕПЛИКИ ВЛАДЕЛЬЦА и сами
#   искали в нём свою границу: в пакетном ходе владелец молчит часами, и каждый Stop заново разбирал всё с его реплики.
#   Замер 9 ноября 2026, сессия 27d00aaf: окно владельца 88–107 МБ — канарейка 30–81 с, `accepted-alternative-gap`
#   22–61 с; окно 1 МБ — 0,4–1 с. Нога цены: расшифровка A — реплика владельца, ~40 МБ работы (20 000 вызовов с
#   кириллическим выводом), уведомление задачи, итог; B — только хвост A от уведомления. Каждый хук выносит на A и B
#   одно суждение (положительный контроль: итог несёт признак каждого хука — рамка умеет ответить «да»), и на A он не
#   дороже полутора B плюс 0,5 с и не дольше 10 с. Размер и порог подобраны замером 10 ноября 2026 на непочиненном
#   дереве: на 12 МБ из 400 длинных строк хуки с одним разбором окна (~0,02 с на МБ) от порога не отличались; на 40 МБ
#   мелких записей A 1,2–7,8 с при B 0,15–0,16 с — все пять красны.
#   0 — всё так; 1 — нет (названо); 2 — нет файлов, рамка ноги цены не собралась либо живой замер не измерен (границ
#   хода в окне нет), а код и регистрация целы — «не измерено» не складывается с «найдено» (D1295, R6).
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in install.sh scripts/stop-hook-latency.sh scripts/measurements.tsv hooks/tests/test_stop_hook_latency.sh; do [ -f "$f" ] || exit 2; done
for h in timestamp-canary-check accepted-alternative-gap fix-level-check output-language-check relative-date-check; do
    [ -f "hooks/$h.sh" ] || exit 2
done
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
bad=0
python3 - <<'PY' || bad=1
import json, sys
s = open("install.sh", encoding="utf-8").read(); i = s.index("HOOKS_CONFIG='") + len("HOOKS_CONFIG='"); j = s.index("'", i)
stop = [h for g in json.loads(s[i:j])["hooks"]["Stop"] for h in g["hooks"]]
for name in ("declared-problem-recorded.sh", "carrier-growth-check.sh"):
    rec = [h for h in stop if h["command"].endswith("/" + name)]
    if not rec or not all(h.get("async") is True for h in rec):
        print("не фоновый:", name); sys.exit(1)
PY
awk -F'\t' '$1 == "stop-hook-latency" && $3 ~ /scripts\/stop-hook-latency\.sh/ { f = 1 } END { exit !f }' scripts/measurements.tsv \
    || { echo "в реестре замеров нет строки stop-hook-latency"; bad=1; }
bash hooks/tests/test_stop_hook_latency.sh >/dev/null 2>&1 || { echo "свидетель замера красен"; bad=1; }
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1235.XXXXXX") || exit 2
python3 - "$PWD" "$W" <<'PY'
import json, os, subprocess, sys, time
R, W = sys.argv[1], sys.argv[2]
now = time.strftime("%Y-%m-%d %H:%M")
def rec(**k): return json.dumps(k, ensure_ascii=False) + "\n"
inject = rec(type="attachment", attachment={"type": "hook_additional_context", "hookName": "UserPromptSubmit",
             "content": ["🕐 %s CET — этой шапкой начни ИТОГОВОЕ сообщение хода" % now]})
final_text = "Отличная идея, учту на будущее: вчера правил fixом."
tail = (rec(type="user", origin={"kind": "task-notification"}, isSidechain=False,
            message={"role": "user", "content": "<task-notification>\n<task-id>b1</task-id>\n</task-notification>"})
        + inject
        + rec(type="assistant", message={"role": "assistant", "content": [{"type": "text", "text": final_text}]}))
blob = "строка вывода команды с путём hooks/x.sh:12 и числом 42; " * 18
work = []
for i in range(20000):   # ≈ 40 МБ вызовов инструмента и их результатов
    work.append(rec(type="assistant", message={"role": "assistant", "content": [
        {"type": "tool_use", "id": "t%d" % i, "name": "Bash", "input": {"command": "true"}}]}))
    work.append(rec(type="user", message={"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t%d" % i, "content": blob}]}))
A, B = os.path.join(W, "a.jsonl"), os.path.join(W, "b.jsonl")
with open(A, "w") as f:
    f.write(rec(type="user", message={"role": "user", "content": "разгребай без меня"}) + inject + "".join(work) + tail)
with open(B, "w") as f:
    f.write(tail)
FILES = {"output-language-check": "output-violations-%s.jsonl", "relative-date-check": "relative-date-findings-%s.jsonl",
         "fix-level-check": "fix-level-%s.jsonl"}
n = [0]
def run(hook, path):
    n[0] += 1
    sid, st = "probe-%d" % n[0], os.path.join(W, "st%d" % n[0])
    os.makedirs(st)
    env = dict(os.environ, STATE_DIR=st, CANARY_STATE_DIR=st, ABLATION_DIR=os.path.join(st, "abl"),
               LESSONS_DIR=os.path.join(st, "lessons"))
    inp = json.dumps({"session_id": sid, "transcript_path": path, "hook_event_name": "Stop",
                      "stop_hook_active": False, "last_assistant_message": final_text})
    t0 = time.time()
    p = subprocess.run(["bash", os.path.join(R, "hooks", hook + ".sh")], input=inp.encode(), env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=W)
    dt = time.time() - t0
    if hook in FILES:
        fp = os.path.join(st, FILES[hook] % sid)
        judged = os.path.isfile(fp) and os.path.getsize(fp) > 0
    else:
        judged = b"additionalContext" in p.stdout
    return dt, judged
bad = 0
for hook in ("timestamp-canary-check", "accepted-alternative-gap", "fix-level-check", "output-language-check",
             "relative-date-check"):
    # Минимум из трёх: под нагрузкой 17–20 два прогона подряд давали 1,6 с при 0,22 у пяти спокойных (10 ноября 2026).
    ra = [run(hook, A) for _ in range(3)]
    rb = [run(hook, B) for _ in range(3)]
    ta, tb = min(x[0] for x in ra), min(x[0] for x in rb)
    ja, jb = all(x[1] for x in ra), all(x[1] for x in rb)
    if not jb:
        print("рамка: %s не вынес суждения на коротком ходе — признак итога не дошёл" % hook, file=sys.stderr)
        sys.exit(2)
    if not ja:
        print("%s: на длинном молчании владельца суждения нет, на коротком есть" % hook)
        bad = 1
    print("%s: A %.2f с, B %.2f с" % (hook, ta, tb), file=sys.stderr)
    if ta > 10 or ta > 1.5 * tb + 0.5:
        print("%s: %.1f с при окне владельца 40 МБ против %.1f с на том же хвосте" % (hook, ta, tb))
        bad = 1
sys.exit(bad)
PY
crc=$?
rm -rf "$W"
[ "$crc" = 2 ] && exit 2
[ "$crc" = 0 ] || bad=1
out=$(bash scripts/stop-hook-latency.sh 2>&1); rc=$?
case "$rc" in
    0) ;;
    2) printf '%s\n' "$out" | head -4; [ "$bad" = 0 ] && exit 2 ;;
    *) printf '%s\n' "$out" | head -4; bad=1 ;;
esac
exit "$bad"
