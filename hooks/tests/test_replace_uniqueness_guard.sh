#!/usr/bin/env bash
# test_replace_uniqueness_guard.sh — отказ приходит на замену первого вхождения без счёта
# вхождений образца в программе питона и не приходит на данные и на законную замену (D522).
#
# Блок B важнее блока A: страж стоит на каждом вызове Bash во всех сессиях, и ложный отказ
# блокирует настоящую работу. Ноги F*/M*/R* — находки скептика 11 октября 2026 (ложные отказы,
# пропуски, исполнение чужого кода); ноги K* убивают мутантов, которых первая редакция теста
# пропускала зелёными.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/replace-uniqueness-guard.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
[ -x "$HOOK" ] || { echo "FAIL: хук не исполняем: $HOOK"; exit 1; }

STATE_DIR=$(mktemp -d) || exit 1; export STATE_DIR
trap 'rm -rf "$STATE_DIR"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

run() {   # run <tool> <command> → permissionDecision или пусто
    jq -cn --arg t "$1" --arg c "$2" '{tool_name:$t, tool_input:{command:$c}}' \
      | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null
}
FIRED=0   # сколько отказов ожидается — для сверки журнала (C4)
assert_fires()  { local g; FIRED=$((FIRED+1)); g=$(run Bash "$2"); [ "$g" = deny ] && ok "$1" || bad "$1" "ожидался deny, получено '${g:-пусто}'"; }
assert_silent() { local g; g=$(run "${3:-Bash}" "$2"); [ -z "$g" ] && ok "$1" || bad "$1" "ожидалось молчание, получено '$g'"; }

R1='s=s.replace(o,n,1)'   # дефектная замена

echo "--- A. Замена первого вхождения без счёта отбивается ---"
assert_fires "A1 assert in + replace(,1)" $'python3 - <<\'PY\'\ns=open(p).read()\nassert o in s\n'"$R1"$'\nopen(p,"w").write(s)\nPY'
assert_fires "A2 помощник rep() из B272"  $'cd web && python3 - <<\'EOF\'\ndef rep(p,o,n):\n    s=open(p).read(); assert o in s, o\n    open(p,"w").write(s.replace(o,n,1))\nrep("a.tsx","x","y")\nEOF'
assert_fires "A3 аргументы и вызов внутри" $'python3 - "$SP" <<EOF\nt=t.replace(a, f(b), 1)\nEOF'
assert_fires "A4 <<- с табами"           $'python3 <<-PY\n\t'"$R1"$'\n\tPY'
assert_fires "A5 второй heredoc команды"  $'cat > a.txt <<\'EOF\'\nx\nEOF\npython3 - <<\'PY\'\ns=s.replace(o,n, 1 )\nPY'
assert_fires "M8 скобка внутри строки"    $'python3 - <<\'PY\'\ns=s.replace("onError(", "onFail(", 1)\nPY'
assert_fires "M5 вложенность глубже"      $'python3 - <<\'PY\'\ns=s.replace(f(g(x)), n, 1)\nPY'
assert_fires "M6 перенос внутри вызова"   $'python3 - <<\'PY\'\ns=s.replace(\n    o,\n    n,\n    1,\n)\nPY'
assert_fires "M13 пробел перед скобкой"   $'python3 - <<\'PY\'\ns=s.replace (o, n, 1)\nPY'
assert_fires "M4 count=1"                $'python3 - <<\'PY\'\ns=s.replace(o, n, count=1)\nPY'
assert_fires "M9 питон в конвейере"       $'cat <<\'PY\' | python3 -\n'"$R1"$'\nPY'
assert_fires "M10 маркер <<\\PY"          $'python3 - <<\\PY\n'"$R1"$'\nPY'
assert_fires "M11 два heredoc в строке"   $'cat <<A >/dev/null; python3 - <<\'B\'\nx\nA\n'"$R1"$'\nB'
assert_fires "M14 pypy3"                 $'pypy3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "M15 env и путь"             $'/usr/bin/env python3.12 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "K1 count( в чужом теле не в счёт" $'cat > a.md <<\'EOF\'\ns.count(o)\nEOF\npython3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "K2 here-string не открывает heredoc" $'grep -c x <<<"PY"\npython3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "K3 маркер с точкой"          $'python3 - <<\'PY.END\'\n'"$R1"$'\nPY.END'
assert_fires "K4 арифметика не открывает heredoc" $'x=$((a<<b)); python3 - <<\'PY\'\n'"$R1"$'\nPY'
# раунд 2 скептика: пропуски и выжившие мутанты
assert_fires "N1 if в начале сегмента"     $'if python3 - <<\'PY\'; then\n'"$R1"$'\nPY\nfi'
assert_fires "N2 do в цикле"              $'for f in a b; do python3 - "$f" <<\'PY\'\n'"$R1"$'\nPY\ndone'
assert_fires "N3 env с присваиванием"      $'env FOO=1 python3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N4 uv run с опцией-значением" $'uv run --with pandas python - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N5 -W со значением"          $'python3 -W ignore - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N6 перенаправление stdout"   $'python3 > out.txt <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N7 апостроф в комментарии"   $'python3 - <<\'PY\'\ns=s.replace(o,  # don\'t\n    n, 1)\nPY'
assert_fires "N8 подстановка \$(…)"         $'X=$(python3 - <<\'PY\'\n'"$R1"$'\nPY\n)'
assert_fires "N9 после | в сегменте"        $'echo start | python3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N10 присваивание перед питоном" $'PYTHONPATH=. python3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N11 timeout"                 $'timeout 60 python3 - <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N12 2>&1 перед heredoc"       $'python3 2>&1 <<\'PY\'\n'"$R1"$'\nPY'
assert_fires "N13 экранированная кавычка"   $'python3 - <<\'PY\'\ns=s.replace("a\\"b", "c", 1)\nPY'
assert_fires "N14 env с опцией"            $'env -i python3 - <<\'PY\'\n'"$R1"$'\nPY'

