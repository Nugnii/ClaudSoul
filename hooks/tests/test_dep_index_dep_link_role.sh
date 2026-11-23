#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py scripts/dep-index.py
# test_dep_index_dep_link_role.sh — связь «зависит от», связь носителя и признак рода A
# держатся на строке КОДА, а не на упоминании имени в комментарии (D284, родня D279/D272).
#
# Механика. D279 снял роль строки у ОДНОГО из четырёх корпусов — колонки тестов. Три
# остальных читали файл целиком: `deps_of` (рёбер «зависит от» 666, из них 274 держались
# только на комментарии), `carrier_corpus` в `impact()` (связей 98, комментарных 4),
# `carriers_a()` в scripts/defect-class-carriers.py (носителей 19, ложных 2 — прибор при
# этом печатает СВОЮ ТОЧНОСТЬ, то есть врёт о себе). Замеры 6 сентября 2026.
#
# У проверки ПОЛ и ПОТОЛОК. Потолок (D1, D4, D6) ловит связь, держащуюся на комментарии;
# пол (D2, D3, D5, D7, D8, D9) — потерянную настоящую. Без пола проходит переснятие
# «связей не считать вовсе».
#
# D8 — отдельная нога и она названа ПО ПРОМАХУ: слепое снятие комментариев во ВСЕХ
# признаках рода A теряет живого носителя scripts/regen-readme-skills.sh, у которого
# awk-извлечение стоит в коде, а слово «frontmatter» — только в комментарии шапки.
# Признак дефекта судится по коду, документальная примета — по всему тексту: у них разная
# роль, и одинаково их сузить значит завести ложное отрицание вместо ложного срабатывания.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
GENERA="$REPO/scripts/defect-class-carriers.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; R="$TMP/repo"
mkdir -p "$R/hooks" "$R/scripts" "$R/launchd" "$R/docs"
cp "$INDEXER" "$R/scripts/dep-index.py"; cp "$GENERA" "$R/scripts/defect-class-carriers.py"
printf '#!/usr/bin/env bash\ntrue\n' > "$R/install.sh"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
for m in beta gamma delta epsilon zeta; do
    printf '#!/usr/bin/env bash\n%s_one() { :; }\n' "$m" > "$R/hooks/$m.sh"
done
# alpha зовёт gamma КОДОМ, beta называет только в комментарии, delta пишет строкой с `#`.
cat > "$R/hooks/alpha.sh" <<'SH'
#!/usr/bin/env bash
# рядом живёт hooks/beta.sh, но мы его не зовём
. "$(dirname "$0")/gamma.sh"
printf '#!/usr/bin/env bash\n' > "$T/hooks/delta.sh"
SH
# Носители: конфигурация, не механизм. epsilon — только в комментарии, zeta — в данных.
printf '# расписание для hooks/epsilon.sh — историческая справка\nзапуск\thooks/zeta.sh\t7\n' \
    > "$R/launchd/schedule.tsv"
# Род A: признак в комментарии (ложный), в коде (настоящий), примета только в прозе.
# Имя поля подставляется через %s, а не пишется литералом: литерал сделал бы носителем
# рода A сам этот тест — проверка растила бы очередь, которую проверяет.
printf '#!/usr/bin/env bash\n# читаем шапку так: awk "/^%s:/ {print}" — про frontmatter\ngrep -q x "$1"\n' \
    name > "$R/hooks/only-comment.sh"
printf '#!/usr/bin/env bash\n# честный читатель frontmatter\nawk "/^%s:/ { print }" "$1"\n' \
    name > "$R/hooks/real-code.sh"
printf '#!/usr/bin/env bash\n# читатель frontmatter скиллов (примета только тут)\nawk "/^%s:/ { print }" "$1"\n' \
    description > "$R/hooks/prose-hint.sh"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_dep_index_dep_link_role.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_dep_index_dep_link_role.sh:$LINENO" >&2; exit 1; }
IDX="$R/.claude-docs/dep-index.tsv"
run() { ( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py "$@" ) ; }
genus() { ( cd "$R" && python3 scripts/defect-class-carriers.py --genus A 2>&1 ) ; }
run --all >/dev/null 2>&1 || { echo "FAIL: базовая сборка не прошла"; exit 1; }
deps() { grep "^hooks/alpha\.sh	" "$IDX" | cut -f3; }

# --- deps_of: потолок и пол --------------------------------------------------------------
if ! grep -q "beta" <<< "$(deps)"; then
    ok "D1 имя в комментарии механизма ребром «зависит от» не считается"
else
    bad "D1" "alpha называет beta только в комментарии, deps: [$(deps)]"
fi
if grep -q "gamma" <<< "$(deps)"; then
    ok "D2 вызов в строке кода ребром остаётся"
else
    bad "D2" "deps alpha: [$(deps)]"
fi
if grep -q "delta" <<< "$(deps)"; then
    ok "D3 строка кода с решёткой ВНУТРИ (printf '#!…') ребром остаётся"
else
    bad "D3" "deps alpha: [$(deps)]"
fi

# --- carrier_corpus в impact(): потолок и пол --------------------------------------------
OUT=$(run --impact hooks/epsilon.sh 2>&1)
if ! grep -q "launchd/schedule.tsv" <<< "$OUT"; then
    ok "D4 имя в комментарии носителя зависимостью не считается"
