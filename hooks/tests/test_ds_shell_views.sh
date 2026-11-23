#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh
# test_ds_shell_views.sh — вид `full` (как его берут стражи) не теряет местный вызов и снимает закавыченное (D1015).
#
# Результат: `_ds_view full` по входу JSON держит местный вызов видимым во всех формах стороны (а) и снимает форму во
#            всех формах стороны (б); вход в 600 КБ — быстрее потолка
# Проверка результата: bash hooks/tests/test_ds_shell_views.sh даёт 0
#
# Предмет — `_ds_view full`, а не цепочка `ds_unquoted_command "$(ds_shell_only …)"`: попытка 21 октября 2026 судила
# цепочку без ступени `ds_code_only`, тогда стоявшей посередине, — комментарий `#42"` внутри многострочной строки
# срезался вместе с закрывающей кавычкой, и рабочий вид терял вызов при зелёном свидетеле. Сторона (в) — вид тел
# heredoc `hbody_raw`: он обязан брать тела у того же разбора (D1039).
# Сторона (а) — формы, где вид ТЕРЯЛ местный вызов: ложное начало heredoc, кавычки без состояния (скептик D1012),
# и формы, на которых упала попытка 21 октября (скептик D1015): стандартное сообщение коммита через `$(cat <<'EOF')`,
# `$'…'`. Сторона (б) — то, ради чего вид заведён. DS_LIB подменяет библиотеку — для положительного контроля на
# прежней редакции. Имя инструмента собрано из
# переменной: страж отсутствующего инструмента судит текст команды.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="${DS_LIB:-$REPO/hooks/detection-signals-lib.sh}"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
t=timeout
RE="(^|[;|&(]|&&|\|\|)[[:space:]]*$t[[:space:]]+[0-9]"
view() { _ds_view full "$(jq -cn --arg c "$1" '{command: $c}')"; printf '%s' "$_DS_V"; }
keep() {  # keep <нога> <команда> — местный вызов обязан остаться виден
    if grep -qE "$RE" <<< "$(view "$2")"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$1]: вид потерял местный вызов: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-90)"; fi
}
drop() {  # drop <нога> <команда> — форма обязана быть снята
    if grep -qE "$RE" <<< "$(view "$2")"; then FAIL=$((FAIL+1)); echo "FAIL [$1]: форма не снята: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-90)"
    else PASS=$((PASS+1)); fi
}
keep A1 "$(printf "grep -n '<<EOF' f.sh\n%s 5 true" "$t")"
keep A2 "$(printf 'git commit -m "doc: the <<EOF form"\n%s 5 true' "$t")"
keep A3 "$(printf 'read a <<< hello\n%s 5 true' "$t")"
keep A4 "$(printf 'echo $((x<<y))\n%s 5 true' "$t")"
keep A5 "$(printf "echo \"it's\"; %s 5 true; echo 'done'" "$t")"
keep A6 "$(printf "# don't forget\n%s 5 true\necho 'ok'" "$t")"
keep A7 "$(printf 'echo "a \\" b"; %s 5 true; echo "c"' "$t")"
keep A8 "$(printf 'echo \\"; %s 5 true; echo "x"' "$t")"
keep A9 "$(printf 'cat <<-EOF\n\tbody\n\tEOF\n%s 5 true' "$t")"
keep A10 "$(printf 'cat <<END-X\nbody\nEND-X\n%s 5 true' "$t")"
keep A11 "$(printf 'echo "a;b"; %s 5 true' "$t")"
keep A12 "$(printf 'cat <<EOF\nbody\nEOF\n%s 5 true' "$t")"
keep A13 "$(printf 'cat <<A; cat <<B\none\nA\ntwo\nB\n%s 5 true' "$t")"
keep A14 "$(printf '%s 5 true # trailing comment' "$t")"
keep A15 "$(printf 'ssh host "uptime"\n%s 5 true' "$t")"
# Формы скептика попытки 21 октября: на них упала та редакция.
keep C1 "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: message\nEOF\n)"\n%s 5 true' "$t")"
# `#42"` в многострочной строке судит нога A14 `test_ds_quote_state.sh`.
keep C3 "$(printf "echo \$'it\\\\'s'; %s 5 true" "$t")"
# Формы финального скептика второй редакции: вложенная подоболочка `((…) …)` — не арифметика; `$[…]` — арифметика.
keep C4 "$(printf '((cd x && make) 2>&1)\ncat <<EOF\ndon'"'"'t panic\nEOF\n%s 5 true' "$t")"
keep C5 "$(printf 'y=$[1<<2]\n%s 5 true' "$t")"
drop B9 "$(printf '((cd x && make) 2>&1 | tee log)\ncat <<EOF\n%s 5 body\nEOF' "$t")"
# D1042: роль знака — по конструкции, которую он закрывает. `)` подстановки слово не кончает; обратная кавычка в "…"
# открывает область команды до парной обратной кавычки; `((` — арифметика, только если внутренняя скобка закрыта вплотную
# перед внешней. Стороны F — красные на прежней редакции (кроме контролей F6, F7: они держат узость).
keep F1 "$(printf 'echo $(true)#x; %s 5 true' "$t")"
keep F2 "$(printf 'y="`echo "it'"'"'s"`"; %s 5 true' "$t")"
drop F3 "$(printf '((cd /tmp && cat <<'"'"'EOF'"'"') && (echo b))\n%s 5 one\nEOF' "$t")"
drop F4 "$(printf 'echo $((ls) | wc -l)\ncat <<'"'"'EOF'"'"'\n%s 5 one\nEOF' "$t")"
drop F5 "$(printf '((cd x && echo "))") && true); cat <<'"'"'EOF'"'"'\n%s 5 one\nEOF' "$t")"
drop F6 "$(printf '(true)# %s 5 true' "$t")"
drop F7 "$(printf 'echo "`date` %s 5 now"' "$t")"
# Финальный скептик c4489c95: конец обратной кавычки оболочка находит сырым поиском — непарный апостроф и комментарий
# внутри наружу не выходят; `$((` без пары в строке — арифметика. Ноги G красные на c4489c95 (G5 — и на прежней).
keep G1 "$(printf 'git commit -m "Fix `it'"'"'s` case"; %s 5 true' "$t")"
drop G2 "$(printf 'echo "Fix `it'"'"'s` ok"; echo '"'"'a; %s 5 true'"'"'' "$t")"
drop G3 "$(printf 'echo "see `issue #4`" && cat <<EOF\n%s 5 body\nEOF' "$t")"
keep G4 "$(printf 'x=$((\n1 << 2\n))\n%s 5 true' "$t")"
keep G5 "$(printf 'x=`echo a # b`; %s 5 true' "$t")"
# Вид кода целиком (с телами heredoc): одиночная обратная кавычка в строке тела области не открывает.
if grep -qE "$RE" <<< "$(_ds_view unq_code_cmd "$(jq -cn --arg c "$(printf 'cat > f.js <<'"'"'EOF'"'"'\nconst tick = "`";\nEOF\n%s 5 true' "$t")" '{command: $c}')"; printf '%s' "$_DS_V")"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [G6]: вид кода потерял вызов после одиночной обратной кавычки в теле"; fi
drop B1 "$(printf 'ssh host "\n%s 5 true\n"' "$t")"
drop B2 "$(printf "ssh host '\n%s 5 true\n'" "$t")"
drop B3 "$(printf 'cat > job.sh <<EOF\n%s 5 true\nEOF' "$t")"
drop B4 "$(printf "cat > job.sh <<'EOF'\n%s 5 true\nEOF" "$t")"
drop B5 "$(printf 'for c in "echo ok; %s 5 true" b; do echo "$c"; done' "$t")"
drop B6 "$(printf 'git commit -m "fix: %s 5 now works"' "$t")"
drop B7 "$(printf 'cat <<-EOF > f\n\t%s 5 x\n\tEOF' "$t")"
drop B8 "$(printf 'cat <<A; cat <<B\n%s 5 one\nA\n%s 5 two\nB' "$t" "$t")"
drop D1 "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\n%s 5 inside the message\nEOF\n)"' "$t")"
drop D1b "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: don'"'"'t break it\n%s 5 inside the message\nEOF\n)"' "$t")"
drop D1c "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: the \"quoted\" word\n%s 5 inside the message\nEOF\n)"' "$t")"
drop D2 "$(printf '# %s 5 true' "$t")"
# (в) Тела heredoc — тем же разбором: ложное начало тела не даёт, настоящее отдаёт строки тела без меток.
body() {  # body <нога> <ожидаемое тело> <команда>
    local got
    _ds_view hbody_raw "$(jq -cn --arg c "$3" '{command: $c}')"; got="$_DS_V"
    if [ "$got" = "$2" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$1]: тело [$(printf '%s' "$got" | tr '\n' '|')] вместо [$(printf '%s' "$2" | tr '\n' '|')]"; fi
}
body H1 "" "$(printf "grep -n '<<EOF' f.sh\necho after")"
body H2 "" "$(printf 'echo $((1<<2))\necho after')"
body H3 "" "$(printf 'read a <<< x\necho after')"
body H4 "one" "$(printf "cat > f <<'EOF'\none\nEOF\necho after")"
body H5 "$(printf 'one\ntwo')" "$(printf 'cat <<A; cat <<B\none\nA\ntwo\nB\necho after')"
body H6 "$(printf '\tone')" "$(printf 'cat <<-EOF\n\tone\n\tEOF\necho after')"
body H7 "fix: msg" "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: msg\nEOF\n)"\necho after')"
body H8 "" "$(printf '((x = 1 << 2))\necho after')"
body H9 "one" "$(printf '((cd /tmp && cat <<'"'"'EOF'"'"') && (echo b))\none\nEOF\necho after')"
# Третий круг D1042 (скептик 3a4d7ddb): единица покрытия — «граница строки» × «вид кавычек вокруг» × «что внутри».
# Область, открытая на одной строке, закрывается на следующей — закрывающая кавычка не открывает новую (M-a); метка
# внутри области — heredoc самой подстановки (L-b); вид с телами (`unq_code_cmd`) ищет конец только в своей строке.
keep K1 "$(printf 'x=`a\nb`; echo "it'"'"'s `date`"; %s 5 true' "$t")"
keep K2 "$(printf 'x="`a\nb`"; echo "it'"'"'s `date`"; %s 5 true' "$t")"
keep K3 "$(printf 'x=`echo a # c\nb`; %s 5 true' "$t")"
keep K4 "$(printf 'x=`echo $((1\n+2))`; %s 5 true' "$t")"
keep K5 "$(printf 'x=`\n`; echo "`date`"; %s 5 true' "$t")"
body K6 "BODYZ" "$(printf 'x=`a\nb`; echo "`date`"\ncat <<EOF\nBODYZ\nEOF\necho after')"
body K7 "" "$(printf 'y="`cat <<EOF`"\necho after')"
body K8 "one" "$(printf 'x=`cat <<EOF\none\nEOF\n`\necho after')"
if grep -qE "$RE" <<< "$(_ds_view unq_code_cmd "$(jq -cn --arg c "$(printf 'cat > f.js <<'"'"'EOF'"'"'\nconst t = "`";\nEOF\n%s 5 true; echo `date`' "$t")" '{command: $c}')"; printf '%s' "$_DS_V")"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [K9]: вид с телами спарил обратную кавычку тела с кавычкой кода"; fi
# K10 — конец подстановки в `"…"` печатается `) `, как у `$(…)`: образцы признаков, у которых `` ` `` — разделитель,
# не читают слово за строкой вызовом (L-a). K11 — второй heredoc на своей строке внутри многострочной области — тело.
if grep -qE "\`[[:space:]]*$t" <<< "$(view "$(printf 'echo "`date`" %s 5' "$t")")"; then FAIL=$((FAIL+1)); echo "FAIL [K10]: конец обратной кавычки в строке открыл позицию команды"
else PASS=$((PASS+1)); fi
body K11 "$(printf 'one\ntwo')" "$(printf 'x=`cat <<A\none\nA\ncat <<B\ntwo\nB\n`\necho after')"
# Четвёртый круг D1042 (скептик c3ff1c81). Состояние разбора видно только по телам heredoc и по виду оболочки, поэтому
# ноги судят тело. K12–K14 (M1): состояние вокруг первого прохода — журналом, вместе с `PS`/`PL`; K15 (L1): тело
# внешнего heredoc — после строки, где закрылась многострочная область; K16: экранированная обратная кавычка в области
# читателя; K17: `'…'` через строку после `$'…'` той же строки (`ansi` возвращается); K18: `$((` внутри области
# одной строки (`arith` возвращается при закрытии); K19: область, закрытая последним знаком строки, — не перенос.
keep K12 "$(printf '( ( true\n) ) ; x=$((\n1 << 2\n))\n%s 5 true' "$t")"
body K13 "BODYZ" "$(printf '( ( true\n)) ; ((cat <<EOF) && true)\nBODYZ\nEOF\necho after')"
body K14 "BODYZ" "$(printf 'x=$((\n1 << 2\n)) && ((cat <<EOF) && true)\nBODYZ\nEOF\necho after')"
body K15 "$(printf 'BODYZ\nBODYZ')" "$(printf 'cat <<EOF; x=`echo a\nb`\nBODYZ\nEOF\necho "it'"'"'s `date`"; cat <<E2\nBODYZ\nE2\necho after')"
keep K16 "$(printf 'x=`echo \\` it'"'"'s`; %s 5 true' "$t")"
body K17 "BODYZ" $'echo \'a\nb\\\'; echo $\'c\'; cat <<EOF\nBODYZ\nEOF\necho after'
body K18 "BODYZ" "$(printf 'x=`echo $((1`; cat <<EOF\nBODYZ\nEOF\necho after')"
body K19 "" "$(printf 'x=`cat <<EOF`\necho after')"
# K20 (регресс фазза четвёртого круга): внешняя метка стоит в строке раньше метки внутри многострочной области — тело
# внутренней bash читает сразу, внешней — после строки, где область закрылась (истина проверена исполнением bash).
body K20 "$(printf 'MARKZ\nBODY2')" "$(printf 'cat - << 2 `cat <<EOF\nMARKZ\nEOF\n`\nBODY2\n2\necho after')"
# K21, K22 (регресс фазза вида оболочки): метка с обратными кавычками — слово целиком вместе с их парой, и закрывающая
# кавычка области не открывает (истина — исполнением bash: тело `bodyz`, конец — строка-метка целиком).
body K21 "bodyz" "$(printf 'cat <<EOF`( `\nbodyz\nEOF`( `\necho after')"
body K22 "bodyz" "$(printf 'cat <<EOF`echo x`\nbodyz\nEOF`echo x`\necho after')"
# K23: слово метки кончается на пробеле после закрытой пары — мутант «пара без закрывающей кавычки» тянет метку дальше.
body K23 "bodyz" "$(printf 'cat <<EOF`true` `true`\nbodyz\nEOF`true`\necho after')"
# Пятый круг D1042 (скептик 2693e19c). Ожидаемое тело — тело, которое bash 3.2 отдал `H` при исполнении этой же
# команды (у `<<-` сырые строки — так судит и H6). K24–K28 (M1): метка в `"…"` с парой обратных кавычек — конец
# слова по вложенности, разделитель — снятие кавычек подряд (``x`(` ``); K25 — разделитель не совпал, тело до
# конца; K28 — прежний дефект всех редакций (разделитель совпал, строка ниже — код). K29–K36 (L2): формы, на
# которых журнал вокруг первого прохода различает мутантов скептика (s1–s8). K37 (L1): метка перед экранированной
# обратной кавычкой — мутант m4 «`\` в поиске конца у `scan`» различим.
body K24 $'bodyz' $'H <<"x`"(`"\nbodyz\nx`(`\necho after'
body K25 $'bodyz\nx`"(`\necho after' $'H <<"x`"(`"\nbodyz\nx`"(`\necho after'
body K26 $'bodyz\n\tEOF' $'H <<-EOF"`"$(`"\\\\\nbodyz\n\tEOF'
body K27 $'bodyz\nEOF\n$((' $'H <<\'EOF\'"`"$(`"\nbodyz\nEOF\n$(('
body K28 $'D1' $'H <<"x`"(`"\nD1\nx`(`\necho \'`\'\nbodyz'
body K29 $'bodyz' $'echo "$(echo a\n)" `echo b`; H <<EOF\nbodyz\nEOF\necho after'
body K30 $'bodyz' $'(echo "$(echo a\n)" ) ; echo "$(echo)" ; H <<EOF\nbodyz\nEOF\necho after'
body K31 $'bodyz' $'echo $(echo a\n)#z; (true); (true); H <<EOF\nbodyz\nEOF\necho after'
body K32 $'' $'x=$(echo a\n) ; (echo b\n)#z; H <<EOF\nbodyz\nEOF\necho after'
body K33 $'bodyz' $'((H <<EOF) && echo "$(echo))")\nbodyz\nEOF\necho after'
body K34 $'bodyz' $'x=$( (true\n)) ;((H <<EOF) && true)\nbodyz\nEOF\necho after'
body K35 $'bodyz' $'echo "$(echo a\n)" `echo b` `echo c`; H <<EOF\nbodyz\nEOF\necho after'
body K36 $'bodyz' $'(echo "$(echo a\n)" ) ; echo "$(echo b\n)" ; H <<EOF\nbodyz\nEOF\necho after'
body K37 $'bodyz' $'H <<EOF; x=`echo \\`echo q\\``\nbodyz\nEOF\necho after'
# K38, K39: незакрытые на конце строки `$(` или кавычка в метке — bash дочитывает слово ниже и падает синтаксисом,
# не исполнив ни строки; вид не называет кодом строки ниже (прежде разделитель совпадал, и `markz` была кодом).
body K38 $'bodyz\nx$(y\nmarkz' $'H <<"x$(y"\nbodyz\nx$(y\nmarkz'
body K39 $'bodyz\nabc\nmarkz' $'H <<"abc\nbodyz\nabc\nmarkz'
# K40–K47 — клетки мутантов читателя метки (истина у bash): экран в слове, скобка внутри `$(…)`, `\` в конце строки
# (bash склеивает строку метки со следующей: тело не кончается, строки ниже — не код), `\` перед обычным знаком и `'`
# внутри `"…"`, метка в кавычках — подстановки тела не код, без кавычек — код; метка в области, закрытой в той же строке.
body K40 $'bodyz' $'H <<EOF\\ x\nbodyz\nEOF x\necho after'
body K41 $'bodyz' $'H <<x$( (true) )y\nbodyz\nx$( (true) )y\necho after'
body K42 $'bodyz\nEOF\nmarkz' $'H <<EOF\\\nbodyz\nEOF\nmarkz'
body K43 $'bodyz' $'H <<"a\\b"\nbodyz\na\\b\necho after'
body K44 $'bodyz' $'H <<"a\'b"\nbodyz\na\'b\necho after'
drop K45 "$(printf 'cat <<"EOF"\nx $(%s 5 true)\nEOF\necho done' "$t")"
keep K46 "$(printf 'cat <<EOF\nx $(%s 5 true)\nEOF\necho done' "$t")"
keep K47 "$(printf 'y="`cat <<EOF`"; %s 5 true' "$t")"
# K48: строка-конец, буквально равная слову с `\` на конце, — тоже не конец (слово ушло на строку ниже).
body K48 $'bodyz\nEOF\\\nmarkz' $'H <<EOF\\\nbodyz\nEOF\\\nmarkz'
# Шестой круг D1042 (скептик e0fa47c0; истина — исполнением bash 3.2). K49 (L1): метка в области, закрытой той же
# строкой, кончается с областью — иначе слово съедает незакрытую `'` после области, и `H <<F` ниже не открывается.
# K50–K52 (M1): `<<` внутри `((` на первом проходе — сдвиг, а не метка; `)` в кавычках внутри `$(…)` пару `((`/`))` не
# съедает. K53–K57 (L2, L4): метку закавычивают `\`, `'…'` (и незакрытая), пара обратных кавычек — подстановки тела не
# код; кавычки внутри `$(…)` метку не закавычивают — код. K58: проход 1 закрыл арифметику строки выше и открыл новую —
# `AP` нижнего уровня возвращается журналом. K59: `)` в кавычках внутри `$(…)` метки слово не кончает.
body K49 $'z1' $'y=`echo <<E`\'a\nb\'; H <<F\nz1\nF\nz2'
keep K50 "$(printf "(( b = 1 << \$(grep -c ')' /dev/null) )); true\n%s 5 true" "$t")"
keep K51 "$(printf '(( x = 1 << $(echo ")") ))\n%s 5 true' "$t")"
keep K52 "$(printf "if (( n < 1 << \$(echo ')' | wc -c) )); then true; fi\n%s 5 true" "$t")"
drop K53 "$(printf 'cat <<\\EOF\nx $(%s 5 true)\nEOF\necho done' "$t")"
drop K54 "$(printf "cat <<'EOF'\nx \$(%s 5 true)\nEOF\necho done" "$t")"
drop K55 "$(printf "H <<'E\nx'\nx \$(%s 5 true)" "$t")"
drop K56 "$(printf 'H <<E`true`\nx $(%s 5 true)\nE`true`\necho done' "$t")"
keep K57 "$(printf "H <<E\$(echo 'a')\nx \$(%s 5 true)\nE\$(echo a)\necho done" "$t")"
keep K58 "$(printf 'x=$(( ( (\n1) ) << 2 )) ; ( ( (( 2 )) ) )\n%s 5 true' "$t")"
body K59 $'z1' $'H <<E$(echo ")")\nz1\nE$(echo ))\nz2'
# K60–K67 — клетки мутантов шестого круга. K60: `$'…'` после `<<` внутри `((` — читатель метки ANSI-кавычек не знает,
# и без арифметики на проходе 1 слово съедает пару `((`/`))`. K61, K62: `\` и обратные кавычки внутри `$(…)` метку не
# закавычивают. K63: флаг кавычек не переходит от прошлой метки. K64: `'…'` внутри `$(…)` закрывается. K65, K66: уровень
# `$(` и `(` метки начинается без кавычек (метка в области, закрытой той же строкой, оставляет кавычку открытой). K67:
# журнал `AP` у каждой строки свой.
keep K60 "$(printf "(( x = 1 << \$'\\\\'' )); true\n%s 5 true" "$t")"
keep K61 "$(printf 'H <<E$(echo \\a)\nx $(%s 5 true)\nE$(echo a)\necho done' "$t")"
keep K62 "$(printf 'H <<E$(echo `true`)\nx $(%s 5 true)\nE$(echo `true`)\necho done' "$t")"
keep K63 "$(printf "cat <<'A'\nq\nA\nH <<B\nx \$(%s 5 true)\nB\necho done" "$t")"
body K64 $'z1' $'H <<E$(echo \')\')\nz1\nE$(echo ))\nz2'
body K65 $'z1' $'y=`cat <<E$("\'`; H <<F$(x)\nz1\nF$(x)\nz2'
body K66 $'z1' $'y=`cat <<E$( ("\'`; H <<F$( (x) )\nz1\nF$( (x) )\nz2'
body K67 $'z1' $'x=$(( ( (\n1) ) << 2 )) ; ( ( (( 2 )) ) ) ; ( y=$(( ( ( (\n1) ) ) << 2 )) ; ( ( (( 2 )) ) )\nH <<EOF\nz1\nEOF\n)\nz2'
# Седьмой круг D1042 (скептик 23a9b42c; истина — исполнением bash 3.2). K68–K71 (M1, L5): `#` внутри арифметики
# комментария не открывает — bash исполняет строки ниже (арифметика падает при раскрытии). K72 (L1): `\` внутри `"…"`
# в `$(…)` метки метку не закавычивает. K73 (L2): незакрытая на конце строки `$(` глубины 1 — разделитель не совпадёт
# (договор вида; bash падает при раскрытии и не исполняет ничего).
keep K68 "$(printf '(( b = 1 << $(echo 2 #) ))\n%s 5 true' "$t")"
keep K69 "$(printf '((H <<$(echo #)))\n%s 5 true' "$t")"
keep K70 "$(printf '(( x = 1 <<$(echo 2 #) ))\n%s 5 true' "$t")"
keep K71 "$(printf '(( x = 1 << 2 #))\n%s 5 true' "$t")"
keep K72 "$(printf 'H <<E$(echo "\\a")\nx $(%s 5 true)\nE$(echo \\a)\necho done' "$t")"
body K73 $')\nz1\n$(x\nz2' $'H <<$(x\n)\nz1\n$(x\nz2'
# Восьмой круг D1042 (скептик cbe36804; истина — исполнением bash 3.2). K74–K76 (M1): внутри `$((` в коде комментарий
# судится — апостроф и скобка в нём не сдвигают строк ниже. K77, K78 (L1): голое `((` и `$((` в `"…"` закрываются, и
# тело heredoc ниже остаётся телом.
body K74 $'z3' $'out=$((cd /tmp\n  # don\'t fail here\n  z1) | wc -l)\nz2\nH <<EOF\nz3\nEOF\nz4'
keep K75 "$(printf "out=\$((cd /tmp\n  # don't fail here\n  true) | wc -l)\necho ')) <<EOF'\n%s 5 true" "$t")"
body K76 $'z2' $'y=$(( 1 +\n2 # don\'t\n))\nz1\nH <<E\nz2\nE\nz3'
body K77 $'z1' $'(( x = 1 #x ))\nH <<E\nz1\nE\nz2'
body K78 $'z2' $'x="$(( 1 # c ))"\nz1\nH <<E\nz2\nE\nz3'
# K79: внутри `$[…]` комментарий не судится. K80: внутри области обратных кавычек в `((` — судится (ложная пара `))`
# за `#` не встаёт). K81: вид арифметики уровня из строки выше возвращается журналом прохода 1.
body K79 $'z1' $'x=$[ 1 # c ]\nH <<E\nz1\nE\nz2'
body K80 $'z1' $'((echo `echo # ))`\necho b) # don\'t\n)\nH <<E\nz1\nE\nz2'
body K81 $'z1' $'x="$(( 1 +\n2 # c ))" ; y=$(( 3 ))\nH <<E\nz1\nE\nz2'
# Цена линейна, а не квадратична. Абсолютный потолок падал под нагрузкой набора (финальный скептик D1015: 768 КБ за
# 16 с при десяти соседях), поэтому судится ОТНОШЕНИЕ: вход в четыре раза больше обязан стоить меньше чем в девять раз
# дороже (линейный разбор — около 4, квадратичный — около 16). Потолок 120 с остаётся на катастрофу.
_now() { python3 -c 'import time; print("%.3f" % time.time())'; }
cost_ratio() {  # cost_ratio <нога> <программа awk, печатающая N повторов>
    local leg="$1" prog="$2" a b t0 t1 t2
    a=$(awk -v N=5000 "$prog"); b=$(awk -v N=20000 "$prog")
    t0=$(_now); view "$a" >/dev/null; t1=$(_now); view "$b" >/dev/null; t2=$(_now)
    if awk -v x="$t0" -v y="$t1" -v z="$t2" 'BEGIN { s = y - x; l = z - y; exit !(l < 120 && (s < 0.05 || l / s < 9)) }'; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$leg]: вход ×4 стоил $(awk -v x="$t0" -v y="$t1" -v z="$t2" 'BEGIN { printf "%.2f с против %.2f с", z - y, y - x }')"; fi
}
cost_ratio E1 'BEGIN { for (i = 0; i < N; i++) printf "echo \"line %d with some words\"; x=1\n", i }'
cost_ratio E2 'BEGIN { for (i = 0; i < N; i++) printf "echo \"word %d\"; ", i }'
# Поиск пары `((` на каждом `((` заново был квадратичен (скептик c4489c95: 8000 `(` — 9 с).
cost_ratio E3 'BEGIN { for (i = 0; i < N; i++) printf "(" }'
# Пары скобок — той же грамматикой, что у разбора: у прежнего поиска не было `$'…'`, и `(($'\''==1)); ` × 4000 стоило
# 24,8 с (скептик 3a4d7ddb, M-b).
cost_ratio E4 'BEGIN { for (i = 0; i < N; i++) printf "(($\047\\\047\047==1)); " }'
# Цена по оси «число строк × глубина»: состояние вокруг первого прохода копировалось на каждой строке (скептик c3ff1c81,
# M2: `(`⏎ × 4000 — 5,8 с).
cost_ratio E5 'BEGIN { for (i = 0; i < N; i++) print "(" }'
cost_ratio E6 'BEGIN { for (i = 0; i < N; i++) print "\"$(" }'
echo "test_ds_shell_views: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
