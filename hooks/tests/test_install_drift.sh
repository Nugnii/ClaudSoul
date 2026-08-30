#!/usr/bin/env bash
# test_install_drift.sh — Signal 6 в session-start.sh: детект расхождения между
# репозиторием, установкой и регистрацией хуков.
#
# Зачем. `case-2026-04-24-install-drift-silent-safeguards`: 8 релизов подряд
# safeguard-хуки лежали в репозитории и в install.sh, но не попадали в
# `~/.claude/hooks/` — молча неактивны. Тогда закрыли направление «зарегистрирован →
# файла нет». Шапка Signal 6 с тех пор обещала и обратную сторону, но код её не
# делал, и за следующие релизы накопилось 9 хуков, которые работают локально и
# которых нет в репозитории — на другой машине их просто не будет.
# Оба направления теперь проверяются здесь, потому что отказ обоих — тихий:
# ничего не падает, просто защита отсутствует.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    if grep -qF "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2'"; fi
}
assert_not_contains() {
    if grep -qF "$2" <<< "$1"; then FAIL=$((FAIL + 1)); echo "FAIL [$3]: неожиданно найдено '$2'"
    else PASS=$((PASS + 1)); fi
}

# Три независимые плоскости: что зарегистрировано, что установлено, что в репозитории.
# $1 — список зарегистрированных, $2 — установленных, $3 — лежащих в репозитории.
setup() {
    rm -rf "$TMP/home" "$TMP/repo"
    mkdir -p "$TMP/home/.claude/hooks" "$TMP/state" "$TMP/repo/hooks"
    local reg=() n
    for n in $1; do reg+=("$(jq -cn --arg c "bash ~/.claude/hooks/$n" '{type:"command",command:$c}')"); done
    jq -n --argjson hooks "$(printf '%s\n' "${reg[@]}" | jq -s .)" \
        '{hooks:{PreToolUse:[{matcher:"Bash",hooks:$hooks}]}}' > "$TMP/home/.claude/settings.json"
    # Четвёртый список ($4) — установленные хуки с маркером принадлежности чужому проекту.
    for n in $2; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/home/.claude/hooks/$n"; done
    for n in ${4:-}; do
        printf '#!/usr/bin/env bash\n# claudsoul-foreign-hook: дом в репозитории своего проекта\nexit 0\n' \
            > "$TMP/home/.claude/hooks/$n"
    done
    for n in $3; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/repo/hooks/$n"; done
}

run() {
    rm -f "$TMP/state"/startup-signals-*.txt
    printf '{"session_id":"drift-test","source":"startup","cwd":"%s"}' "$TMP/repo" | \
        env HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$TMP/repo" \
            bash "$HOOK" >/dev/null 2>&1
    cat "$TMP/state"/startup-signals-*.txt 2>/dev/null || true
}

# === T1: всё согласовано → о дрейфе молчим ===
setup "a.sh b.sh" "a.sh b.sh" "a.sh b.sh"
OUT=$(run)
assert_not_contains "$OUT" "Install drift" "T1: согласованное состояние — тишина"

# === T2: зарегистрирован, но не установлен (направление v1.6.1) ===
setup "a.sh b.sh" "a.sh" "a.sh b.sh"
OUT=$(run)
assert_contains "$OUT" "зарегистрированы, но не установлены" "T2a: прямой дрейф пойман"
assert_contains "$OUT" "b.sh" "T2b: назван конкретный хук"

# === T3: работает и зарегистрирован, но копии в репозитории нет (направление v1.11) ===
setup "a.sh b.sh" "a.sh b.sh" "a.sh"
OUT=$(run)
assert_contains "$OUT" "обратный" "T3a: обратный дрейф пойман"
assert_contains "$OUT" "b.sh" "T3b: назван конкретный хук"
assert_not_contains "$OUT" "зарегистрированы, но не установлены" "T3c: не путается с прямым"

# === T4: оба направления сразу — оба сигнала ===
setup "a.sh b.sh c.sh" "a.sh b.sh" "a.sh c.sh"
OUT=$(run)
assert_contains "$OUT" "зарегистрированы, но не установлены" "T4a: прямой (c.sh не установлен)"
assert_contains "$OUT" "обратный" "T4b: обратный (b.sh не в репозитории)"

# === T5: нет каталога репозитория → обратная проверка молчит, не падает ===
setup "a.sh" "a.sh" "a.sh"
rm -rf "$TMP/repo/hooks"
OUT=$(run)
assert_not_contains "$OUT" "обратный" "T5: без каталога репозитория обратный дрейф не сообщается"

# === T7: хук помечен как чужой → сигнала нет ===
#
# Сообщение сигнала само предлагало «либо перенеси в репозиторий проекта, которому они
# принадлежат» — но не проверяло, что это уже сделано, и повторялось каждую сессию.
# Проверенный случай: `projecta-security-gate.sh` лежит в git своего проекта с 2026-07-05,
# а ClaudSoul называл его «копии в репозитории нет» ещё 22.08. Тест T6 при этом терпел
# ровно одну такую запись — костыль под конкретный файл вместо признака.
setup "a.sh b.sh" "a.sh" "a.sh" "b.sh"
OUT=$(run)
assert_not_contains "$OUT" "обратный" "T7: помеченный чужим хук в сигнал не идёт"

