#!/usr/bin/env bash
# СУДИТ: hooks/merge-root-gate.sh
# test_merge_root_gate.sh — страж слияния в главную ветку: починка входит с корнем (решение владельца 9 октября 2026).
# Результат: каждый признак отказывает на своём плохом входе и молчит на хорошем, отличающемся
#            ОДНИМ свойством (различающая способность): (а) код без пункта / только документы;
#            (б) пункт без корня, с корнем вне карты / с корнем, «не дефект»; (в) карточка без
#            «Зависимостей»; (г) проба с носителями без «Предела» / с «Пределом», сломанная проба;
#            (д) изменённое число в ожидании старого теста и теста, созданного в той же ветке /
#            с «Ожидание изменено:», переименование вызова, новый тест-файл. Разбор команды:
#            `-C`, `cd &&`, `--ff-only`, `-m`; тишина на `--abort`, упоминании в кавычках, не-main,
#            синхронизации с upstream, проекте без карты, без прибора root-map.
# Проверка результата: bash hooks/tests/test_merge_root_gate.sh даёт 0
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/merge-root-gate.sh"
CS_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
for t in jq python3 git; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP: $t недоступен"; exit 0; }; done
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
denied() { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
assert_silent() { if [ -z "${1:-}" ]; then ok; else bad "$2" "ожидалась тишина, получено: ${1:0:300}"; fi; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
export STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$CS_ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$TMP/repo"; mkdir -p "$R/src" "$R/tests" "$R/scripts/probes" "$R/docs"
git -C "$R" init -q -b main
cat > "$R/ROOTS.md" <<'EOF'
# ROOTS

## R1 — тестовый корень
**Устройство.** src делает BAD.
**Признак.** `scripts/probes/R1.sh`
**Зависимости (чек-лист регрессии).** tests/a.test.js
**Держит.** —

## R2 — корень без чек-листа
**Признак.** `scripts/probes/R2.sh`
**Держит.** —

## R3 — корень со сломанной пробой
**Признак.** `scripts/probes/R3.sh`
**Зависимости.** —
**Держит.** —
EOF
printf '#!/usr/bin/env bash\ngrep -rn BAD src\nexit 0\n' > "$R/scripts/probes/R1.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/probes/R2.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$R/scripts/probes/R3.sh"
cat > "$R/BACKLOG.md" <<'EOF'
# BACKLOG

### B1 ☐ [P2] пункт с корнем R1
**Корень.** R1 (`ROOTS.md`, проба `scripts/probes/R1.sh`).

### B2 ☐ [P2] пункт без корня
**Проверка.** `false` → 0

### B3 ☐ [P2] задача
**Корень.** не дефект — новая возможность

### B4 ☐ [P2] корень без чек-листа
**Корень.** R2

### B5 ☐ [P2] корень со сломанной пробой
**Корень.** R3

### B6 ☐ [P2] корень вне карты
**Корень.** R9

### B7 ☐ [P2] пункт без разбора
**Корень.** нет — разбор не проводился

### B8 ☐ [P2] задача, корень с заглавной
**Корень.** Не дефект — заглавной буквой

### B9 ☐ [P2] корень не заведён
**Корень.** не заведён — разбор впереди
EOF
printf 'module.exports = 1;\n' > "$R/src/a.js"
cat > "$R/tests/a.test.js" <<'EOF'
it("сумма", () => {
  expect(sum(1, 2)).toEqual({
    total: 1290,
  });
  expect(oldFn(2)).toBe(4);
});
EOF
git -C "$R" add -A && git -C "$R" commit -qm init

# br <ветка> <сообщение> <файл> <содержимое> [<файл> <содержимое> …] — ветка от main с одним коммитом
br() {
    local b="$1" m="$2"; shift 2
    git -C "$R" checkout -q -b "$b" main
    while [ $# -ge 2 ]; do mkdir -p "$(dirname "$R/$1")"; printf '%s' "$2" > "$R/$1"; shift 2; done
    git -C "$R" add -A && git -C "$R" commit -qm "$m"
    git -C "$R" checkout -q main
}
TEST_BAD=$(sed 's/total: 1290,/total: 1290.02,/' "$R/tests/a.test.js")
TEST_REN=$(sed 's/oldFn(2)).toBe(4)/newFn(2)).toBe(4)/' "$R/tests/a.test.js")
LIMIT=$(awk '{ print } /^[*][*]Зависимости [(]чек-лист/ { print "**Предел.** один носитель остаётся — легаси-вход." }' "$R/ROOTS.md")
br good      "fix: правка (B1)"              src/a.js 'module.exports = 2;'
br noitem    "fix: правка без пункта"        src/a.js 'module.exports = 3;'
br docsonly  "docs: заметка"                 docs/x.md 'текст'
br bodyonly  "fix: правка"                   src/a.js 'module.exports = 4;'
git -C "$R" checkout -q bodyonly && git -C "$R" commit -q --amend -m $'fix: правка\n\nвнесено правкой B2' && git -C "$R" checkout -q main
br noroot    "fix: правка (B2)"              src/a.js 'module.exports = 5;'
br notdefect "feat: возможность (B3)"        src/a.js 'module.exports = 6;'
br nodeps    "fix: правка (B4)"              src/a.js 'module.exports = 7;'
br broken    "fix: правка (B5)"              src/a.js 'module.exports = 8;'
br missing   "fix: правка (B6)"              src/a.js 'module.exports = 9;'
br noanalysis "fix: правка (B7)"             src/a.js 'module.exports = 10;'
br carriers  "fix: правка (B1)"              src/a.js 'BAD();'
br limited   "fix: правка (B1)"              src/a.js 'BAD();' ROOTS.md "$LIMIT"
br expect    "fix: правка (B1)"              tests/a.test.js "$TEST_BAD"
br stated    $'fix: правка (B1)\n\nОжидание изменено: сумма теперь с копейками по решению владельца' tests/a.test.js "$TEST_BAD"
br renamed   "fix: правка (B1)"              tests/a.test.js "$TEST_REN"
br newtest   "test: новый (B1)"              tests/c.test.js 'expect(f()).toBe(1290.02);'
# Форма fix/fundsell: тест-файл создан в ветке (1290) и подогнан в ней же (1290,02).
br inbranch  "test: новый (B1)"              tests/b.test.js $'expect(f()).toEqual({\n  total: 1290,\n});\n'
git -C "$R" checkout -q inbranch && printf 'expect(f()).toEqual({\n  total: 1290.02,\n});\n' > "$R/tests/b.test.js" \
    && git -C "$R" commit -qam "fix: подгонка (B1)" && git -C "$R" checkout -q main

check() { bash "$HOOK" --check "$R" main "$1" 2>&1; }   # → вывод; код — вердикт
expect_rc() {  # <ветка> <код> <метка> [<подстрока вывода>]
    local out rc; out=$(check "$1"); rc=$?
    if [ "$rc" -ne "$2" ]; then bad "$3" "код $rc вместо $2: ${out:0:400}"; return; fi
    if [ -n "${4:-}" ] && ! grep -qF -- "$4" <<< "$out"; then bad "$3" "нет «$4» в выводе: ${out:0:400}"; return; fi
    ok
}
# --- различающая способность: пара «плохо → отказ / то же, но хорошо → пропуск» ---
expect_rc good      0 "T0 пункт с корнем, проба на нуле — пропуск"
expect_rc noitem    1 "Ta код без пункта — отказ" "нет пункта"
expect_rc docsonly  0 "Ta' только документы без пункта — пропуск"
expect_rc bodyonly  1 "Ta'' пункт только в теле сообщения — не назван" "нет пункта"
expect_rc noroot    1 "Tb пункт без корня — отказ" "B2: нет строки"
expect_rc notdefect 0 "Tb' «не дефект» — пропуск"
expect_rc missing   1 "Tb'' корень вне карты — отказ" "R9 не найден"
# D1020: «нет — …» начинается с «не», и префикс засчитывал его как «не дефект» (пара — Tb').
expect_rc noanalysis 1 "Tb''' корень «нет — разбор не проводился» — отказ" "B7: «**Корень.** нет"
expect_rc nodeps    1 "Tc нет «Зависимостей» — отказ" "R2 (B4): в карточке нет поля"
expect_rc carriers  1 "Td носители без «Предела» — отказ" "не дошла до нуля (1 носит."
expect_rc limited   0 "Td' носители с названным «Пределом» — пропуск"
expect_rc broken    1 "Td'' проба упала — отказ словами" "код 3. Прибор сломан"
expect_rc expect    1 "Te число в ожидании изменено молча — отказ" "tests/a.test.js:3"
expect_rc stated    0 "Te' «Ожидание изменено:» — пропуск"
expect_rc renamed   0 "Te'' переименование вызова, число то же — пропуск"
expect_rc newtest   0 "Te''' новый тест-файл — не считается"
expect_rc inbranch  1 "Te'''' тест создан и подогнан в ветке (форма fix/fundsell) — отказ" "tests/b.test.js:2"
# D524: ветки нет — «прибор сломан» с её именем, а не «пропуск» пустого диапазона (пара — T0).
expect_rc no-such-branch 2 "Tf ветки нет — прибор сломан, не пропуск" "no-such-branch: git не разрешает"

# --- путь хука: разбор команды ---
hook() {  # hook <команда> [cwd] → вывод; страж с кодом ≠ 0 дописывает «[код N]», и тишина такой не засчитывается
    local o rc
    o=$(jq -cn --arg c "$1" --arg d "${2:-$R}" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' | bash "$HOOK" 2>/dev/null)
    rc=$?; printf '%s' "$o"; [ "$rc" -eq 0 ] || printf '[код %s]' "$rc"
}
OUT=$(hook "git -C $R merge --ff-only noroot" "$TMP")
denied "$OUT" && grep -q "B2" <<< "$OUT" && ok || bad "H1" "-C … merge --ff-only на ветке без корня не отбит: ${OUT:0:300}"
OUT=$(hook "cd $R && git merge --no-ff -m 'слияние noroot' noroot" "$TMP")
denied "$OUT" && ok || bad "H2" "cd && merge -m не отбит: ${OUT:0:300}"
OUT=$(hook "git merge good"); assert_silent "$OUT" "H3 хорошая ветка отбита"
OUT=$(hook "git merge --abort"); assert_silent "$OUT" "H4 --abort отбит"
OUT=$(hook "echo 'git merge noroot'"); assert_silent "$OUT" "H5 упоминание в кавычках отбито"
OUT=$(hook "git merge noroot && git merge expect")
denied "$OUT" && grep -q "B2" <<< "$OUT" && grep -q "tests/a.test.js:3" <<< "$OUT" && ok \
    || bad "H6" "две ветки в одной команде — не обе названы: ${OUT:0:400}"
# Не main: та же ветка молчит. Синхронизация с upstream своей ветки — молчит, чужая удалённая — нет.
C="$TMP/clone"; git clone -q "$R" "$C"
git -C "$C" checkout -q -b dev
OUT=$(hook "git merge origin/noroot" "$C"); assert_silent "$OUT" "H7 слияние в не-main отбито"
git -C "$C" checkout -q main
OUT=$(hook "git merge origin/main" "$C"); assert_silent "$OUT" "H8 синхронизация с origin/main отбита"
OUT=$(hook "git merge origin/noroot" "$C")
denied "$OUT" && ok || bad "H9" "удалённая ветка без корня в main не отбита: ${OUT:0:300}"
# Проекта без карты корней — молчание.
mv "$C/ROOTS.md" "$C/ROOTS.off"
OUT=$(hook "git merge origin/noroot" "$C"); assert_silent "$OUT" "H10 проект без ROOTS.md — отказ"
mv "$C/ROOTS.off" "$C/ROOTS.md"
# Прибора нет — «инструмента здесь нет», а не отказ.
OUT=$(jq -cn --arg c "git merge noroot" --arg d "$R" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' \
      | CLAUDSOUL_ROOT="$TMP/nowhere" bash "$HOOK" 2>/dev/null)
assert_silent "$OUT" "H11 без root-map.py — отказ вместо молчания"
# Непарная кавычка при настоящем `git merge` — отказ словами, а не пропуск.
OUT=$(hook "git merge noroot; echo \"x")
denied "$OUT" && grep -q "не удалось разобрать" <<< "$OUT" && ok || bad "H12" "неразобранная команда пропущена: ${OUT:0:300}"

# --- путь прямого коммита в main (D1019, D1021): судит ловушка git commit-msg -------------------------------------
# Коммит ИСПОЛНЯЕТСЯ по-настоящему: вердикт — сдвинулся ли HEAD, причина — вывод ловушки. Пары «плохо → отказ / то же,
# но хорошо → пропуск». После каждого вызова ветка и индекс возвращаются как были.
CR="$TMP/crepo"; git clone -q "$R" "$CR"
bash "$HOOK" --install "$CR" >/dev/null 2>&1 && ok || bad "C0" "ловушка commit-msg не поставилась"
cgo() {  # cgo <команда> [каталог] → вывод; код 0 — коммит вошёл
    local d="${2:-$CR}" h0 ix o rc=1
    h0=$(git -C "$d" rev-parse HEAD); ix=$(git -C "$d" rev-parse --path-format=absolute --git-path index)
    cp "$ix" "$TMP/idx.save"
    o=$(cd "$d" && bash -c "$1" 2>&1)
    # Ветка возвращается, только если коммит вошёл: отбитый HEAD не сдвинул, а внутри слияния `reset --soft` git не делает.
    [ "$(git -C "$d" rev-parse HEAD)" != "$h0" ] && { rc=0; git -C "$d" reset -q --soft "$h0"; }
    cp "$TMP/idx.save" "$ix"
    printf '%s' "$o"; return $rc
}
# cden <команда> <метка> <подстрока вывода | «-»: вывод уведён> [каталог]; cok <команда> <метка> [каталог]
cden() { local o; if o=$(cgo "$1" "${4:-}"); then bad "$2" "коммит вошёл, ожидался отказ: ${o:0:300}"
    elif [ "$3" = - ] || grep -qF -- "$3" <<< "$o"; then ok; else bad "$2" "коммит не вошёл, но без «$3»: ${o:0:300}"; fi; }
cok()  { local o; if o=$(cgo "$1" "${3:-}"); then ok; else bad "$2" "коммит не вошёл: ${o:0:300}"; fi; }
printf 'module.exports = 42;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git commit -m "fix: правка без пункта"' "C1 починка без пункта — отказ" "нет пункта: починка меняет код"
cok  'git commit -m "fix: правка (B1)"' "C1' починка с пунктом и корнем — пропуск"
cok  'git commit -m "chore: учёт"' "C2 не-починка без пункта — пропуск"
cok  'git commit -m "feat: возможность"' "C2' новая возможность без пункта — не судится"
# Дальше ловушка — из МИНИМАЛЬНОЙ копии стражей (скептик opus по a289b017, M): предмет ног — страж корня, а полная
# ловушка гоняла на каждом из ~100 коммитов ещё четыре стража (`GUARDS` в commit-trap.sh) — около 65 с CPU из 115, и ни
# одна нога их вывода не ждёт. Ноги C0–C2' выше идут на полной ловушке; отсутствующий страж ловушка пропускает (I3').
MIN="$TMP/minhooks"; mkdir -p "$MIN"
cp "$HOOK" "$HOOKS_DIR"/commit-trap.sh "$HOOKS_DIR"/paths-lib.sh "$HOOKS_DIR"/backlog-lib.sh "$HOOKS_DIR"/command-scope-lib.sh "$MIN/"
cp -R "$HOOKS_DIR/lib" "$MIN/"
HOOKI="$MIN/merge-root-gate.sh"
bash "$HOOKI" --install "$CR" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_merge_root_gate.sh:$LINENO" >&2; exit 1; }
cden 'git commit -m "perf(x): быстрее"' "C2'' perf без пункта — отказ" "нет пункта"
cden 'git commit -m "fix: правка (B2)"' "C3 пункт без корня — отказ" "B2: нет строки"
cden 'git commit -m "fix: правка (B7)"' "C3' корень «нет — …» — отказ" "B7: «**Корень.** нет"
cok  'git commit -m "fix: правка (B3)"' "C3'' «не дефект» — пропуск"
cden 'git commit -m "fix: правка (B8)"' "C3''' «Не …» с заглавной — не «не дефект», отказ" "B8"
cden 'git commit -m "fix: правка (B9)"' "C3'''' «не заведён — …» — корня нет, отказ" "B9: «**Корень.** не …» — не корень"
cden 'git commit -m "fix: правка (B5)"' "C4 сломанная проба без предела — отказ словами" "Прибор сломан"
printf '%s\n' 'fix: правка без пункта' '' 'тело' > "$TMP/msg-bad.txt"; printf '%s\n' 'fix: правка (B1)' > "$TMP/msg-ok.txt"
cden "git commit -F $TMP/msg-bad.txt" "C5 -F файл без пункта — отказ" "нет пункта"
cok  "git commit -F $TMP/msg-ok.txt" "C5' -F файл с пунктом — пропуск"
cden "$(printf '%s\n' "git commit -F - <<'EOF'" 'fix: правка без пункта' 'EOF')" "C6 встроенный текст -F - без пункта — отказ" "нет пункта"
cok  "$(printf '%s\n' "git commit -F - <<'EOF'" 'fix: правка (B1)' 'EOF')" "C6' встроенный текст с пунктом — пропуск"
cden "$(printf '%s\n' "git commit -m \"\$(cat <<'EOF'" 'fix: правка без пункта' '' 'тело' 'EOF' ')"')" "C7 -m \$(cat <<EOF) без пункта — отказ" "нет пункта"
cok  "$(printf '%s\n' "git commit -m \"\$(cat <<'EOF'" 'fix: правка (B1)' 'EOF' ')"')" "C7' -m \$(cat <<EOF) с пунктом — пропуск"
cden "cd $CR && git -C $CR commit -m 'fix: правка без пункта'" "C8 cd && -C — отказ" "нет пункта"
cok  'git commit -m "docs: заметка"' "C8' тип docs — не судится"
# Индекс без кода — коммит починки документов не судится.
git -C "$CR" reset -q; git -C "$CR" checkout -q -- src; mkdir -p "$CR/docs"; printf 'заметка\n' > "$CR/docs/y.md"
git -C "$CR" add docs/y.md || bad "C9-подготовка" "документ не попал в индекс — нога C9 судила бы пустой индекс"
cok  'git commit -m "fix: опечатка в документе"' "C9 починка одних документов — пропуск"
# -a: изменённый отслеживаемый файл вне индекса входит в коммит — и в суд.
git -C "$CR" reset -q; rm -f "$CR/docs/y.md"; printf 'module.exports = 43;\n' > "$CR/src/a.js"
cden 'git commit -am "fix: правка без пункта"' "C10 -am без пункта — отказ" "нет пункта"
cok  'git commit --allow-empty -m "fix: правка без пункта"' "C10' без -a код в коммит не идёт — пропуск"
# Не main — молчание: такую ветку судит слияние.
git -C "$CR" checkout -q -b dev; git -C "$CR" add src/a.js
cok  'git commit -m "fix: правка без пункта"' "C11 коммит не в main — пропуск"
git -C "$CR" checkout -q main
# --amend --no-edit судит сообщение повторяемого коммита. Подготовка — коммит владельца в обход: с признаком агента его
# сняла бы ловушка post-commit (D1023), и ответ ноги зависел бы от того, кто запустил тест.
env -u CLAUDECODE -u AI_AGENT git -C "$CR" commit -q --no-verify -m "fix: правка без пункта"; printf 'module.exports = 44;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git commit --amend --no-edit' "C12 --amend --no-edit с темой без пункта — отказ" "нет пункта"
git -C "$CR" reset -q --hard HEAD~1
# (д) на коммите: число в ожидании старого теста изменено молча — отказ; с «Ожидание изменено:» — пропуск.
sed 's/total: 1290,/total: 1290.02,/' "$R/tests/a.test.js" > "$CR/tests/a.test.js"; git -C "$CR" add tests/a.test.js
cden 'git commit -m "fix: правка (B1)"' "C13 ожидание изменено молча — отказ" "tests/a.test.js:3 (в коммите)"
cok  "$(printf '%s\n' "git commit -F - <<'EOF'" 'fix: правка (B1)' '' 'Ожидание изменено: сумма с копейками по решению владельца' 'EOF')" "C13' «Ожидание изменено:» — пропуск"
git -C "$CR" reset -q --hard
# (г) при названном «Пределе»: на коммите проба не исполняется (её ответ вердикт не решает, а проба R5 ClaudSoul
# дольше 120 с — волна проверки D1019), здоровье пробы — у замера root-map-drift; на слиянии исполняется, и упавшая
# проба — отказ словами и при пределе.
printf 'module.exports = 45;\n' > "$CR/src/a.js"
awk '{ print } /^## R3 / { print "**Предел.** проба чинится отдельно." }' "$R/ROOTS.md" > "$CR/ROOTS.md"; git -C "$CR" add src/a.js ROOTS.md
cok  'git commit -m "fix: правка (B5)"' "C14 предел на коммите — проба не исполняется, пропуск"
git -C "$CR" reset -q --hard
br brokenlim "fix: правка (B5)" src/a.js 'module.exports = 46;' ROOTS.md "$(awk '{ print } /^## R3 / { print "**Предел.** проба чинится отдельно." }' "$R/ROOTS.md")"
expect_rc brokenlim 1 "Td''' предел на слиянии — проба исполняется, упавшая — отказ словами" "код 3. Прибор сломан"

# Формы сообщения: всё это git читает сам — ловушка судит готовое сообщение.
NR="$TMP/noroots"; git -C "$TMP" clone -q "$R" noroots; mv "$NR/ROOTS.md" "$NR/ROOTS.off"
bash "$HOOKI" --install "$NR" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_merge_root_gate.sh:$LINENO" >&2; exit 1; }
printf 'module.exports = 50;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
printf 'module.exports = 50;\n' > "$NR/src/a.js"; git -C "$NR" add src/a.js
D469=$(printf '%s\n' "git commit -q -F - <<'MSG'" "fix(D469): прибор падал Traceback'ом там, где ждали код" 'MSG')
cok  "$D469" "C15 настоящая команда D469 в проекте без карты — коммит входит" "$NR"
cden "$D469" "C15' та же команда в main с картой — судится по делу: пункта нет" "нет пункта"
cok  "$(printf '%s\n' "git commit -F - <<'EOF'" "chore: don't panic" 'EOF')" "C15'' апостроф в сообщении не-починки — пропуск"
cok  "printf 'fix: x\\n' | git commit -F -" "C16 конвейер в проекте без карты — коммит входит" "$NR"
cden "printf 'fix: правка без пункта\\n' | git commit -F -" "C16' конвейер в main с картой — судится по делу" "нет пункта"
cden "git commit -F - <<< 'fix: правка без пункта'" "C17 here-string без пункта — отказ" "нет пункта"
printf '%s\n' 'chore: учёт' > "$TMP/msg-chore.txt"
cok  "git commit -F - < $TMP/msg-chore.txt" "C17' сообщение из < файл — не-починка проходит"
cden "git commit -m \"\$(cat $TMP/msg-bad.txt)\"" "C18 -m \$(cat файл) без пункта — отказ" "нет пункта"
cden "M='fix: правка без пункта'; git commit -m \"\$M\"" "C18' тема в переменной той же команды — отказ" "нет пункта"
cden "git commit -m \$'fix: правка без пункта\\n\\nтело'" "C18'' \$'…' без пункта — отказ" "нет пункта"
cden 'git commit -m "" -m "fix: правка без пункта"' "C18''' пустой первый абзац — тема из второго, отказ" "нет пункта"
cden 'git commit -m "Fix: правка без пункта"' "C18'''' Fix с заглавной — отказ" "нет пункта"
cden 'time git commit -m "fix: правка без пункта"' "C19 обёртка time — отказ" "нет пункта"
cden 'env A=1 git commit -m "fix: правка без пункта"' "C19' обёртка env — отказ" "нет пункта"
cok  "SP=$TMP; git commit -F \"\$SP/msg-chore.txt\"" "C20 -F \"\$SP/…\" не-починки — пропуск"
cden "SP=$TMP; git commit -F \"\$SP/msg-bad.txt\"" "C20' -F \"\$SP/…\" починки без пункта — отказ" "нет пункта"
cok  "$(printf '%s\n' "cat > $TMP/w-ok.txt <<'EOF'" 'chore: учёт' 'EOF' "git commit -F $TMP/w-ok.txt")" "C20'' файл, записанный той же командой, — пропуск"
cden "$(printf '%s\n' "cat > $TMP/w-bad.txt <<'EOF'" 'fix: правка без пункта' 'EOF' "git commit -F $TMP/w-bad.txt")" "C20''' он же с починкой без пункта — отказ" "нет пункта"
# Коммит с путями: в коммит идут пути из рабочего дерева, индекс пуст.
git -C "$CR" reset -q; printf 'module.exports = 51;\n' > "$CR/src/a.js"
cden 'git commit -m "fix: правка без пункта" -- src/a.js' "C21 коммит путей без пункта — отказ" "нет пункта"
cden 'git commit -o -m "fix: правка без пункта" src/a.js' "C21' -o путь без пункта — отказ" "нет пункта"
cok  'git commit -m "fix: правка (B1)" -- src/a.js' "C21'' коммит путей с пунктом — пропуск"
git -C "$CR" checkout -q -- src
# --amend с новой темой судит то, что ляжет на HEAD^: код прошлого коммита входит в переписанный.
printf 'module.exports = 52;\n' > "$CR/src/a.js"; git -C "$CR" commit -qam "chore: учёт"
cden 'git commit --amend -m "fix: правка без пункта"' "C22 --amend с темой починки без пункта — отказ" "нет пункта"
cden 'git -c color.ui=never commit -q --amend -m "fix: правка без пункта"' "C22'' --amend через git -c — отказ" "нет пункта"
git -C "$CR" reset -q --hard HEAD~1
# (д) при --amend: ожидание, молча изменённое в переписываемом HEAD, входит в новый коммит — старое берётся от HEAD^.
# Строки в HEAD сдвинуты: иначе номера строк у HEAD и HEAD^ совпадают, и нога не отличила бы основу (мутант выжил).
{ printf '// a\n// b\n// c\n'; sed 's/total: 1290,/total: 1290.02,/' "$R/tests/a.test.js"; } > "$CR/tests/a.test.js"
git -C "$CR" commit -qam "chore: учёт"
printf 'module.exports = 54;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git commit --amend -m "fix: правка (B1)"' "C22' --amend: ожидание, изменённое молча в HEAD, — отказ" "tests/a.test.js:3 (в коммите)"
git -C "$CR" reset -q --hard HEAD~1
# Документ с именем не-ASCII — документ, а не код.
mkdir -p "$CR/docs"; printf 'x\n' > "$CR/docs/заметка.md"; git -C "$CR" add "docs/заметка.md"
cok  'git commit -m "fix: опечатка в документе"' "C23 документ с именем не-ASCII — не код, пропуск"
git -C "$CR" reset -q --hard

# Сообщение идёт файлом (окружение больше 1 МБ не проходит в exec), тема — абзац, как у git.
printf 'module.exports = 53;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
python3 -c 'import sys; open(sys.argv[1], "w").write("fix: правка (B1)\n\n" + "строка тела длиной в сорок с лишним байт\n" * 30000)' "$TMP/msg-long.txt"
cok  "git commit -F $TMP/msg-long.txt" "C24 сообщение больше 1 МБ с пунктом — пропуск, а не «прибор сломан»"
cok  "$(printf 'git commit -m "fix: правка\n(B1)"')" "C25 тема перенесена на вторую строку абзаца — git видит пункт, страж тоже"
cden "$(printf 'git commit -m "fix: правка\n\n(B1)"')" "C25' пункт во втором абзаце — не тема, отказ" "нет пункта"
# Прибора нет (root-map.py у ClaudSoul не найден) — «инструмента здесь нет»: ловушка молчит, коммит входит.
OUT=$(export CLAUDSOUL_ROOT="$TMP/nowhere"; cgo 'git commit -m "fix: правка без пункта"') && ok \
    || bad "C26" "прибора нет, а коммит не вошёл: ${OUT:0:300}"
git -C "$CR" reset -q --hard

# Снимок — репозиторий git: пробы карты зовут git. Проба R2/R3 ClaudSoul ищет `git grep … | …` — в голом каталоге git
# падал, конвейер давал пусто, и пустота читалась нулём носителей. Модель — та же форма пробы.
printf '#!/usr/bin/env bash\ngit grep -n BAD -- src | cat\n' > "$CR/scripts/probes/R1.sh"
printf 'BAD();\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js scripts/probes/R1.sh
cden 'git commit -m "fix: правка (B1)"' "C33 проба на git grep в снимке коммита видит носителя — отказ, а не ложный ноль" "не дошла до нуля"
# Проба R6 ClaudSoul без репозитория отвечает кодом 2 — законный коммит получал «прибор сломан».
printf '#!/usr/bin/env bash\ngit rev-parse --show-toplevel >/dev/null 2>&1 || exit 2\nexit 0\n' > "$CR/scripts/probes/R1.sh"
printf 'module.exports = 60;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js scripts/probes/R1.sh
cok  'git commit -m "fix: правка (B1)"' "C33' проба, которой нужен репозиторий, — в снимке на нуле, пропуск"
git -C "$CR" reset -q --hard
br gitgrep "fix: правка (B1)" src/a.js 'BAD();' scripts/probes/R1.sh $'#!/usr/bin/env bash\ngit grep -n BAD -- src | cat\n'
expect_rc gitgrep 1 "Tg проба на git grep в снимке ветки видит носителя — отказ, а не ложный ноль" "не дошла до нуля"

# (г) таймаут пробы: при названном «Пределе» прощается, без предела — «прибор сломан». Срок 120 с зашит у владельца
# пробы (scripts/root-map.py), и ждать его в тесте — две минуты; поэтому обёртка над НАСТОЯЩИМ root-map.py подменяет
# ему один запуск процесса на «не уложился» — текст таймаута отдаёт сам владелец, а не копия в тесте.
# С D1239 проба идёт через `hooks/lib/bounded_run.py` — подменяется и он (без этого коммит входил, C14' краснела).
# Подменяется ОДНА функция настоящего модуля, а не перечень его имён (D1295, 15 ноября 2026): с f860c7d0 владелец ловит
# `subprocess.SubprocessError`, и подделка из двух имён роняла прибор AttributeError вместо «не уложилась».
FR="$TMP/fakeroot"; mkdir -p "$FR/scripts"
printf '%s\n' 'import importlib.util, subprocess, types' \
    "_s = importlib.util.spec_from_file_location('real_root_map', '$CS_ROOT/scripts/root-map.py')" \
    '_m = importlib.util.module_from_spec(_s); _s.loader.exec_module(_m)' \
    'def _late(cmd, **k): raise subprocess.TimeoutExpired(cmd, k.get("timeout", 0))' \
    '_m.subprocess = types.ModuleType("subprocess"); _m.subprocess.__dict__.update(subprocess.__dict__); _m.subprocess.run = _late' \
    'def _late_b(cmd, timeout, **k): raise subprocess.TimeoutExpired(cmd, timeout)' \
    '_m.bounded_run = types.SimpleNamespace(run_bounded=_late_b) if _m.bounded_run else None' \
    'parse, carriers_of = _m.parse, _m.carriers_of' > "$FR/scripts/root-map.py"
printf 'module.exports = 55;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
if OUT=$(export CLAUDSOUL_ROOT="$FR"; cgo 'git commit -m "fix: правка (B1)"'); then bad "C14'" "таймаут пробы без «Предела» — коммит вошёл"
elif grep -qF "не уложилась" <<< "$OUT"; then ok; else bad "C14'" "таймаут пробы без «Предела» не назван «прибор сломан»: ${OUT:0:300}"; fi
awk '{ print } /^## R1 / { print "**Предел.** проба дольше срока." }' "$R/ROOTS.md" > "$CR/ROOTS.md"; git -C "$CR" add ROOTS.md
OUT=$(export CLAUDSOUL_ROOT="$FR"; cgo 'git commit -m "fix: правка (B1)"') && ok || bad "C14''" "таймаут пробы при «Пределе» — коммит не вошёл: ${OUT:0:300}"
git -C "$CR" reset -q --hard

# Команда коммита в любой обёртке: комментарии, запись файла той же командой, подстановки, кавычки, подкаталог.
printf 'module.exports = 61;\n' > "$CR/src/a.js"
cden "$(printf 'git add src/a.js  # в индекс\ngit commit -m "fix: правка без пункта"')" "C27 комментарий в строке перед коммитом не прячет коммит — отказ" "нет пункта"
OUT=$(hook "$(printf 'git status  # смотрю\ngit merge noroot')")
denied "$OUT" && grep -q "B2" <<< "$OUT" && ok || bad "C27'" "комментарий в строке перед слиянием спрятал слияние: ${OUT:0:300}"
git -C "$CR" add src/a.js
printf 'fix: старая тема\n' > "$TMP/m-stale.txt"
cok  "$(printf '%s\n' "cat <<'EOF' > $TMP/m-stale.txt" 'feat: новая возможность' 'EOF' "git commit -F $TMP/m-stale.txt")" "C28 «cat <<EOF > файл» — судится тело, а не старый файл"
printf 'feat: старая тема\n' > "$TMP/m-old.txt"
cden "printf 'fix: правка без пункта\\n' > $TMP/m-old.txt && git commit -F $TMP/m-old.txt" "C28' файл, который пишет та же команда, — судится записанное" "нет пункта"
MSGC=$(printf '%s\n' "MSG=\$(cat <<'EOF'" 'fix: правка без пункта' 'EOF' ')' 'git commit -m "$MSG"')
cden "$MSGC" "C29 MSG=\$(cat <<EOF) и -m \"\$MSG\" — тема из тела, отказ" "нет пункта"
cok  "${MSGC/без пункта/(B1)}" "C29' то же с пунктом — пропуск"
cden "git commit -m \"\$(printf 'fix: x')\"" "C30 тема из подстановки команды — судится по делу" "нет пункта"
cok  "git commit -m 'fix(B1): handle \$PATH'" "C31 \$ в одинарных кавычках — буква: пропуск"
cden "git commit -m 'fix: handle \$PATH'" "C31' то же без пункта — отказ" "нет пункта"
git -C "$CR" reset -q; git -C "$CR" checkout -q -- src; printf 'module.exports = 62;\n' > "$CR/src/a.js"
cden "cd $CR/src && git commit -m 'fix: правка без пункта' -- a.js" "C32 путь от подкаталога команды — отказ" "нет пункта"
git -C "$CR" reset -q --hard
printf 'module.exports = 63;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git commit -m "fix: правка без пункта"  # заметка' "C27'' комментарий в конце строки коммита — отказ" "нет пункта"
git -C "$CR" reset -q --hard

# Снимок и пробы — то, что остаётся при любом устройстве суда (волна проверки D1019).
# Корень пробы — снимок, даже если в окружении CLAUDSOUL_REPO смотрит в другой каталог (здесь — в $R без носителя).
printf '#!/usr/bin/env bash\ncd "${CLAUDSOUL_REPO:-.}" || exit 2\ngit grep -n BAD -- src | cat\n' > "$CR/scripts/probes/R1.sh"
printf 'BAD();\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js scripts/probes/R1.sh
if OUT=$(export CLAUDSOUL_REPO="$R"; cgo 'git commit -m "fix: правка (B1)"'); then bad "C33''" "проба ушла в чужой CLAUDSOUL_REPO — коммит вошёл"
elif grep -qF "не дошла до нуля" <<< "$OUT"; then ok; else bad "C33''" "проба ушла в чужой CLAUDSOUL_REPO, а не в снимок: ${OUT:0:300}"; fi
git -C "$CR" reset -q --hard
# Связанный worktree: git отдаёт ловушке GIT_DIR и GIT_INDEX_FILE, и до снимка они не доходят — коммит «snapshot» не
# ложится ни в одну ветку репозитория, а суд идёт по индексу worktree.
WR="$TMP/wrepo"; git clone -q "$R" "$WR"; bash "$HOOKI" --install "$WR" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_merge_root_gate.sh:$LINENO" >&2; exit 1; }
git -C "$WR" checkout -q --detach; git -C "$WR" worktree add -q "$TMP/wt" main
printf 'module.exports = 64;\n' > "$TMP/wt/src/a.js"; git -C "$TMP/wt" add src/a.js
cden 'git commit -m "fix: правка без пункта"' "W1 worktree: починка без пункта — отказ" "нет пункта" "$TMP/wt"
cok  'git commit -m "fix: правка (B1)"' "W1' worktree: с пунктом — пропуск" "$TMP/wt"
[ "$(git -C "$WR" log --all --format=%s | grep -c '^snapshot$')" = 0 ] && ok || bad "W2" "снимок лёг коммитом «snapshot» в репозиторий worktree"
# GIT_DIR в окружении сухого прогона слияния: снимок ветки не ложится коммитом в настоящий main.
H0=$(git -C "$R" rev-parse HEAD)
OUT=$(export GIT_DIR="$R/.git" GIT_INDEX_FILE="$R/.git/index"; check limited 2>&1)
[ "$(git -C "$R" rev-parse HEAD)" = "$H0" ] && ok || bad "C33''''" "GIT_DIR на сухом прогоне слияния — снимок ветки лёг коммитом в настоящий main"
git -C "$R" reset -q --hard "$H0"

# Ссылка снимка не переписывается насквозь: отслеживаемая ссылка на файл вне репозитория, заменённая в дереве обычным
# файлом, при `git commit -a` своей цели не трогает.
OUTSIDE="$TMP/outside.txt"; printf 'исходное\n' > "$OUTSIDE"
ln -s "$OUTSIDE" "$CR/src/shared.cfg"; git -C "$CR" add src/shared.cfg; git -C "$CR" commit -qm "chore: ссылка"
rm "$CR/src/shared.cfg"; printf 'местное\n' > "$CR/src/shared.cfg"; printf 'module.exports = 70;\n' > "$CR/src/a.js"
cgo 'git commit -a -m "fix: правка (B1)"' >/dev/null
[ "$(cat "$OUTSIDE")" = "исходное" ] && ok || bad "C35" "git commit -a переписал файл вне репозитория сквозь ссылку снимка"
git -C "$CR" reset -q --hard HEAD~1
# Удалённый в дереве файл уходит и из снимка: починка, удаляющая последний носитель, проходит.
printf 'BAD();\n' > "$CR/src/old.js"; git -C "$CR" add src/old.js; git -C "$CR" commit -qm "chore: носитель"
rm "$CR/src/old.js"
cok  'git commit -a -m "fix: удалён носитель (B1)"' "C36 удаление последнего носителя с -a — проба на нуле, пропуск"
git -C "$CR" reset -q --hard HEAD~1
# Глобальные настройки git не ломают снимок: ловушки (core.hooksPath, init.templateDir), autocrlf и safecrlf на
# отслеживаемом CRLF, подпись коммитов. Свои ловушки и подпись репозитория — местной настройкой: глобальная
# core.hooksPath увела бы сам коммит мимо ловушки, а подписывать его нечем; снимок обязан устоять без этих поправок.
GH="$TMP/ghome"; mkdir -p "$GH/hooks" "$GH/tpl/hooks"
printf '#!/bin/sh\nexit 1\n' > "$GH/hooks/reference-transaction"; cp "$GH/hooks/reference-transaction" "$GH/tpl/hooks/"
cp "$GH/hooks/reference-transaction" "$GH/hooks/pre-commit"; chmod +x "$GH"/hooks/* "$GH"/tpl/hooks/*
printf '[core]\n\thooksPath = %s/hooks\n\tautocrlf = input\n\tsafecrlf = true\n[init]\n\ttemplateDir = %s/tpl\n[commit]\n\tgpgsign = true\n[user]\n\tname = t\n\temail = t@t\n' "$GH" "$GH" > "$GH/.gitconfig"
mkdir -p "$CR/docs"; printf 'a\r\nb\r\n' > "$CR/docs/win.txt"; git -C "$CR" add docs/win.txt; git -C "$CR" commit -qm "chore: CRLF"
git -C "$CR" config core.hooksPath "$CR/.git/hooks"; git -C "$CR" config commit.gpgsign false
printf 'module.exports = 71;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
OUT=$(export HOME="$GH"; cgo 'git commit -m "fix: правка (B1)"') && ok \
    || bad "C37" "глобальные ловушки, шаблон, autocrlf/safecrlf или подпись сломали снимок: ${OUT:0:300}"
git -C "$CR" config --unset core.hooksPath; git -C "$CR" config --unset commit.gpgsign
git -C "$CR" reset -q --hard HEAD~1
# Вывод пробы не в UTF-8 — носители по делу, а не «страж упал»: байты заменяет владелец пробы (scripts/root-map.py).
printf '#!/usr/bin/env bash\nprintf "src/a.js:1:\\xbf\\xf3\\n"\n' > "$CR/scripts/probes/R1.sh"
printf 'module.exports = 72;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js scripts/probes/R1.sh
cden 'git commit -m "fix: правка (B1)"' "C38 вывод пробы не в UTF-8 — отказ по носителям, а не падение прибора" "не дошла до нуля"
git -C "$CR" reset -q --hard
# Неучтённые зависимости — у судимого проекта: CLAUDE_PROJECT_DIR пробы — судимый репозиторий, а не проект сессии.
mkdir -p "$CR/node_modules"; printf 'x\n' > "$CR/node_modules/dep.js"
printf '#!/usr/bin/env bash\n[ -f "$CLAUDE_PROJECT_DIR/node_modules/dep.js" ] || exit 2\nexit 0\n' > "$CR/scripts/probes/R1.sh"
printf 'module.exports = 78;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js scripts/probes/R1.sh
OUT=$(export CLAUDE_PROJECT_DIR="$TMP"; cgo 'git commit -m "fix: правка (B1)"') && ok \
    || bad "C44" "проба с неучтённой зависимостью не увидела её у судимого проекта: ${OUT:0:300}"
git -C "$CR" reset -q --hard; rm -r "$CR/node_modules"

# Перенаправления, экраны, два встроенных текста, путь с пробелом.
printf 'module.exports = 73;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git commit -m "fix: правка без пункта" 2>&1 | tail -3' "C40 перенаправление 2>&1 — отказ" -
cden 'git commit -q -m "fix: правка без пункта" > /dev/null' "C40' > /dev/null — отказ" "нет пункта"
cok  'git commit -m "fix(B1): обработка \`null\`"' "C41 экранированная обратная кавычка — буква: пропуск"
cden 'git commit -m "fix: обработка \`null\` без пункта"' "C41' то же без пункта — отказ" "нет пункта"
cok  'git commit -m "chore: версия \$NAME"' "C41'' экранированный \$ — буква: не-починка проходит"
TWO=$(printf '%s\n' "cat > $TMP/notes.txt <<'EOF'" 'fix: старая заметка' 'EOF' "git commit -m \"\$(cat <<'EOF'" 'chore: обычный коммит' 'EOF' ')"')
cok  "$TWO" "C42 два встроенных текста с одним тегом — судится тело сообщения, а не заметки"
cden "${TWO/chore: обычный коммит/fix: правка без пункта}" "C42' то же с починкой без пункта — отказ" "нет пункта"
mkdir -p "$TMP/My Dir"; printf 'fix: старая тема без пункта\n' > "$TMP/My Dir/msg.txt"
cok  "$(printf '%s\n' "cat > \"$TMP/My Dir/msg.txt\" <<'EOF'" 'fix(B1): новая тема' 'EOF' "git commit -F \"$TMP/My Dir/msg.txt\"")" "C43 путь с пробелом в кавычках — судится тело, а не старый файл"
git -C "$CR" reset -q; printf 'module.exports = 74;\n' > "$CR/src/a.js"
cden 'git commit -m "fix: правка без пункта" -- src/a.js 2>/dev/null' "C40'' перенаправление после путей — отказ" -
git -C "$CR" add src/a.js
cden 'git commit -m "fix: правка без пункта" -- 2>/dev/null' "C40''' после -- одно перенаправление — судится индекс: отказ" -
git -C "$CR" reset -q --hard

# --- D1021: форма команды вне любого перечня — суд у git, а не у разбора текста -----------------------------------
printf 'module.exports = 80;\n' > "$CR/src/a.js"
cden 'git add src/a.js && git commit -m "fix: правка без пункта"' "F1 git add && git commit одной командой (D1019) — отказ" "нет пункта"
git -C "$CR" add src/a.js
cden "bash -c \"git commit -q -m 'fix: правка без пункта'\"" "F2 bash -c — отказ" "нет пункта"
cok  "bash -c \"git commit -q -m 'fix: правка (B1)'\"" "F2' bash -c с пунктом — пропуск"
cden "eval \"git commit -q -m 'fix: правка без пункта'\"" "F3 eval — отказ" "нет пункта"
cden 'git commit -q -am"fix: правка без пункта"' "F4 слитное -am\"…\" — отказ" "нет пункта"
cden "$(printf 'git commit \\\n  -m "fix: правка без пункта"')" "F5 перенос строки \\\\ — отказ" "нет пункта"
cden 'if true; then git commit -m "fix: правка без пункта"; fi' "F6 if/then перед git — отказ" "нет пункта"
cden "cd /; GIT_DIR='$CR/.git' GIT_WORK_TREE='$CR' git commit -m 'fix: правка без пункта'" "F7 GIT_DIR=… git commit из чужого каталога — отказ" "нет пункта"
# Сообщение из редактора: строки-комментарии сняты, как у git, — пункт в комментарии не назван, комментарий над темой
# темой не считается.
printf '#!/bin/sh\nprintf "fix: правка без пункта\\n# пункт (B1) — в комментарии\\n" > "$1"\n' > "$TMP/ed.sh"
printf '#!/bin/sh\nprintf "# заметка\\nfix: правка (B1)\\n" > "$1"\n' > "$TMP/ed2.sh"; chmod +x "$TMP/ed.sh" "$TMP/ed2.sh"
cden "GIT_EDITOR=$TMP/ed.sh git commit" "F8 редактор, пункт только в комментарии — отказ" "нет пункта"
cok  "GIT_EDITOR=$TMP/ed2.sh git commit" "F8' редактор, комментарий над темой снят — пропуск"
git -C "$CR" reset -q --hard
# Коммит незаконченного слияния судится, как любой: слияние судило ветку, а в индекс после него кладут и свой код
# (скептик D1021). Тема «Merge …» — не починка.
git -C "$CR" checkout -q -b conflict; printf 'module.exports = 90;\n' > "$CR/src/a.js"; git -C "$CR" commit -qam "chore: ветка"
git -C "$CR" checkout -q main; printf 'module.exports = 91;\n' > "$CR/src/a.js"; git -C "$CR" commit -qam "chore: main"
git -C "$CR" merge -q conflict >/dev/null 2>&1 || true; printf 'module.exports = 92;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git commit -m "fix: слияние без пункта"' "F9 незаконченное слияние, тема починки без пункта — отказ" "нет пункта"
cok  'git commit --no-edit' "F9' незаконченное слияние с темой «Merge …» — не починка, входит"
git -C "$CR" merge --abort 2>/dev/null || true; git -C "$CR" reset -q --hard HEAD~1  # конфликт слияния ожидаем, abort после завершённого — тоже (D1219)
# Очистка сообщения: режим git ловушке не сообщает, сообщение читается дважды. `core.commentChar=f` без редактора —
# git тему сохраняет, ловушка тоже; пункт только в строке «#» без редактора назван не в каждом прочтении — отказ
# (сознательно: git эту строку сохранит, но пункт в комментарии — не заявка).
printf 'module.exports = 93;\n' > "$CR/src/a.js"; git -C "$CR" add src/a.js
cden 'git -c core.commentChar=f commit -m "fix: правка без пункта"' "F10 core.commentChar=f — тема не съедена, отказ" "нет пункта"
cok  'git -c core.commentChar=f commit -m "fix: правка (B1)"' "F10' core.commentChar=f с пунктом — пропуск"
cden "$(printf 'git commit -m "fix: правка\n# (B1)"')" "F10'' пункт только в строке «#» — назван не в каждом прочтении, отказ" "нет пункта"
git -C "$CR" reset -q --hard
# Сокращение `--amen`, которое git принимает: основа — HEAD^, код переписываемого коммита судится.
printf 'module.exports = 94;\n' > "$CR/src/a.js"; git -C "$CR" commit -qam "feat: код"
cden 'git commit --amen -m "fix: правка без пункта"' "F11 --amen — сокращение --amend, отказ" "нет пункта"
git -C "$CR" reset -q --hard HEAD~1

# --- PreToolUse на коммите (D1021): обход ловушки ловится по слову, судимый main без ловушки — отказ -------------
phook() { hook "$1" "${2:-$CR}"; }
pden() { local o; o=$(phook "$1" "${4:-}"); if denied "$o" && grep -qF -- "$3" <<< "$o"; then ok; else bad "$2" "ожидался отказ с «$3»: ${o:0:300}"; fi; }
pok()  { assert_silent "$(phook "$1" "${3:-}")" "$2"; }
pok  'git commit -m "fix: правка без пункта"' "P0 ловушка стоит — PreToolUse молчит, судит git"
pden 'git commit --no-verify -m "chore: учёт"' "P1 --no-verify — отказ" "обходит ловушку"
pden 'git commit -nm "chore: учёт"' "P1' слитное -nm — отказ" "обходит ловушку"
pok  'git commit -mn' "P1'' -mn: n — текст сообщения, а не ключ — молчание"
pden 'git -c core.hooksPath=/dev/null commit -m "chore: учёт"' "P1''' core.hooksPath в вызове — отказ" "обходит ловушку"
pden "bash -c 'git commit --no-verify -m x'" "P1'''' --no-verify внутри bash -c — отказ по слову" "обходит ловушку"
# D1342: коммит с обходом ВНУТРИ `bash -c` судится в СВОЁМ каталоге, а не в каталоге команды: каталог вложенного
# коммита даёт владелец разбора команд. Чужой каталог и каталог из переменной — не «коммит в main» (так же судится тот
# же коммит после `cd` снаружи); `cd` или `-C` в сам судимый репозиторий — отказ, как прежде.
mkdir -p "$TMP/elsewhere" && git -C "$TMP/elsewhere" init -q \
    || { echo "подготовка мира не удалась: hooks/tests/test_merge_root_gate.sh:$LINENO" >&2; exit 1; }
pok  "bash -c 'cd \"$TMP/elsewhere\" && git commit --no-verify -qm init --allow-empty'" "P1m обход внутри bash -c в чужом каталоге — не коммит в main: молчание"
pok  "bash -c 'R=\$(mktemp -d); cd \"\$R\" && git init -q . && GIT_CONFIG_COUNT=0 git commit -qm init --allow-empty'" "P1n обход внутри bash -c, каталог из переменной — как после cd снаружи: молчание"
pok  "R=\$(mktemp -d); cd \"\$R\" && git init -q . && GIT_CONFIG_COUNT=0 git commit -qm init --allow-empty" "P1n' тот же коммит без bash -c — молчание (образец для P1n)"
pden "bash -c 'cd \"$CR\" && git commit --no-verify -m x'" "P1o обход внутри bash -c с cd в судимый репозиторий — отказ" "обходит ловушку"
pden "cd \"$TMP/elsewhere\" && bash -c 'git -C \"$CR\" commit --no-verify -m x'" "P1p обход внутри bash -c с -C в судимый репозиторий — отказ" "обходит ловушку"
# Скептик opus по db409435 (D1342): послабление — только доказуемая форма (один вызов `bash -c`, `cd <цель> && …`, цель —
# литеральный абсолютный путь либо переменная из `$(mktemp -d)`, звенья из разрешённых программ). Всё остальное — отказ
# в каталоге команды, как прежде: первая починка пропускала каждую из форм ниже.
pden "cd .. && bash -c 'cd ${CR##*/} && git commit --no-verify -m x'" "P1q внешний cd до bash -c и относительный cd внутри — отказ" "обходит ловушку"
pden "bash -c 'cd \"\$HOME/${CR##*/}\" && git commit --no-verify -m x'" "P1r каталог через \$HOME внутри bash -c — отказ" "обходит ловушку"
pden "bash -c 'R=\$(mktemp -d); R=\"$CR\"; cd \"\$R\" && git commit --no-verify -m x'" "P1s переменная mktemp переприсвоена — отказ" "обходит ловушку"
pden "bash -c 'cd \"$TMP/elsewhere\" && cd \"$CR\" && git commit --no-verify -m x'" "P1t второй cd в цепочке — отказ" "обходит ловушку"
pden "bash -c 'cd \"$TMP/elsewhere\"; git commit --no-verify -m x'" "P1u точка с запятой после cd (сбой cd не оборвёт цепочку) — отказ" "обходит ловушку"
pden "bash -c 'cd \"$TMP/elsewhere\" && GIT_DIR=\"$CR/.git\" git commit --no-verify -m x'" "P1v GIT_DIR в звене — отказ" "обходит ловушку"
pden "bash -c 'cd \"$TMP/elsewhere\" && python3 -c \"import os\" && git commit --no-verify -m x'" "P1w звено с интерпретатором — отказ" "обходит ловушку"
pden "bash -c 'cd \"$TMP/elsewhere\" && git commit --no-verify -m x'; true" "P1x соседняя команда после bash -c — отказ" "обходит ловушку"
pden "bash -c 'R=\$(mktemp -d \"$CR/tXXXX\"); cd \"\$R\" && git commit --no-verify -m x'" "P1y mktemp с шаблоном внутри репозитория — отказ" "обходит ловушку"
# D1025: команда git, которая не коммит, со словами «commit» и `--no-verify` в аргументах — не обход; глобальные ключи
# с путём в кавычках (в том числе экранированных) между `git` и `commit` форму обхода не прячут.
pok  "git grep -n -E 'commit[^|]*(--no-verify|-n )' -- src" "P1g git grep с образцом про обход — не коммит: молчание"
pden "bash -c 'git -c \"user.name=a b\" commit --no-verify -m x'" "P1h ключ со значением в кавычках внутри bash -c — отказ" "обходит ловушку"
pden "bash -c \"git -c \\\"user.name=a b\\\" commit --no-verify -m x\"" "P1i значение в экранированных кавычках — отказ" "обходит ловушку"
# Широта «git … commit» — страховка поверх разборщика: незнакомый глобальный ключ он не разбирает (скептик D1025 —
# сужение запасного разбора до перечня ключей открыло эти формы).
pden 'git --no-optional-locks commit --no-verify -m "fix: x"' "P1j незнакомый глобальный ключ перед commit — отказ" "обходит ловушку"
pden "bash -c 'git -p commit --no-verify -m x'" "P1k -p в bash -c — отказ" "обходит ловушку"
# Значение ключа, взятое словом, — не подкоманда: `--namespace log` не делает вхождение читающим (скептик D1025, вторая
# редакция).
pden 'git --namespace log -c core.hooksPath=/dev/null commit -m "fix: x"' "P1l значение ключа словом «log» — отказ" "обходит ловушку"
pok  'git --no-pager log --grep commit --no-verify' "P1m ключ разборщика перед читающей подкомандой — молчание"
pok  "$(printf '%s\n' "git commit -F - <<'EOF'" 'chore: о ключе --no-verify' 'EOF')" "P1''''' слово в теле встроенного текста — данные: молчание"
pok  'git commit --no-verify -m "chore: учёт"' "P1'''''' проект без карты — обход не судится" "$NR"
NT="$TMP/notrap"; git clone -q "$R" "$NT"
pden 'git commit -m "chore: учёт"' "P2 судимый main без ловушки — отказ с командой установки" "--install" "$NT"
pden 'git status; git commit -m "chore: учёт"; echo "x' "P2' неразобранная команда коммита в main без ловушки — отказ" "--install" "$NT"
git -C "$NT" checkout -q -b dev
pok  'git commit -m "chore: учёт"' "P2'' без ловушки, ветка не main — молчание" "$NT"
git -C "$NT" checkout -q main; bash "$HOOKI" --install "$NT" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_merge_root_gate.sh:$LINENO" >&2; exit 1; }
pok  'git commit -m "chore: учёт"' "P2''' ловушка поставлена — молчание" "$NT"
# Находки скептика D1021: формы обхода, которые git принимает, и ложные отказы командам, которые не коммит.
pden 'git commit --no-verif -m "chore: учёт"' "P3 --no-verif — сокращение, git его принимает: отказ" "обходит ловушку"
pden 'git -c core.hookspath=/dev/null commit -m "chore: учёт"' "P3' core.hookspath строчными — отказ" "обходит ловушку"
pden "GIT_CONFIG_GLOBAL=$TMP/cfg git commit -m 'chore: учёт'" "P3'' GIT_CONFIG_GLOBAL перед коммитом — отказ" "обходит ловушку"
pden "HOME=$TMP git commit -m 'chore: учёт'" "P3''' HOME перед коммитом — отказ" "обходит ловушку"
pden "export GIT_CONFIG_COUNT=1; git commit -m 'chore: учёт'" "P3'''' export GIT_CONFIG_* — отказ" "обходит ловушку"
pok  "HOME=$TMP bash -c true; git commit -m 'chore: учёт'" "P3''''' HOME у другой команды — до git не доходит: молчание"
pden "git -c alias.ci='commit -n' ci -m 'chore: учёт'" "P4 псевдоним -c alias с обходом — отказ" "обходит ловушку"
pden "git config alias.ci 'commit -n'" "P4' git config alias с обходом — отказ" "обходит ловушку"
pok  "git config alias.st status" "P4'' псевдоним без коммита — молчание"
pok  "grep -n 'hooksPath\\|commit-msg' hooks/merge-root-gate.sh" "P5 grep по словам — не коммит: молчание"
pok  "git config --get core.hooksPath; ls .git/hooks/commit-msg" "P5' чтение настройки и имя commit-msg — молчание"
pok  "grep -c -- --no-verify hooks/x.sh; git commit -q -m 'docs: x'" "P5'' слово в grep рядом с законным коммитом — молчание"
pok  "git commit -q -uno -m 'feat: x'" "P5''' -uno: n — значение -u, а не ключ — молчание"
pok  "git commit -q -m 'feat: x' && git log -n 3" "P5'''' -n у git log — молчание"
pok  'git merge origin/good' "P6 проходящее слияние в судимом main — молчание, а не падение стража"

# --- --install: чужую ловушку не переписывает, повтор на месте, исчезнувший страж — молчание ----------------------
FT="$TMP/foreign"; git clone -q "$R" "$FT"; printf '#!/bin/sh\nexit 0\n' > "$FT/.git/hooks/commit-msg"; chmod +x "$FT/.git/hooks/commit-msg"
bash "$HOOK" --install "$FT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$FT/.git/hooks/commit-msg")" = "$(printf '#!/bin/sh\nexit 0')" ] && ok \
    || bad "I1" "чужая ловушка commit-msg переписана или код не 2 (код $rc)"
bash "$HOOK" --install "$CR" >/dev/null 2>&1 && grep -q claudsoul-merge-root-gate "$CR/.git/hooks/commit-msg" && ok \
    || bad "I2" "повторная установка своей ловушки не прошла"
# Путь стража с пробелом и апострофом: ловушка его зовёт (судит), а исчезнувший страж — «инструмента нет».
Q="$TMP/it's my dir"; mkdir -p "$Q"; cp "$HOOK" "$HOOKS_DIR"/commit-trap.sh "$HOOKS_DIR"/paths-lib.sh "$HOOKS_DIR"/backlog-lib.sh "$HOOKS_DIR"/command-scope-lib.sh "$Q/"
GT="$TMP/gonegate"; git clone -q "$R" "$GT"; bash "$Q/merge-root-gate.sh" --install "$GT" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_merge_root_gate.sh:$LINENO" >&2; exit 1; }
printf 'module.exports = 95;\n' > "$GT/src/a.js"; git -C "$GT" add src/a.js
cden 'git commit -m "fix: правка без пункта"' "I3 путь стража с пробелом и апострофом — ловушка судит" "нет пункта" "$GT"
rm "$Q/merge-root-gate.sh"
cok  'git commit -m "fix: правка без пункта"' "I3' страж удалён — ловушка молчит («инструмента нет»), коммит входит" "$GT"
# Совет установки при чужой ловушке исполним дословно: дописанная строка судит, PreToolUse её узнаёт, а `--amend`
# узнаётся у деда (родитель стража — оболочка чужой ловушки).
LINE=$(bash "$HOOK" --install "$FT" 2>&1 | grep 'commit-msg — не переписываю' | sed 's/.*строку: //')
printf '#!/bin/sh\n%s\nexit 0\n' "$LINE" > "$FT/.git/hooks/commit-msg"
pok  'git commit -m "chore: учёт"' "I4 строка совета в чужой ловушке — PreToolUse узнаёт ловушку" "$FT"
printf 'module.exports = 96;\n' > "$FT/src/a.js"; git -C "$FT" add src/a.js
cden 'git commit -m "fix: правка без пункта"' "I4' дописанная строка судит" "нет пункта" "$FT"
git -C "$FT" commit -qm "feat: код"
cden 'git commit --amend -m "fix: правка без пункта"' "I4'' --amend в чужой ловушке узнаётся у деда — отказ" "нет пункта" "$FT"
# core.hooksPath на каталог внутри рабочего дерева: шим лёг бы файлом проекта — установка отказывает.
HP="$TMP/hp"; git clone -q "$R" "$HP"; git -C "$HP" config core.hooksPath .githooks
bash "$HOOK" --install "$HP" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -e "$HP/.githooks/commit-msg" ] && ok || bad "I5" "ловушка легла в каталог внутри рабочего дерева (код $rc)"

echo "test_merge_root_gate: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