echo "--- B. Данные и законная замена проходят ---"
assert_silent "B1 со счётом"              $'python3 - <<\'PY\'\nassert s.count(o)==1, o\n'"$R1"$'\nPY'
assert_silent "B2 замена всех вхождений"   $'python3 - <<\'PY\'\ns=s.replace(o,n)\nPY'
assert_silent "B3 текст в cat > файл"      $'cat > f.md <<\'EOF\'\nформа `s.replace(o, n, 1)` после `assert o in s`\nEOF'
assert_silent "B4 питон внутри тела cat"   $'cat > h.sh <<\'EOF\'\npython3 - <<\'PY\'\n'"$R1"$'\nPY\nEOF'
assert_silent "B5 here-string"            $'grep -c x <<< "s.replace(o,n,1)"'
assert_silent "B6 сообщение коммита"       $'git commit -m "$(cat <<\'EOF\'\nfix: s.replace(o, n, 1) клал правку не туда\nEOF\n)"'
assert_silent "B7 счёт в помощнике"        $'python3 - <<\'EOF\'\ndef rep(p,o,n):\n    s=open(p).read(); assert s.count(o)==1, o\n    open(p,"w").write(s.replace(o,n,1))\nEOF'
assert_silent "B8 не Bash"                 $'python3 - <<\'PY\'\n'"$R1"$'\nPY' Write
assert_silent "F1 питон раньше в строке"   $'python3 build.py && cat > notes.md <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "F2 python в имени папки"    $'cd ~/python-tools && git commit -m "$(cat <<\'EOF\'\n'"$R1"$'\nEOF\n)"'
assert_silent "F3 python в имени файла"    $'cat > python.md <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "F4 stdin скрипта — данные"  $'python3 render.py <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "F5 pandas, два аргумента"   $'python3 - <<\'PY\'\ndf["ok"].replace("yes", 1)\nPY'
assert_silent "F6 два heredoc данных"      $'cat <<\'A\' > a.md; cat <<\'B\' > b.md\na\nA\npython3 - <<\'PY\'\n'"$R1"$'\nPY\nB'
assert_silent "F8 python в заголовке PR"   $'gh pr create --title "python: guard" --body "$(cat <<\'EOF\'\n'"$R1"$'\nEOF\n)"'
assert_silent "F12 сдвиг в арифметике"     $'python3 x.py --mask $((1<<n)) && cat > f.md <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "K5 <<- не течёт за маркер"  $'python3 <<-PY\n\tprint(1)\n\tPY\ncat > f.md <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "K6 python -m"              $'python3 -m json.tool <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "S1 цикл по счёту"           $'python3 - <<\'PY\'\nfor _ in range(s.count(o)): s = s.replace(o, n, 1)\nPY'
assert_silent "S2 -m слитно с модулем"     $'python3 -mjson.tool <<\'EOF\'\n'"$R1"$'\nEOF'
assert_silent "S3 скрипт дальше в конвейере" $'cat <<\'EOF\' | python3 render.py\n'"$R1"$'\nEOF'
assert_silent "S4 конвейер за && — чужой"   $'cat > f.md <<\'EOF\' && git diff | python3 -\n'"$R1"$'\nEOF'
assert_silent "S5 имя лишь с префиксом python3" $'python3-lint - <<\'PY\'\n'"$R1"$'\nPY'

