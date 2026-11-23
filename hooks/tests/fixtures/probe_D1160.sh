#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/command-scope-lib.sh hooks/lib/write_targets.py
# Проба D1160: при живом поводе страж разбора отбивает запись любой из 42 форм — 18 прежде принимались за чтение, 24
# пропускали первые редакции признака (тело `bash <<X` в начале строки, после `cd … &&`, после `2>&1`, под обёртками с
# ключами, в `<(…)` и в `bash -c "$(cat <<X …)"`; `bash -c '…'`; две подоболочки `((…); …)`; `find -exec`/`-execdir`;
# `xargs rm` и `xargs -J`; `git rm`; `eval rm`; `rm` в обратных апострофах и в `"$(…)"`; `env -C`; `stdbuf`; `unlink`;
# `ruby -i`; PIL `.save(`; `\"` в `[[ … ]]` — находки скептика opus по d33e7943 и 6ee336f8 и замера), — и молчит на 21
# чтении: «>» в теле heredoc интерпретатора (и внутри тела оболочки), в арифметике, в кавычках, в подстановке внутри
# "…" и `\>`; `tee`/`rm`/`-i` не в позиции команды; `command -v`/`-pv`. Отдельной ногой — вызов git после `]]` в кавычках.
# Повод — отметка полосы провалов (`error_streak_fired_<сессия>`), как в probe_D1105.sh. Цели — в дереве: запись в
# песочницу Bash не освобождает (квантор, `hooks/five-whys-gate.sh` про Bash), но так проба не зависит от этого решения.
# Перевод строки в форме записан как `\n` и раскрывается при чтении.
# Код: 0 — все 42 отбиты, чтения молчат; 1 — нет (названо); 2 — нет стража, jq или контроль «узнанная запись» не отбит.
set -u
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/five-whys-gate.sh"
[ -f "$H" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1160.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
T="$W/t.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$T"
jq -cn --arg t "Побочно вылезла дыра в границе слова, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$T"
touch "$W/error_streak_fired_p1160"
gate() { jq -cn --arg c "$1" --arg p "$T" --arg d "$PWD" \
    '{session_id:"p1160", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
    | STATE_DIR="$W" bash "$H" 2>/dev/null; }

grep -q '"deny"' <<< "$(gate 'echo x >> hooks/x.sh')" || { echo "контроль: узнанная запись при поводе не отбита"; exit 2; }

bad=0
while IFS= read -r c; do
    [ -n "$c" ] || continue
    c=${c//\\n/$'\n'}
    grep -q '"deny"' <<< "$(gate "$c")" || { echo "запись принята за чтение: ${c%%$'\n'*}"; bad=1; }
done <<'FORMS'
echo x > "hooks/x.sh"
echo x >"hooks/x.sh"
echo x &> hooks/x.sh
echo x &>> hooks/x.sh
echo x |tee hooks/x.sh
echo x | tee "hooks/x.sh"
git -C . commit -m m
git -c user.name=a commit -m m
sed -E -i '' 's/a/b/' hooks/x.sh
sed -e 's/a/b/' -i hooks/x.sh
perl -pi -e 's/a/b/' hooks/x.sh
perl -0777 -pi -e 's/a/b/' hooks/x.sh
cp /tmp/a hooks/x.sh
mv /tmp/a hooks/x.sh
rm hooks/x.sh
node -e "require('fs').writeFileSync('hooks/x.sh','x')"
awk '{print}' hooks/a > "hooks/x.sh"
install -m 644 /tmp/a hooks/x.sh
bash <<'X'\necho x | tee hooks/x.sh\nX
bash <<'X'\ngit commit -m m\nX
cd . && bash <<'X'\necho x | tee hooks/x.sh\nX
bash -c 'cd hooks && sed -i.bak s/a/b/ x.sh'
((echo x > hooks/f); true)
find hooks -name x.sh -exec sed -i s/a/b/ {} +
ls hooks/*.bak | xargs rm
python3 -c "from PIL import Image; Image.new('RGB',(1,1)).save('hooks/x.png')"
bash 2>&1 <<'X'\ntouch hooks/x.sh\nX
bash <(cat <<'X'\ntouch hooks/x.sh\nX\n)
bash -c "$(cat <<'X'\ntouch hooks/x.sh\nX\n)"
sudo -E bash <<'X'\nrm hooks/x.sh\nX
timeout 60 bash <<'X'\nrm hooks/x.sh\nX
git rm hooks/x.sh
eval rm hooks/x.sh
echo `rm hooks/x.sh`
echo "$(rm hooks/x.sh)"
ls hooks/*.bak | xargs -J % rm %
env -C hooks rm x.sh
stdbuf -oL sed -i s/a/b/ hooks/x.sh
unlink hooks/x.sh
ruby -i -pe 'x' hooks/x.sh
find hooks -execdir rm {} +
[[ $x == \" ]] && echo x > hooks/f
FORMS

# Чтения. Пять первых — с замера шага 2 (10 расшифровок): heredoc со сравнением, глушение `2>/dev/null` (разбор целей
# отдаёт /dev/null) и `sed -n …; grep -i`, где ключ `-i` соседней команды цеплялся к `sed`. Остальные — находки скептика
# opus по d33e7943 и 6ee336f8: оператор в кавычках, имена не в позиции команды, `-M` у perl, арифметика, `tee` в поток,
# кавычки подстановки внутри "…" (№326 его замера), слова `rm`/`tee` в теле heredoc интерпретатора, `\"` в подстановке,
# хозяин heredoc — питон после команды оболочки.
while IFS= read -r c; do
    [ -n "$c" ] || continue
    c=${c//\\n/$'\n'}
    grep -q '"deny"' <<< "$(gate "$c")" && { echo "чтение принято за запись: ${c%%$'\n'*}"; bad=1; }
done <<'READS'
grep -n x hooks/x.sh
python3 -I - <<'X'\nprint(len(s)>1)\nX
cat hooks/x.sh | head -1
grep -rn x hooks 2>/dev/null | head -3
sed -n 1,5p hooks/x.sh; grep -n -i x hooks/x.sh
grep -n '>' hooks/x.sh | head -3
grep -c ">>" hooks/x.sh
grep -rn rm hooks/x.sh
command -v rm
c="$(grep -c "=>" hooks/x.sh)"; echo "$c"
perl -MTime::HiRes=time -le "print time"
if (( $(ls -1 hooks | wc -l) > 50 )); then echo many; fi
[[ "$x" == ">" ]] && echo y
echo x | tee /dev/stderr
bash -c 'f "$(printf "<a from=\"b\">")"; echo rc=$?'
python3 - <<'X'\nprint("rm tee")\nX
[ a \> b ] && echo y
cd . && bash <<'SH'\npython3 - <<'PY'\nprint(1 > 0)\nPY\nSH
echo "$(printf "a\"b > c")"
command -pv rm
bash hooks/x.sh; python3 - <<'PY'\nprint(1 > 0)\nPY
READS
# Конец `[[ … ]]` — вне кавычек (L1 скептика): страж этого не видит (коммит судит и `is_git_commit`), видят вызовы git.
python3 -I - "$PWD/hooks/lib" <<'PY' || { echo "лексер: «]]» в кавычках кончил условие, вызов git после него потерян"; bad=1; }
import sys; sys.path.insert(0, sys.argv[1]); import write_targets as w
sys.exit(0 if [g["sub"] for g in w.git_calls('[[ "$x" == "]]" ]] && git commit -m m')] == ["commit"] else 1)
PY
[ "$bad" -eq 0 ] && echo "42 формы записи отбиты, 21 чтение молчит, вызов git после «]]» в кавычках виден"
exit "$bad"
