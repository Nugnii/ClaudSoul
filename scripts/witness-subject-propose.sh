#!/usr/bin/env bash
# witness-subject-propose.sh — объявлятель предмета свидетеля-атаки (D474).
# Результат: у свидетеля, чей предмет выбран ПРОГОНОМ, в шапке стоит строка `# СУДИТ:`, и
#   очередь `behavior-condition-probe.sh --unresolved` на столько же короче.
# Проверка результата: bash hooks/tests/test_witness_subject_propose.sh даёт 0
#
# ЧТО ДЕЛАЕТ. Для свидетелей из перечня `behavior-condition-probe.sh --unresolved` берёт
# кандидатов у ИНДЕКСА ЗАВИСИМОСТЕЙ (владелец связи «тест ↔ механизм»), прогоняет каждого
# через выхолащивание и предлагает строку шапки `# СУДИТ:` из тех, от потери которых
# свидетель КРАСНЕЕТ. Краснеет один — предмет файл; краснеет несколько — предмет СПИСОК.
#
# ПОЧЕМУ ПРОГОН, А НЕ ПРИЗНАК. Измерено 21 сентября 2026 (D474): признак «имя теста →
# одноимённый механизм» дал 68 кандидатов, из них подтвердил прогон 62; признак «предмет
# задан переменной» — 68 кандидатов, 56 подтверждённых и 7 СЛЕПЫХ. Разделителя по форме
# не нашлось: `hooks/tests/drift-check.sh` стоит предметом у 8 подтверждённых и у 3 слепых
# одновременно. Признак только сужает круг; решает прогон.
#
# КОНТРОЛЬ РАМКИ ПЕРВЫМ. Свидетель, красный БЕЗ всякой порчи, покраснеет и от любого
# кандидата — и объявил бы предметом первый попавшийся файл. Такой пропускается с именем:
# у него другой класс («рамка не собралась»), и он не задача этого приёма.
#
# ВЛАДЕЛЬЦЫ, У КОТОРЫХ СПРОШЕНО, А НЕ ВЫВЕДЕНО ЗАНОВО:
#   · перечень неразрешённых — `scripts/behavior-condition-probe.sh --unresolved`;
#   · кандидаты — `.claude-docs/dep-index.tsv`, колонка `tests`;
#   · выхолащивание — `hooks/subject-probe-lib.sh` (та же функция, что у прибора).
#
# Коды: 0 — работа сделана, 2 — мерить нечем (нет индекса, снимка, библиотеки).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || { echo "BROKEN: нет корня репозитория"; exit 2; }

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# Замок общего файла — у владельца (`hooks/state-lock-lib.sh`), а не своей реализацией.
_SLL="$REPO/hooks/state-lock-lib.sh"
[ -f "$_SLL" ] || { echo "BROKEN: нет hooks/state-lock-lib.sh — править общий файл нечем"; exit 2; }
# shellcheck source=/dev/null
. "$_SLL"

_SPL="$REPO/hooks/subject-probe-lib.sh"
[ -f "$_SPL" ] || { echo "BROKEN: нет hooks/subject-probe-lib.sh — выхолащивать нечем"; exit 2; }
# shellcheck source=/dev/null
. "$_SPL"

UNRES=$(bash scripts/behavior-condition-probe.sh --unresolved) \
    || { echo "BROKEN: перечень неразрешённых не получен"; exit 2; }
[ -n "$UNRES" ] || { echo "неразрешённых нет — объявлять нечего"; exit 0; }

# КАНДИДАТЫ БЕРУТСЯ У ИНДЕКСА, А НЕ ВЫВОДЯТСЯ ИМЕНЕМ: у индекса связь уже записана, и
# второй её вывод был бы родом K реестра (правило вынесено, копия у потребителя осталась).
CAND=$(python3 - <<'PY'
import csv
pairs = {}
for r in csv.reader(open(".claude-docs/dep-index.tsv", encoding="utf-8"), delimiter="\t"):
    if not r or r[0].startswith("#") or len(r) < 5:
        continue
    for t in r[4].split(","):
        t = t.strip()
        if t:
            pairs.setdefault(t, []).append(r[0])
for t, ms in sorted(pairs.items()):
    print(t + "\t" + " ".join(sorted(set(ms))))
PY
) || { echo "BROKEN: индекс зависимостей не разобран"; exit 2; }

