#!/usr/bin/env bash
# СУДИТ: scripts/archive-checks-after-commit.sh
# test_archive_select_probe_code.sh — сверка архива после коммита выбирает пункт, чья проба ПОДКЛЮЧАЕТ или исполняет
# изменённый файл кодом, а не только тот, чья строка «# СУДИТ:» его называет (D1312, корень R3).
#
# Повод (16 ноября 2026, скептик D1309): `--select hooks/tests/alerts-read.sh` выбирал только D291, а пробы D441, D514,
# D1231 подключают `alerts-read.sh` кодом — после его правки они краснели незамеченными до архивного свода.
#
# A1 — живой случай в снимке дерева: выбраны D441, D514, D1231 (и прежний D291 — положительный контроль);
# A2 — подставная проба, подключающая файл кодом, выбрана;
# A3 — проба, назвавшая файл только в комментарии, не выбрана;
# A4 — проба с похожим, но другим именем (`my-zz-helper.sh`, `zz-helper.sh.bak`) не выбрана.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
[ -f "$REPO/scripts/archive-checks-after-commit.sh" ] || { echo "SKIP: прибора нет — это другое дерево"; exit 0; }
# Сверка архива работает над бэклогом (`scripts/backlog-recheck.sh --archive` без BACKLOG.md отказывает), а бэклог и его
# архив в открытый снимок не входят: «предмета нет» здесь значит «изъят по решению», а не поломку (D1364, корень R6).
UNIVERSE_ROOT="$REPO"; . "$REPO/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_archive_select_probe_code" "бэклог и архив долга (BACKLOG.md, BACKLOG-archive.md)"; exit 0
fi
command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет git или python3"; exit 0; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
S=$(mktemp -d) || { echo "BROKEN: нет временного каталога"; exit 2; }
trap 'rm -rf "$S"' EXIT
# Снимок закоммиченного дерева: сверке нужен HEAD (`git rev-parse HEAD`), иначе она молча выходит кодом 0.
{ git -C "$REPO" archive HEAD | tar -x -C "$S" && git -C "$S" init -q && git -C "$S" add -A \
    && git -C "$S" -c user.name=t -c user.email=t@t commit -qm snap; } >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: hooks/tests/test_archive_select_probe_code.sh:$LINENO" >&2; exit 2; }
# Прибор под судом — из рабочего дерева: снимок HEAD нёс бы прежнюю редакцию, и свидетель судил бы не ту правку.
cp "$REPO/scripts/archive-checks-after-commit.sh" "$S/scripts/" \
    || { echo "подготовка мира не удалась: hooks/tests/test_archive_select_probe_code.sh:$LINENO" >&2; exit 2; }
F="$S/hooks/tests/fixtures"
printf '#!/usr/bin/env bash\necho помощник\n' > "$S/hooks/tests/zz-helper.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\n. "$(dirname "$0")/../zz-helper.sh"\nexit 0\n' > "$F/probe_D9001.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\n# раньше подключала zz-helper.sh\nexit 0\n' > "$F/probe_D9002.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\n. ./my-zz-helper.sh; cat zz-helper.sh.bak\nexit 0\n' > "$F/probe_D9003.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\nT="hooks/tests/zz-helper.sh"\necho x >> "$W/$T"\nexit 0\n' > "$F/probe_D9004.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\ncp "$R/hooks/tests/zz-helper.sh" "$W/" || exit 2\nexit 0\n' > "$F/probe_D9005.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\n. ./other.sh   # прежде подключала zz-helper.sh\nexit 0\n' > "$F/probe_D9006.sh"
# A8, A9 (D1338): документ, объявленный пробой в «СУДИТ», — такой же предмет, как код; документ, который проба называет
# только командой, выбора по-прежнему не даёт (иначе BACKLOG.md гнал бы архив на каждый коммит).
mkdir -p "$S/domains"
printf '# Домен\n' > "$S/domains/zz-judged.md"
printf '# Домен\n' > "$S/domains/zz-named.md"
printf '#!/usr/bin/env bash\n# СУДИТ: domains/zz-judged.md\nexit 0\n' > "$F/probe_D9007.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: scripts/nothing.sh\nexit 0\n' > "$F/probe_D9008.sh"
printf '\n- ☑ **D9008** подставной пункт\n  **Проверка.** `grep -q Домен domains/zz-named.md && bash hooks/tests/fixtures/probe_D9008.sh` → 0\n' >> "$S/BACKLOG-archive.md"
for n in 9001 9002 9003 9004 9005 9006 9007; do
    printf '\n- ☑ **D%s** подставной пункт\n  **Проверка.** `bash hooks/tests/fixtures/probe_D%s.sh` → 0\n' "$n" "$n" >> "$S/BACKLOG-archive.md"
done

sel() { (cd "$S" && bash scripts/archive-checks-after-commit.sh --select "$1" 2>&1); }
OUT=$(sel hooks/tests/alerts-read.sh)
for id in D291 D441 D514 D1231; do
    grep -qw "$id" <<< "$OUT" && ok || bad "A1 $id" "правка alerts-read.sh не выбрала $id: $OUT"
done
OUT=$(sel hooks/tests/zz-helper.sh)
grep -qw D9001 <<< "$OUT" && ok || bad A2 "проба, подключающая файл кодом, не выбрана: $OUT"
grep -qw D9002 <<< "$OUT" && bad A3 "выбрана проба, назвавшая файл только в комментарии: $OUT" || ok
grep -qw D9003 <<< "$OUT" && bad A4 "выбрана проба с похожим именем: $OUT" || ok
# A5–A7 — по кругу скептика opus по 02a4ba72 (H1, H2, M3): зависимость — подключение или исполнение, а не упоминание.
# A5 — имя-данные в присваивании (проба правит такой файл в своей песочнице) не выбирает: так D1249 выбирала сама себя;
# A6 — копия в песочницу командой `cp` (так D1231 берёт соседа свидетеля) выбирает;
# A7 — имя в хвостовом комментарии строки-подключения не выбирает.
OUT=$(sel hooks/tests/zz-helper.sh)
grep -qw D9004 <<< "$OUT" && bad A5 "выбрана проба, назвавшая файл данными в присваивании: $OUT" || ok
grep -qw D9005 <<< "$OUT" && ok || bad A6 "проба, копирующая файл в песочницу командой cp, не выбрана: $OUT"
grep -qw D9006 <<< "$OUT" && bad A7 "выбрана проба, назвавшая файл в хвостовом комментарии: $OUT" || ok
OUT=$(sel domains/zz-judged.md)
grep -qw D9007 <<< "$OUT" && ok || bad A8 "документ, объявленный пробой в «СУДИТ», не выбрал её пункт: $OUT"
OUT=$(sel domains/zz-named.md)
grep -qw D9008 <<< "$OUT" && bad A9 "документ, названный только в команде «Проверки», дал выбор: $OUT" || ok

echo "test_archive_select_probe_code: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
