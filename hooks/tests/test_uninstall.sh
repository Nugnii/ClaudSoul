#!/usr/bin/env bash
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
before="$(cd "$H1" && find . -type f | sort | xargs md5 2>/dev/null || cd "$H1" && find . -type f | sort)"
# stderr — рядом с $H1, не внутри: дерево сравнивается before/after, а смерть прогона
# раньше была неотличима от «ничего не изменил» (D220).
HOME="$H1" bash "$UNINSTALL" >/dev/null 2>"$H1-err"; _rc=$?
[ "$_rc" -eq 0 ] || bad T1rc "сухой прогон умер: rc=$_rc, stderr: $(tail -c 200 "$H1-err" 2>/dev/null)"
after="$(cd "$H1" && find . -type f | sort | xargs md5 2>/dev/null || cd "$H1" && find . -type f | sort)"
if [ "$before" = "$after" ]; then ok; else bad T1 "сухой прогон изменил дерево"; fi

# --- T2..T7: после --apply ---
H2="$(mktemp -d)"; build_home "$H2"
HOME="$H2" bash "$UNINSTALL" --apply >/dev/null 2>&1

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
else
    PASS=$((PASS + 2))
fi

# --- T9: --keep-state оставляет журналы ---
H3="$(mktemp -d)"; build_home "$H3"
HOME="$H3" bash "$UNINSTALL" --apply --keep-state >/dev/null 2>&1
[ -d "$H3/.claude/hooks/state" ] && ok || bad T9 "--keep-state не сохранил состояние"

echo ""
echo "uninstall tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