# СНИМОК — ПОЛНЫЙ КЛОН, А НЕ `git archive` (урок D474, 21 сентября 2026): архив не несёт
# истории, а часть свидетелей берёт положительный контроль из неё (`git show <коммит>^:файл`)
# — восемь были записаны «красен без правок», и трое подтвердились сразу на полном клоне.
SNAP=$(mktemp -d) || { echo "BROKEN: нет временного каталога"; exit 2; }
trap 'rm -rf "$SNAP"' EXIT
# Снимок строит ВЛАДЕЛЕЦ, и он накрывает клон РАБОЧИМ содержимым: иначе предмет вычитывался
# из коммита, а строка ложилась в рабочую копию — объявлятель сам производил ложную зелень,
# а новый, ещё не закоммиченный свидетель попадал в «рамка не собралась» (класс I противника).
sp_snapshot "$SNAP/repo" || { echo "BROKEN: клон дерева не собрался"; exit 2; }
# Вывод — рядом с клоном, а не в нём: в клоне он неотслеживаемый файл судимого дерева (D1222, 8 ноября 2026).
OUTF="$SNAP/.propose-out"
SNAP="$SNAP/repo"

PROPOSED=0; FRAMED=0; BLIND=0; NOCAND=0
while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ -f "$t" ] || continue
    cands=$(printf '%s\n' "$CAND" | awk -F'\t' -v k="$t" '$1==k {print $2; exit}')
    if [ -z "$cands" ]; then
        # ЗАПАСНОЙ ИСТОЧНИК: ПУТИ, КОТОРЫЕ ТЕСТ НАЗЫВАЕТ САМ (22 сентября 2026).
        # У 15 свидетелей остатка индекс не знает кандидатов вовсе — связь туда не попала.
        # Замер того дня: 9 из 15 называют в своём тексте хотя бы один путь вне hooks/tests/.
        # Это по-прежнему лишь сужение круга: решает ПРОГОН, как и у кандидатов из индекса.
        # Пути внутри hooks/tests/ отброшены намеренно — там лежат фикстуры, которые тест
        # кладёт сам, и выхолащивать их значит судить свою же песочницу.
        cands=$(grep -oE '(hooks|scripts|lib|bin)/[A-Za-z0-9_./-]+\.(sh|py)' "$t" 2>/dev/null \
            | grep -v '^hooks/tests/' | sort -u | tr '\n' ' ')
        cands="${cands% }"
    fi
    if [ -z "$cands" ]; then
        NOCAND=$((NOCAND + 1)); continue
    fi
    # Живой прогон идёт через ТОГО ЖЕ владельца срока, что и выхолощенный: свидетель,
    # не возвращающийся никогда, вешал объявлятель целиком, а его зовёт реестр замеров.
    live_rc=$( cd "$SNAP" 2>/dev/null && sp_run_witness "$SNAP" "$t" /dev/null; echo $? )
    if [ "${live_rc:-1}" -ne 0 ]; then
        FRAMED=$((FRAMED + 1))
        printf 'рамка не собралась: %s\n' "$t"
        continue
    fi
    red=""
    for c in $cands; do
        [ -f "$SNAP/$c" ] || continue
        sp_hollow_run "$SNAP" "$t" "$c" "$OUTF"
        rc=$?
        [ "$rc" -ne 0 ] && [ "$rc" -ne 9 ] && red="${red}${red:+ }$c"
    done
    if [ -z "$red" ]; then
        BLIND=$((BLIND + 1))
        printf 'ни один кандидат не краснит: %s (кандидатов: %s)\n' "$t" "$(printf '%s' "$cands" | wc -w | tr -d ' ')"
        continue
    fi
    PROPOSED=$((PROPOSED + 1))
    printf '# СУДИТ: %s\t%s\n' "$red" "$t"
    if [ "$APPLY" = 1 ]; then
        # ПРАВКА ОБЩЕГО ФАЙЛА ИДЁТ ПОД ЗАМКОМ (род H реестра): свидетель читается целиком и
        # переписывается целиком, а дерево правят и параллельные сессии. Единица блокировки —
        # ФАЙЛ, и имя берут обе половины протокола одно, иначе защита мнимая.
        # Строка встаёт ВТОРОЙ, сразу под shebang: прибор читает только шапку (30 строк).
        with_lock "$t" python3 - "$t" "$red" <<'PY'
import io, sys
p, subj = sys.argv[1], sys.argv[2]
lines = io.open(p, encoding="utf-8").read().split("\n")
if any(l.startswith("# СУДИТ:") for l in lines[:30]):
    raise SystemExit(0)
at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(at, "# СУДИТ: " + subj)
io.open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
    fi
done <<EOF
$UNRES
EOF

printf 'предложено: %d; рамка не собралась: %d; ни один не краснит: %d; кандидатов нет: %d\n' \
    "$PROPOSED" "$FRAMED" "$BLIND" "$NOCAND"
[ "$APPLY" = 1 ] && printf 'строки ВПИСАНЫ в свидетелей (--apply)\n'
exit 0
