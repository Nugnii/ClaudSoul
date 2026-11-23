#!/usr/bin/env bash
# СУДИТ: hooks/lib/transcript_window.py hooks/hook-input-lib.sh hooks/root-cause-lib.sh
# test_transcript_window.sh — окно текущего хода (D498): читатель хода получает то же, что из всей расшифровки, а цена не растёт с историей.
#
# Предмет — РАВЕНСТВО вердиктов на окне и на всём файле при тех же входах. Окно начинается с
# последней реплики владельца (определение `transcript_user_texts`); читатель с более широкой
# границей (любая запись user — `rc_turn_text`) находит свою внутри окна. Цена — отдельно,
# пробой пункта `hooks/tests/fixtures/probe_D498.sh`.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
W="$HOOKS/lib/transcript_window.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "ожидалось «$3», получено «$2»"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
def u(x, **kw): return json.dumps(dict({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": x}]}}, **kw), ensure_ascii=False)
def a(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def e(fp): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Edit", "input": {"file_path": fp}}]}}, ensure_ascii=False)
tr = json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}})
lines = [u("первая реплика"), a("ответ 1"), e("/tmp/x y.txt"), tr, u("вторая реплика"), a("Почему так? Почему иначе? Почему вообще?"),
         json.dumps({"type": "user", "isCompactSummary": True, "message": {"role": "user", "content": "сводка"}}),
         json.dumps({"type": "user", "isMeta": True, "message": {"role": "user", "content": [{"type": "text", "text": "мета"}]}}),
         json.dumps({"type": "user", "isSidechain": True, "message": {"role": "user", "content": [{"type": "text", "text": "ветка"}]}}),
         json.dumps({"type": "user", "origin": {"kind": "task-notification"}, "message": {"role": "user", "content": [{"type": "text", "text": "задача"}]}}),
         tr, a("после сжатия")]
open(f"{t}/t.jsonl", "w").write("\n".join(lines) + "\n")
PY
F="$T/t.jsonl"

# T1 — граница: последняя реплика владельца; сводка, мета, ветка, уведомление и результат
# инструмента границей не служат.
OFF=$(python3 "$W" "$F")
eq T1 "$(tail -c +$((OFF + 1)) "$F" | head -1 | jq -r '.message.content[0].text')" "вторая реплика"

# T2 — недописанная последняя строка в окно не входит: `jq -s` на ней упал бы целиком.
cp "$F" "$T/p.jsonl"; printf '%s' '{"type":"assistant","mess' >> "$T/p.jsonl"
read -r S E <<< "$(python3 "$W" "$T/p.jsonl" --range)"
eq T2 "$E" "$(wc -c < "$F" | tr -d ' ')"

# T3 — тёплый счёт по метке равен холодному: после дописанного ответа и после новой реплики.
mkdir -p "$T/st" || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
python3 "$W" "$F" --state "$T/st" >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ещё"}]}}' >> "$F"
eq T3a "$(python3 "$W" "$F" --state "$T/st")" "$(python3 "$W" "$F")"
python3 -c 'import json;print(json.dumps({"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"третья"}]}}, ensure_ascii=False))' >> "$F"
WARM=$(python3 "$W" "$F" --state "$T/st"); COLD=$(python3 "$W" "$F")
eq T3b "$WARM" "$COLD"
[ "$WARM" -gt "$OFF" ] && ok || bad T3c "новая реплика не сдвинула начало хода: $WARM ≤ $OFF"

# T4 — файл укоротился (переписан): метка не используется, счёт холодный.
head -n 5 "$F" > "$T/short.jsonl"; cp "$T/short.jsonl" "$F.tmp"; cat "$F.tmp" > "$F"
eq T4 "$(python3 "$W" "$F" --state "$T/st")" "$(python3 "$W" "$F")"

# T5 — окно с последнего текста агента ДО реплики (читатель текста агента до реплики).
cat > "$F" <<'EOF'
{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"раз"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"текст агента"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"два"}]}}
EOF
read -r S E <<< "$(python3 "$W" "$F" --range --from-agent)"
eq T5 "$(tail -c +$((S + 1)) "$F" | head -1 | jq -r '.message.content[0].text')" "текст агента"

