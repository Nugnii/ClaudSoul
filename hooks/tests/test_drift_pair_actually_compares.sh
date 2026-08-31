#!/usr/bin/env bash
# test_drift_pair_actually_compares.sh — пара не «упомянута», а действительно сравнивает.
#
# Результат: подмена содержимого приёмника меняет вывод drift-check — по каждому приёмнику.
# Проверка результата: bash hooks/tests/test_drift_pair_actually_compares.sh даёт 0
#
# Зачем отдельно от `test_drift_pairs_cover_install.sh`. Тот судит ТЕКСТОМ: путь приёмника
# встречается в исполняемом коде детектора. Текст не отличает вызов, стоящий в заведомо
# ложной ветке, и путь, только присвоенный переменной, — а оба означают «сравнения нет».
# Здесь предмет другой: не наличие строки, а НАБЛЮДАЕМОЕ поведение. Испортили файл в
# приёмнике — вывод обязан измениться; не изменился, значит пары нет, как её ни называй.
#
# КОНТРПРИМЕР: пара «регистрация хуков» подменой файла не проверяется — её предмет не
# содержимое файлов, а записи в settings.json; она покрыта своими проверками.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"

# Установка-песочница: раскладываем то же, что install.sh, но своими руками и без
# регистрации — предмет теста в сравнении содержимого, а не в настройках.
mkdir -p "$HOME_DIR/hooks/lib" "$HOME_DIR/commands" "$HOME_DIR/bin" \
         "$HOME_DIR/templates" "$HOME_DIR/global-lessons"
cp "$REPO"/hooks/*.sh "$HOME_DIR/hooks/" 2>/dev/null
cp "$REPO"/hooks/lib/* "$HOME_DIR/hooks/lib/" 2>/dev/null
cp "$REPO"/bin/*.sh "$HOME_DIR/bin/" 2>/dev/null
cp "$REPO"/templates/*.tmpl "$HOME_DIR/templates/" 2>/dev/null
cp "$REPO"/knowledge/*.md "$HOME_DIR/global-lessons/" 2>/dev/null
cp "$REPO/scripts/statusline-claudsoul.sh" "$HOME_DIR/statusline-claudsoul.sh" 2>/dev/null
# Правила: приёмник `~/.claude/CLAUDE.md` наполняется не копированием, а слиянием области
# между маркерами (`lib/claude-md-merge.sh`). Без него проба «правила» невозможна, и пара
# оставалась непробованной — то есть невидимой ОБОИМ стражам разом.
if [ -f "$REPO/lib/claude-md-merge.sh" ] && [ -f "$REPO/rules/CLAUDE.md" ]; then
    ( . "$REPO/lib/claude-md-merge.sh"
      _cm_write_managed_block "$REPO/rules/CLAUDE.md" > "$HOME_DIR/CLAUDE.md" ) 2>/dev/null
fi
for _sd in "$REPO"/skills/*/; do
    [ -d "$_sd" ] || continue
    _sn=$(basename "$_sd")
    mkdir -p "$HOME_DIR/commands/$_sn"
    cp "$_sd/SKILL.md" "$HOME_DIR/commands/$_sn/SKILL.md" 2>/dev/null
    if [ -d "$_sd/references" ]; then
        mkdir -p "$HOME_DIR/commands/$_sn/references"
        cp "$_sd"/references/*.md "$HOME_DIR/commands/$_sn/references/" 2>/dev/null
    fi
done

run_drift() { CLAUDSOUL_REPO="$REPO" CLAUDE_HOME="$HOME_DIR" bash "$DRIFT" 2>/dev/null; }

PASS=0; FAIL=0
# Один файл на приёмник: портим его и требуем, чтобы вывод изменился.
probe() {
    _label="$1"; _victim="$2"
    if [ -z "$_victim" ] || [ ! -f "$_victim" ]; then
        echo "SKIP [$_label]: в песочнице нет файла для подмены"
        return
    fi
    # Восстановление КОПИЕЙ файла, а не через `$(cat)`: подстановка команды срезает
    # завершающие переводы строки, файл остаётся изменённым, и следующая проба сравнивает
    # уже испорченную песочницу. Первая версия этого теста проходила именно так — по
    # ложной причине: вывод отличался у каждой пробы независимо от подмены.
    cp "$_victim" "$TMP/keep.bak"
    # Опорный вывод берётся ПЕРЕД каждой пробой, а не один раз: иначе накопленные следы
    # прошлых проб сами по себе дают различие.
    _before=$(run_drift)
    printf '%s\n' "# подмена ради проверки" >> "$_victim"
    _after=$(run_drift)
    cp "$TMP/keep.bak" "$_victim"
    if [ "$_after" = "$_before" ]; then
        FAIL=$((FAIL + 1))
        echo "FAIL [$_label]: подмена содержимого не изменила вывод — пара не сравнивает этот приёмник"
    else
        PASS=$((PASS + 1))
    fi
}

first_of() { ls $1 2>/dev/null | head -1; }

probe "хуки"             "$HOME_DIR/hooks/knowledge-counter-bump.sh"
probe "библиотеки хуков" "$(first_of "$HOME_DIR/hooks/lib/*")"
probe "скиллы"           "$(first_of "$HOME_DIR/commands/*/SKILL.md")"
probe "bin"              "$(first_of "$HOME_DIR/bin/*")"
probe "шаблоны"          "$(first_of "$HOME_DIR/templates/*.tmpl")"
probe "статусная строка" "$HOME_DIR/statusline-claudsoul.sh"
# Пара «правила» сравнивает не файл целиком, а ОБЛАСТЬ МЕЖДУ МАРКЕРАМИ — значит и портить
# надо внутри неё. Дописанная в конец строка лежит вне области, вывод не меняет, и проба
# объявила бы рабочую пару несравнивающей: предмет подмены обязан совпадать с предметом
# сравнения.
probe_rules() {
    _v="$HOME_DIR/CLAUDE.md"
    if [ ! -f "$_v" ]; then echo "SKIP [правила]: в песочнице нет $_v"; return; fi
    cp "$_v" "$TMP/keep.bak"
    _before=$(run_drift)
    awk 'NR == 2 { print "# подмена внутри управляемой области" } { print }' "$_v" > "$_v.new" \
        && mv "$_v.new" "$_v"
    _after=$(run_drift)
    cp "$TMP/keep.bak" "$_v"
    if [ "$_after" = "$_before" ]; then
        FAIL=$((FAIL + 1))
        echo "FAIL [правила]: подмена внутри области между маркерами не изменила вывод"
    else
        PASS=$((PASS + 1))
    fi
}
probe_rules

# Список проб обязан покрывать ВСЕ приёмники install.sh, а не те, что вспомнились. Иначе
# «по каждому приёмнику» — обещание, которое проверять нечем.
EXPECTED=$(bash "$REPO/hooks/tests/test_drift_pairs_cover_install.sh" 2>/dev/null \
    | sed -n 's/^приёмников install.sh: \([0-9]*\).*/\1/p')
PROBED=$((PASS + FAIL))
if [ -n "$EXPECTED" ] && [ "$PROBED" -lt "$((EXPECTED - 1))" ]; then
    echo "FAIL: приёмников у install.sh — $EXPECTED, пробовано $PROBED: часть пар не проверена вовсе"
    FAIL=$((FAIL + 1))
fi

echo "приёмников проверено подменой: $((PASS + FAIL)), пар без сравнения: $FAIL"
[ "$FAIL" -eq 0 ]