else
    bad "D4" "вывод: $OUT"
fi
OUT=$(run --impact hooks/zeta.sh 2>&1)
if grep -q "launchd/schedule.tsv" <<< "$OUT"; then
    ok "D5 имя в строке данных носителя зависимостью остаётся"
else
    bad "D5" "вывод: $OUT"
fi

# --- род A в реестре родов: потолок и два пола -------------------------------------------
G=$(genus)
if ! grep -q "only-comment.sh" <<< "$G"; then
    ok "D6 признак рода A в комментарии носителем не делает"
else
    bad "D6" "$(printf '%s' "$G" | grep only-comment)"
fi
if grep -q "real-code.sh" <<< "$G"; then
    ok "D7 признак рода A в строке кода носителем оставляет"
else
    bad "D7" "род A: $(printf '%s' "$G" | head -1)"
fi
if grep -q "prose-hint.sh" <<< "$G"; then
    ok "D8 документальная примета в комментарии носителя не теряет"
else
    bad "D8" "род A: $(printf '%s' "$G" | head -1) — потерян живой носитель (адрес класса: scripts/regen-readme-skills.sh)"
fi

# --- живое дерево: потолок и пол числом --------------------------------------------------
LIVE=$(cd "$REPO" && python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
di = importlib.util.module_from_spec(spec); spec.loader.exec_module(di)
mech = di.mechanisms(); ms = set(mech)
tot = com = 0
for m in mech:
    t = di.read(m)
    full = set(di.deps_of(m, t, ms))
    code = set(di.deps_of(m, di.code_only(t), ms))
    tot += len(code); com += len(full - code)
print(tot, com)
PY
) || LIVE=""
if [ -n "$LIVE" ]; then
    TOT=$(printf '%s' "$LIVE" | awk '{print $1}'); COM=$(printf '%s' "$LIVE" | awk '{print $2}')
    if [ "$TOT" -ge 300 ]; then
        ok "D9 живое дерево: рёбер на строках кода $TOT — корпус не схлопнут"
    else
        bad "D9" "рёбер на строках кода всего $TOT (было 392 на 6 сентября 2026)"
    fi
    echo "     (справочно: рёбер, державшихся только на комментарии, было $COM)"
fi
LIVEIDX=$(cd "$REPO" && python3 - <<'PY'
import os
R = [l.rstrip().split("\t") for l in open(".claude-docs/dep-index.tsv") if l.strip() and not l.startswith("# ")]
code = lambda t: "\n".join(l for l in open(t, errors="ignore").read().split("\n") if not l.lstrip().startswith("#"))
bad = sum(1 for r in R if len(r) > 2 for d in [x.strip() for x in r[2].split(",") if x.strip()]
          if os.path.exists(r[0])
          and os.path.basename(d).rsplit(".", 1)[0] in open(r[0], errors="ignore").read()
          and os.path.basename(d).rsplit(".", 1)[0] not in code(r[0]))
print(bad)
PY
) || LIVEIDX=""
if [ "$LIVEIDX" = "0" ]; then
    ok "D10 записанный индекс: рёбер, держащихся только на комментарии, нет"
else
    bad "D10" "в .claude-docs/dep-index.tsv таких рёбер $LIVEIDX"
fi

# D11: ДОКСТРИНГ .py — ПРОЗА. Библиотека перечисляет в шапке своих потребителей и получала
# ребро НАЗАД к каждому: связь замыкалась в кольцо, которого в исполнении нет. Замер
# 13 сентября 2026: из 66 рёбер «зависит от» у .py-файлов 45 (68%) держались только на
# докстринге; после починки колец в карте связей стало 25 вместо 58. Прежняя редакция цену
# ЗНАЛА («docstring-связей на дереве 7»), но сверщика у числа не было, и оно уплыло вшестеро.
# Правило берётся У ВЛАДЕЛЬЦА (`code_only` самого прибора), а не переписывается здесь:
# копия правила у потребителя — род K, и она разошлась бы молча.
DOCIDX=$(cd "$REPO" && python3 - <<'DOCPY'
import os, importlib.util
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
di = importlib.util.module_from_spec(spec); spec.loader.exec_module(di)
rows = [l.rstrip().split(chr(9)) for l in open(".claude-docs/dep-index.tsv") if l.strip() and not l.startswith("# ")]
bad = 0
for r in rows:
    if len(r) < 3 or not r[0].endswith(".py") or not os.path.exists(r[0]):
        continue
    code = di.code_only(open(r[0], errors="ignore").read(), True)
    # Ребро по импорту (шаг 1в) держится на `from brain import …`, где имени файла нет, — его правило тоже у владельца.
    imported = di.import_deps(r[0], code)
    for d in [x.strip() for x in r[2].split(",") if x.strip()]:
        if os.path.basename(d) not in code and d not in imported:
            bad += 1
print(bad)
DOCPY
) || DOCIDX=""
if [ "$DOCIDX" = "0" ]; then
    ok "D11 записанный индекс: рёбер, держащихся только на докстринге .py, нет"
else
    bad "D11" "в .claude-docs/dep-index.tsv рёбер на прозе докстринга: $DOCIDX"
fi
echo ""
echo "dep-index dep-link-role: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
