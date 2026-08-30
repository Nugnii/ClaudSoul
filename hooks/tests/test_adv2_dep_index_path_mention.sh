#!/usr/bin/env bash
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
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
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
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1
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

echo ""
echo "adv2 path-mention: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
