#!/usr/bin/env bash
# АТАКА: верное утверждение о matcher'е объявлено расхождением, если названо не всё.
#
# `matcher_ok` признаёт заявленное либо полным совпадением строки, либо ОДНИМ элементом
# из `real.split("|")`. Заявленное подмножество из двух элементов — `PreToolUse[Edit|Write]`
# у хука с matcher'ом `Edit|Write|MultiEdit|Bash` — не проходит ни ту, ни другую ветвь.
# Утверждение при этом истинно: хук на Edit и на Write срабатывает.
#
# Вход: док с matcher'ом-подмножеством настоящего.
# Ожидание: 0 расхождений.
# Факт: «заявлено matcher …; в install.sh — …», код возврата 1 — правки требуют от
# верного документа, ровно тем способом, который страж перечисляет в своих комментариях
# как отвергнутый.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PICK=$(python3 - "$REPO/install.sh" <<'PY'
import json, pathlib, re, sys
cfg = json.loads(re.search(r"HOOKS_CONFIG='(\{.*?\n\})'",
                           pathlib.Path(sys.argv[1]).read_text(), re.S).group(1))
best = None
for ev, groups in cfg["hooks"].items():
    for g in groups:
        mt = g.get("matcher", "")
        if len(mt.split("|")) < 3:
            continue
        for h in g.get("hooks", []):
            m = re.search(r"hooks/([A-Za-z0-9._-]+\.sh)", h.get("command", ""))
            if m and not m.group(1).endswith("-lib.sh"):
                # хук ровно с одной регистрацией — чтобы вход не смешивал два дефекта
                seen = sum(1 for e2, gs in cfg["hooks"].items() for g2 in gs
                           for h2 in g2.get("hooks", [])
                           if m.group(1) in h2.get("command", ""))
                if seen == 1:
                    best = (m.group(1), ev, mt)
                    break
        if best:
            break
    if best:
        break
if best:
    name, ev, mt = best
    parts = mt.split("|")
    print(f"{name};{ev};{mt};{'|'.join(parts[:2])}")
PY
)
[ -n "$PICK" ] || { echo "SKIP: не нашёл хука с составным matcher'ом"; exit 0; }
IFS=';' read -r HOOK EVENT REAL_M SUB <<< "$PICK"
STEM="${HOOK%.sh}"

TMP=$(mktemp -d)
D="$TMP/repo"
mkdir -p "$D/hooks/tests" "$D/.claude-docs/modules"
cp "$REPO/install.sh" "$D/"
cp "$GUARD" "$D/hooks/tests/"

cat > "$D/.claude-docs/modules/$STEM.md" <<DOC
# Модуль $STEM

**Назначение.** Что-то делает.

**Файлы.** \`hooks/$HOOK\` ($EVENT[$SUB], инжект additionalContext).
DOC

OUT=$(bash "$D/hooks/tests/test_module_doc_registration_claims.sh" 2>&1)
RC=$?
echo "  настоящий matcher: $EVENT[$REAL_M]; в доке названо подмножество $EVENT[$SUB]"
printf '%s\n' "$OUT" | sed 's/^/  | /'
echo "  код возврата: $RC"

if [ "$RC" -eq 0 ]; then
    echo "PASS: верное подмножество matcher'а пропущено"
    exit 0
fi
echo "FAIL: утверждение $EVENT[$SUB] истинно — хук срабатывает на каждом из названных"
echo "      инструментов, — а страж объявил его расхождением. Проверка признаёт лишь"
echo "      точное совпадение строки или ОДИН элемент из real.split(\"|\")."
exit 1
