#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py
# test_project_graph.sh — свидетель карты связей: рёбра по РОЛИ, а не по виду текста.
# Предмет: имя, определённое в нескольких файлах, ребра не даёт; присваивание вызовом не
# считается; настоящий вызов ребро даёт (положительный контроль к обоим); `--scc` отличает
# дерево со спайкой от дерева без неё; ответ берётся из кэша, а устаревший кэш при запрете
# сборки отвечает кодом 3, а не минутной пересборкой; имя внутри строкового литерала ребра
# «использует» не даёт, а вызов в `"$(…)"` и программа после `-c` — дают (D428); строка с
# непарной кавычкой остаётся кодом, а названные пределы сканера закреплены ногами (T19–T25);
# перечень файлов у карты тот же, что у учёта, — новый файл до `git add` несёт рёбра, игнорируемый
# узлом не становится, не-ASCII путь приходит как есть, оба перечня равны множествами (T26–T30, D429); копия правила «код, а не проза» сверена с владельцем (T31).
# имя теста с двумя путями ребра «проверяет» не даёт (T32–T33), конфликтный файл стоит в перечне один раз (T34).
# `--touch` равен полной сборке на том же файле: рёбра зависимости, «проверяет» у теста и «описывает» у документа
# считаются заново правилом учёта, роль — у `dep_role`, исчезнувшая снимается, новый тест и новый документ видны у
# своего механизма сразу, нечитаемый файл рёбер не теряет, `DEP_ROLES` сверен с `dep_role` (T35–T38, D430).
# `--check` судит ЦЕЛОСТЬ снимка: висячее ребро (цель и исток) и повтор id — код 1 с названным нарушением,
# прочие режимы на такой карте — код 4, а не 0 и не `KeyError`; целая карта с одиноким узлом проходит, пустая
# по-прежнему нет, `--refresh` сломанный кэш лечит (T39–T44, D427); запись не по схеме (нет поля, которое читатели
# берут без `.get`) — тот же отказ со словом, а не `KeyError` с кодом-вердиктом (T45).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
TOOL="$REPO_ROOT/scripts/project-graph.py"
# Адрес библиотек владельца (`_find_lib` карты и учёта) называется ВСЕМ вызовам теста: песочницы копируют приборы без
# `hooks/lib`, и без названного адреса библиотека находилась только по установке хозяина машины — на раннере CI тест
# шёл по запасным правилам приборов, ноги T12b и T12c краснели (D1348). Адрес одному вызову из двух давал расхождение
# сборок в T35, поэтому он один на весь тест.
export CLAUDSOUL_ROOT="$REPO_ROOT"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

mkrepo() {  # mkrepo <каталог> — дерево-песочница с учётом
    local d="$1"; mkdir -p "$d/scripts" "$d/hooks" "$d/.claude-docs" "$d/mcp-server/visualization"
    ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t )
    cp "$TOOL" "$d/scripts/"
}
run() {  # run <репо> [флаги…]
    ( cd "$1" && shift; LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$PWD" python3 scripts/project-graph.py "$@" 2>&1 )
}
mkdir -p "$TMP/lessons"

# ── дерево A: одно имя у ДВУХ владельцев, третий файл его зовёт ────────────────
A="$TMP/a"; mkrepo "$A"
printf '#!/usr/bin/env bash\nhelper_common() { echo 1; }\n' > "$A/hooks/one.sh"
printf '#!/usr/bin/env bash\nhelper_common() { echo 2; }\n' > "$A/hooks/two.sh"
printf '#!/usr/bin/env bash\nhelper_common\n' > "$A/hooks/caller.sh"
# и рядом ЧЕСТНОЕ имя с одним владельцем — положительный контроль
printf '#!/usr/bin/env bash\nsolo_helper() { echo 3; }\n' > "$A/hooks/solo.sh"
printf '#!/usr/bin/env bash\nsolo_helper\n' >> "$A/hooks/caller.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/one.sh\ta\t\t\t\thelper_common\n'
  printf 'hooks/two.sh\tb\t\t\t\thelper_common\n'
  printf 'hooks/solo.sh\tc\t\t\t\tsolo_helper\n'
  printf 'hooks/caller.sh\td\t\t\t\t\n'; } > "$A/.claude-docs/dep-index.tsv"
( cd "$A" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )

OUT_A=$(run "$A" --node hooks/caller.sh)
if grep -qF "solo_helper" <<< "$OUT_A"; then ok
else bad T1 "имя с ОДНИМ владельцем не дало ребра — контроль пуст, T2 нечем проверять"; fi
if grep -qF "helper_common" <<< "$OUT_A"; then
  bad T2 "имя с двумя владельцами дало ребро: $(grep -o 'helper_common' <<< "$OUT_A" | head -1)"
else ok; fi
if grep -qF "имён без владельца" <<< "$(run "$A" --check)"; then ok
else bad T3 "отброшенные имена не названы числом — молчаливая потеря"; fi

# ── дерево B: присваивание против вызова ──────────────────────────────────────
B="$TMP/b"; mkrepo "$B"
printf '#!/usr/bin/env bash\nfetch_stats() { echo s; }\n' > "$B/hooks/lib.sh"
printf '#!/usr/bin/env bash\nfetch_stats=$(echo 1)\n' > "$B/hooks/assign.sh"
printf '#!/usr/bin/env bash\nfetch_stats\n'          > "$B/hooks/call.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\tfetch_stats\n'
  printf 'hooks/assign.sh\tb\t\t\t\t\n'
  printf 'hooks/call.sh\tc\t\t\t\t\n'; } > "$B/.claude-docs/dep-index.tsv"
( cd "$B" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )

if grep -qF "fetch_stats" <<< "$(run "$B" --node hooks/call.sh)"; then ok
else bad T4 "настоящий вызов ребра не дал — контроль к T5 пуст"; fi
if grep -qF "fetch_stats" <<< "$(run "$B" --node hooks/assign.sh)"; then
  bad T5 "присваивание засчитано вызовом"
else ok; fi

# ── дерево C: спайка есть и спайки нет ────────────────────────────────────────
C="$TMP/c"; mkrepo "$C"
printf '#!/usr/bin/env bash\nbash hooks/y.sh\n' > "$C/hooks/x.sh"
printf '#!/usr/bin/env bash\nbash hooks/x.sh\n' > "$C/hooks/y.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/x.sh\ta\thooks/y.sh\t\t\t\n'
  printf 'hooks/y.sh\tb\thooks/x.sh\t\t\t\n'; } > "$C/.claude-docs/dep-index.tsv"
