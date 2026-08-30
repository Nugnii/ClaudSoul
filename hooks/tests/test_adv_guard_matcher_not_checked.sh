#!/usr/bin/env bash
# test_adv_guard_matcher_not_checked.sh — заявленный matcher не сверяется, и об этом не
# сказано: страж отчитывается «утверждение проверено», проверив половину утверждения.
#
# Вход: модульный док с записью `hooks/module-doc-check.sh` (PreToolUse[Read], …).
#   В install.sh хук стоит на PreToolUse с matcher «Bash»: на чтении файлов он не срабатывает
#   никогда. Форма записи взята из дерева дословно — так пишут module-doc-check.md
#   (`PreToolUse[Bash]`), five-whys-gate.md (`PreToolUse[Edit|Write|MultiEdit|Bash]`),
#   partial-read-guard.md (`PostToolUse[Read]`).
# Ожидание: либо расхождение названо (matcher сверяется), либо в выводе сказано, что
#   matcher не проверяется, — тогда «проверено» означает то, что означает.
# Факт: `events_in` берёт из скобок только имя события, скобочная часть `[Read]` не
#   участвует ни в сверке, ни в выводе. Печатается «утверждений о регистрации проверено: 1,
#   расходятся с install.sh: 0», код 0. Ложное утверждение о дереве — ровно то, ради чего
#   страж заведён, — прошло с отметкой «проверено».
#
# Достижимость: matcher назван в шести модульных доках из восемнадцати (backlog-vanish-check,
#   partial-read-guard, module-doc-check, five-whys-gate, doc-impact-check, rules-write-bypass),
#   то есть эта форма утверждения в дереве уже живёт; перенос хука на другой matcher (обычная правка: сузить
#   с Bash до Bash+Edit, снять Read) не встретит ни одного сторожа.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_SRC="$REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD_SRC" ] || { echo "FAIL: нет $GUARD_SRC"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

premise=$(python3 - "$REPO/install.sh" <<'PY'
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S)
if not m: print("SKIP"); raise SystemExit
cfg = json.loads(m.group(1)); pairs = set()
for e, gs in cfg.get("hooks", {}).items():
    for g in gs:
        for h in g.get("hooks", []):
            if "module-doc-check.sh" in h.get("command", ""):
                pairs.add((e, g.get("matcher", "")))
print("OK" if pairs == {("PreToolUse", "Bash")} else "SKIP")
PY
)
[ "$premise" = "OK" ] || { echo "SKIP: посылка входа изменилась (module-doc-check и matcher Bash)"; exit 0; }

T="$(mktemp -d)"; P="$T/repo"
mkdir -p "$P/hooks/tests" "$P/.claude-docs/modules"
cp "$REPO/install.sh" "$P/install.sh"
cp "$GUARD_SRC" "$P/hooks/tests/guard.sh"

cat > "$P/.claude-docs/modules/matcher.md" <<'MD'
# Модуль: страж модульных доков

**Файлы.** `hooks/module-doc-check.sh` (PreToolUse[Read], инжект при чтении файлов).

**Зависимости.** git, jq.
MD

echo "в install.sh: module-doc-check.sh на PreToolUse, matcher Bash"
echo "в документе:  PreToolUse[Read] — на чтении хук не срабатывает никогда"
out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
echo "код возврата стража: $rc"

honest=0
case "$out" in
    *matcher*|*Matcher*|*"[Read]"*|*"не сверя"*|*"не провер"*) honest=1 ;;
esac

fail=0
if [ "$rc" -eq 0 ] && [ "$honest" -eq 0 ]; then
    echo "ПРОВАЛ: ложный matcher принят молча — вывод объявляет утверждение проверенным, сверив только событие"
    fail=1
fi
[ "$fail" -eq 0 ] && echo "OK: matcher либо сверяется, либо объявлен непроверяемым"
exit "$fail"
