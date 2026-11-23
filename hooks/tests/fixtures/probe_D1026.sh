#!/usr/bin/env bash
# СУДИТ: hooks/pipefail-grep-q-notice.sh hooks/bash-write-dispatch.sh
# probe_D1026.sh — подсказка стража записи доходит до агента, а нечитаемый ответ стража не читается как «чисто» (D1026).
#
# Коды: 0 — страж `pipefail-grep-q-notice` на строке, чей разрез до 100 знаков ложится после `\`, и на строке с `\` в
#       образце `grep` отвечает разбираемым JSON с подсказкой; диспетчер записи командой называет стража, ответившего
#       не JSON протокола; 1 — дефект D1026: вывод стража не разбирается (подсказка теряется на обоих путях) либо
#       диспетчер записал нечитаемый ответ пройденной парой молча; 2 — судить нечем: нет стража, диспетчера или jq,
#       страж молчит на дефектной строке, либо диспетчер не донёс и разбираемую находку (контроль).
# Повод — 22 октября 2026 (D1024): страж узнал строку 316 `docs-family-check.sh`, след записан, подсказки нет.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
GUARD="$REPO/hooks/pipefail-grep-q-notice.sh"
DISP="bash-write-""dispatch.sh"   # имя собрано из частей: в песочнице все стражи — заглушки (образец test_adv_dispatch_guard_crash_passed.sh)
[ -f "$GUARD" ] && [ -f "$REPO/hooks/$DISP" ] && [ -f "$REPO/hooks/paths-lib.sh" ] || exit 2
for t in git jq; do command -v "$t" >/dev/null 2>&1 || exit 2; done
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT

# (а) Страж записи: вывод — JSON протокола с подсказкой.
L1='        if [ "$TRAP" -eq 1 ]; then project_git -C "$CWD" show ":$doc" 2>/dev/null | grep -Fq "$VER_PLAIN" && continue'  # sigpipe-ok: образец, который судит страж
L2='ok=$(printf "%s" "$v" | grep -qE '"'"'\.sh$'"'"') && echo ok'  # sigpipe-ok: образец, который судит страж
for L in "$L1" "$L2"; do
    OUT=$(jq -n --arg c "$(printf 'set -o pipefail\n%s\n' "$L")" --arg f "$T/x.sh" \
            '{session_id:"probe-d1026",tool_name:"Write",tool_input:{file_path:$f,content:$c}}' \
          | STATE_DIR="$T/state" bash "$GUARD" 2>/dev/null)
    [ -n "$OUT" ] || exit 2
    jq -e '.hookSpecificOutput.additionalContext | test("Пайп в grep -q")' >/dev/null 2>&1 <<< "$OUT" || exit 1
done

# (б) Диспетчер: страж с нечитаемым ответом назван; контроль — разбираемая находка другого стража дошла.
SB="$T/sb"; SR="$T/repo"; SH="$T/home"; mkdir -p "$SB/hooks" "$SR" "$SH"
cp "$REPO/hooks/$DISP" "$REPO/hooks/paths-lib.sh" "$SB/hooks/" || exit 2
GL=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP"); set -- $GL; [ "$#" -ge 2 ] || exit 2
G_BAD=$1 G_CTL=$2
for g in $GL; do printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/hooks/$g"; done
printf '%s\n' '#!/usr/bin/env bash' 'case "$(cat)" in *BAD-KEY*) printf "%s\n" "{\"hookSpecificOutput\":{\"additionalContext\":\"a \\»\"}}" ;; esac' > "$SB/hooks/$G_BAD"
printf '%s\n' '#!/usr/bin/env bash' 'case "$(cat)" in *CTL-KEY*) printf "%s\n" "{\"hookSpecificOutput\":{\"additionalContext\":\"CTL-FOUND\"}}" ;; esac' > "$SB/hooks/$G_CTL"
( cd "$SR" && export HOME="$SH" GIT_CONFIG_NOSYSTEM=1 && git init -q . && echo base > base.md && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || exit 2
touch -t 202001010000 "$SR/base.md"
run() { printf '{"tool_name":"Bash","session_id":"probe-d1026","cwd":"%s"}' "$SR" \
    | env HOME="$SH" GIT_CONFIG_NOSYSTEM=1 STATE_DIR="$T/dstate" PATHS_LIB="$SB/hooks/paths-lib.sh" \
          BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null; }
run >/dev/null; sleep 1
echo "BAD-KEY" > "$SR/a.md"; echo "CTL-KEY" > "$SR/b.md"
D=$(run)
grep -qF "CTL-FOUND" <<< "$D" || exit 2
grep -qF "${G_BAD%.sh}" <<< "$D" || exit 1
exit 0
