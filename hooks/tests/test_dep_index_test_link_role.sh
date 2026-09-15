#!/usr/bin/env bash
# test_dep_index_test_link_role.sh — связь «механизм → тест» в индексе зависимостей держится
# на строке КОДА теста, а не на упоминании имени в комментарии (D279).
#
# Механика. `build()` подавал в `mentions()` полный текст теста, и роль строки в вердикт не
# входила: комментарий прувера делал прувер тестом названного там хука. Замер 3 сентября
# 2026 на боевом дереве: связей «механизм → тест» 838, из них 227 держались исключительно
# на строке-комментарии (regex прибора; одна-строка пункта, сверяющая подстрокой, даёт 211),
# у четырёх механизмов — все до одной. Тот же корень, что D272, в другом механизме.
#
# У проверки есть ПОЛ и ПОТОЛОК, и оба нужны: потолок (R2, R2py, R3, R4) ловит лишние связи,
# пол (R1, R1b, R6) — потерянные. Без пола проходит переснятие «выкинуть любую строку с #»,
# которое теряет 10 настоящих связей вида `printf '#!/usr/bin/env bash…' > …`.
#
# КОНТРПРИМЕР: docstring в .py-тесте кодом считается — замер 3 сентября 2026: таких связей 7,
# и это известно.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; R="$TMP/repo"
mkdir -p "$R/hooks/tests" "$R/.claude-docs" "$R/scripts" "$R/docs" "$R/mcp-server/tests"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
for m in alpha beta gamma delta epsilon zeta; do
    printf '#!/usr/bin/env bash\n%s_one() { :; }\n' "$m" > "$R/hooks/$m.sh"
done
# R1/R2: тест зовёт alpha кодом, beta называет ТОЛЬКО в комментарии — форма прувера (D272).
printf '#!/usr/bin/env bash\n# проверяет beta, см. hooks/beta.sh\nbash "$R/hooks/alpha.sh"\n' \
    > "$R/hooks/tests/test_call.sh"
# R3: gamma названа только в комментариях — в шапке и с отступом внутри if.
printf '#!/usr/bin/env bash\n# см. hooks/gamma.sh\nif true; then\n    # и здесь gamma.sh\n    true\nfi\n' \
    > "$R/hooks/tests/test_comment.sh"
# R1b: две формы строки КОДА, содержащей символ `#` — хвостовой комментарий и # внутри строки.
printf '#!/usr/bin/env bash\nbash "$R/hooks/delta.sh"   # запуск\n' \
    > "$R/hooks/tests/test_hash_tail.sh"
printf '#!/usr/bin/env bash\nprintf %%s "#!/bin/sh" > "$T/hooks/epsilon.sh"\n' \
    > "$R/hooks/tests/test_hash_in_string.sh"
# R2py: тот же дефект в .py-тесте — на боевом дереве их 26, и симптома там сегодня нет.
printf '# zeta.sh проверяется отдельно\nimport os\nos.system("true")\n' \
    > "$R/mcp-server/tests/test_py_comment.py"
# R5: документ называет механизм ТОЛЬКО в заголовке (# в markdown — заголовок, не комментарий).
printf '# Хук alpha.sh\n\nописание.\n' > "$R/docs/alpha.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )
col()  { grep "^hooks/$1\.sh	" "$R/.claude-docs/dep-index.tsv" | cut -f5; }
dcol() { grep "^hooks/$1\.sh	" "$R/.claude-docs/dep-index.tsv" | cut -f4; }

# --- ПОЛ: строка кода связывает --------------------------------------------------------
if [ "$(col alpha)" = "hooks/tests/test_call.sh" ]; then
    ok "R1 тест, зовущий механизм кодом, связан с ним"
else
    bad "R1" "test_call.sh зовёт bash \"\$R/hooks/alpha.sh\", колонка tests alpha: [$(col alpha)]"
fi
if [ "$(col delta)" = "hooks/tests/test_hash_tail.sh" ]; then
    ok "R1b-1 строка кода с хвостовым комментарием связью остаётся"
else
    bad "R1b-1" "test_hash_tail.sh зовёт delta.sh строкой с хвостовым #, колонка tests delta: [$(col delta)]"
fi
if [ "$(col epsilon)" = "hooks/tests/test_hash_in_string.sh" ]; then
    ok "R1b-2 строка кода с # внутри строки связью остаётся"
else
    bad "R1b-2" "test_hash_in_string.sh пишет epsilon.sh, колонка tests epsilon: [$(col epsilon)]"
fi
if [ "$(dcol alpha)" = "docs/alpha.md" ]; then
    ok "R5 заголовок markdown связью docs остаётся — снятие # не касается документов"
else
    bad "R5" "docs/alpha.md называет alpha.sh в заголовке, колонка docs alpha: [$(dcol alpha)]"
fi
# --- ПОТОЛОК: комментарий не связывает --------------------------------------------------
if [ -z "$(col beta)" ]; then
    ok "R2 имя в комментарии .sh-теста связью не считается"
else
    bad "R2" "test_call.sh называет beta только в комментарии, колонка tests beta: [$(col beta)]"
fi
if [ -z "$(col zeta)" ]; then
    ok "R2py имя в комментарии .py-теста связью не считается"
else
    bad "R2py" "test_py_comment.py называет zeta только в комментарии, колонка tests zeta: [$(col zeta)]"
