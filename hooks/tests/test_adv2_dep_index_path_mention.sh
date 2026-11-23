#!/usr/bin/env bash
# СУДИТ: scripts/dep-index.py
# test_adv2_dep_index_path_mention.sh — документ, который называет механизм ПОЛНЫМ ПУТЁМ
# («**Файлы.** `hooks/co-cognition-lib.sh`»), в индексе с этим механизмом не связывается.
#
# Механика. `mentions()` ищет имя без расширения с отрицательным просмотром назад
#     (?<![A-Za-z0-9_./-])
# В этот запрет входит СЛЭШ. Значит `alpha` в тексте `hooks/alpha.sh` не совпадает никогда:
# перед именем стоит `/`. Совпадает только голое `alpha.sh` или голое `alpha`.
#
# Почему это не мелочь: путь от корня — канонический способ сослаться на файл, и именно им
# пользуются модульные доки («**Файлы.** `hooks/X.sh`»), мосты и мастер-копия правил. Тот
# же дефект бьёт и по колонке тестов: `bash "$REPO/hooks/alpha.sh"` — стандартная форма
# вызова в этом каталоге тестов — механизмом не считается.
#
# Исход — ровно тот класс, ради которого страж делался: механизм правится, его справочник
# существует, хук про него МОЛЧИТ. Молчание стража неотличимо от «ничего не задето».
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks/tests" "$R/.claude-docs/modules" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n' > "$R/hooks/alpha.sh"
# Модульный док в форме, которую требует module-doc-check и которой написаны все
# .claude-docs/modules/*.md в этом дереве.
printf '# Подсчёт метрики\n\n**Файлы.** `hooks/alpha.sh` — считает метрику потока.\n' \
    > "$R/.claude-docs/modules/schyot.md"
# Тест в форме, которой написаны все тесты этого каталога.
printf '#!/usr/bin/env bash\nR=$(pwd)\nbash "$R/hooks/alpha.sh"\n' > "$R/hooks/tests/test_alpha.sh"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_path_mention.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_path_mention.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )
ROW=$(grep '^hooks/alpha\.sh	' "$R/.claude-docs/dep-index.tsv")
DOCS=$(printf '%s' "$ROW" | cut -f4)
TESTS=$(printf '%s' "$ROW" | cut -f5)

# --- B1a: документ по пути ---------------------------------------------------------
if [ "$DOCS" = ".claude-docs/modules/schyot.md" ]; then
    ok "B1a документ, называющий механизм полным путём, связан с ним в индексе"
else
    bad "B1a" "док .claude-docs/modules/schyot.md содержит «**Файлы.** \`hooks/alpha.sh\`»,
      колонка docs строки hooks/alpha.sh: [${DOCS:-«ПУСТО»}]
      строка целиком: $(printf '%s' "$ROW" | tr '\t' '|')"
fi

# --- B1b: тест по пути -------------------------------------------------------------
if [ "$TESTS" = "hooks/tests/test_alpha.sh" ]; then
    ok "B1b тест, зовущий механизм полным путём, связан с ним в индексе"
else
    bad "B1b" "тест hooks/tests/test_alpha.sh зовёт bash \"\$R/hooks/alpha.sh\",
      колонка tests строки hooks/alpha.sh: [${TESTS:-«ПУСТО»}]"
fi

# --- B1c: чем это кончается на коммите ---------------------------------------------
printf '#!/usr/bin/env bash\nfoo_one() { echo ИНОЕ ПОВЕДЕНИЕ; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_path_mention.sh:$LINENO" >&2; exit 1; }
REPORT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/alpha.sh 2>&1 )
if grep -qF ".claude-docs/modules/schyot.md" <<< "$REPORT"; then
    ok "B1c правка механизма назвала его собственный модульный док"
else
    bad "B1c" "механизм переписан по поведению, его модульный док не тронут,
      отчёт --impact: [${REPORT:-«ТИШИНА, rc=0 — хук выйдет молча»}]"
fi

