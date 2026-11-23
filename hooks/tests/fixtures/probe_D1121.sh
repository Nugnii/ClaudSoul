#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh hooks/backlog-vanish-check.sh
# probe_D1121 — «бэклог не прочитан» и «бэклог пуст» различаются у библиотеки и у её читателя. Красная (1), пока
# `backlog_read` отвечает кодом 0 и пустотой на файл без права на чтение, а страж исчезновения пунктов, судящий только
# наличие файла, называет каждый пункт HEAD исчезнувшим, хотя содержимое не менялось. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
LIB="$R/hooks/backlog-lib.sh"; HOOK="$R/hooks/backlog-vanish-check.sh"
[ -f "$LIB" ] && [ -f "$HOOK" ] && command -v git >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 2
[ "$(id -u)" -ne 0 ] || exit 2   # у root право на чтение не отнять
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1121.XXXXXX") || exit 2
cd "$T" && git init -q . && git config user.email t@t && git config user.name t || exit 2
printf -- '- ☐ **D10** первый\n- ☐ **D11** второй\n' > BACKLOG.md; printf 'архив\n' > BACKLOG-archive.md
git add -A && git commit -qm base || exit 2
chmod 000 BACKLOG.md
cat BACKLOG.md >/dev/null 2>&1 && { chmod 644 BACKLOG.md; exit 2; }   # право не отнялось — рамка
( . "$LIB" && backlog_read "$T/BACKLOG.md" >/dev/null 2>&1 ); rc=$?
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash "$HOOK" 2>/dev/null)
chmod 644 BACKLOG.md
[ "$rc" -ne 0 ] || { echo "backlog_read ответил 0 на нечитаемый бэклог" >&2; exit 1; }
grep -q 'D1[01]' <<< "$OUT" && { echo "нечитаемый бэклог назван исчезновением пунктов" >&2; exit 1; }
# Положительный контроль: читаемый бэклог без пункта — страж называет пропажу.
printf -- '- ☐ **D10** первый\n' > BACKLOG.md
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash "$HOOK" 2>/dev/null)
grep -q 'D11' <<< "$OUT" || exit 2
echo "нечитаемый бэклог — не пустой"
exit 0
