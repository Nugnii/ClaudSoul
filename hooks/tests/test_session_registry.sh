#!/usr/bin/env bash
# test_session_registry.sh — метки времени реестра сессий разбираются на обеих системах.
#
# Повод. В `session-registry-lib.sh` было три места, где эпоха бралась через `date -j`
# (ключ BSD, на Linux его нет) с запасной веткой `|| echo 0`. На Ubuntu все три молча
# отдавали ноль: длительность сессии, возраст прерванной сессии и «столько-то назад» в
# стартовом контексте считались от 1970 года. Ошибки при этом не было — только числа.
#
# Почему проверка нужна отдельная. Единственный тест, который трогал эту библиотеку
# (`test_startup_signals.sh`), кладёт в песочницу только сам файл библиотеки, поэтому
# разбор времени там не исполняется вовсе: тест остаётся зелёным при заведомо сломанном
# `iso_epoch`. Зелёный прогон без покрытия — это и есть та рамка проверки, из-за которой
# расхождение macOS/Linux дожило до CI.
#
# T4 — отрицательный контроль: с заглушкой вместо `iso_epoch` тест обязан покраснеть.
# Без него зелёные T1-T3 не означают, что здесь вообще что-то измеряется.
#
# T5/T5b (D277, 3 сентября 2026) — каталог проекта приходит ПАРАМЕТРОМ, а не из $PWD.
# Прежде `_sr_detect_project` читал только $PWD, и регистрация из чужого каталога
# процесса приписывала сессию ему: прогон из `/` давал `"project_name": "/"`. Умолчание
# на $PWD осталось и проверяется отдельно — у CLI-вызывающего
# (`knowledge-counter-bump.sh:609`) payload'а нет, и каталог процесса там законный вход.

set -uo pipefail
# Каталог реестра сессий выводится ИЗ HOME намеренно: предмет проверки — умолчание,
# по которому хук определяет проект. Раннер даёт каждому тесту свой SR_SESSIONS_DIR
# (D271), и унаследованная переменная увела бы запись в чужой каталог — тест зеленел
# бы в одиночку и краснел под раннером. Образец тот же, что в
# test_knowledge_delta_reaches_registry.sh:62 и test_startup_signals.sh:29.
unset SR_SESSIONS_DIR

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен — реестр без него не пишется"; exit 0; }

