#!/usr/bin/env bash
# test_adv_dep_index_nonascii_paths.sh — путь с кириллицей выпадает и из индекса, и из
# хука, и обе потери молчаливы.
#
# Механика. `git ls-files` при core.quotePath (умолчание) отдаёт не-ASCII путь в
# кавычках с восьмеричными экранами: "skills/\320\277.../GUIDE.md". `tracked()` берёт
# строку как есть, `read()` не может её открыть и по `except OSError: return ""` отдаёт
# ПУСТОТУ. Документ, который нельзя прочитать, неотличим от документа, который ничего
# не упоминает: ни строки предупреждения нигде.
#
# То же на стороне хука: `git diff --cached --name-only` цитирует так же, а `xargs`
# кавычки снимает, но восьмеричные экраны оставляет буквальными — в отчёт попадает
# путь, которого нет на диске.
#
# Живой носитель на момент замера (28 августа 2026, 155 строк индекса): два документа
# по кириллическим путям — docs/грилинг/GUIDE.md и docs/противник/GUIDE.md, оба под
# учётом git, оба в корпусе документов и оба нечитаемые (2 из 136). Ни одного механизма
# по стему они тогда не называли, поэтому индекс врал не строкой, а корпусом.
# ПОКА ШЛА ЭТА ПРОВЕРКА, соседняя сессия поставила в индекс переименование обоих в
# латиницу (skills/adversary, skills/grilling) — носитель уезжает, устройство остаётся.
# Поэтому живая часть (A4a) ниже — условная: есть кириллический путь под учётом → она
# обязана быть красной, нет — она молчит и НЕ засчитывается зелёной. Красное держат
# A4b/A4c на своей фикстуре: они не зависят от того, что сейчас лежит в дереве.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/doc-impact-check.sh"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# --- A4a. Живое дерево: сколько документов корпуса не открывается ------------------
UNREADABLE=$( cd "$REPO" && python3 - <<'PY'
import os, re, subprocess
REPO = os.getcwd()
out = subprocess.run(["git","-C",REPO,"ls-files","--cached","--others","--exclude-standard","*.md"],
                     capture_output=True, text=True).stdout
DOC_SKIP = re.compile(r"_drafts/|^knowledge/|(^|/)(CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG|BACKLOG-archive)\.md$"
                      r"|-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$")
docs = [p for p in out.splitlines() if p and not DOC_SKIP.search(p)]
bad = [p for p in docs if not os.path.exists(os.path.join(REPO, p))]
print(len(docs)); print(len(bad))
for b in bad: print(b)
PY
)
TOTAL=$(printf '%s\n' "$UNREADABLE" | sed -n 1p)
NBAD=$(printf '%s\n' "$UNREADABLE" | sed -n 2p)
NONASCII=$(git -C "$REPO" ls-files --cached --others --exclude-standard '*.md' | grep -c '\\3')
if [ "${NBAD:-0}" -eq 0 ] && [ "${NONASCII:-0}" -eq 0 ]; then
    echo "NOTE [A4a]: под учётом сейчас нет ни одного пути с не-ASCII (проверено ls-files),"
    echo "      поэтому живой носитель отсутствует и проверка НЕ засчитывается зелёной."
    echo "      На момент замера их было 2 из ${TOTAL} документов корпуса; устройство не менялось."
elif [ "${NBAD:-0}" -eq 0 ]; then
    bad "A4a" "под учётом ${NONASCII} путей с не-ASCII, но ни один не попал в нечитаемые —
      предпосылка проверки разъехалась, разобрать вручную"
else
    bad "A4a" "из ${TOTAL} документов корпуса ${NBAD} не открываются, ошибка проглочена (read() → \"\"):
$(printf '%s\n' "$UNREADABLE" | sed -n '3,$p' | sed 's/^/      · /')"
fi

# --- A4b. Документ по кириллическому пути описывает механизм → страж молчит --------
TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/.claude-docs" "$R/scripts" "$R/docs/противник"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n' > "$R/hooks/alpha.sh"
printf '# Скилл\n\nСтраж `alpha` описан здесь: когда он говорит и когда молчит.\n' > "$R/docs/противник/GUIDE.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n# правка поведения\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/alpha.sh 2>&1 )
if grep -qF "GUIDE.md" <<< "$OUT"; then
    ok "A4b кириллический документ назван"
else
    bad "A4b" "docs/противник/GUIDE.md описывает alpha; после правки alpha отчёт: [${OUT:-«ПУСТО»}]
      ls-files отдаёт документ так: $(git -C "$R" ls-files -- 'skills/*' | head -1)"
fi

# --- A4c. Механизм по кириллическому пути → хук печатает несуществующий путь -------
if command -v jq >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\nbeta_fn() { :; }\n' > "$R/docs/противник/tool.sh"
    git -C "$R" add -A >/dev/null 2>&1
    HOUT=$(jq -cn --arg c "git commit -m x" --arg d "$R" --arg s s1 \
             '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:$s}' \
           | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null \
           | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
    if grep -qF 'docs/противник/tool.sh' <<< "$HOUT"; then
        ok "A4c хук назвал новый механизм настоящим путём"
    else
        bad "A4c" "новый механизм docs/противник/tool.sh; хук назвал путь, которого нет на диске:
$(printf '%s\n' "$HOUT" | grep -F '320' | sed 's/^/      /')"
    fi
else
    echo "SKIP [A4c]: нет jq"
fi

echo ""
echo "adv nonascii-paths: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
