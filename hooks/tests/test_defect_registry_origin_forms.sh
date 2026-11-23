#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# test_defect_registry_origin_forms.sh — разбор происхождения имени судит МЕСТО, а не форму.
#
# Результат: сужение признаков родов F и H не ловит ложных и не теряет настоящих
# Проверка результата: bash hooks/tests/test_defect_registry_origin_forms.sh даёт 0
#
# Повод (9 сентября 2026, D306/D308/D310/D370). `_h_kind` сливал два разных предмета в один
# исход «общий»: «происхождения в файле НЕТ» (законно общее — имя из окружения) и
# «происхождение ЕСТЬ, разбор его не узнал». Четыре ложных носителя рода H держались ровно
# на этом, а род F числил носителем глоб, копирующий дерево в песочницу.
#
# Почему тест ОТДЕЛЬНЫЙ, а не нога в контрпримерах. `test_defect_registry_counterexamples.sh`
# подаёт контрпримеры только НЕПУСТОМУ роду (`rows_of` → skip на пустом), а род H после
# сужения пуст — и машинного тормоза у сужения не осталось бы вовсе. Здесь предмет
# создаётся тестом, поэтому он есть всегда, независимо от состояния дерева.
#
# Рамка — СВОЙ git-репозиторий: реестр берёт файлы из индекса git и вне репозитория видит
# ноль (проверка в рамке, где механизм не работает — замер 4 сентября 2026).
set -uo pipefail
unset BACKLOG_CHECKS_NESTED

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
REG="${DCC_REGISTRY:-$REPO/scripts/defect-class-carriers.py}"
[ -f "$REG" ] || { echo "FAIL: нет $REG"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0; FAIL=0
FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

mkdir -p "$FIX/scripts" "$FIX/hooks"
cp "$REG" "$FIX/scripts/defect-class-carriers.py"
# Реестр читает `ROOT/install.sh` без гейта (`_registrations`, род J) и без него падает
# целиком. В боевом дереве файл есть всегда, поэтому дефект латентный; здесь он назван
# заглушкой, а не обойдён молчанием.
printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/install.sh"

# --- ЛОЖНЫЕ: место, где мир ни от чего не зависит -------------------------------------
# H-ложный 1: переменная ЦИКЛА, перечень ведёт в mktemp.
cat > "$FIX/hooks/false_loop.sh" <<'EOF'
#!/usr/bin/env bash
T=$(mktemp -d)
for f in "$T"/a/*.txt; do
    sed 's/x/y/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
EOF
# H-ложный 2: распаковка кортежа, argv подан из ЛИЧНОГО каталога.
cat > "$FIX/hooks/false_unpack.sh" <<'EOF'
#!/usr/bin/env bash
TMP=$(mktemp -d)
R2="$TMP/b"
python3 - "$R2/install.sh" "$R2/other.sh" <<'PY'
import sys, pathlib
p, q = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
t = p.read_text()
p.write_text(t.replace("a", "b"))
PY
EOF
# H-ложный 3: значение ВЫЗОВА функции, печатающей путь под mktemp.
cat > "$FIX/hooks/false_func.sh" <<'EOF'
#!/usr/bin/env bash
TMP=$(mktemp -d)
sandbox() { _s="$TMP/$1"; mkdir -p "$_s"; printf '%s' "$_s"; }
path=$(sandbox live)
jq '.a = 1' "$path" > "$path.t" && mv "$path.t" "$path"
EOF
# F-ложный: глоб — ИСТОЧНИК копии в свежесозданный каталог.
cat > "$FIX/hooks/false_copy.sh" <<'EOF'
#!/usr/bin/env bash
TMP=$(mktemp -d)
mkdir -p "$TMP/hooks"
cp "$REPO"/hooks/*.sh "$TMP/hooks/"
EOF

# --- НАСТОЯЩИЕ: положительный контроль ------------------------------------------------
# H-настоящий: распаковка кортежа, argv подан ОБЩИМ файлом (форма backlog-archive.sh).
cat > "$FIX/hooks/real_unpack.sh" <<'EOF'
#!/usr/bin/env bash
BACKLOG="${BACKLOG_FILE:-$HOME/.claude/BACKLOG.md}"
ARCHIVE="${BACKLOG_ARCHIVE:-$HOME/.claude/ARCH.md}"
python3 - "$BACKLOG" "$ARCHIVE" <<'PY'
import sys, pathlib
backlog, archive = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
lines = backlog.read_text().splitlines(True)
backlog.write_text("".join(lines[1:]))
PY
EOF
# H-настоящий: прямая правка общего файла из окружения.
cat > "$FIX/hooks/real_plain.sh" <<'EOF'
#!/usr/bin/env bash
STATE="$HOME/.claude/hooks/state/shared.json"
jq '.n += 1' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
EOF
# H-ложный 4: АВТОР заготовки. Файл ПИШЕТ чужую программу в файл; тело чужого heredoc —
# данные, а не код автора. Поймано на себе 9 сентября 2026: этот самый тест стал носителем
# рода H на своих же заготовках (:58 и :87), и правка легла в `_h_py_lines`.
cat > "$FIX/hooks/false_author.sh" <<'OUTER'
#!/usr/bin/env bash
cat > "$SOMEWHERE/generated.sh" <<'INNER'
python3 - "$SHARED_FILE" <<'PY'
import sys, pathlib
target = pathlib.Path(sys.argv[1])
t = target.read_text()
target.write_text(t + "x")
PY
INNER
OUTER

# F-настоящий: глоб решает, ЧТО СНИМАТЬ, — невидимое остаётся в системе (форма uninstall.sh).
mkdir -p "$FIX/hooks/lib"
printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/hooks/lib/deep.sh"
cat > "$FIX/hooks/real_glob.sh" <<'EOF'
#!/usr/bin/env bash
DIR="$HOME/.claude"
for src in "$DIR"/hooks/*.sh; do
    rm -f "$src"
done
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.local
git -C "$FIX" config user.name t
git -C "$FIX" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_registry_origin_forms.sh:$LINENO" >&2; exit 1; }
git -C "$FIX" commit -qm fix >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_registry_origin_forms.sh:$LINENO" >&2; exit 1; }

_carriers() { # <буква> — печатает строки носителей
    (cd "$FIX" && python3 scripts/defect-class-carriers.py --genus "$1" 2>/dev/null \
        | grep '^  ·')
}
H=$(_carriers H)
F=$(_carriers F)

# Положительный контроль ПЕРВЫМ: пустой ответ прибора обязан быть отказом, а не зелёным.
grep -q real_unpack <<< "$H" && ok || bad "T1" "настоящий носитель H (argv из общего файла) не пойман — прибор ослеп: [$H]"
grep -q real_plain <<< "$H"  && ok || bad "T2" "настоящий носитель H (общий файл из окружения) не пойман: [$H]"
grep -q real_glob <<< "$F"   && ok || bad "T3" "настоящий носитель F (глоб решает, что снимать) не пойман: [$F]"

# Ложные: каждая из трёх неразобранных форм и глоб-копия в песочницу.
grep -q false_loop <<< "$H"   && bad "T4" "переменная цикла под mktemp числится носителем H" || ok
grep -q false_unpack <<< "$H" && bad "T5" "распаковка кортежа из личного каталога числится носителем H" || ok
grep -q false_func <<< "$H"   && bad "T6" "значение функции, печатающей путь под mktemp, числится носителем H" || ok
grep -q false_copy <<< "$F"   && bad "T7" "глоб-источник копии в песочницу числится носителем F" || ok
grep -q false_author <<< "$H" && bad "T8" "автор заготовки числится носителем: тело чужого heredoc сочтено кодом" || ok

echo ""
echo "defect registry origin forms: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