# --- B1d: достижимость на боевом дереве, только чтение ------------------------------
if [ -f "$REPO/.claude-docs/dep-index.tsv" ]; then
    LIVE=$(cd "$REPO" && python3 - <<'PY' 2>/dev/null
import importlib.util
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
di = importlib.util.module_from_spec(spec); spec.loader.exec_module(di)
rows = di.load()
docs = [(p, di.read(p)) for p in di.documents()]
blind = [m for m, r in rows.items() if not r[3] and any(m in t for _, t in docs)]
lost = sum(1 for m, r in rows.items() for p, t in docs
           if m in t and p not in ((r[3].split(",")) if r[3] else []))
print("%d %d %s" % (len(blind), lost, ",".join(sorted(blind)[:4])))
PY
)
    BLIND=$(printf '%s' "$LIVE" | awk '{print $1}')
    LOST=$(printf '%s' "$LIVE" | awk '{print $2}')
    WHO=$(printf '%s' "$LIVE" | awk '{print $3}')
    if [ -z "${BLIND:-}" ]; then
        echo "SKIP: боевой индекс не прочитался — замер достижимости пропущен"
    elif [ "$BLIND" -eq 0 ]; then
        ok "B1d в боевом дереве нет механизмов, чей единственный документ назван путём"
    else
        bad "B1d" "боевое дерево: связей «документ называет механизм путём» потеряно $LOST,
      из них $BLIND механизмов остались с ПУСТОЙ колонкой docs — про них страж молчит всегда: $WHO"
    fi
fi

# --- B2 (D1339): граница имени и язык файла — правилом прибора, а не формой строки ---------
# Три места одного прибора решали по форме: упоминание путём пропускало после основы чужое расширение
# (`archive/outcome.tsv` читался упоминанием `outcome.sh`), носитель сверялся подстрокой (`outcome.sh` находился в
# `injection-outcome.sh`), публичные имена TS и JS брались правилом питона. Ноги зовут функции прибора из рабочего
# дерева; у каждой отрицательной ноги рядом положительный контроль — законная связь обязана остаться.
B2=$(cd "$REPO" && python3 - <<'PY' 2>&1
import importlib.util
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
di = importlib.util.module_from_spec(spec); spec.loader.exec_module(di)
bad = []
corpus = [("foreign.md", "журнал лежит в archive/outcome.tsv и в $T/outcome.py"),
          ("own.md", "смотри scripts/outcome.sh"),
          ("path.md", "модуль core/outcome читает вход"),
          ("dot.md", "см. core/outcome.")]
got = di.mentions("outcome.sh", corpus)
if "foreign.md" in got:
    bad.append("a: путь с чужим расширением засчитан упоминанием outcome.sh")
for need in ("own.md", "path.md", "dot.md"):
    if need not in got:
        bad.append("a-ctrl: потеряно законное упоминание " + need)
hit = getattr(di, "carrier_names", None)
if hit is None:
    bad.append("b: у прибора нет правила границы имени для носителя")
else:
    if hit("outcome.sh", '"command": "bash scripts/injection-outcome.sh"'):
        bad.append("b: имя внутри другого имени засчитано носителю")
    if hit("check.sh", "ProgramArguments doc-check.sh"):
        bad.append("b: check.sh найден в doc-check.sh")
    if not hit("outcome.sh", '"command": "bash scripts/outcome.sh debt"'):
        bad.append("b-ctrl: потерян настоящий носитель")
    if not hit("scripts/outcome.sh", "x\tbash scripts/outcome.sh\t"):
        bad.append("b-ctrl: потерян носитель, названный путём")
ts = ("export async function GET() {}\nexport const helper = () => 1\nexport default class Page {}\n"
      "class Hidden {}\nfunction inner() {}\nexport type T = number\nexport const _private = 1\n")
names = di.public_names("web/app/route.ts", ts)
if names != ["GET", "Page", "helper"]:
    bad.append("c: публичные имена TS: " + ",".join(names))
if di.public_names("lib/x.py", "def f():\n    pass\nclass C: pass\n") != ["C", "f"]:
    bad.append("c-ctrl: правило питона сдвинулось")
print("; ".join(bad) if bad else "ok")
PY
)
if [ "$B2" = "ok" ]; then
    ok "B2 чужое расширение — не упоминание, имя внутри имени — не носитель, имена TS — экспортированное"