# === T8: контроль к T7 — тот же расклад без маркера обязан гореть ===
# Без него зелёный T7 неотличим от выключенной проверки.
setup "a.sh b.sh" "a.sh b.sh" "a.sh"
OUT=$(run)
assert_contains "$OUT" "обратный" "T8: без маркера обратный дрейф на месте"

# === T9: маркер гасит только помеченный, соседей — нет ===
setup "a.sh b.sh c.sh" "a.sh c.sh" "a.sh" "b.sh"
OUT=$(run)
assert_contains "$OUT" "обратный" "T9a: непомеченный c.sh назван"
assert_contains "$OUT" "c.sh" "T9b: назван именно он"
assert_not_contains "$OUT" "b.sh" "T9c: помеченный b.sh в списке не появился"

# === T6: живая система — хуков без копии и без маркера быть не должно ===
# Прежде здесь стояло «≤1»: допуск под конкретный проектный файл. Признак заменил
# счёт — теперь чужой хук объявляет себя сам, и порог стал нулевым.
# Проверка смотрит на ЖИВУЮ установку, а не на фикстуру. В CI её нет, каталог
# отсутствует, и glob подставляется буквально: `[ -f "$REPO/hooks/*.sh" ]` ложно,
# в список попадает строка «*.sh», тест краснеет на пустом месте. Отсутствие живой
# установки — не дрейф, а отсутствие предмета проверки: об этом говорится вслух,
# чтобы «неприменимо» не читалось как «проверено и чисто».
if [ ! -d "$HOME/.claude/hooks" ]; then
    echo "SKIP [T6]: живой установки нет ($HOME/.claude/hooks) — проверять нечего"
else
    LIVE_UNTRACKED=""
    for f in "$HOME"/.claude/hooks/*.sh; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ -f "$REPO_ROOT/hooks/$b" ] && continue
        grep -q 'claudsoul-foreign-hook' "$f" 2>/dev/null && continue
        LIVE_UNTRACKED="$LIVE_UNTRACKED $b"
    done
    if [ -z "$LIVE_UNTRACKED" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [T6]: в установке есть хуки без копии в репозитории и без маркера:$LIVE_UNTRACKED"; fi
fi

# --- T7: хук репозитория, ЗАРЕГИСТРИРОВАННЫЙ живьём, но не объявленный установщиком ----
# Третье направление, и самое тихое из трёх. T6 ловит файл без копии в репозитории;
# «призрак регистрации» в drift-check ловит объявление без файла. Здесь — файл есть,
# работает на этой машине, а `HOOKS_CONFIG` установщика о нём не знает: на чистой машине
# он копируется и не срабатывает никогда, и ни один прогон этого не скажет.
# Повод (28 августа 2026): rules-write-bypass и declared-problem-recorded прожили так
# полдня и попали бы в релиз. Найдено сверкой чисел, не проверкой — проверки не было.
# Регистрация ЧУЖОГО файла (нет копии в репозитории) сюда не относится: это дело машины.
if [ ! -f "$HOME/.claude/settings.json" ]; then
    echo "SKIP [T7]: живых настроек нет — проверять нечего"
elif ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP [T7]: нужен python3"
else
    UNDECLARED=$(python3 - "$HOME/.claude/settings.json" "$REPO_ROOT/install.sh" "$REPO_ROOT/hooks" <<'PYEOF'
import json, re, sys, pathlib

def names(obj, out):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "command" and isinstance(v, str):
                out.update(re.findall(r"([a-z0-9-]+\.sh)", v))
            else:
                names(v, out)
    elif isinstance(obj, list):
        for v in obj:
            names(v, out)

live = set()
names(json.loads(pathlib.Path(sys.argv[1]).read_text()).get("hooks", {}), live)
src = pathlib.Path(sys.argv[2]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", src, re.S)
if not m:
    sys.exit(3)
declared = set()
names(json.loads(m.group(1)), declared)
repo = pathlib.Path(sys.argv[3])
print(" ".join(sorted(n for n in live - declared if (repo / n).is_file())))
PYEOF
)
    _t7_rc=$?
    if [ "$_t7_rc" -ne 0 ]; then
        # Разбор не состоялся — это отказ проверки, а не её успех. Молчаливое «пусто»
        # здесь означало бы «объявлено ноль хуков», то есть зелёный на сломанном конфиге.
        FAIL=$((FAIL + 1)); echo "FAIL [T7]: разбор HOOKS_CONFIG не состоялся (код $_t7_rc) — проверка сломана, а не чиста"
    elif [ -z "$UNDECLARED" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [T7]: хуки репозитория работают живьём, но установщик их не объявляет: $UNDECLARED"; fi
fi

echo ""
echo "install-drift tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
