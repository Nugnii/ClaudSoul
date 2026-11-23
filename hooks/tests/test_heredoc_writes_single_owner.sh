#!/usr/bin/env bash
# СУДИТ: hooks/detection-signals-lib.sh scripts/signal-precision-corpus.py
# test_heredoc_writes_single_owner.sh — разбор «куда пишет heredoc» существует в одном месте,
# и оба потребителя дают одно и то же на одном входе.
#
# Предмет (D366). До 12 сентября 2026 предикат heredoc_target_regex разбирал команду awk-ом, а
# scripts/signal-precision-corpus.py — своей регуляркой; они расходились в 1356 случаях из
# 1357. Род K видит копию, СОХРАНИВШУЮ ИМЯ, а переписанную другим примитивом — нет; условие
# снятия предела — «сверка ПОВЕДЕНИЯ, а не имени». Эта нога и есть та сверка: один набор
# форм записи, два потребителя, ответы обязаны совпасть дословно.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
LIB="$ROOT/hooks/detection-signals-lib.sh"
CORPUS="$ROOT/scripts/signal-precision-corpus.py"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# shellcheck source=/dev/null
. "$LIB"
command -v ds_heredoc_writes >/dev/null 2>&1 || { echo "FAIL: ds_heredoc_writes недоступна — владелец разбора сломан"; exit 1; }

# Ответ владельца, свёрнутый в ту же форму, что отдаёт python: `цель<TAB>тело` на запись,
# переводы строк тела заменены на \n, чтобы записи сравнивались построчно.
owner() { printf '%s' "$1" | ds_heredoc_writes | awk -F'\t' '
    $1 == "T" { n++; tg[n] = $2; next }
    /^\|/     { body = body substr($0, 2) "\\n"; next }
    $0 == "E" { for (i = 1; i <= n; i++) printf "%s\t%s\n", tg[i], body; n = 0; body = "" }'; }
corpus() { python3 - "$CORPUS" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for t, b in m.heredoc_writes(sys.argv[2]):
    print(t + "\t" + b.replace("\n", "\\n"))
PY
}

# T1: владелец печатает протокол: цель, тело, конец.
got=$(printf "cat > hooks/x.sh <<'EOF'\nтело\nEOF\n" | ds_heredoc_writes | tr '\n' '~')
if [ "$got" = "T	hooks/x.sh~|тело~E~" ]; then ok; else bad "T1" "протокол владельца: «${got}»"; fi

# T2: сверка ПОВЕДЕНИЯ — один набор форм, два потребителя, дословное совпадение.
forms=(
  "$(printf "cat > hooks/x.sh <<'EOF'\nтело\nEOF\n")"                                # цель до маркера
  "$(printf "python3 - <<'PY' > hooks/gen.sh\nprint(1)\nPY\n")"                       # цель после маркера
  "$(printf "cat <<EOF | tee hooks/a.sh\nx\nEOF\n")"                                  # труба не рвёт поток
  "$(printf "git show HEAD:hooks/x.sh > /tmp/x.sh && python3 - <<'PY'\nprint(1)\nPY\n")"  # за разделителем — чужая
  "$(printf "cat >> \"hooks/b c.sh\" <<-'M'\n\tstrip\n\tM\n")"                        # кавычки, <<-, табы
  "$(printf "cat > a.txt <<A\n1\nA\ncat > b.txt <<B\n2\nB\n")"                        # два heredoc подряд
  "$(printf "echo без heredoc > hooks/z.sh\n")"                                       # записи нет
)
i=0
for f in "${forms[@]}"; do
    i=$((i + 1))
    o=$(owner "$f"); c=$(corpus "$f")
    if [ "$o" = "$c" ]; then ok; else bad "T2.$i" "потребители разошлись: владелец «${o}» / корпус «${c}»"; fi
done

# T3: контрпример к T2 — набор не пустой: хотя бы у трёх форм есть запись, и у формы
# «за разделителем» её нет. Иначе T2 зеленела бы на паре пустых ответов.
n_nonempty=0; for f in "${forms[@]}"; do [ -n "$(owner "$f")" ] && n_nonempty=$((n_nonempty + 1)); done
if [ "$n_nonempty" -ge 3 ] && [ -z "$(owner "${forms[3]}")" ]; then ok
else bad "T3" "набор не различает: непустых $n_nonempty, за разделителем «$(owner "${forms[3]}")»"; fi

# T4: второй реализации в корпусе нет — ни по имени, ни по устройству (регулярка с маркером).
if ! grep -q 'HEREDOC_RE' "$CORPUS" && ! grep -qE 're\.compile\([^)]*<<' "$CORPUS" && grep -q 'ds_heredoc_writes' "$CORPUS"; then ok
else bad "T4" "в корпусе осталась своя реализация разбора heredoc"; fi

# T5: отказ прибора — ошибка, а не пустой список (пустой читался бы как «записей нет»).
if DS_LIB=/nonexistent/lib.sh corpus "${forms[0]}" >/dev/null 2>&1; then bad "T5" "без библиотеки корпус ответил, будто записей нет"; else ok; fi

echo ""
echo "heredoc writes single owner: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