fi
if [ -z "$(col gamma)" ]; then
    ok "R3 комментарий с отступом связью не считается"
else
    bad "R3" "test_comment.sh называет gamma только в комментариях, колонка tests gamma: [$(col gamma)]"
fi
# --- R7: путь «--changed <механизм>» считает те же связи, что полная пересборка ----------
printf '#!/usr/bin/env bash\nbeta_one() { :; }\n# hooks/beta.sh правлен\n' > "$R/hooks/beta.sh"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm ch >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --changed hooks/beta.sh >/dev/null )
if [ -z "$(col beta)" ]; then
    ok "R7 пересборка изменённого механизма не возвращает комментарную связь"
else
    bad "R7" "после --changed hooks/beta.sh колонка tests beta: [$(col beta)]"
fi

# --- Боевое дерево, только чтение: R4 (потолок) и R6 (пол) -------------------------------
LIVE=$(cd "$REPO" && python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
di = importlib.util.module_from_spec(spec); spec.loader.exec_module(di)
import re, subprocess
rows = di.build()
def code(t, is_py=False):
    # ОПРЕДЕЛЕНИЕ ЗДЕСЬ НАМЕРЕННО СВОЁ, а не взятое у прибора: иначе сужение корпуса в
    # приборе согласованно уменьшило бы обе стороны сверки и прошло бы молча. Поэтому
    # договор меняется здесь ОТДЕЛЬНЫМ решением — 13 сентября 2026 к строкам-комментариям
    # добавлены докстринги .py: библиотека, перечислившая в шапке потребителей, получала
    # ребро назад, и 45 из 66 рёбер «зависит от» у .py держались только на прозе. По
    # корпусу ТЕСТОВ та же правка сняла 11 связей, и каждая осмотрена: прозаические
    # упоминания вида «Мгновенную реакцию даёт хук X» и строки «Применение:» — тест такой
    # механизм не трогает. Прежняя редакция цену знала числом («docstring-связей 7») и
    # сверщика ему не имела.
    out, doc = [], None
    for l in t.split(chr(10)):
        st = l.lstrip()
        if doc is not None:
            if doc in st: doc = None
            continue
        if st.startswith("#"): continue
        if is_py:
            m = re.match(r"^[A-Za-z]*(" + chr(34)*3 + "|" + chr(39)*3 + ")", st)
            if m:
                if m.group(1) not in st[m.end():]: doc = m.group(1)
                continue
        out.append(l)
    return chr(10).join(out)
# Универсум тестов считается ТУТ, а не берётся у прибора: сужение корпуса в приборе иначе
# согласованно уменьшило бы обе стороны сверки и прошло бы незамеченным.
# Флаги те же, что у `tracked()` прибора, и это не заимствование, а определение дерева:
# под учётом ПЛЮС новые незакоммиченные. Голый `git ls-files` даёт ложную красноту в
# рабочем дереве — замер 3 сентября 2026: 346 под учётом против 349 в дереве (три ещё не
# добавленных теста), R8 краснел бы не по своей причине, а R4 считал бы лишними связи
# новых тестов.
tracked = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, text=True).stdout.splitlines()
mine = sorted(p for p in tracked if p.endswith((".sh", ".py")) and re.search(r"(^|/)tests?/", p))
corpus = [(t, code(di.read(t), t.endswith(".py"))) for t in mine]
seen = {}
for p in rows: seen[os.path.basename(p)] = seen.get(os.path.basename(p), 0) + 1
amb = {n for n, c in seen.items() if c > 1}
extra = []; missing = []
for p, r in rows.items():
    have = set(di.split_list(r[4]))
    want = set(di.mentions(os.path.basename(p), corpus, p, amb))
    extra += ["%s<-%s" % (p, t) for t in sorted(have - want)]
    missing += ["%s<-%s" % (p, t) for t in sorted(want - have)]
print("%d %d %d %d %s | %s" % (len(extra), len(missing), len(mine), len(di.tests()),
                               ",".join(extra[:3]) or "-", ",".join(missing[:3]) or "-"))
PY
) || { bad "R4/R6" "замер на боевом дереве не выполнился"; LIVE=""; }
if [ -n "$LIVE" ]; then
    EX=$(printf '%s' "$LIVE" | awk '{print $1}'); MI=$(printf '%s' "$LIVE" | awk '{print $2}')
    UNI=$(printf '%s' "$LIVE" | awk '{print $3}'); COR=$(printf '%s' "$LIVE" | awk '{print $4}')
    WHO=$(printf '%s' "$LIVE" | cut -d' ' -f5-)
    if [ "$UNI" = "$COR" ]; then
        ok "R8 корпус тестов прибора совпадает с учтёнными тестами дерева ($COR)"
    else
        bad "R8" "прибор берёт $COR тестов, в дереве учтено $UNI — корпус сужен"
    fi
    if [ "$EX" -eq 0 ]; then
        ok "R4 боевое дерево: лишних связей (держатся на комментарии) нет"
    else
        bad "R4" "боевое дерево: лишних связей $EX — $WHO"
    fi
    if [ "$MI" -eq 0 ]; then
        ok "R6 боевое дерево: потерянных связей (имя в строке кода) нет"
    else
        bad "R6" "боевое дерево: потеряно связей $MI — $WHO"
    fi
fi

echo ""
echo "dep-index test-link-role: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
