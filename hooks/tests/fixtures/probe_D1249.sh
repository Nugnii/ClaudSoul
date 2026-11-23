#!/usr/bin/env bash
set -u
# СУДИТ: scripts/archive-checks-after-commit.sh hooks/commit-trap.sh
# probe_D1249 — коммит, ломающий «Проверку» закрытого пункта архива, называется сразу после коммита, а не недельным
#   замером. В клоне репозитория, прибор `scripts/archive-checks-after-commit.sh`:
#   (а) коммит безвредной правки трекера интрузивности — `--sync` гонит задетые «Проверки» (среди них D1248): код 0,
#       напоминаний нет;
#   (б) та же вершина, а в рабочей копии — незакоммиченное снятие охраны D1248: судится коммит, а не копия — код 0,
#       напоминаний нет (скептик, M2);
#   (в) коммит нового файла, путь которого называет только пункт ⊘ архива: ⊘ инварианта не объявляет — код 3 «нечего
#       судить», напоминаний нет (скептик, H1);
#   (г) коммит снятия охраны через поставленную ловушку git `post-commit` при унаследованных GIT_DIR/GIT_WORK_TREE и
#       замке, брошенном убитым прогоном, — в очереди напоминаний строка с этим коммитом и «красны: … D1248» (скептик,
#       M1, M3, M4).
# Код: 0 — все четыре ноги держатся; 1 — нет (названо); 2 — нет прибора, клон или контроль не собрались.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/archive-checks-after-commit.sh" ] && command -v git >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
C="$W/repo"; ST="$W/state"; mkdir -p "$ST"
# Сказанное читается во всех каналах (D1304): строка о коммите идёт в канал проекта, а не в общую очередь.
# shellcheck source=/dev/null
. "$R/hooks/tests/alerts-read.sh" || exit 2
git clone -q --local "$R" "$C" 2>/dev/null || exit 2
# Рабочая копия накрывает клон: прибор, исполнитель и ловушка берутся из нынешнего дерева, а не из последнего коммита.
# Исполнитель архива — тоже: перечень пунктов отбор берёт у него (`--list`, D1283).
for f in scripts/archive-checks-after-commit.sh hooks/tests/fixtures/probe_D1196.sh hooks/commit-trap.sh \
    hooks/state-lock-lib.sh scripts/backlog-recheck.sh; do cp "$R/$f" "$C/$f" || exit 2; done
T="hooks/intrusiveness-tracker.sh"
GUARD='if \[ "\$ST_REASONS" != "non_user_turn" \]; then'
grep -q "$GUARD" "$C/$T" || { echo "рамка: охраны D1248 в трекере нет" >&2; exit 2; }
cm() { (cd "$C" && git add -A && git -c core.hooksPath=/dev/null -c user.email=p@p -c user.name=p commit -q --allow-empty -m "$1") >/dev/null 2>&1; }
run() { (cd "$C" && env STATE_DIR="$ST" bash scripts/archive-checks-after-commit.sh --sync >/dev/null 2>&1); }
brk() { sed -i.bak "s/$GUARD/if true; then/" "$C/$T" && rm -f "$C/$T.bak"; }
cm base || exit 2
miss=""
# (а)
printf '# безвредная строка комментария\n' >> "$C/$T"; cm harmless
run; rc=$?
[ "$rc" = 1 ] || [ "$rc" = 2 ] && { echo "рамка: безвредная правка — код $rc (задетые «Проверки» не держатся и без поломки)" >&2; exit 2; }
[ "$rc" = 0 ] || miss="$miss (а) код $rc вместо 0 (выбор пуст?);"
[ -n "$(alerts_of "$ST")" ] && { miss="$miss (а) безвредная правка дала напоминание;"; alerts_clear "$ST"; }
# (б)
brk; run; rc=$?
[ "$rc" = 0 ] || miss="$miss (б) незакоммиченная поломка винится коммиту (код $rc);"
[ -n "$(alerts_of "$ST")" ] && { miss="$miss (б) напоминание от рабочей копии;"; alerts_clear "$ST"; }
(cd "$C" && git checkout -q -- "$T") || exit 2
# (в)
# Пункт ⊘ ложится в архив СВОИМ коммитом, файл — следующим: с D1338 правка самого архива судится пробой, объявившей
# его в «СУДИТ» (D1122), и общий коммит выбрал бы её — нога же судит выбор по ФАЙЛУ, который называет только пункт ⊘.
printf -- '- ⊘ **D99249** пункт не делается.\n  **Проверка.** `bash hooks/probe-d1249-void.sh` → 0\n' >> "$C/BACKLOG-archive.md"
cm void-item
printf '#!/usr/bin/env bash\n' > "$C/hooks/probe-d1249-void.sh"
cm void
run; rc=$?
[ "$rc" = 3 ] || miss="$miss (в) пункт ⊘ выбран (код $rc вместо 3);"
[ -n "$(alerts_of "$ST")" ] && { miss="$miss (в) напоминание от пункта ⊘;"; alerts_clear "$ST"; }
# (г)
(cd "$C" && env -u CLAUDECODE -u AI_AGENT CLAUDSOUL_ROOT="$C" bash hooks/commit-trap.sh --install "$C") >/dev/null 2>&1 \
    || { echo "рамка: ловушка в клоне не встала" >&2; exit 2; }
# Брошенный замок: владелец — процесс, которого уже нет.
true & dp=$!; wait "$dp"
[ -d "$ST/archive-checks-after-commit.lock" ] && miss="$miss замок остался после законченных прогонов;"
mkdir -p "$ST/archive-checks-after-commit.lock" && printf '%s x\n' "$dp" > "$ST/archive-checks-after-commit.lock/owner" || exit 2
brk
(cd "$C" && git add -A && env -u CLAUDECODE -u AI_AGENT CLAUDSOUL_ROOT="$C" STATE_DIR="$ST" GIT_DIR="$C/.git" \
    GIT_WORK_TREE="$C" git -c user.email=p@p -c user.name=p commit -q --no-verify -m broken) >/dev/null 2>&1 \
    || { echo "рамка: коммит поломки не прошёл" >&2; exit 2; }
sha=$(git -C "$C" rev-parse --short=8 HEAD)
# Адресат строки — проект клона (канал проекта, D1304; скептик opus по 9310f120, M4): чтение «всех каналов» пропускало
# мутанта, вернувшего строку в общую очередь.
_pk=$(printf '%s' "$(cd "$C" && pwd -P)" | cksum | awk '{print $1}')
hit=""
for _ in $(seq 1 120); do
    grep -F "$sha" "$ST/project-signals-$_pk.txt" 2>/dev/null | grep -oE 'красны:[ D0-9]+' | grep -qw D1248 && { hit=1; break; }
    sleep 1
done
[ -n "$hit" ] || miss="$miss (г) за 120 с ловушка не назвала коммит $sha с «красны: … D1248»;"
# Фон дописал строку и снимает замок — дать ему выйти до сноса песочницы.
for _ in 1 2 3 4 5; do [ -d "$ST/archive-checks-after-commit.lock" ] || break; sleep 1; done
[ -z "$miss" ] && { echo "поломка закрытого пункта названа после коммита ловушкой, безвредная правка, рабочая копия и ⊘ тихи"; exit 0; }
echo "не держится:$miss"
exit 1