# T6 — быстрая проверка «правка, затем реплика» равна прежнему разбору стража поправок.
REF='[ .[] | if .type == "user" then ((.message.content // []) as $c | if ($c|type)=="string" then (if ($c|length)>0 then "H" else empty end) elif ($c|type)=="array" then (if ([$c[]|select(.type=="tool_result")]|length)>0 then empty elif ([$c[]|select(.type=="text")|select(.text//""|length>0)]|length)>0 then "H" else empty end) else empty end) elif .type=="assistant" then ([(.message.content//[])[]|select(.type=="tool_use")|select(.name=="Edit" or .name=="Write" or .name=="MultiEdit")|select((.input.file_path//"")==$f)]|if length>0 then "E" else empty end) else empty end] | join("") | if test("EH") then 1 else 0 end'
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
def u(x): return json.dumps({"type":"user","message":{"role":"user","content":[{"type":"text","text":x}]}}, ensure_ascii=False)
def e(fp): return json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":fp}}]}}, ensure_ascii=False)
tr = json.dumps({"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok /tmp/x y.txt"}]}})
cases = {"eh": [u("q"), e("/tmp/x y.txt"), tr, u("не так")], "he": [u("q"), e("/tmp/x y.txt"), tr],
         "other": [u("q"), e("/tmp/z.txt"), u("x")], "mention": [u("про /tmp/x y.txt"), u("ещё")],
         "eeh": [u("q"), e("/tmp/x y.txt"), e("/tmp/x y.txt"), u("x")]}
for k, ls in cases.items():
    open(f"{t}/c-{k}.jsonl", "w").write("\n".join(ls) + "\n")
PY
for k in eh he other mention eeh; do
    eq "T6-$k" "$(python3 "$W" "$T/c-$k.jsonl" --context-hit '/tmp/x y.txt')" \
        "$(jq -rs --arg f '/tmp/x y.txt' "$REF" "$T/c-$k.jsonl")"
done

# T7 — читатель хода разборщика причин даёт на окне то же, что на всём файле: граница у него
# шире (любая запись user), и его окно лежит внутри окна хода.
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
def u(x, **kw): return json.dumps(dict({"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":x}]}}, **kw), ensure_ascii=False)
def a(x): return json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":x}]}}, ensure_ascii=False)
ls = [u("старое"), a("старый ответ"), u("новая реплика"), a("часть 1"),
      json.dumps({"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":[{"type":"text","text":"задача завершена"}]}}),
      a("часть 2"), json.dumps({"type":"user","isCompactSummary":True,"message":{"role":"user","content":"сводка"}}), a("часть 3")]
open(f"{t}/rc.jsonl", "w").write("\n".join(ls) + "\n")
PY
WIN=$(bash -c '. "$1/root-cause-lib.sh"; rc_turn_text "$2"' _ "$HOOKS" "$T/rc.jsonl")
FULL=$(bash -c '. "$1/root-cause-lib.sh"; transcript_turn_window() { cat "$1"; }; rc_turn_text "$2"' _ "$HOOKS" "$T/rc.jsonl")
eq T7 "$WIN" "$FULL"

# T7b — граница разборщика совпадает с репликой (после неё записей user нет): окно, начатое
# ПОЗЖЕ реплики, отрезало бы «часть 1». Здесь T7 различала бы только раннее окно — то
# безвредно; позднее различает эта нога.
printf '%s\n' \
  '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"старое"}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"старый ответ"}]}}' \
  '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"новая"}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"часть 1"}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"часть 2"}]}}' > "$T/rc2.jsonl"
eq T7b "$(bash -c '. "$1/root-cause-lib.sh"; rc_turn_text "$2"' _ "$HOOKS" "$T/rc2.jsonl")" "часть 1
часть 2"

# T8 — помощника нет: окно вырождается в файл целиком (дорого, но верно).
mkdir -p "$T/nolib"; cp "$HOOKS/hook-input-lib.sh" "$T/nolib/"
eq T8 "$(bash -c '. "$1/hook-input-lib.sh"; transcript_turn_window "$2" | wc -l' _ "$T/nolib" "$T/rc.jsonl" | tr -d ' ')" \
    "$(wc -l < "$T/rc.jsonl" | tr -d ' ')"

