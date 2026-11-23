#!/usr/bin/env bash
set -u
# СУДИТ: hooks/changelog-reminder.sh hooks/docs-family-check.sh hooks/backlog-vanish-check.sh
# probe_D1279 — братья D1278: стражи PreToolUse-суда коммита судят репозиторий, В КОТОРЫЙ идёт коммит (`cd <другой> &&
#   git commit`), а не папку сессии. Папка сессии — репозиторий с поводом для каждого стража (код без CHANGELOG, подъём
#   версии без семьи документов, исчезнувший открытый пункт бэклога), другой репозиторий — чистый:
#   (п) `cd <другой> && git commit` — страж молчит (судит другой, там повода нет);
#   (к) `git commit` в самой сессии — страж говорит (положительный контроль: повод в рамке живой).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v git >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
O="$W/other"; mkdir -p "$O" && g "$O" init -q && printf 'x\n' > "$O/f.txt" && g "$O" add f.txt || exit 2
sess() {   # <хук> → каталог сессии с поводом для этого стража
    local S="$W/s-$1"; mkdir -p "$S" && g "$S" init -q || return 1
    case "$1" in
        changelog-reminder)
            printf '# CHANGELOG\n' > "$S/CHANGELOG.md"; g "$S" add -A && g "$S" commit -qm base || return 1
            printf 'echo x\n' > "$S/x.sh"; g "$S" add x.sh ;;
        docs-family-check)
            printf '1.0.0\n' > "$S/VERSION"; printf '# C\n' > "$S/CHANGELOG.md"; printf '# R\n' > "$S/README.md"
            g "$S" add -A && g "$S" commit -qm base || return 1
            printf '1.0.1\n' > "$S/VERSION"; g "$S" add VERSION ;;
        backlog-vanish-check)
            printf '%s\n' '# BACKLOG' '' '- ☐ **D1** пункт' '  **Корень.** R3 — роль.' > "$S/BACKLOG.md"
            g "$S" add -A && g "$S" commit -qm base || return 1
            printf '%s\n' '# BACKLOG' '' > "$S/BACKLOG.md"; g "$S" add BACKLOG.md ;;
    esac
    printf '%s' "$S"
}
said() {   # <хук> <каталог сессии> <команда> → 1, если страж что-то сказал
    local out
    out=$(jq -nc --arg c "$3" --arg d "$2" --arg s "s-d1279-$1-$RANDOM" \
        '{hook_event_name:"PreToolUse",session_id:$s,cwd:$d,tool_name:"Bash",tool_input:{command:$c}}' \
        | (cd "$2" && env -u CLAUDECODE -u AI_AGENT STATE_DIR="$W/state-$1" bash "$R/hooks/$1.sh") 2>/dev/null)
    [ -n "$out" ] && echo 1 || echo 0
}
miss=""
for h in changelog-reminder docs-family-check backlog-vanish-check; do
    [ -f "$R/hooks/$h.sh" ] || exit 2
    mkdir -p "$W/state-$h"
    S=$(sess "$h") || exit 2
    k=$(said "$h" "$S" "git commit -qm x")
    [ "$k" = 1 ] || { echo "рамка: $h молчит и на коммите в самой сессии" >&2; exit 2; }
    p=$(said "$h" "$S" "cd \"$O\" && git commit -qm x")
    [ "$p" = 0 ] || miss="$miss $h;"
    # (к2) коммит в саму сессию из её подкаталога — судится корень репозитория сессии, страж говорит (скептик D1279, M3:
    #      шаг «корень» у docs-family-check ничем не охранялся); (м) коммиты в другой и в сессию одной командой —
    #      каталог не один, судится сессия (M2: прежде первый коммит снимал суд второго).
    mkdir -p "$S/sub"
    [ "$(said "$h" "$S" "cd sub && git commit -qm x")" = 1 ] || miss="$miss $h (подкаталог сессии молчит);"
    [ "$(said "$h" "$S" "cd \"$O\" && git commit -qm a; cd \"$S\" && git commit -qm x")" = 1 ] || miss="$miss $h (второй коммит в сессию не судится);"
done
[ -z "$miss" ] && { echo "коммит в другой репозиторий судится там, куда идёт: стражи молчат; в самой сессии говорят"; exit 0; }
echo "судят папку сессии на коммите в другой репозиторий:$miss"
exit 1