else
    bad "B2" "$B2"
fi

# --- B3 (D1339, скептик H1): учёт помнит, какой редакцией правила он собран -----------------
# Правило меняется вне судимого дерева (прибор один на все проекты), а строки чужого учёта остаются от прежнего: имена,
# которых прежнее правило не знало, отчёт называл «новыми» на каждом файле. Нога ломает учёт так, как его оставляет
# смена правила: колонка имён пуста. Со своей отметкой это новая способность (контроль), без отметки — другая редакция.
IDX="$R/.claude-docs/dep-index.tsv"
di() { ( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py "$@" 2>&1 ); }
if grep -q '^# правило [0-9a-f]\{12\}$' "$IDX"; then ok "B3a запись учёта ставит отметку редакции правила"
else bad "B3a" "в шапке учёта нет строки «# правило <хеш>»: $(head -3 "$IDX" | tr '\n' '|')"; fi
awk -F'\t' 'BEGIN { OFS = "\t" } /^hooks\/alpha\.sh\t/ { $6 = "" } { print }' "$IDX" > "$IDX.n" && mv "$IDX.n" "$IDX"
if grep -qF "новые публичные имена — учёт требует" <<< "$(di --impact hooks/alpha.sh)"; then ok "B3b контроль: при своей отметке имя без записи в учёте — новое"
else bad "B3b" "рамка не различает: имя foo_one стёрто из учёта, отметка своя, а «новым» оно не названо"; fi
grep -v '^# правило ' "$IDX" > "$IDX.n" && mv "$IDX.n" "$IDX"
REPORT=$(di --impact hooks/alpha.sh)
if grep -qF "новые публичные имена — учёт требует" <<< "$REPORT"; then bad "B3c" "учёт без отметки редакции судит имена: $(grep -A1 'новые публичные' <<< "$REPORT" | tr '\n' ' ')"
elif grep -qF "другой редакцией правила" <<< "$REPORT"; then ok "B3c учёт другой редакции правила имён не судит и называет себя"
else bad "B3c" "о другой редакции правила отчёт молчит: [$REPORT]"; fi
# Полноту пересборки показывает строка ДРУГОГО механизма: строку файла, названного в `--changed`, пересобирает и
# частичная сборка (мутант «без полной пересборки» прежнюю редакцию ноги проходил).
other_names() { awk -F'\t' '/^scripts\/dep-index\.py\t/ { print $6 }' "$IDX"; }
blank_other() { awk -F'\t' 'BEGIN { OFS = "\t" } /^scripts\/dep-index\.py\t/ { $6 = "" } { print }' "$IDX" > "$IDX.n" && mv "$IDX.n" "$IDX"; }
[ -n "$(other_names)" ] || { echo "подготовка мира не удалась: у строки scripts/dep-index.py нет имён: hooks/tests/test_adv2_dep_index_path_mention.sh:$LINENO" >&2; exit 1; }
blank_other
di --changed hooks/alpha.sh >/dev/null
if grep -q '^# правило ' "$IDX" && [ -n "$(other_names)" ]; then ok "B3d частичная пересборка учёта другой редакции — полная: отметка на месте, строки прочих пересобраны"
else bad "B3d" "после --changed по учёту без отметки: отметок $(grep -c '^# правило ' "$IDX"), имена строки scripts/dep-index.py: [$(other_names | cut -c1-40)]"; fi
blank_other
di --changed hooks/alpha.sh >/dev/null
if [ -z "$(other_names)" ]; then ok "B3e контроль: при своей отметке частичная пересборка чужих строк не трогает"
else bad "B3e" "рамка не различает: при своей отметке строка scripts/dep-index.py пересобрана и частичной сборкой"; fi

echo ""
echo "adv2 path-mention: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