# T9 — точка последней речи тёплая: повторный вызов режима реплики не перечитывает ход (D1142,
# скептик: +2,3 с на каждом вызове инструмента в ходе 127 МБ). Судит устройство, а не время —
# порог пробы цены по времени (probe_D498_long_turn) выше разбора 8 МБ и такой рост не видит.
# Строка посреди хода переписывается на месте (та же длина, тот же inode) вложением-репликой:
# видит её только тот, кто перечитал ход. Холодный вызов её видит — контроль, что подмена удалась.
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
def u(x): return json.dumps({"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":x}]}}, ensure_ascii=False)
def a(x): return json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":x}]}})
mid = a("x" * 300)
ls = [u("старое"), a("ответ"), u("реплика хода")] + [a(f"step {i}") for i in range(50)] + [mid] + [a(f"tail {i}") for i in range(50)]
open(f"{t}/sp.jsonl", "w").write("\n".join(ls) + "\n")
q = lambda p: json.dumps({"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":p}})
swap = q("swap" + "y" * (len(mid) - len(q("swap"))))
assert len(swap) == len(mid)
open(f"{t}/sp.mid", "w").write(mid); open(f"{t}/sp.swap", "w").write(swap)
PY
mkdir -p "$T/sps"
R0=$(python3 "$W" "$T/sp.jsonl" --state "$T/sps" --range --reply)
python3 - "$T" <<'PY'
import sys
t = sys.argv[1]
b = open(f"{t}/sp.jsonl", "rb").read(); mid = open(f"{t}/sp.mid", "rb").read(); swap = open(f"{t}/sp.swap", "rb").read()
with open(f"{t}/sp.jsonl", "r+b") as f:
    f.seek(b.index(mid)); f.write(swap)
PY
COLD9=$(python3 "$W" "$T/sp.jsonl" --range --reply)
[ "$COLD9" != "$R0" ] && ok || bad T9c "подмена посреди хода не видна и холодному вызову: проба не судит"
eq T9 "$(python3 "$W" "$T/sp.jsonl" --state "$T/sps" --range --reply)" "$R0"
# T9b — дописанная реплика посреди хода тёплым вызовом находится (точка двигается вперёд).
python3 -c 'import json;print(json.dumps({"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":"дописана"}}, ensure_ascii=False))' >> "$T/sp.jsonl"
read -r S9 E9 <<< "$(python3 "$W" "$T/sp.jsonl" --state "$T/sps" --range --reply)"
eq T9b "$(tail -c +$((S9 + 1)) "$T/sp.jsonl" | head -1 | jq -r '.attachment.prompt')" "дописана"

# T10 — сжатие файла, замеченное обычным окном хода, гасит и метку речи (скептик D1142, круг 3, L1): файл переписан
# на месте короче, окно хода это видит, файл дорастает новой речью — тёплый ответ режима реплики равен холодному.
q10() { python3 -c 'import json,sys;print(json.dumps({"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":sys.argv[1]}}))' "$1"; }
a10() { printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"$1\"}]}}"; }
r10='{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"r0"}}'
mkdir -p "$T/s10"
{ printf '%s\n' "$r10"; a10 a1; q10 q1; a10 a2; a10 a3; } > "$T/t10.jsonl"
python3 "$W" "$T/t10.jsonl" --state "$T/s10" --range --reply >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
{ printf '%s\n' "$r10"; a10 a1; } > "$T/t10.short"; python3 - "$T/t10.jsonl" "$T/t10.short" <<'PY'
import sys
with open(sys.argv[1], "r+b") as f:
    f.truncate(0); f.write(open(sys.argv[2], "rb").read())
PY
python3 "$W" "$T/t10.jsonl" --state "$T/s10" --range >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
{ q10 q-new1; q10 q-new2; a10 a4; a10 a5; a10 a6; } >> "$T/t10.jsonl"
eq T10 "$(python3 "$W" "$T/t10.jsonl" --state "$T/s10" --range --reply)" "$(python3 "$W" "$T/t10.jsonl" --range --reply)"

