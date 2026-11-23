#!/usr/bin/env bash
# test_defect_genus_m.sh — свидетель признака рода M реестра scripts/defect-class-carriers.py.
# Предмет: признак ловит свидетеля, чья песочница построена там, где судимый механизм её
#          отбрасывает, — И ЧЕРЕЗ ДИСПЕТЧЕР ТОЖЕ, — и не ловит четыре законных вида.
#
# Зачем отдельным свидетелем, а не ногой контрпримеров. Род M сейчас ПУСТ (носителей 0), и
# машинная сверка контрпримеров на пустом роде честно говорит «НЕ ИЗМЕРЕНО» — мерить нечего.
# Значит у признака не осталось бы ни одного живого доказательства: он мог бы не работать
# вовсе, и это было бы неотличимо от чистоты. Здесь носитель СОЗДАЁТСЯ в пробном дереве.
#
# Живой репозиторий не читается и не правится: реестр копируется в песочницу, и ROOT у него
# выводится от собственного пути (`parents[1]`), поэтому смотрит он в пробное дерево.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
REG="$REPO/scripts/defect-class-carriers.py"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

[ -f "$REG" ] || { echo "FAIL: нет $REG"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git     >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

# Песочница здесь в /tmp ЗАКОННО: судимый механизм — реестр родов, исключения `*/tmp/*` он
# не несёт, и вход ему верен. Ровно тот контрпример, что записан у рода M.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/scripts" "$R/hooks/tests"
cp "$REG" "$R/scripts/"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t

# Механизм-носитель исключения и диспетчер, достающий его вызовом.
printf '#!/usr/bin/env bash\ncase "$F" in */tmp/*) exit 0 ;; esac\necho "нашёл"\n' > "$R/hooks/guard.sh"
printf '#!/usr/bin/env bash\nGUARDS="guard.sh"\nfor g in $GUARDS; do bash "$D/$g"; done\n' > "$R/hooks/dispatcher.sh"
# Механизм БЕЗ исключения — его свидетели в область рода не входят.
printf '#!/usr/bin/env bash\necho "иной страж"\n' > "$R/hooks/plain.sh"

mk() {  # mk <имя> <тело>
    printf '%s\n' "$2" > "$R/hooks/tests/$1"
}
mk test_sick.sh     '#!/usr/bin/env bash
H="$D/guard.sh"
TMP=$(mktemp -d)'
mk test_healthy.sh  '#!/usr/bin/env bash
H="$D/guard.sh"
TMP=$(mktemp -d "${HOME}/.proba.XXXXXX")'
mk test_comment.sh  '#!/usr/bin/env bash
# судит guard.sh — но только на словах
TMP=$(mktemp -d)'
mk test_plain.sh    '#!/usr/bin/env bash
H="$D/plain.sh"
TMP=$(mktemp -d)'
mk test_indirect.sh '#!/usr/bin/env bash
H="$D/dispatcher.sh"
TMP=$(mktemp -d)'
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_genus_m.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm i >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_genus_m.sh:$LINENO" >&2; exit 1; }

carriers() {  # печатает имена носителей, по одному на строку
    ( cd "$R" && python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("reg", "scripts/defect-class-carriers.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
for path, _subj in mod.carriers_m():
    print(path.name)
' 2>&1 )
}

OUT=$(carriers); RC=$?
[ "$RC" = 0 ] || bad T0 "признак упал: $OUT"

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: прямая связь, песочница в /tmp — носитель найден.
grep -qx "test_sick.sh" <<< "$OUT" && ok || bad T1 "прямой носитель не найден: «${OUT}»"

# T2 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ЧЕРЕЗ ДИСПЕТЧЕР. Без этой ноги признак зеленел бы на редакции,
# которая выронила ЕДИНСТВЕННОГО настоящего носителя дерева: у test_bash_write_dispatch связь
# с backlog-touch-check идёт списком $GUARDS, а не именем в тексте (прогон CI 34886464295).
grep -qx "test_indirect.sh" <<< "$OUT" && ok || bad T2 "носитель через диспетчер не найден: «${OUT}»"

# T3 — песочница вынесена в $HOME: это и есть починка, носителем быть нельзя.
grep -qx "test_healthy.sh" <<< "$OUT" && bad T3 "здоровый пойман" || ok

# T4 — имя механизма стоит в КОММЕНТАРИИ: упоминание в прозе связью не является.
grep -qx "test_comment.sh" <<< "$OUT" && bad T4 "поймано упоминание в комментарии" || ok

# T5 — механизм без исключения: вход ему верен, песочница в /tmp законна (482 таких в дереве).
grep -qx "test_plain.sh" <<< "$OUT" && bad T5 "пойман свидетель механизма без исключения" || ok

# T6 — МУТАНТ: снять исключение у механизма — вселенная пуста, носителей ноль. Без этой ноги
# T1/T2 зеленели бы на признаке, который судит один лишь `mktemp -d` и потому ловит 482 файла.
printf '#!/usr/bin/env bash\necho "нашёл"\n' > "$R/hooks/guard.sh"
printf '#!/usr/bin/env bash\nGUARDS=""\n' > "$R/hooks/dispatcher.sh"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_genus_m.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm m >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_genus_m.sh:$LINENO" >&2; exit 1; }
MUT=$(carriers)
[ -z "$MUT" ] && ok || bad T6 "после снятия исключения признак всё ещё видит носителей: «${MUT}»"

echo "test_defect_genus_m: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
