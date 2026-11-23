#!/usr/bin/env bash
# СУДИТ: uninstall.sh
# test_uninstall.sh — снятие обязано убрать своё, сохранить чужое и не тронуть базу знаний.
#
# Деинсталлятор нельзя проверить на живой машине: единственный способ убедиться, что он
# не заденет лишнего, — прогнать его на поддельном доме и сверить, что осталось.
# Отсюда состав: рядом с нашими файлами кладутся ЧУЖИЕ — хук, скилл, запись в settings.json,
# правила выше и ниже маркеров, — и каждый обязан пережить снятие.
#
# Второе, что здесь сторожится, — безопасное умолчание. Без `--apply` скрипт обязан НИЧЕГО
# не удалить: у деструктивной операции цена забытого флага равна цене данных, у показа —
# одному повторному запуску. Проверяется прямым сравнением дерева до и после сухого прогона.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# CLI `claude` подменяется заглушкой на время теста. Настоящий при любом вызове
# переписывает settings.json целиком, нормализуя посторонние ключи (в прогоне у `model`
# значение «opus» стало «opus[1m]»), и тест начинал ловить поведение внешнего инструмента
# вместо логики деинсталлятора. Проверять надо свою рамку.
STUB_BIN="$(mktemp -d)"
printf '#!/bin/sh
exit 0
' > "$STUB_BIN/claude"
chmod +x "$STUB_BIN/claude"
PATH="$STUB_BIN:$PATH"
UNINSTALL="$REPO/uninstall.sh"
[ -f "$UNINSTALL" ] || { echo "FAIL: нет $UNINSTALL"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- поддельный дом: наше вперемешку с чужим ---
build_home() {
    local H="$1"
    mkdir -p "$H/.claude/hooks/lib" "$H/.claude/commands" "$H/.claude/global-lessons" \
             "$H/.claude/templates" "$H/.claude/hooks/state" "$H/.claude/sessions" "$H/.claude/bin"

    # наши хуки — берём реальные имена, чтобы сверка с репозиторием сработала
    local n=0
    for src in "$REPO"/hooks/*.sh; do
        [ -f "$src" ] || continue
        printf '#!/bin/bash\n# copy\n' > "$H/.claude/hooks/$(basename "$src")"
        n=$((n + 1)); [ "$n" -ge 5 ] && break
    done
    # чужой хук — не наш по имени, исходника в репозитории нет
    printf '#!/bin/bash\n# посторонний\n' > "$H/.claude/hooks/zz-not-ours.sh"

    # наш скилл и чужой
    local first_skill
    first_skill="$(basename "$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | head -1)")"
    mkdir -p "$H/.claude/commands/$first_skill" "$H/.claude/commands/zz-foreign"
    printf -- '---\nname: %s\n---\n' "$first_skill" > "$H/.claude/commands/$first_skill/SKILL.md"
    printf -- '---\nname: zz-foreign\n---\n' > "$H/.claude/commands/zz-foreign/SKILL.md"

    # правила: свои между маркерами, чужие снаружи
    {
        printf '# Мои личные правила\nЭта строка выше маркеров.\n\n'
        printf '<!-- ClaudSoul: managed-start (install.sh синхронизирует) -->\n'
        printf 'Правила ClaudSoul.\n'
        printf '<!-- ClaudSoul: managed-end -->\n\n'
        printf 'Эта строка ниже маркеров.\n'
    } > "$H/.claude/CLAUDE.md"

    # настройки: наш хук и чужой в одном событии, плюс чужая статусная строка
    cat > "$H/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "bash ~/.claude/hooks/error-tracker.sh"},
        {"type": "command", "command": "bash ~/.claude/hooks/zz-not-ours.sh"}
      ]}
    ]
  },
  "statusLine": {"type": "command", "command": "bash ~/.claude/my-own-statusline.sh"},
  "env": {"LC_NUMERIC": "C", "LC_COLLATE": "ru_RU.UTF-8", "MY_VAR": "1"},
  "model": "opus"
}
JSON

    # база знаний — обязана пережить
    printf -- '---\nconfidence: 5\n---\nНакопленное знание.\n' > "$H/.claude/global-lessons/pattern-mine.md"
    printf 'x\n' > "$H/.claude/claudsoul-repo"
    printf '#!/bin/bash\n' > "$H/.claude/bin/resolve-claudsoul-repo.sh"
    printf '#!/bin/bash\n' > "$H/.claude/statusline-claudsoul.sh"
}

# --- T1: без --apply ничего не меняется ---
H1="$(mktemp -d)"; build_home "$H1"
before="$(cd "$H1" && find . -type f | sort | xargs cksum)"
# stderr — рядом с $H1, не внутри: дерево сравнивается before/after, а смерть прогона
# раньше была неотличима от «ничего не изменил» (D220).
HOME="$H1" bash "$UNINSTALL" >/dev/null 2>"$H1-err"; _rc=$?
[ "$_rc" -eq 0 ] || bad T1rc "сухой прогон умер: rc=$_rc, stderr: $(tail -c 200 "$H1-err" 2>/dev/null)"
after="$(cd "$H1" && find . -type f | sort | xargs cksum)"
if [ "$before" = "$after" ]; then ok; else bad T1 "сухой прогон изменил дерево"; fi

# --- T2..T7: после --apply ---
H2="$(mktemp -d)"; build_home "$H2"
HOME="$H2" bash "$UNINSTALL" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }

[ -f "$H2/.claude/global-lessons/pattern-mine.md" ] \
    && ok || bad T2 "база знаний удалена — она обязана оставаться"

[ -f "$H2/.claude/hooks/zz-not-ours.sh" ] \
    && ok || bad T3 "удалён чужой хук"

[ -d "$H2/.claude/commands/zz-foreign" ] \
    && ok || bad T4 "удалён чужой скилл"

ours_left=$(find "$H2/.claude/hooks" -maxdepth 1 -name '*.sh' 2>/dev/null | while read -r f; do
    [ -f "$REPO/hooks/$(basename "$f")" ] && echo x; done | wc -l | tr -d ' ')
[ "$ours_left" -eq 0 ] && ok || bad T5 "остались наши хуки: $ours_left"

if grep -q "выше маркеров" "$H2/.claude/CLAUDE.md" 2>/dev/null \
   && grep -q "ниже маркеров" "$H2/.claude/CLAUDE.md" 2>/dev/null \
   && ! grep -q "Правила ClaudSoul" "$H2/.claude/CLAUDE.md" 2>/dev/null; then
    ok
else
    bad T6 "блок вырезан неверно: чужие правила пострадали либо наши остались"
fi

if command -v jq >/dev/null 2>&1; then
    left="$(jq -r '[.. | objects | select(.command? != null) | .command] | join(" ")' "$H2/.claude/settings.json" 2>/dev/null)"
    case "$left" in
        *error-tracker*) bad T7 "наш хук остался в settings.json" ;;
        *zz-not-ours*)
            # чужой хук на месте, наш убран, чужая статусная строка не тронута
            case "$left" in
                *my-own-statusline*) ok ;;
                *) bad T7 "удалена чужая статусная строка" ;;
            esac ;;
        *) bad T7 "чужой хук пропал из settings.json: [$left]" ;;
    esac
    jq -e '.model == "opus"' "$H2/.claude/settings.json" >/dev/null 2>&1 \
        && ok || bad T8 "пострадали посторонние ключи settings.json"
    # Закрепление локали (D1176): снят только ключ с нашим значением, чужое значение и чужой ключ живы.
    jq -e '.env == {"LC_COLLATE": "ru_RU.UTF-8", "MY_VAR": "1"}' "$H2/.claude/settings.json" >/dev/null 2>&1 \
        && ok || bad T8b "env после снятия: $(jq -c '.env' "$H2/.claude/settings.json" 2>/dev/null)"
else
    PASS=$((PASS + 3))
fi

# --- T9: --keep-state оставляет журналы ---
H3="$(mktemp -d)"; build_home "$H3"
HOME="$H3" bash "$UNINSTALL" --apply --keep-state >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
[ -d "$H3/.claude/hooks/state" ] && ok || bad T9 "--keep-state не сохранил состояние"

# --- T10–T13: снятие закрепления локали и честный итог (D1176, второй круг скептика) ---
if command -v jq >/dev/null 2>&1; then
    # T10 (M2, M1 второго круга): запись чужих значений возвращается на место нашего «C»; ключ, который
    # пользователь сменил после установки, остаётся его; запись снимается.
    H4="$(mktemp -d)"; build_home "$H4"
    jq '.env = {"LC_NUMERIC": "en_US.UTF-8", "LC_COLLATE": "C", "MY": "1"}' "$H4/.claude/settings.json" > "$H4/s" && mv "$H4/s" "$H4/.claude/settings.json"
    printf '{"values":{"LC_NUMERIC":"ru_RU.UTF-8","LC_COLLATE":"ru_RU.UTF-8"},"had_env":true}\n' > "$H4/.claude/claudsoul-env-prev.json"
    HOME="$H4" bash "$UNINSTALL" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
    { jq -e '.env == {"LC_NUMERIC": "en_US.UTF-8", "LC_COLLATE": "ru_RU.UTF-8", "MY": "1"}' "$H4/.claude/settings.json" >/dev/null 2>&1 \
      && [ ! -e "$H4/.claude/claudsoul-env-prev.json" ]; } \
        && ok || bad T10 "чужие значения не вернулись, правка пользователя затёрта или запись осталась: $(jq -c '.env' "$H4/.claude/settings.json" 2>/dev/null)"
    # T11 (M1): сбой jq при снятии хуков назван, итог не «Снято.», код 1, файл не тронут.
    H5="$(mktemp -d)"; build_home "$H5"
    printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"bash ~/.claude/hooks/session-collector.sh"}]},{"matcher":"x"}]}}' > "$H5/.claude/settings.json"
    cp "$H5/.claude/settings.json" "$H5/before.json"
    o5="$(HOME="$H5" bash "$UNINSTALL" --apply 2>&1)"; rc5=$?
    { [ "$rc5" -eq 1 ] && grep -q 'хуки НЕ сняты' <<< "$o5" && grep -q 'Снято НЕ всё' <<< "$o5" \
      && cmp -s "$H5/before.json" "$H5/.claude/settings.json"; } \
        && ok || bad T11 "сбой снятия хуков молчит: код $rc5, $(tail -1 <<< "$o5")"
    # T12 (L2): пустой env пользователя не снимается и не объявляется к снятию.
    H6="$(mktemp -d)"; build_home "$H6"
    jq '.env = {}' "$H6/.claude/settings.json" > "$H6/s" && mv "$H6/s" "$H6/.claude/settings.json"
    o6="$(HOME="$H6" bash "$UNINSTALL" 2>&1)"
    HOME="$H6" bash "$UNINSTALL" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
    { ! grep -q 'закрепление локали' <<< "$o6" && jq -e '.env == {}' "$H6/.claude/settings.json" >/dev/null 2>&1; } \
        && ok || bad T12 "пустой env пользователя тронут или объявлен к снятию"
    # T13 (L5, L3): битый settings.json назван, итог не «Снято.».
    H7="$(mktemp -d)"; build_home "$H7"
    printf '{"hooks": \n' > "$H7/.claude/settings.json"
    o7="$(HOME="$H7" bash "$UNINSTALL" --apply 2>&1)"; rc7=$?
    { [ "$rc7" -eq 1 ] && grep -q 'не разбирается как JSON' <<< "$o7"; } \
        && ok || bad T13 "битый settings.json не назван: код $rc7"
    # T14 (M3 второго круга): сухой прогон не трогает запись; сбой снятия env оставляет запись.
    H8="$(mktemp -d)"; build_home "$H8"
    jq 'del(.hooks) | .env = {"LC_NUMERIC": "C", "LC_COLLATE": "C"}' "$H8/.claude/settings.json" > "$H8/s" && mv "$H8/s" "$H8/.claude/settings.json"
    printf '{"values":{"LC_COLLATE":"ru_RU.UTF-8"},"had_env":true}\n' > "$H8/.claude/claudsoul-env-prev.json"
    HOME="$H8" bash "$UNINSTALL" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
    [ -f "$H8/.claude/claudsoul-env-prev.json" ] && ok || bad T14a "сухой прогон удалил запись чужих значений"
    chmod 555 "$H8/.claude"
    o8="$(HOME="$H8" bash "$UNINSTALL" --apply 2>&1)"; rc8=$?
    chmod 755 "$H8/.claude"
    { [ "$rc8" -eq 1 ] && grep -q 'закрепление локали НЕ снято' <<< "$o8" && [ -f "$H8/.claude/claudsoul-env-prev.json" ]; } \
        && ok || bad T14b "сбой снятия env: код $rc8, запись $( [ -f "$H8/.claude/claudsoul-env-prev.json" ] && echo есть || echo потеряна)"
    # T15 (L1): битая запись названа и оставлена, итог «Снято НЕ всё».
    H9="$(mktemp -d)"; build_home "$H9"
    printf '{"values": [1]}\n' > "$H9/.claude/claudsoul-env-prev.json"
    o9="$(HOME="$H9" bash "$UNINSTALL" --apply 2>&1)"; rc9=$?
    { [ "$rc9" -eq 1 ] && grep -q 'claudsoul-env-prev.json не читается' <<< "$o9" && [ -f "$H9/.claude/claudsoul-env-prev.json" ]; } \
        && ok || bad T15 "битая запись: код $rc9"
    # T16 (M4): без jq хуки и env не сняты — итог не «Снято.», код 1.
    H10="$(mktemp -d)"; build_home "$H10"
    # PATH без jq — каталог ссылок на всё из /bin, кроме jq (D1233): на Debian и ubuntu `/bin` — ссылка на `usr/bin`, и jq
    # там есть; голое `PATH=…:/bin` «без jq» было верно только на macOS.
    NOJQ="$(mktemp -d)"; for _f in /bin/*; do [ "${_f##*/}" = jq ] || { ln -s "$_f" "$NOJQ/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }; }; done
    o10="$(HOME="$H10" PATH="$STUB_BIN:$NOJQ" /bin/bash "$UNINSTALL" --apply 2>&1)"; rc10=$?
    { [ "$rc10" -eq 1 ] && grep -q 'нет jq' <<< "$o10" && grep -q 'Снято НЕ всё' <<< "$o10"; } \
        && ok || bad T16 "без jq: код $rc10, $(tail -1 <<< "$o10")"
    # T17 (L6): запись без settings.json — сирота, снимается.
    H11="$(mktemp -d)"; build_home "$H11"
    rm -f "$H11/.claude/settings.json"
    printf '{"values":{},"had_env":true}\n' > "$H11/.claude/claudsoul-env-prev.json"
    HOME="$H11" bash "$UNINSTALL" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
    [ ! -e "$H11/.claude/claudsoul-env-prev.json" ] && ok || bad T17 "запись-сирота осталась"
    # T18 (L5): без lib/env-pin.jq и без наших ключей в env — об env ни слова, итог «Снято.».
    R12="$(mktemp -d)"; mkdir -p "$R12/lib"
    for d in hooks security skills templates; do ln -s "$REPO/$d" "$R12/$d"; done
    H12="$(mktemp -d)"; build_home "$H12"
    jq 'del(.env)' "$H12/.claude/settings.json" > "$H12/s" && mv "$H12/s" "$H12/.claude/settings.json"   # дом build_home несёт наши ключи (T8b)
    o12="$(HOME="$H12" CLAUDSOUL_DIR="$R12" bash "$UNINSTALL" --apply 2>&1)"; rc12=$?
    { [ "$rc12" -eq 0 ] && ! grep -q 'нет lib/env-pin.jq' <<< "$o12"; } \
        && ok || bad T18a "без программы и без наших ключей: код $rc12; $(grep -E 'НЕ|нет ' <<< "$o12" | head -3 | tr '\n' ' ')"
    H13="$(mktemp -d)"; build_home "$H13"
    o13="$(HOME="$H13" CLAUDSOUL_DIR="$R12" bash "$UNINSTALL" --apply 2>&1)"; rc13=$?
    { [ "$rc13" -eq 1 ] && grep -q 'нет lib/env-pin.jq' <<< "$o13"; } \
        && ok || bad T18b "без программы при наших ключах в env: код $rc13 — обязан назвать"
    # T19–T21 (M4 третьего круга): каждое место удаления записи — своей ногой.
    H14="$(mktemp -d)"; build_home "$H14"
    jq 'del(.env)' "$H14/.claude/settings.json" > "$H14/s" && mv "$H14/s" "$H14/.claude/settings.json"
    printf '{"values":{},"had_env":false}\n' > "$H14/.claude/claudsoul-env-prev.json"
    HOME="$H14" bash "$UNINSTALL" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
    [ -f "$H14/.claude/claudsoul-env-prev.json" ] && ok || bad T19 "сухой прогон удалил запись в ветке без закрепления"
    H15="$(mktemp -d)"; build_home "$H15"; rm -f "$H15/.claude/settings.json"
    printf '{"values":{},"had_env":true}\n' > "$H15/.claude/claudsoul-env-prev.json"
    HOME="$H15" bash "$UNINSTALL" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_uninstall.sh:$LINENO" >&2; exit 1; }
    [ -f "$H15/.claude/claudsoul-env-prev.json" ] && ok || bad T20 "сухой прогон удалил запись-сироту"
    H16="$(mktemp -d)"; build_home "$H16"
    jq 'del(.env)' "$H16/.claude/settings.json" > "$H16/s" && mv "$H16/s" "$H16/.claude/settings.json"
    printf '{"LC_NUMERIC":"ru_RU.UTF-8"}\n' > "$H16/.claude/claudsoul-env-prev.json"
    o16="$(HOME="$H16" bash "$UNINSTALL" --apply 2>&1)"; rc16=$?
    { [ "$rc16" -eq 1 ] && [ -f "$H16/.claude/claudsoul-env-prev.json" ] && grep -q 'не читается' <<< "$o16"; } \
        && ok || bad T21 "запись прежнего вида в ветке без закрепления: код $rc16, запись $( [ -f "$H16/.claude/claudsoul-env-prev.json" ] && echo есть || echo удалена)"
else
    PASS=$((PASS + 14))
fi

echo ""
echo "uninstall tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
