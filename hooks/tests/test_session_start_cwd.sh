#!/usr/bin/env bash
# test_session_start_cwd.sh — session-start решает по каталогу СЕССИИ и по корню ClaudSoul,
# а не по каталогу процесса.
#
# Повод (D277, 3 сентября 2026). Класс «вход берётся из окружения процесса вместо payload
# сессии» пришёл в этот хук двумя разными формами, и обе жили молча:
#   · регистрация в реестре зависела от того, состоялся ли `cd` в payload-каталог (:26-28).
#     `cd` там с `|| true`: каталога нет — молча не состоялся, и сессия записывается на
#     каталог ПРОЦЕССА. Теперь каталог передаётся аргументом, и от `cd` регистрация не
#     зависит;
#   · сигнал дрейфа установки звал «Запусти <X>/install.sh», где X был `${CWD:-$PWD}`.
#     Переменная `CWD` в файле не присваивается НИ РАЗУ, то есть это всегда был $PWD —
#     каталог сессии после `cd`. Установщик там не лежит: он в репозитории ClaudSoul.
#     Зеркальное сообщение обратного дрейфа (:305) печатало $CLAUDSOUL_ROOT с самого
#     начала — расхождение двух соседних строк одного блока.
#
# Почему отдельный файл. `test_install_drift.sh` проверяет ОБНАРУЖЕНИЕ дрейфа (кто
# зарегистрирован, кого нет), `test_startup_signals.sh` — состав сигналов. Ни один не
# судит о том, ОТКУДА взяты каталоги в этих решениях, и оба оставались зелёными на
# сломанном хуке.
#
# Названный предел: третья форма того же класса — `sr_update_knowledge` двумя аргументами
# в `hooks/knowledge-frontmatter-check.sh:91` — здесь НЕ проверяется: файл вне перечня
# пункта D277, форма отдана отдельным кандидатом в долг.
# Условие снятия: предел уйдёт вместе с закрытием D287 — когда шестой носитель получит вход
# параметром, эта форма перестанет быть исключением, и её проверка встанет сюда рядом с
# остальными пятью.

set -uo pipefail
# Каталог реестра сессий выводится ИЗ HOME намеренно: предмет проверки — умолчание,
# по которому хук определяет проект. Раннер даёт каждому тесту свой SR_SESSIONS_DIR
# (D271), и унаследованная переменная увела бы запись в чужой каталог — тест зеленел
# бы в одиночку и краснел под раннером. Образец тот же, что в
# test_knowledge_delta_reaches_registry.sh:62 и test_startup_signals.sh:29.
unset SR_SESSIONS_DIR

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен — реестр без него не пишется"; exit 0; }

PASS=0
FAIL=0
assert_eq() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: получено '$got', ожидалось '$want'"; fi
}
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq -- "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: не найдено '$needle' в: $(printf '%s' "$haystack" | head -c 200)"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq -- "$needle" <<< "$haystack"; then
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: найдено то, чего быть не должно — '$needle'"
    else PASS=$((PASS + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

H="$TMP/home"
S="$H/.claude/hooks/state"
SESS="$TMP/session-proj"      # каталог СЕССИИ (приходит полем .cwd payload)
REPO="$TMP/claudsoul-repo"    # корень ClaudSoul (в нём лежит install.sh)
OTHER="$TMP/other-proj"       # каталог ПРОЦЕССА — заведомо не тот и не другой
mkdir -p "$S" "$H/.claude/hooks" "$SESS" "$REPO/hooks" "$OTHER"
printf '# session fixture\n' > "$SESS/CLAUDE.md"
printf '# other fixture\n'   > "$OTHER/CLAUDE.md"

# Дрейф установки: зарегистрирован хук, которого физически нет в ~/.claude/hooks/.
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/ghost.sh"}]}]}}' \
    > "$H/.claude/settings.json"

# Прогон хука ИЗ КАТАЛОГА ПРОЦЕССА, отличного от каталога сессии, — так его и запускает
# Claude Code. Каталог сессии подаётся единственным законным входом: полем .cwd payload.
run_start() { # sid, cwd-payload, cwd-процесса
    printf '{"session_id":"%s","source":"startup","cwd":"%s","hook_event_name":"SessionStart"}' "$1" "$2" \
        | (cd "$3" && env HOME="$H" STATE_DIR="$S" CLAUDSOUL_ROOT="$REPO" \
            bash "$HOOK" >/dev/null 2>&1)
}

# === T1: сессия зарегистрирована по каталогу из payload, а не по каталогу процесса ===
run_start s1 "$SESS" "$OTHER"
assert_eq "$(jq -r '.project' "$H/.claude/sessions/active/s1.json" 2>/dev/null)" "$SESS" \
    "T1: реестр записал каталог сессии из payload"

# T1b (отрицательный контроль). Тот же процесс, но каталог сессии ДРУГОЙ — запись обязана
# поехать за payload. Без этой пары T1 зеленел бы у версии, которая всегда пишет $SESS.
run_start s1b "$OTHER" "$SESS"
assert_eq "$(jq -r '.project' "$H/.claude/sessions/active/s1b.json" 2>/dev/null)" "$OTHER" \
    "T1b: запись поехала за payload, а не за каталогом процесса"

# T1c — единственный случай, который отличает ПАРАМЕТР от `cd` на :26-28. Каталог сессии
# исчез между стартом сессии и запуском хука (агент снёс подпапку, сессию перезапустили):
# `[ -d ]` не проходит, `cd` не состоится и промолчит по `|| true`. С каталогом-параметром
# подъём идёт от payload и находит корень проекта; без параметра запись достаётся каталогу
# ПРОЦЕССА. T1/T1b этого не различают — там `cd` состоялся и подменил собой вход.
run_start s1c "$SESS/gone" "$OTHER"
assert_eq "$(jq -r '.project' "$H/.claude/sessions/active/s1c.json" 2>/dev/null)" "$SESS" \
    "T1c: каталог сессии исчез — проект берётся подъёмом от payload, не от каталога процесса"

# === T2: подсказка дрейфа зовёт install.sh из корня ClaudSoul ===
SIG=$(cat "$S/startup-signals-s1.txt" 2>/dev/null)
assert_contains "$SIG" "Запусти $REPO/install.sh" "T2: назван установщик из корня ClaudSoul"

# T2b (отрицательный контроль). Каталог сессии в этой строке не должен появляться вовсе —
# именно он там стоял, и подсказка вела в проект, где install.sh нет.
assert_not_contains "$SIG" "$SESS/install.sh" "T2b: каталог сессии установщиком не назван"
# T2c: и каталог процесса тоже — на случай, если $PWD подставится другим путём.
assert_not_contains "$SIG" "$OTHER/install.sh" "T2c: каталог процесса установщиком не назван"

echo ""
echo "session-start cwd: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