PASS=0
FAIL=0
assert_eq() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: получено '$got', ожидалось '$want'"; fi
}
assert_ne() {
    local got="$1" unwanted="$2" label="$3"
    if [ "$got" != "$unwanted" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: значение '$got' совпало с '$unwanted'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/libs-real" "$TMP/libs-stub"
cp "$HOOKS_DIR/session-registry-lib.sh" "$TMP/libs-real/"
cp "$HOOKS_DIR/portable-lib.sh" "$TMP/libs-real/"
cp "$HOOKS_DIR/session-registry-lib.sh" "$TMP/libs-stub/"
printf '%s\n' 'iso_epoch() { echo ""; }' 'file_mtime() { echo ""; }' > "$TMP/libs-stub/portable-lib.sh"

# Проба гоняет библиотеку в отдельной песочнице HOME и печатает три числа —
# по одному на каждое место, где раньше стоял `date -j`.
cat > "$TMP/probe.sh" <<'PROBE'
set -uo pipefail
LIBDIR="$1"
export HOME="$2"
mkdir -p "$HOME/.claude/sessions/active"
export SR_OVERRIDE_SESSION_ID="probe-sid"
# shellcheck source=/dev/null
source "$LIBDIR/session-registry-lib.sh"

NOW=$(date +%s)
stamp() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }

# 1. Длительность: старт два часа назад → 120 минут
sr_register_session
ACT="$SR_ACTIVE_DIR/probe-sid.json"
jq --arg s "$(stamp $((NOW - 7200)))" '.started_at = $s' "$ACT" > "$ACT.t" && mv "$ACT.t" "$ACT"
sr_finalize_session "проба" 2>/dev/null
echo "duration=$(jq -r '.duration_min' "$SR_LAST_SESSION" 2>/dev/null)"

# 2. Прерванная сессия: чужой активный файл восьмичасовой давности при пороге 6 часов
printf '{"session_id":"stale-uuid","project_name":"proj","started_at":"%s"}' \
    "$(stamp $((NOW - 28800)))" > "$SR_ACTIVE_DIR/stale-uuid.json"
echo "interrupted=$(sr_detect_interrupted 6 | jq -r '[.[] | select(.session_id == "stale-uuid")] | length' 2>/dev/null)"

# 2b. Свежая сессия часовой давности прерванной считаться не должна. Именно эту половину
# ломает неразобранная метка: возраст от нуля эпохи превышает любой порог, и живые
# параллельные сессии объявляются прерванными.
printf '{"session_id":"fresh-uuid","project_name":"proj","started_at":"%s"}' \
    "$(stamp $((NOW - 3600)))" > "$SR_ACTIVE_DIR/fresh-uuid.json"
echo "fresh=$(sr_detect_interrupted 6 | jq -r '[.[] | select(.session_id == "fresh-uuid")] | length' 2>/dev/null)"

# 3. «Столько-то назад» в стартовом контексте: конец прошлой сессии два часа назад
jq --arg e "$(stamp $((NOW - 7200)))" '.ended_at = $e' "$SR_LAST_SESSION" > "$SR_LAST_SESSION.t" \
    && mv "$SR_LAST_SESSION.t" "$SR_LAST_SESSION"
echo "ago=$(sr_get_startup_context | grep -o 'Последняя сессия: [^ ]* назад' | head -1 | sed 's/.*: //')"
PROBE

probe() { bash "$TMP/probe.sh" "$1" "$2" 2>/dev/null; }
field() { printf '%s\n' "$1" | grep "^$2=" | head -1 | cut -d= -f2-; }

REAL=$(probe "$TMP/libs-real" "$TMP/home-real")
assert_eq "$(field "$REAL" duration)"    "120" "T1: длительность сессии в минутах"
assert_eq "$(field "$REAL" interrupted)" "1"   "T2: сессия старше порога опознана как прерванная"
assert_eq "$(field "$REAL" fresh)"       "0"   "T2b: свежая сессия прерванной не считается"
assert_eq "$(field "$REAL" ago)"         "2ч назад" "T3: возраст прошлой сессии в стартовом контексте"

# T4: отрицательный контроль — заглушка вместо разбора времени
STUB=$(probe "$TMP/libs-stub" "$TMP/home-stub")
assert_ne "$(field "$STUB" duration)" "120" "T4: с заглушкой длительность обязана разъехаться"

# === T5/T5b (D277): каталог сессии — вход функции, а не состояние процесса ===
mkdir -p "$TMP/proj-arg"
printf '# fixture\n' > "$TMP/proj-arg/CLAUDE.md"
cat > "$TMP/probe-cwd.sh" <<'PROBE2'
set -uo pipefail
LIBDIR="$1"; export HOME="$2"; ARG="$3"
mkdir -p "$HOME/.claude/sessions/active"
export SR_OVERRIDE_SESSION_ID="probe-cwd"
# shellcheck source=/dev/null
source "$LIBDIR/session-registry-lib.sh"
if [ -n "$ARG" ]; then sr_register_session "$ARG"; else sr_register_session; fi
jq -r '.project_name' "$SR_ACTIVE_DIR/probe-cwd.json"
PROBE2

# T5: процесс стоит в `/`, каталог сессии подан аргументом → проект берётся из аргумента.
# Это ровно живой случай knowledge-activator.sh:841: хук не делает `cd`, payload есть.
T5=$(cd / && bash "$TMP/probe-cwd.sh" "$TMP/libs-real" "$TMP/home-arg" "$TMP/proj-arg" 2>/dev/null)
assert_eq "$T5" "proj-arg" "T5: каталог сессии параметром — проект по нему, а не по каталогу процесса"

# T5b (отрицательный контроль и контракт совместимости): без аргумента остаётся $PWD.
# Без этого случая T5 зеленел бы и у версии, которая игнорирует $PWD вовсе, — а на нём
# держится CLI-вызывающий, у которого payload'а нет.
T5B=$(cd "$TMP/proj-arg" && bash "$TMP/probe-cwd.sh" "$TMP/libs-real" "$TMP/home-noarg" "" 2>/dev/null)
assert_eq "$T5B" "proj-arg" "T5b: без параметра умолчание $PWD сохранено"
# И то же умолчание из `/` обязано дать НЕ каталог сессии — иначе T5 не о параметре.
T5C=$(cd / && bash "$TMP/probe-cwd.sh" "$TMP/libs-real" "$TMP/home-root" "" 2>/dev/null)
assert_ne "$T5C" "proj-arg" "T5c: без параметра из чужого каталога проект НЕ угадывается"

echo ""
echo "session-registry tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