( cd "$C" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
run "$C" --scc >/dev/null 2>&1; RC_C=$?
[ "$RC_C" = "1" ] && ok || bad T6 "взаимная пара не признана спайкой (код $RC_C)"

D="$TMP/d"; mkrepo "$D"
printf '#!/usr/bin/env bash\necho one\n' > "$D/hooks/z.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/z.sh\ta\t\t\t\t\n'; } > "$D/.claude-docs/dep-index.tsv"
( cd "$D" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
OUT_D=$(run "$D" --scc); RC_D=$?
if [ "$RC_D" = "0" ] && grep -qF "спаек (кусков, где всё достижимо из всего): 0" <<< "$OUT_D"; then ok
else bad T7 "дерево без взаимных ссылок не даёт «спаек: 0» (код $RC_D)"; fi

# ── кэш: запрет сборки при устаревшем кэше отвечает кодом 3 ───────────────────
touch -t 200001010000 "$A/mcp-server/visualization/project-graph-data.json" 2>/dev/null
( cd "$A" && PROJECT_GRAPH_NO_BUILD=1 LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$A" \
    python3 scripts/project-graph.py --node hooks/caller.sh >/dev/null 2>&1 ); RC_S=$?
[ "$RC_S" = "3" ] && ok || bad T8 "устаревший кэш при запрете сборки дал код $RC_S вместо 3"

# ── T9-T12: РОЛЬ РЕБРА ЗАВИСИМОСТИ. Учёт знает ЧТО от чего зависит и не знает КАК;
# карте различие нужно, потому что рекурсию даёт только ИСПОЛНЕНИЕ. Замер 14 сентября 2026
# (D406): спайка по сырым «вызовам» — 45 узлов, после разведения четырёх ролей — НОЛЬ.
R="$TMP/roles"; mkrepo "$R"
printf '#!/usr/bin/env bash\necho lib\n' > "$R/hooks/lib.sh"
printf '#!/usr/bin/env bash\nsource hooks/lib.sh\n'                        > "$R/hooks/calls.sh"
printf '#!/usr/bin/env bash\ngrep -c . hooks/lib.sh\n'                     > "$R/hooks/reads.sh"
printf '#!/usr/bin/env bash\nprintf "запусти hooks/lib.sh руками\\n"\n'   > "$R/hooks/says.sh"
printf '#!/usr/bin/env bash\nMSG="смотри hooks/lib.sh за подробностями"\necho "$MSG"\n' > "$R/hooks/const.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\t\n'
  printf 'hooks/calls.sh\tb\thooks/lib.sh\t\t\t\n'
  printf 'hooks/reads.sh\tc\thooks/lib.sh\t\t\t\n'
  printf 'hooks/says.sh\td\thooks/lib.sh\t\t\t\n'
  printf 'hooks/const.sh\te\thooks/lib.sh\t\t\t\n'
  printf 'hooks/infn.sh\tf\thooks/lib.sh\t\t\t\n'
  printf 'hooks/ifnot.sh\tg\thooks/lib.sh\t\t\t\n'; } > "$R/.claude-docs/dep-index.tsv"
# T12b, T12c (D1340): позицию команды называет разбор владельца (`calls`, hooks/lib/write_targets.py), а не перечень
# начал строки — запуск в теле функции с трубой в awk и запуск под `if !` с путём из подстановки читались «читает».
cat > "$R/hooks/infn.sh" <<'SH'
#!/usr/bin/env bash
stat_key() { bash "$REPO/hooks/lib.sh" 2>/dev/null | awk -F= -v k="$1" '$1==k {print $2}'; }
SH
cat > "$R/hooks/ifnot.sh" <<'SH'
#!/usr/bin/env bash
if ! bash "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib.sh" unclassified "$1"; then exit 1; fi
SH
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
# Роль берётся БЕЗ диапазона букв: GNU grep отвергает `[а-яё]` в локали C.UTF-8
# («Invalid collation character»), и на раннере CI эта нога молча теряла вывод — четыре
# ноги краснели с пустым сообщением (прогон 34872897131, 14 сентября 2026). Класс назван
# в pattern-shell-portability; отрицание `[^-]` диапазона не содержит и переносимо.
role() { run "$R" --node "$1" 2>/dev/null | grep -oE -- '--[^-]+-->' | head -1 | tr -d '>-'; }
[ "$(role hooks/calls.sh)" = "зовёт" ] && ok || bad T9  "source не признан вызовом: $(role hooks/calls.sh)"
[ "$(role hooks/reads.sh)" = "читает" ] && ok || bad T10 "чтение файла признано вызовом: $(role hooks/reads.sh)"
[ "$(role hooks/says.sh)"  = "называет" ] && ok || bad T11 "имя в сообщении признано вызовом: $(role hooks/says.sh)"
[ "$(role hooks/const.sh)" = "называет" ] && ok || bad T12 "имя в строковой константе признано вызовом: $(role hooks/const.sh)"
[ "$(role hooks/infn.sh)"  = "зовёт" ] && ok || bad T12b "запуск в теле функции с трубой в awk не признан вызовом: $(role hooks/infn.sh)"
[ "$(role hooks/ifnot.sh)" = "зовёт" ] && ok || bad T12c "запуск под if-not с путём из подстановки не признан вызовом: $(role hooks/ifnot.sh)"
# T12d (D1340): вид стража `--touch` называет тем же правилом, что сборка, — новый хук с каналом инжекта не числится
# простым хуком до пересборки.
GK="$TMP/gkind"; mkrepo "$GK"
printf '#!/usr/bin/env bash\nbase_helper() { echo 1; }\n' > "$GK/hooks/base.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'; printf 'hooks/base.sh\ta\t\t\t\tbase_helper\n'; } > "$GK/.claude-docs/dep-index.tsv"
( cd "$GK" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
run "$GK" --refresh >/dev/null 2>&1
cat > "$GK/hooks/newguard.sh" <<'SH'
#!/usr/bin/env bash
jq -cn --arg m x '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
SH
run "$GK" --touch hooks/newguard.sh >/dev/null 2>&1
gkind() { python3 -c 'import json, sys
g = json.load(open(sys.argv[1]))
print(next((n.get("type", "?") + "/" + str(n.get("channel", "")) for n in g["nodes"] if n.get("key") == "hooks/newguard.sh"), "нет"))' "$GK/mcp-server/visualization/project-graph-data.json"; }
GK_TOUCH=$(gkind); run "$GK" --refresh >/dev/null 2>&1; GK_BUILD=$(gkind)
{ [ "$GK_BUILD" = "guard/инжект" ] && [ "$GK_TOUCH" = "$GK_BUILD" ]; } && ok \
    || bad T12d "после touch: ${GK_TOUCH}; после сборки на том же файле: ${GK_BUILD} (ожидался guard/инжект у обоих)"
# T12e (скептик D1340, M1): живой зовущий делает `--touch` ДО записи файла — узел встаёт видом hook, и после записи
# читатель карты обязан назвать его стражем без пересборки. Порядок взят у `hooks/impact-inject.sh`, а не у сборки.
run "$GK" --touch hooks/prewrite.sh >/dev/null 2>&1
cat > "$GK/hooks/prewrite.sh" <<'SH'
#!/usr/bin/env bash
jq -cn '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}}'
SH
GK_PRE=$(run "$GK" --node hooks/prewrite.sh 2>/dev/null | head -1)
case "$GK_PRE" in *'(guard)'*) ok ;; *) bad T12e "узел, внесённый до записи файла, после записи назван не стражем: ${GK_PRE}" ;; esac
# T12g (D1345): тот же порядок — `--touch` ДО записи, — и после записи читатель карты называет исходящие связи файла
# без повторного касания и без пересборки: «сам стоит на 0» значило и «связей нет», и «связи ещё не считались».
# Контроль T12h: файл, внесённый после записи и ни на кого не опирающийся, остаётся без исходящих связей.
run "$GK" --touch hooks/prelink.sh >/dev/null 2>&1
printf '#!/usr/bin/env bash\nsource hooks/base.sh\n' > "$GK/hooks/prelink.sh"
GK_OUT=$(run "$GK" --node hooks/prelink.sh 2>/dev/null | grep -c -- '--> hooks/base.sh')
[ "${GK_OUT:-0}" -ge 1 ] && ok || bad T12g "узел, внесённый до записи, после записи без исходящей связи к hooks/base.sh"
printf '#!/usr/bin/env bash\necho one\n' > "$GK/hooks/alone.sh"
run "$GK" --touch hooks/alone.sh >/dev/null 2>&1
GK_ALONE=$(run "$GK" --node hooks/alone.sh 2>/dev/null | grep -c -- '--> hooks/')
[ "${GK_ALONE:-0}" -eq 0 ] && ok || bad T12h "рамка не различает: у файла без зависимостей названы исходящие связи (${GK_ALONE})"
# T12i (скептик D1345, M1): строка касания ДО записи — её страж правки показывает создающей сессии — не говорит
# «записано 0»; после записи то же касание называет счёт.
GK_SAY=$(run "$GK" --touch hooks/presay.sh 2>/dev/null)
case "$GK_SAY" in *'файла ещё нет'*) ok ;; *) bad T12i "касание до записи: ${GK_SAY}" ;; esac
printf '#!/usr/bin/env bash\nsource hooks/base.sh\n' > "$GK/hooks/presay.sh"
case "$(run "$GK" --touch hooks/presay.sh 2>/dev/null)" in *'исходящих рёбер записано 1'*) ok ;; *) bad T12i-ctrl "касание после записи счёта не назвало" ;; esac
# T12j (L2, L4): первое чтение после записи файла пишет досчитанное в кэш — пометки на диске нет, ребро есть.
gdisk() { python3 -c 'import json, sys
g = json.load(open(sys.argv[1])); k = sys.argv[2]
n = next(x for x in g["nodes"] if x.get("key") == k)
print(("помечен" if n.get("unread") else "чист") + "/" + str(sum(1 for e in g["edges"] if e.get("source") == n["id"])))' "$GK/mcp-server/visualization/project-graph-data.json" "$1"; }
run "$GK" --touch hooks/predisk.sh >/dev/null 2>&1
printf '#!/usr/bin/env bash\nsource hooks/base.sh\n' > "$GK/hooks/predisk.sh"
GK_D0=$(gdisk hooks/predisk.sh); run "$GK" --node hooks/base.sh >/dev/null 2>&1; GK_D1=$(gdisk hooks/predisk.sh)
{ [ "$GK_D0" = "помечен/0" ] && [ "$GK_D1" = "чист/1" ]; } && ok || bad T12j "кэш на диске до чтения: ${GK_D0}, после: ${GK_D1} (ожидались помечен/0 и чист/1)"
# T12k (L1): снимок не по схеме при помеченном узле называется отказом целости, а не трассой досчёта.
run "$GK" --touch hooks/prebroken.sh >/dev/null 2>&1
printf '#!/usr/bin/env bash\nsource hooks/base.sh\n' > "$GK/hooks/prebroken.sh"
python3 -c 'import json, sys
p = sys.argv[1]; g = json.load(open(p)); g["edges"].append({"target": 1, "type": "зовёт"}); json.dump(g, open(p, "w"), ensure_ascii=False)' "$GK/mcp-server/visualization/project-graph-data.json"
GK_BR=$(run "$GK" --scc 2>&1); GK_RC=$?
case "$GK_RC:$GK_BR" in *Traceback*) bad T12k "ломаный снимок с помеченным узлом упал трассой (код ${GK_RC})" ;; 4:*) ok ;; *) bad T12k "ломаный снимок: код ${GK_RC}, ждали названный отказ целости (4): ${GK_BR:0:160}" ;; esac
run "$GK" --refresh >/dev/null 2>&1
# T12f (скептик D1340, H1): ленивый импорт рядом со строкой, НАЗЫВАЮЩЕЙ тот же файл, — «подгружает», а не «зовёт».
mkdir -p "$R/pkg"
printf 'def helper():\n    return 1\n' > "$R/pkg/lazylib.py"
printf 'import os\n\ndef use():\n    d = os.path.join("pkg", "lazylib.py")\n    import lazylib\n    return lazylib.helper(), d\n' > "$R/pkg/lazyuser.py"
{ printf 'pkg/lazylib.py\th\t\t\t\thelper\n'; printf 'pkg/lazyuser.py\ti\tpkg/lazylib.py\t\t\tuse\n'; } >> "$R/.claude-docs/dep-index.tsv"
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm lazy >/dev/null 2>&1 )
run "$R" --refresh >/dev/null 2>&1
[ "$(role pkg/lazyuser.py)" = "подгружает" ] && ok || bad T12f "ленивый импорт рядом с упоминанием имени файла: $(role pkg/lazyuser.py)"