echo "--- T. Время линейно на подобранном вводе ---"
# Раунд 2: 5000 heredoc в одной строке — 0,9 с, 20000 — 15 с; 5000 незакрытых `.replace(` — 17 с.
python3 - "$HOOK" <<'TIME' && ok "T1-T2 подобранный ввод < 3 с" || bad "T1-T2 подобранный ввод < 3 с" "квадратичный разбор вернулся"
import json, os, signal, subprocess, sys, time
for name, cmd in (("T1", "x" + " <<a" * 20000 + " # replace"),
                  ("T2", "python3 - <<'PY'\n" + "s.replace(" * 20000 + "\nPY")):
    t = time.time()
    # своя группа процессов: по сроку гасится и питон стража, а не только bash (иначе питон остаётся сиротой)
    p = subprocess.Popen(["bash", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        p.communicate(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}), timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
    if time.time() - t > 3:
        print(name, round(time.time() - t, 1), "с"); sys.exit(1)
TIME

echo "--- C. Текст причины и журнал ---"
R=$(jq -cn --arg c $'python3 - <<\'PY\'\n'"$R1"$'\nPY' '{tool_name:"Bash",tool_input:{command:$c}}' \
    | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
# маркер отказа — первым символом: по нему читатели расшифровки отличают отказ стража от провала (deny-mark-lib)
case "$R" in "🚫"*) ok "C1 маркер отказа первым" ;; *) bad "C1 маркер отказа первым" "${R:0:40}" ;; esac
grep -qF 'count(o) == 1' <<< "$R" && ok "C2 замена названа" || bad "C2 замена названа" "нет формы со счётом"
grep -qF '`.replace(o,n,1)`' <<< "$R" && ok "C3 место названо" || bad "C3 место названо" "нет найденной замены"
# журнал: строк столько, сколько отказов в блоках A и C, а не вызовов — молчание не пишется
N=$(cat "$STATE_DIR"/replace-uniqueness-fired-*.jsonl 2>/dev/null | grep -c '"replace-first-no-count"')
[ "$N" = $((FIRED + 1)) ] && ok "C4 журнал = отказам" || bad "C4 журнал = отказам" "строк $N, ожидалось $((FIRED + 1))"

echo "--- R. Чужой код в каталоге вызова не исполняется ---"
T=$(mktemp -d) || exit 1
printf 'print("INJECTED")\n' > "$T/json.py"; cp "$T/json.py" "$T/re.py"
G=$( cd "$T" && jq -cn '{tool_name:"Bash",tool_input:{command:"echo ok | sed s/.replace(//"}}' \
     | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null )
rm -rf "$T"
[ -z "$G" ] && ok "R1 json.py в cwd не исполняется" || bad "R1 json.py в cwd не исполняется" "получено '$G'"
G=$( jq -cn --arg c $'python3 - <<\'PY\'\n'"$R1"$'\nPY' '{tool_name:"Bash",tool_input:{command:$c}}' \
     | env -u HOME STATE_DIR= bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null )
[ "$G" = deny ] && ok "R2 без HOME отказ не теряется" || bad "R2 без HOME отказ не теряется" "получено '${G:-пусто}'"

echo "--- E. Формы владельца heredoc из настоящих команд (D1327: 3 пропуска на 13 368 командах) ---"
assert_fires "E1 присваивание с подстановкой перед питоном" "cd /r && CHK=\$(cat /tmp/chk.txt) CHK=\"\$CHK\" python3 - <<'PY'
$R1
PY"
assert_fires "E2 питон программой дочерней оболочки" "bash -c 'python3 - <<\"PY\"
$R1
PY
'"
assert_silent "E3 подстановка с питоном в значении — чужой heredoc остаётся данными" "X=\$(python3 -V) cat > f.txt <<'EOF'
$R1
EOF"
assert_silent "E4 дочерняя оболочка без питона — данные" "bash -c 'cat > f.txt <<\"EOF\"
$R1
EOF
'"

echo "--- D. Проба пункта ---"
( cd "$REPO" && bash hooks/tests/fixtures/probe_D522.sh ) && ok "D1 probe_D522 → 0" || bad "D1 probe_D522 → 0" "код $?"

echo "PASS: $PASS  FAIL: $FAIL"
exit $(( FAIL != 0 ))