# T11 — окно от границы читателя (D1235): `--wide` начинается с последней записи, которую берёт jq-двойник `turn_user`,
# `--no-summary` — с последней, которую берёт `real_user` канарейки; `isCompactSummary: 0` в jq истинно — запись не
# граница «без сводки» (питонское `not 0` взяло бы её, и окно началось бы позже границы читателя). Тёплый счёт равен
# холодному.
. "$HOOKS/hook-input-lib.sh" || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
python3 - "$T/t11.jsonl" <<'PY'
import json, sys
def u(x, **kw): return json.dumps(dict({"type": "user", "message": {"role": "user", "content": x}}, **kw), ensure_ascii=False)
def a(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
open(sys.argv[1], "w").write("\n".join([u("реплика", origin={"kind": "human"}), a("a1"),
    u("задача", origin={"kind": "task-notification"}), a("a2"), u("ветка", isSidechain=True),
    u("сводка-ноль", isCompactSummary=0), a("a3")]) + "\n")
PY
first11() { python3 "$W" "$T/t11.jsonl" "$@" --emit | sed -n 2p | jq -r '.message.content'; }
last11() { jq -rs "$HIL_TURN_USER_JQ"'def real_user: turn_user and ((.isCompactSummary // false) | not) and ((.isSidechain // false) | not);
    [.[] | select('"$1"')] | last | .message.content' "$T/t11.jsonl"; }
eq T11a "$(first11 --wide)" "$(last11 turn_user)"
eq T11b "$(first11 --no-summary)" "$(last11 real_user)"
eq T11c "$(first11 --no-summary)" "задача"
mkdir -p "$T/s11" || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
python3 "$W" "$T/t11.jsonl" --state "$T/s11" --wide --range >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
python3 "$W" "$T/t11.jsonl" --state "$T/s11" --no-summary --range >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_transcript_window.sh:$LINENO" >&2; exit 1; }
printf '%s\n' '{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"задача-2"}}' >> "$T/t11.jsonl"
eq T11d "$(python3 "$W" "$T/t11.jsonl" --state "$T/s11" --wide --range)" "$(python3 "$W" "$T/t11.jsonl" --wide --range)"
eq T11e "$(python3 "$W" "$T/t11.jsonl" --state "$T/s11" --no-summary --range)" "$(python3 "$W" "$T/t11.jsonl" --no-summary --range)"
eq T11f "$(first11 --wide)" "задача-2"

# T12 (D1346): служебная копия запроса (`api-request-blob`) читателю не отдаётся — ни окном, ни свёрткой, ни запасным
# путём без помощника. Клиент пишет её слитно, фикстура — и слитно, и с пробелом после двоеточия. Настоящая запись,
# в тексте которой эти слова стоят (кавычки экранированы), остаётся.
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
def u(x): return json.dumps({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def a(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
copy = {"type": "api-request-blob", "hash": "h", "message": {"role": "assistant", "content": [{"type": "text", "text": "КОПИЯ"}]}}
lines = [u("реплика"), a("настоящий ответ"), json.dumps(copy, ensure_ascii=False), json.dumps(copy, ensure_ascii=False, separators=(",", ":")),
         a('упомянул запись {"type":"api-request-blob"} словами'), a("последний ответ")]
open(f"{t}/t12.jsonl", "w").write("\n".join(lines) + "\n")
PY
W12=$(python3 "$W" "$T/t12.jsonl" --emit | sed 1d)
eq T12a "$(grep -c 'КОПИЯ' <<< "$W12")" "0"
eq T12b "$(jq -r 'select(.type == "assistant") | .message.content[0].text' <<< "$W12" | wc -l | tr -d ' ')" "3"
eq T12c "$(python3 "$W" "$T/t12.jsonl" --emit | head -1)" "ok"
# shellcheck source=/dev/null
. "$HOOKS/hook-input-lib.sh"
eq T12d "$(_ttw_whole "$T/t12.jsonl" | grep -c 'КОПИЯ')" "0"
eq T12e "$(_ttw_whole "$T/t12.jsonl" | wc -l | tr -d ' ')" "4"
F12=$(python3 "$W" "$T/t12.jsonl" --fold t12 --state "$T/s12" -- sh -c 'cat' | sed 1d)
eq T12f "$(grep -c 'КОПИЯ' <<< "$F12")" "0"
eq T12g "$(grep -c 'последний ответ' <<< "$F12")" "1"
# T12h (скептик D1346, L1): состояние свёртки, накопленное редакцией ДО отсечения копий, не продолжается — подпись
# шага у него другая, и свёртка идёт заново. Состояние прежней редакции подделывается её подписью (хеш одной команды).
CNT='cat "$1" /dev/stdin 2>/dev/null | grep -c . || true'
python3 - "$T" "$CNT" <<'PY'
import hashlib, os, sys
t, cnt = sys.argv[1], sys.argv[2]
path = os.path.abspath(f"{t}/t12.jsonl"); st = f"{t}/s12h"; os.makedirs(st, exist_ok=True)
key = hashlib.sha1(path.encode()).hexdigest()[:16]
old_sig = hashlib.sha1("\0".join(["sh", "-c", cnt, "x"]).encode()).hexdigest()[:16]
size = os.path.getsize(path)
open(f"{st}/transcript-fold-t12h-{key}", "w").write(f"{os.stat(path).st_ino} {size} {old_sig} 0\nЗАВЫШЕНО\n")
PY
F12H=$(python3 "$W" "$T/t12.jsonl" --fold t12h --state "$T/s12h" -- sh -c "$CNT" x | sed 1d)
case "$F12H" in *ЗАВЫШЕНО*) bad T12h "накопленное прежней редакции принято за своё: ${F12H}" ;; *) ok ;; esac

echo "test_transcript_window: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