# ── T13-T18: СТРОКА — НЕ ВЫЗОВ (17 сентября 2026, D428). Имя внутри строкового литерала НАЗВАНО,
# а не вызвано: `print("fn(")`, `echo "fn("` и образец `grep 'fn('` давали ребро в файл определения.
# Отрицательные ноги (T13, T16) красны на механизме без снятия литералов. Положительные взяты не
# наугад, а по замеру на копии живого дерева — это формы, на которых валились ранние редакции
# починки: `"$(fn "$arg")"` (снятие кавычек регуляркой теряло 28 настоящих вызовов) и программа
# после `-c` (15 рёбер, из них 4 — через перенос `-c \` и склейку литералов). Без них ноги
# «ребра нет» проходили бы и на сканере, снимающем всё подряд.
S="$TMP/strings"; mkrepo "$S"; mkdir -p "$S/pkg"
printf '#!/usr/bin/env bash\nliteral_probe_fn() { echo s; }\n' > "$S/hooks/lib.sh"
cat > "$S/hooks/say.sh" <<'EOF'
#!/usr/bin/env bash
echo "literal_probe_fn("
grep -q 'literal_probe_fn(' x
EOF
cat > "$S/hooks/nested.sh" <<'EOF'
#!/usr/bin/env bash
x="$(literal_probe_fn "$1")"
EOF
cat > "$S/hooks/prog.sh" <<'EOF'
#!/usr/bin/env bash
bash -c \
  '. hooks/lib.sh; literal_probe_fn'
EOF
printf 'print("literal_probe_fn(")\n'                     > "$S/pkg/printer.py"
printf 'from x import literal_probe_fn\nliteral_probe_fn()\n' > "$S/pkg/caller.py"
printf 'import subprocess\nsubprocess.run(["bash", "-c", ". hooks/lib.sh; literal_probe_fn"])\n' > "$S/pkg/prog.py"
# ── T19-T22: НАХОДКИ СКЕПТИКА (17 сентября 2026, D428). Первая редакция сканера при непарной
# кавычке выбрасывала ХВОСТ строки — вызов после закрытия многострочного литерала терялся, то
# есть ошибка шла в сторону МЕНЬШЕЙ связности, против объявленного правила. Слово-программу она
# знала одно (голый `-c`), а строка с тысячей незакрытых `(` роняла сборку ВСЕЙ карты. Все четыре
# ноги красны на той редакции и зелёны на механизме до D428 — формы взяты из воспроизведения.
cat > "$S/hooks/tail_sq.sh" <<'EOF'
#!/usr/bin/env bash
out=$(awk '
{print}
' "$f" | literal_probe_fn)
EOF
cat > "$S/hooks/tail_dq.sh" <<'EOF'
#!/usr/bin/env bash
P="{
 \"a\": 1
}"; literal_probe_fn "$P"
EOF
cat > "$S/hooks/prog_lc.sh" <<'EOF'
#!/usr/bin/env bash
bash -lc '. hooks/lib.sh; literal_probe_fn x'
EOF
cat > "$S/hooks/prog_eval.sh" <<'EOF'
#!/usr/bin/env bash
eval ". hooks/lib.sh; literal_probe_fn x"
EOF
cat > "$S/hooks/prog_trap.sh" <<'EOF'
#!/usr/bin/env bash
trap 'rm -f "$T"; literal_probe_fn x' EXIT
EOF
{ printf '#!/usr/bin/env bash\nx='; printf '(%.0s' $(seq 1 1200); printf '\nliteral_probe_fn x\n'; } > "$S/hooks/deep.sh"
# ── T23-T25: НАЗВАННЫЕ ПРЕДЕЛЫ ЗАКРЕПЛЕНЫ. Ребро здесь — НЕ достоинство, а объявленный предел
# (докстринг `blank_strings`): образец после `grep -c` и тело heredoc остаются кодом, .py, который
# tokenize не разобрал, возвращается как есть. Нога краснеет, когда предел СНЯТ либо сломан, —
# тогда правятся докстринг и эта нога вместе, а не молча одно из двух.
printf '#!/usr/bin/env bash\ngrep -c "literal_probe_fn(" x\n'      > "$S/hooks/limit_grep_c.sh"
printf '#!/usr/bin/env bash\ncat <<TXT\nliteral_probe_fn(\nTXT\n'   > "$S/hooks/limit_heredoc.sh"
printf 'print("literal_probe_fn(")\nx = (\n'                        > "$S/pkg/limit_broken.py"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\tliteral_probe_fn\n'
  for f in hooks/say.sh hooks/nested.sh hooks/prog.sh pkg/printer.py pkg/caller.py pkg/prog.py \
           hooks/tail_sq.sh hooks/tail_dq.sh hooks/prog_lc.sh hooks/prog_eval.sh hooks/prog_trap.sh \
           hooks/deep.sh hooks/limit_grep_c.sh hooks/limit_heredoc.sh pkg/limit_broken.py; do
      printf '%s\tb\t\t\t\t\n' "$f"; done; } > "$S/.claude-docs/dep-index.tsv"
