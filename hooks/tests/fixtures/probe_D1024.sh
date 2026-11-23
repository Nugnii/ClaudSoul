#!/usr/bin/env bash
# СУДИТ: hooks/docs-family-check.sh
# probe_D1024.sh — страж семейства документов в ловушке git находит номер версии в документе, где бы он ни стоял (D1024).
#
# Коды: 0 — во временном репозитории ловушка `--commit-msg` не называет `CHANGELOG.md`, где новая версия стоит в первой
#       строке и за ней 200 КБ текста, и называет контроль `PLAN.md`, который версии вёл, а новую не упомянул;
#       1 — `CHANGELOG.md` назван «нет упоминания» (дефект D1024: `git show | grep -Fq` под `pipefail` — `grep` выходит
#       на первом совпадении, `git show` получает SIGPIPE, статус конвейера 141 читается «не нашёл»);
#       2 — судить нечем: нет стража или git, либо контроль не назван (страж молчит на всём).
# Повод — 22 октября 2026, релизы ProjectA v2.122.1 и v2.122.2: ловушка назвала три документа, где номер был.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/docs-family-check.sh"
[ -f "$HOOK" ] || exit 2
command -v git >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state" GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n' > "$GIT_CONFIG_GLOBAL"
R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q || exit 2
printf 'v1.0.0\n' > "$R/CHANGELOG.md"; printf 'v1.0.0\n' > "$R/PLAN.md"
git -C "$R" add -A && git -C "$R" commit -qm init || exit 2
{ printf '## [1.0.1]\n'; head -c 200000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$R/CHANGELOG.md"
printf 'v1.0.0 plan\n' > "$R/PLAN.md"
git -C "$R" add -A || exit 2
printf 'm\n' > "$T/msg"
OUT=$(cd "$R" && bash "$HOOK" --commit-msg "$T/msg" 2>&1)
case "$OUT" in *"PLAN.md (нет упоминания"*) ;; *) exit 2 ;; esac
case "$OUT" in *"CHANGELOG.md (нет упоминания"*) exit 1 ;; esac
exit 0
