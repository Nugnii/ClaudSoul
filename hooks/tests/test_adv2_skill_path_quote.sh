#!/usr/bin/env bash
# test_adv2_skill_path_quote.sh — `tr -d '"'` портит путь, который git выдал в кавычках
# с escape-последовательностью, и оба стража молча пропускают скилл.
#
# Атака. Фильтр `^"?skills/[^/]+/SKILL\.md"?$` | `tr -d '"'` рассчитан на то, что кавычки
# — только обёртка. Но git кавычит имя и ПРИ quotepath=false, если в нём есть `"`, `\`
# или управляющий символ, и при этом ЭКРАНИРУЕТ его внутри:
#     skills/sk"ill/SKILL.md   →   "skills/sk\"ill/SKILL.md"
# `tr -d '"'` снимает обе внешние кавычки и внутреннюю, а обратный слэш оставляет:
#     skills/sk\ill/SKILL.md
# Такого пути нет ни в индексе, ни на диске:
#   • quality-gate-check:  `git show ":$rel"` → `|| return 0` — контракт не проверен;
#   • skill-review-check:  `git show` падает, откат на рабочий файл, `[ -f ]` ложно
#                          → `return 0` — контракт не проверен.
# Итог: скилл с нарушенным контрактом уходит в коммит через оба гейта молча.
#
# Контроль в том же тесте: тот же самый файл в каталоге с ASCII-именем ловится обоими.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# SKILL.md, нарушающий контракт по всем пунктам: нет frontmatter, нет **Type:**,
# нет Definition of Done, нет Version/Last Updated.
BAD_SKILL='# Скилл без контракта

Тело без единого обязательного поля.
'

make_repo() {   # make_repo <имя каталога скилла>
    local repo="$TMP/repo"
    rm -rf "$repo"; mkdir -p "$repo"
    ( cd "$repo" && git init -q . && git config user.email adv@test && git config user.name adv )
    mkdir -p "$repo/docs"; echo "seed" > "$repo/docs/seed.md"
    ( cd "$repo" && git add -A && git commit -qm init )
    mkdir -p "$repo/skills/$1"
    printf '%s' "$BAD_SKILL" > "$repo/skills/$1/SKILL.md"
    ( cd "$repo" && git add -A )
    printf '%s' "$repo"
}

run_hook() {   # run_hook <хук> <репозиторий>
    rm -rf "$TMP/state"; mkdir -p "$TMP/state" "$TMP/home"
    printf '{"session_id":"adv2-%s","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' \
        "$RANDOM" "$2" \
        | env HOME="$TMP/home" STATE_DIR="$TMP/state" bash "$HOOKS_DIR/$1" 2>/dev/null
}

check() {   # check <label> <output>
    local label="$1" out="$2"
    if grep -qF 'additionalContext' <<< "$out"; then
        PASS=$((PASS + 1)); echo "PASS [$label]"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: страж промолчал на SKILL.md без контракта"
        echo "       вывод хука: ${out:-<пусто>}"
    fi
}

for hook in quality-gate-check.sh skill-review-check.sh; do
    [ -f "$HOOKS_DIR/$hook" ] || { echo "FAIL: $HOOKS_DIR/$hook not found"; exit 1; }

    REPO=$(make_repo 'plainname')
    check "контроль $hook: skills/plainname/SKILL.md" "$(run_hook "$hook" "$REPO")"

    REPO=$(make_repo 'sk"ill')
    check "атака $hook: skills/sk\"ill/SKILL.md — тот же файл, имя с кавычкой" \
        "$(run_hook "$hook" "$REPO")"
done

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