( cd "$S" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
uses() { grep -qF "использует literal_probe_fn" <<< "$(run "$S" --node "$1")"; }
if uses hooks/say.sh;    then bad T13 "имя в кавычках эха и в образце grep засчитано вызовом"; else ok; fi
uses hooks/nested.sh  && ok || bad T14 "вызов в \"\$(fn \"\$1\")\" ребра не дал — подстановка внутри кавычек снята как текст"
uses hooks/prog.sh    && ok || bad T15 "программа после «-c \\» с переносом ребра не дала — снята как текст"
if uses pkg/printer.py;  then bad T16 "имя в строке .py засчитано вызовом"; else ok; fi
uses pkg/caller.py    && ok || bad T17 "настоящий вызов в .py ребра не дал — контроль к T16 пуст"
uses pkg/prog.py      && ok || bad T18 "программа в subprocess.run([\"bash\", \"-c\", …]) ребра не дала"
uses hooks/tail_sq.sh && ok || bad T19 "вызов после закрытия многострочного '…' потерян — непарная кавычка съела хвост строки"
uses hooks/tail_dq.sh && ok || bad T20 "вызов после закрытия многострочного \"…\" потерян — непарная кавычка съела хвост строки"
LOST=""; for f in prog_lc prog_eval prog_trap; do uses "hooks/$f.sh" || LOST="$LOST $f"; done
[ -z "$LOST" ] && ok || bad T21 "программа после слова-программы (-lc / eval / trap) ребра не дала:$LOST"
uses hooks/deep.sh    && ok || bad T22 "строка с 1200 незакрытых «(» уронила сборку либо съела вызов ниже: $(run "$S" --node hooks/deep.sh | tail -1)"
uses hooks/limit_grep_c.sh  && ok || bad T23 "ПРЕДЕЛ изменился: образец после «grep -c» больше не код — поправь докстринг blank_strings и эту ногу вместе"
uses hooks/limit_heredoc.sh && ok || bad T24 "ПРЕДЕЛ изменился: тело heredoc больше не код — поправь докстринг blank_strings и эту ногу вместе"
uses pkg/limit_broken.py    && ok || bad T25 "ПРЕДЕЛ изменился: .py, который tokenize не разобрал, больше не возвращается как есть"

# ── T26-T30: ОДИН УНИВЕРСУМ НА ОБА КОНЦА СВЯЗИ (17 сентября 2026, D429). Карта читает строки учёта
# И сама обходит дерево; перечень у неё был свой (`git ls-files`: только индекс и без `-z`), у учёта
# свой (`--cached --others --exclude-standard -z`), и концы расходились молча — файл до `git add`
# у учёта был, у карты нет. T26 и T28 красны на механизме до правки; T27 — контроль, что перечень
# не расширен ДО игнорируемого (кэш карты стал бы собственным узлом) и до каталога вложенного
# репозитория (`--others` отдаёт его записью `nested/` с пустым именем). Не-ASCII файл ЗАКОММИЧЕН
# нарочно: так `-z` отделён от `--others`, и та же нога судит историю (T29: путь из `git log`
# приходил в кавычках, и `edits30` терялся). T30 — адрес отказа у самого корня: правило перечня
# ПОВТОРЕНО в карте литералом, поэтому оба перечня снимаются с одного дерева и сравниваются
# множествами; разойдутся литералы — нога назовёт разность поимённо.
U="$TMP/universe"; mkrepo "$U"; cp "$REPO_ROOT/scripts/dep-index.py" "$U/scripts/"
printf '#!/usr/bin/env bash\nuniverse_probe_fn() { echo u; }\n' > "$U/hooks/lib.sh"
printf '#!/usr/bin/env bash\nuniverse_probe_fn x\n' > "$U/hooks/проба.sh"
printf 'mcp-server/visualization/project-graph-data.json\nhooks/ignored.sh\n' > "$U/.gitignore"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\tuniverse_probe_fn\n'; } > "$U/.claude-docs/dep-index.tsv"
# Ссылка на каталог — запись дерева, не файл (D1185): правило повторено в обоих перечнях, поэтому ниже сравнение по
# `lexists`, а не `isfile` — фильтр самой ноги снимал запись-каталог с обеих сторон, и мутант без правила в карте
# проходил (скептик D1185, M1).
ln -s hooks "$U/hl"
( cd "$U" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\nuniverse_probe_fn x\n' > "$U/hooks/new.sh"       # новый: не добавлен, не игнорируется
printf '#!/usr/bin/env bash\nuniverse_probe_fn x\n' > "$U/hooks/ignored.sh"   # игнорируется
( mkdir -p "$U/nested" && cd "$U/nested" && git init -q . ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_graph.sh:$LINENO" >&2; exit 1; }
uses_u() { grep -qF "использует universe_probe_fn" <<< "$(run "$U" --node "$1")"; }
uses_u hooks/new.sh && ok || bad T26 "новый файл до «git add» без ребра «использует»: $(run "$U" --node hooks/new.sh | head -1)"
if grep -qF "в карте нет" <<< "$(run "$U" --node hooks/ignored.sh)" \
   && grep -qF "в карте нет" <<< "$(run "$U" --node nested/)"; then ok
else bad T27 "игнорируемый файл либо каталог вложенного репозитория стал узлом карты"; fi
uses_u "hooks/проба.sh" && ok || bad T28 "не-ASCII путь не дал узла с ребром — перечень без «-z»: $(run "$U" --node 'hooks/проба.sh' | head -1)"
# PYTHONDONTWRITEBYTECODE: импорт учёта иначе кладёт `scripts/__pycache__/…pyc` ПОСЛЕ снимка карты,
# и перечни расходятся на артефакте самого замера, а не на правиле.
UNI=$(cd "$U" && CLAUDSOUL_REPO="$U" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import importlib.util, json, os
spec = importlib.util.spec_from_file_location('dep_index', 'scripts/dep-index.py')
dep = importlib.util.module_from_spec(spec); spec.loader.exec_module(dep)
own = {p for p in dep.tracked('*') if os.path.lexists(p)}
g = json.load(open('mcp-server/visualization/project-graph-data.json'))
got = {n['key'] for n in g['nodes'] if os.path.lexists(n['key'])}
hist = next((n.get('edits30') for n in g['nodes'] if n['key'] == 'hooks/проба.sh'), None)
print('hist=%s' % hist)
print('equal n=%d' % len(own) if own == got
      else 'учёт−карта: %s; карта−учёт: %s' % (sorted(own - got), sorted(got - own)))
PY
)
grep -qx 'hist=1' <<< "$UNI" && ok || bad T29 "история не-ASCII файла потеряна — путь из «git log» пришёл в кавычках: $(grep '^hist=' <<< "$UNI")"
# Равенство двух ПУСТОТ ничего не значит, поэтому рядом с вердиктом печатается размер множества
# и нога требует его ненулевым.
if grep -qE '^equal n=[1-9]' <<< "$UNI"; then ok
else bad T30 "перечень карты разошёлся с перечнем учёта на одном дереве — $(tail -1 <<< "$UNI")"; fi

# ── T31: ВТОРАЯ КОПИЯ ПРАВИЛА УЧЁТА В КАРТЕ — `code_lines` против владельца `code_only` (брат D429,
# 17 сентября 2026). Докстринг `code_lines` с 13 сентября обещал «расхождение поймает нога теста
# карты», а ноги не было: объявление без сверки. Замер на живом дереве в день заведения — 845
# файлов .sh/.py, расхождений 0; здесь те же две функции гоняются по всем файлам песочниц этого
# теста (комментарии, докстринги, heredoc, непарные кавычки) и сравниваются выходом.
CMP=$(cd "$U" && CLAUDSOUL_REPO="$U" LESSONS_DIR="$TMP/lessons" PYTHONDONTWRITEBYTECODE=1 python3 - "$TMP" <<'PY'
import glob, importlib.util, os, sys
def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), 'scripts/%s.py' % name)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
pg, di = load('project-graph'), load('dep-index')
files = [f for f in glob.glob(os.path.join(sys.argv[1], '*', '**', '*'), recursive=True)
         if f.endswith(('.sh', '.py')) and os.path.isfile(f)]
bad = [f for f in files
       if pg.code_lines(open(f, errors='replace').read(), f.endswith('.py'))
       != di.code_only(open(f, errors='replace').read(), f.endswith('.py'))]
print('same n=%d' % len(files) if not bad else 'расходятся: %s' % sorted(bad)[:5])
PY
)
if grep -qE '^same n=[1-9]' <<< "$CMP"; then ok
else bad T31 "code_lines карты разошлась с code_only учёта — ${CMP:-сверка не отработала}"; fi

# ── T32-T33: ИМЯ ТЕСТА С ДВУМЯ ПУТЯМИ РЕБРА «ПРОВЕРЯЕТ» НЕ ДАЁТ (17 сентября 2026, D429, находка
# скептика). Шаг 3б держал словарь «имя теста → путь»; пока перечень был индексом git, имена не
# повторялись, а с неотслеживаемыми в перечне черновая копия под любым `…/tests/…` забирала ребро
# настоящего теста себе. T32 — положительный контроль (имя одно — ребро есть), без него T33 зелена
# и на карте, не умеющей рёбер «тест → тест» вовсе. T33 красна на редакции со словарём `{имя: путь}`.
# `--refresh` обязателен: свежесть кэша решает mtime учёта, новый файл его не двигает.
DUP="$TMP/dupname"; mkrepo "$DUP"; mkdir -p "$DUP/hooks/tests" "$DUP/zz/tests"
printf '#!/usr/bin/env bash\necho a\n' > "$DUP/hooks/tests/test_a.sh"
printf '#!/usr/bin/env bash\nbash hooks/tests/test_a.sh\n' > "$DUP/hooks/tests/test_b.sh"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > "$DUP/.claude-docs/dep-index.tsv"
( cd "$DUP" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
if grep -qF "test_b.sh --проверяет" <<< "$(run "$DUP" --refresh --node hooks/tests/test_a.sh)"; then ok
else bad T32 "тест с единственным именем не получил ребра «проверяет» — контроль пуст, T33 нечем проверять"; fi
cp "$DUP/hooks/tests/test_a.sh" "$DUP/zz/tests/test_a.sh"   # неотслеживаемая копия с тем же именем
if grep -qF "test_b.sh --проверяет" <<< "$(run "$DUP" --refresh --node zz/tests/test_a.sh)"; then
  bad T33 "ребро «проверяет» ушло на неотслеживаемую копию теста — имя с двумя путями получило владельца"
else ok; fi

# ── T34: КОНФЛИКТНЫЙ ФАЙЛ СТОИТ В ПЕРЕЧНЕ ОДИН РАЗ (D429, находка скептика: ветку `set` в
# `tracked_files()` не держала ни одна нога, мутант без неё проходил 31 из 31). При неразрешённом
# слиянии индекс называет путь по разу на стадию; замер 17 сентября 2026: без `set` у такого файла
# 3 одинаковых ребра «использует» вместо 1.
MRG="$TMP/merge"; mkrepo "$MRG"
printf '#!/usr/bin/env bash\nmerge_probe_fn() { echo m; }\n' > "$MRG/hooks/lib.sh"
printf '#!/usr/bin/env bash\nmerge_probe_fn x\necho base\n' > "$MRG/hooks/caller.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\tmerge_probe_fn\n'; } > "$MRG/.claude-docs/dep-index.tsv"
( cd "$MRG" && git add -A && git commit -qm i && B0=$(git symbolic-ref --short HEAD) \
  && git checkout -qb side && printf '#!/usr/bin/env bash\nmerge_probe_fn x\necho side\n' > hooks/caller.sh && git commit -qam s \
  && git checkout -q "$B0" && printf '#!/usr/bin/env bash\nmerge_probe_fn x\necho main\n' > hooks/caller.sh && git commit -qam m
  git merge side ) >/dev/null 2>&1 || true  # конфликт слияния и есть предмет ноги: стадии индекса читает строка ниже (D1219)
STAGES=$(cd "$MRG" && git ls-files -- hooks/caller.sh | wc -l | tr -d ' ')
N_EDGE=$(run "$MRG" --refresh --node hooks/caller.sh | grep -cF "использует merge_probe_fn")
# Рамка названа отдельно от вердикта: не сложился конфликт — нога не о механизме.
if [ "$STAGES" -lt 2 ]; then bad T34 "рамка: конфликт слияния не сложился (стадий $STAGES) — ноге нечего судить"
elif [ "$N_EDGE" -eq 1 ]; then ok
else bad T34 "конфликтный файл дал рёбер «использует»: $N_EDGE вместо 1 — путь стоит в перечне по разу на стадию"; fi

# ── T35-T38: ИНКРЕМЕНТ РАВЕН ПОЛНОЙ СБОРКЕ НА ТОМ ЖЕ ФАЙЛЕ (17 сентября 2026, D430). `--touch` держал
# своё правило ребра — «имя любого узла с `/` стоит в теле подстрокой» даёт «зовёт» — и только
# дописывал; сборка берёт цели у учёта (`deps_of`), а роль у `dep_role`. Сверки «инкремент = сборка»
# не было ни в приборе, ни в тесте (аудит, находка G-02), и расхождение жило молча: на копии живого
# дерева из 1100 файлов .sh/.py/.md совпадали 227. Дерево ниже несёт по файлу на каждый класс
# расхождения: четыре роли `dep_role`, цель в КОРНЕ дерева (прежний фильтр `/` её терял), имя-подстроку
# (`mylib.sh` при механизме `lib.sh`), тест и документ (у сборки там «проверяет» и «описывает», а
# прежний `touch` писал «зовёт»), и рядом ребро ИНОГО класса — «использует», которое сниматься не вправе.
# У КАЖДОЙ КЛАУЗЫ ПРАВИЛА УЧЁТА — СВОЙ ФАЙЛ-СВИДЕТЕЛЬ (находка скептика того же дня): без них нога
# не замечала трёх мутантов `body_deps` — тело без `code_lines` (на копии живого дерева это 176
# механизмов из 256 и 568 лишних рёбер), снятый развод одноимённых путём, голое неоднозначное имя всем
# кандидатам; в живом дереве одноимённых 0, так что последние два ловит ТОЛЬКО песочница. Отсюда
# `cmt.sh` (имя лишь в комментарии), пара `hooks/dup.sh` и `scripts/dup.sh` с `bypath.sh` и `bare.sh`.
# То же для `body_mentions`: имя в комментарии теста, составное имя голым и односложное голым в
# документе, одноимённый путём, хроника (`CHANGELOG.md`), снимок по пометке, архив по имени, «тест → тест».
# T35 — сверка ПОВЕДЕНИЕМ, и она же держит литеральную копию правила учёта в `body_deps`: учёт собран
# владельцем, карта — полной сборкой, затем КАЖДЫЙ файл проходит `--touch`, и рёбра всей карты обязаны
# остаться теми же. T35 красна на механизме до правки; T36 — исчезнувшая зависимость (E8), T37 — новый
# файл вне учёта получает ту же роль, что даст сборка после пересчёта учёта (E9), T38 — файл не
# прочитан: рёбра остаются, причина названа.
# Физический путь: на macOS mktemp даёт /var/…, а это ссылка на /private/var — `touch` считает путь файла от cwd
# и с логическим корнем отвечает «файл вне дерева»; равенство T35 тогда было бы равенством двух нетронутых карт,
# поэтому нога отдельно требует, чтобы КАЖДЫЙ `--touch` отработал.
INC="$(cd "$TMP" && pwd -P)/inc"; mkrepo "$INC"; cp "$REPO_ROOT/scripts/dep-index.py" "$INC/scripts/"; mkdir -p "$INC/hooks/tests" "$INC/docs"
printf '#!/usr/bin/env bash\ntouch_probe_fn() { echo l; }\n'                    > "$INC/hooks/lib.sh"
printf '#!/usr/bin/env bash\necho inst\n'                                        > "$INC/install.sh"
printf '#!/usr/bin/env bash\nsource hooks/lib.sh\ntouch_probe_fn x\n'            > "$INC/hooks/calls.sh"
printf '#!/usr/bin/env bash\ngrep -c . hooks/lib.sh\n'                           > "$INC/hooks/reads.sh"
printf '#!/usr/bin/env bash\nprintf "запусти hooks/lib.sh руками\\n"\n'         > "$INC/hooks/says.sh"
printf '#!/usr/bin/env bash\ncat <<J\n"command": "bash hooks/lib.sh"\nJ\n' > "$INC/hooks/reg.sh"
printf '#!/usr/bin/env bash\nbash install.sh\n'                                  > "$INC/hooks/top.sh"
printf '#!/usr/bin/env bash\nrm -f mylib.sh\n'                                   > "$INC/hooks/sub.sh"
printf '#!/usr/bin/env bash\nbash hooks/lib.sh\n'                                > "$INC/hooks/tests/test_lib.sh"
printf '# заметка\n\nБиблиотека `hooks/lib.sh` держит пробную функцию.\nСтраж my-mech стоит рядом, слово solo тут просто слово, одноимённый назван путём: scripts/dup.sh.\n' > "$INC/docs/note.md"
printf '#!/usr/bin/env bash\n# см. hooks/lib.sh — имя только в комментарии\necho c\n'  > "$INC/hooks/cmt.sh"
printf '#!/usr/bin/env bash\necho d1\n'                                          > "$INC/hooks/dup.sh"
printf '#!/usr/bin/env bash\necho d2\n'                                          > "$INC/scripts/dup.sh"
printf '#!/usr/bin/env bash\nbash scripts/dup.sh\n'                              > "$INC/hooks/bypath.sh"
printf '#!/usr/bin/env bash\nbash dup.sh\n'                                      > "$INC/hooks/bare.sh"
printf '#!/usr/bin/env bash\necho m\n'                                           > "$INC/hooks/my-mech.sh"
printf '#!/usr/bin/env bash\necho s\n'                                           > "$INC/hooks/solo.sh"
printf '#!/usr/bin/env bash\n# hooks/lib.sh — имя только в комментарии\ntrue\n'   > "$INC/hooks/tests/test_cmt.sh"
printf '#!/usr/bin/env bash\nbash hooks/tests/test_lib.sh\n'                     > "$INC/hooks/tests/test_peer.sh"
printf '# хроника\n\nЗаведён hooks/lib.sh.\n'                                     > "$INC/CHANGELOG.md"
printf '<!-- doc-kind: snapshot -->\n# разбор\n\nТогда hooks/lib.sh был иным.\n'  > "$INC/docs/snap.md"
printf '# архив\n\nПрежний hooks/lib.sh.\n'                                       > "$INC/docs/old-archive.md"
( cd "$INC" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
inc_index() { ( cd "$INC" && CLAUDSOUL_REPO="$INC" STATE_DIR="$TMP/state" PYTHONDONTWRITEBYTECODE=1 python3 scripts/dep-index.py --all >/dev/null 2>&1 ); }
snap() {  # snap [исходник] → «исходник<TAB>тип<TAB>цель» по всем рёбрам кэша (либо одного исходника), сортировано
    python3 - "$INC/mcp-server/visualization/project-graph-data.json" "${1:-}" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); k = {n['id']: n['key'] for n in g['nodes']}
for s, t, d in sorted((k[e['source']], e['type'], k[e['target']]) for e in g['edges']):
    if not sys.argv[2] or s == sys.argv[2]:
        print(s + '\t' + t + '\t' + d)
PY
}
inc_index || bad T35 "рамка: учёт песочницы не собрался"
run "$INC" --refresh >/dev/null
FULL=$(snap)
# Положительный контроль: сборка дала все четыре роли, цель в корне, «проверяет», «описывает» и
# «использует» — иначе равенство ниже было бы равенством двух пустот.
MISS=""
for want in "hooks/calls.sh	зовёт	hooks/lib.sh" "hooks/reads.sh	читает	hooks/lib.sh" "hooks/says.sh	называет	hooks/lib.sh" \
            "hooks/reg.sh	устанавливает	hooks/lib.sh" "hooks/top.sh	зовёт	install.sh" "hooks/tests/test_lib.sh	проверяет	hooks/lib.sh" \
            "docs/note.md	описывает	hooks/lib.sh" "hooks/calls.sh	использует touch_probe_fn	hooks/lib.sh" \
            "hooks/bypath.sh	зовёт	scripts/dup.sh" "hooks/tests/test_peer.sh	проверяет	hooks/tests/test_lib.sh" \
            "docs/note.md	описывает	hooks/my-mech.sh" "docs/note.md	описывает	scripts/dup.sh"; do
    grep -qxF "$want" <<< "$FULL" || MISS="$MISS [$want]"
done
# Отрицательный контроль: пары, которых у сборки быть НЕ должно, — иначе файл-свидетель свою клаузу не
# упражняет, и мутант этой клаузы прошёл бы равенство.
for pair in "hooks/cmt.sh hooks/lib.sh" "hooks/bare.sh hooks/dup.sh" "hooks/bare.sh scripts/dup.sh" "hooks/bypath.sh hooks/dup.sh" \
            "hooks/sub.sh hooks/lib.sh" "hooks/tests/test_cmt.sh hooks/lib.sh" "docs/note.md hooks/solo.sh" "docs/note.md hooks/dup.sh" \
            "CHANGELOG.md hooks/lib.sh" "docs/snap.md hooks/lib.sh" "docs/old-archive.md hooks/lib.sh"; do
    awk -F'\t' -v s="${pair% *}" -v d="${pair#* }" '$1 == s && $3 == d { f = 1 } END { exit !f }' <<< "$FULL" && MISS="$MISS [лишнее: $pair]"
done
NOTOUCH=""
[ -z "$MISS" ] && ok || bad T35a "рамка: полная сборка не дала ожидаемых рёбер либо дала лишние —$MISS"
# T35b: `DEP_ROLES` — второе объявление множества значений `dep_role`; согласованность держал только текст
# комментария («новая роль вносится и сюда»), то есть то же устройство корня R5, которое пункт лечит.
# Сверка по ФОРМЕ строки (`cache[key] = '<роль>'`), и это её названный предел: роль, возвращённая иной
# формой, не видна — поэтому пустой улов считается отказом рамки, а не согласием.
ROLES=$(python3 - "$TOOL" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
a, b = s.index('def dep_role('), s.index('\nDEP_ROLES = ')
got = set(re.findall(r"^\s+cache\[key\] = '([^']+)'$", s[a:b], re.M))   # строка КОДА целиком: та же форма в комментарии — не роль
decl = set(re.findall(r"'([^']+)'", s[b + 1:].split('\n', 1)[0]))
print(len(got), ' '.join(sorted(got ^ decl)))
PY
)
if [ "${ROLES%% *}" -lt 2 ] 2>/dev/null; then bad T35b "рамка: литералов роли в dep_role найдено «${ROLES%% *}» — сверять не с чем"
elif [ -z "${ROLES#* }" ]; then ok
else bad T35b "DEP_ROLES и значения dep_role разошлись: ${ROLES#* }"; fi
while IFS= read -r f; do
    grep -q '^в карте: ' <<< "$(run "$INC" --touch "$f")" || NOTOUCH="$NOTOUCH $f"
done < <(git -C "$INC" ls-files '*.sh' '*.py' '*.md')
AFTER=$(snap)
if [ -n "$NOTOUCH" ]; then bad T35 "рамка: «--touch» не отработал на:$NOTOUCH — равенство ниже судило бы нетронутую карту"
elif [ "$AFTER" = "$FULL" ]; then ok
else bad T35 "после «--touch» каждого файла рёбра карты разошлись с полной сборкой: $(diff <(printf '%s\n' "$FULL") <(printf '%s\n' "$AFTER") | grep '^[<>]' | head -4 | tr '\t\n' ' ;')"; fi
# T36: зависимость убрана из файла, вызов функции оставлен — ребро зависимости снято, «использует» стоит.
printf '#!/usr/bin/env bash\ntouch_probe_fn x\n' > "$INC/hooks/calls.sh"
run "$INC" --touch hooks/calls.sh >/dev/null
GOT=$(snap hooks/calls.sh | cut -f2- | tr '\t\n' ' ;')
[ "$GOT" = "использует touch_probe_fn hooks/lib.sh;" ] && ok \
    || bad T36 "зависимость из hooks/calls.sh убрана, «использует» оставлен — у файла рёбра «${GOT}», ждали одно «использует»"
# T37: новый файл вне учёта — роль та же, что даст сборка, когда учёт его догонит.
printf '#!/usr/bin/env bash\ngrep x hooks/lib.sh\n' > "$INC/hooks/fresh.sh"
run "$INC" --touch hooks/fresh.sh >/dev/null
INCR=$(snap hooks/fresh.sh)
inc_index; run "$INC" --refresh >/dev/null
if [ "$INCR" = "hooks/fresh.sh	читает	hooks/lib.sh" ] && [ "$(snap hooks/fresh.sh)" = "$INCR" ]; then ok
else bad T37 "новый файл: «--touch» дал «$(tr '\t\n' ' ;' <<< "$INCR")», сборка после пересчёта учёта — «$(snap hooks/fresh.sh | tr '\t\n' ' ;')»"; fi
# T37b: НОВЫЙ ТЕСТ и НОВЫЙ ДОКУМЕНТ видны у своего механизма сразу после `--touch` — с меткой владельца и
# той же парой, что даст сборка после пересчёта учёта. Первая редакция D430 здесь молчала (рёбер 0), а
# прежний механизм писал «зовёт»: находка скептика, регрессия против слова владельца «при создании
# новое должно попадать в карту». Поверхность потребителя — ответ `--node <механизм> --brief`.
printf '#!/usr/bin/env bash\nbash hooks/lib.sh >/dev/null\n'  > "$INC/hooks/tests/test_fresh.sh"
printf '# свежее\n\nПро `hooks/lib.sh`.\n'                   > "$INC/docs/fresh.md"
run "$INC" --touch hooks/tests/test_fresh.sh >/dev/null; run "$INC" --touch docs/fresh.md >/dev/null
INCR="$(snap hooks/tests/test_fresh.sh);$(snap docs/fresh.md)"
BRIEF=$(PROJECT_GRAPH_NO_BUILD=1 run "$INC" --node hooks/lib.sh --brief)
inc_index; run "$INC" --refresh >/dev/null
if [ "$INCR" = "hooks/tests/test_fresh.sh	проверяет	hooks/lib.sh;docs/fresh.md	описывает	hooks/lib.sh" ] \
   && [ "$(snap hooks/tests/test_fresh.sh);$(snap docs/fresh.md)" = "$INCR" ] \
   && grep -qF "test_fresh.sh" <<< "$BRIEF" && grep -qF "fresh.md" <<< "$BRIEF"; then ok
else bad T37b "новые тест и документ: «--touch» дал «$(tr '\t\n' ' ;' <<< "$INCR")», сборка — «$(snap hooks/tests/test_fresh.sh | tr '\t\n' ' ;')$(snap docs/fresh.md | tr '\t\n' ' ;')», ответ по механизму: «${BRIEF}»"; fi
# T38: файл стоит в карте, а с диска не читается — рёбра остаются, отказ чтения назван (род B).
rm -f "$INC/hooks/reads.sh"
OUT_GONE=$(run "$INC" --touch hooks/reads.sh)
if [ "$(snap hooks/reads.sh)" = "hooks/reads.sh	читает	hooks/lib.sh" ] && grep -qF "НЕ ПРОЧИТАНО" <<< "$OUT_GONE"; then ok
else bad T38 "нечитаемый файл: рёбра «$(snap hooks/reads.sh | tr '\t\n' ' ;')», вывод «${OUT_GONE}» — ждали прежнее ребро и названный отказ чтения"; fi

# ── T39-T44: ЦЕЛОСТЬ СНИМКА (17 сентября 2026, D427, корень R6). `--check` судил непустоту и отвечал 0 на
# карте с ребром в несуществующий узел; прочие режимы считали по такому ребру молча либо падали `KeyError`
# с кодом 1 — тем же, каким `--scc` говорит «спайки есть». Кэш пишется РУКОЙ и свежее учёта: судится снимок,
# а не сборка (сборка цела построением, сломать её нечем). У каждой красной ноги рядом контроль на целой
# карте тем же режимом — иначе «код 4» мог бы значить «режим не работает вовсе».
G="$TMP/whole"; mkrepo "$G"
printf '#!/usr/bin/env bash\necho one\n'          > "$G/hooks/one.sh"
printf '#!/usr/bin/env bash\nbash hooks/one.sh\n' > "$G/hooks/two.sh"
printf '#!/usr/bin/env bash\necho alone\n'        > "$G/hooks/alone.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/one.sh\ta\t\t\t\t\n'
  printf 'hooks/two.sh\tb\thooks/one.sh\t\t\t\n'
  printf 'hooks/alone.sh\tc\t\t\t\t\n'; } > "$G/.claude-docs/dep-index.tsv"
( cd "$G" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
GC="$G/mcp-server/visualization/project-graph-data.json"
N1='{"id":1,"name":"one.sh","type":"hook","key":"hooks/one.sh"}'
N2='{"id":2,"name":"two.sh","type":"hook","key":"hooks/two.sh"}'
N3='{"id":3,"name":"alone.sh","type":"hook","key":"hooks/alone.sh"}'
cache() {  # cache <узлы> <рёбра> — снимок рукой; сборка запрещена, чтобы судился ИМЕННО он
    printf '{"nodes":[%s],"edges":[%s],"domains":[],"shared_names":{}}' "$1" "$2" > "$GC"; touch "$GC"
}
edge() { printf '{"source":%s,"target":%s,"type":"зовёт","strength":3}' "$1" "$2"; }
chk() { PROJECT_GRAPH_NO_BUILD=1 run "$G" "$@"; }
# T39: положительный контроль — целая карта с ОДИНОКИМ узлом проходит (одинокий узел законен), пустая — нет.
cache "$N1,$N2,$N3" "$(edge 2 1)"
OUT_W=$(chk --check); RC_W=$?
if [ "$RC_W" = "0" ] && grep -q 'узлов: 3 ' <<< "$OUT_W"; then ok
else bad T39 "целая карта с одиноким узлом не прошла --check (код $RC_W): ${OUT_W}"; fi
cache "$N1,$N2" ""
chk --check >/dev/null 2>&1; RC_E=$?
[ "$RC_E" = "1" ] && ok || bad T39b "карта без рёбер дала --check код $RC_E — требование непустоты потеряно"
# T40-T42: три формы нарушения — код 1, нарушение НАЗВАНО, числа снимка напечатаны (видно, что судили его).
# `${want}` в скобках намеренно: bash 3.2 берёт первый байт «»» в имя переменной, и под `set -u` нога
# умирала «unbound variable» ровно тогда, когда обязана краснеть (поймано прогоном на механизме без правки).
for form in "T40|висячая цель|$N1|$(edge 1 999)|узла 999 в карте нет" \
            "T41|висячий исток|$N1|$(edge 999 1)|узла 999 в карте нет" \
            "T42|повтор id|$N1,${N2/\"id\":2/\"id\":1}|$(edge 1 1)|id 1 у 2 узлов: hooks/one.sh, hooks/two.sh"; do
    IFS='|' read -r leg what nodes edges want <<< "$form"
    cache "$nodes" "$edges"
    OUT_B=$(chk --check); RC_B=$?
    if [ "$RC_B" = "1" ] && grep -qF "$want" <<< "$OUT_B" && grep -q '^узлов: ' <<< "$OUT_B"; then ok
    else bad "$leg" "$what: --check дал код $RC_B, ждали 1 и «${want}»: ${OUT_B}"; fi
done
# T43: прочие режимы на нецелой карте — код 4 и слово «НЕ ЦЕЛА»; на целой тем же вызовом — свой обычный код.
# `--check` рядом с другим режимом стража не обходит: режим старше, и отвечает он.
for mode in "--node hooks/one.sh" "--node hooks/one.sh --brief" "--scc" "--cycles" "--scc --check" ""; do
    cache "$N1,$N2" "$(edge 2 1)"
    # shellcheck disable=SC2086
    chk $mode >/dev/null 2>&1; RC_OK=$?
    cache "$N1,$N2" "$(edge 2 1),$(edge 1 999)"
    # shellcheck disable=SC2086
    OUT_M=$(chk $mode); RC_M=$?
    if [ "$RC_OK" = "0" ] && [ "$RC_M" = "4" ] && grep -qF "НЕ ЦЕЛА" <<< "$OUT_M" && ! grep -qF "Traceback" <<< "$OUT_M"; then ok
    else bad T43 "режим «${mode:-без флагов}»: на целой карте код $RC_OK (ждали 0), на нецелой $RC_M (ждали 4): $(tail -2 <<< "$OUT_M" | tr '\n' ' ')"; fi
done
# T44: сломанный кэш ЛЕЧИТСЯ пересборкой, а не застревает: `--refresh` собирает карту заново, и она цела.
cache "$N1" "$(edge 1 999)"
run "$G" --refresh --check >/dev/null 2>&1; RC_R=$?
chk --check >/dev/null 2>&1; RC_R2=$?
if [ "$RC_R" = "0" ] && [ "$RC_R2" = "0" ]; then ok
else bad T44 "после --refresh на сломанном кэше --check дал $RC_R, повторно по кэшу $RC_R2 — ждали 0 и 0"; fi

# T45: СХЕМА ЗАПИСИ — тот же отказ, а не `KeyError` с кодом 1 (замечание скептика к D427). Поля, которые
# читатели берут без `.get`, обязаны быть: нет поля — `--check` отвечает 1 и НАЗЫВАЕТ, `--scc` отвечает 4, а не
# единицей-вердиктом «спайки есть». Контроль «режим вообще работает» — первая половина T43 (целая карта, код 0).
for form in "узел без id|{\"name\":\"one.sh\",\"type\":\"hook\",\"key\":\"hooks/one.sh\"}|$(edge 1 1)" \
            "узел без key|{\"id\":1,\"name\":\"one.sh\",\"type\":\"hook\"},$N2|$(edge 2 1)" \
            "ребро без target|$N1|{\"source\":1,\"type\":\"зовёт\",\"strength\":3}"; do
    IFS='|' read -r what nodes edges <<< "$form"
    cache "$nodes" "$edges"
    OUT_S=$(chk --check); RC_S=$?
    OUT_S2=$(chk --scc); RC_S2=$?
    if [ "$RC_S" = "1" ] && [ "$RC_S2" = "4" ] && grep -qF "не по схеме" <<< "$OUT_S" \
        && grep -qF "не по схеме" <<< "$OUT_S2" && ! grep -qF "Traceback" <<< "${OUT_S}${OUT_S2}"; then ok
    else bad T45 "${what}: --check дал $RC_S (ждали 1), --scc дал $RC_S2 (ждали 4), оба со словом «не по схеме»: $(tail -1 <<< "$OUT_S") / $(tail -1 <<< "$OUT_S2")"; fi
done

# ── T46 (D1069): упоминание называет механизм ЦЕЛЫМ именем, а не хвостом чужого; имя многих — только путём ──
# Своё дерево (прибор лежит в нём): голое имя годится, если оно в дереве одно. `t.sh` внутри `knowledge-inject.sh`
# связью не является; `dup.sh` носят два механизма — по голому имени не вешается ни на один. Положительный
# контроль — уникальное `solo.sh`. (Вид `__init__.py` карта не знает — его карточка рёбер не показывает.)
K="$TMP/k"; mkrepo "$K"; mkdir -p "$K/tests"
for f in hooks/knowledge-inject.sh hooks/solo.sh tests/t.sh hooks/dup.sh scripts/dup.sh; do printf '#!/usr/bin/env bash\necho x\n' > "$K/$f"; done
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  for f in hooks/knowledge-inject.sh hooks/solo.sh hooks/dup.sh scripts/dup.sh; do printf '%s\ta\t\t\t\t\n' "$f"; done; } > "$K/.claude-docs/dep-index.tsv"
( cd "$K" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
L46="$TMP/lessons46"; mkdir -p "$L46"
printf -- '---\nname: case-k1\n---\nпро hooks/knowledge-inject.sh, solo.sh и dup.sh\n' > "$L46/case-k1.md"
k46() { ( cd "$K" && LESSONS_DIR="$L46" CLAUDSOUL_REPO="$K" python3 scripts/project-graph.py --node "$1" 2>&1 ); }
grep -qF "case-k1" <<< "$(k46 hooks/solo.sh)" && ok || bad T46a "уникальное имя целым словом не дало ребра — контроль пуст"
grep -qF "case-k1" <<< "$(k46 tests/t.sh)" && bad T46b "хвост чужого имени (t.sh в knowledge-inject.sh) дал ребро" || ok
grep -qF "case-k1" <<< "$(k46 hooks/dup.sh)" && bad T46c "имя, которое носят два механизма, дало ребро по голому имени" || ok

echo "test_project_graph: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
