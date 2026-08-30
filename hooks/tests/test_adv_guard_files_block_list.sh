#!/usr/bin/env bash
# test_adv_guard_files_block_list.sh — блок «Файлы», оформленный списком с новой строки,
# не даёт стражу ни одного утверждения: пустая строка после маркера обрывает блок сразу.
#
# Вход: модульный док в обычной markdown-разметке —
#     **Файлы.**
#     (пустая строка)
#     - `hooks/partial-read-guard.sh` (Stop) — ЛОЖЬ, хук на PostToolUse
#     - `hooks/module-doc-check.sh` (Stop) — ЛОЖЬ, хук на PreToolUse
# Ожидание: два расхождения, код 1.
# Факт: `claims()` режет блок по `text.find("\n\n", start)`, а пустая строка стоит сразу за
#   маркером. Блок вырождается в саму строку «**Файлы.**», утверждений извлекается ноль.
#   Печатается «утверждений о регистрации проверено: 0, расходятся: 0», код 0. Тот же исход
#   даёт список, разбитый пустой строкой посередине: всё после неё вне предмета.
#
# Достижимость: замер по дереву на 29 августа 2026 — 17 модульных доков из 18 пишут состав в
#   той же строке, что и маркер, ablation-runner.md — таблицей со следующей строки (её блок
#   захватывается). Вёрстки «пустая строка, затем список» в модульных доках пока нет, но в
#   README.md она встречается дважды: привычка в проекте есть, запрета на неё нет нигде.
#   Первый же док, свёрстанный списком, выпадет молча, и вывод стража об этом не скажет —
#   он печатает, сколько утверждений НАШЁЛ, а не сколько их в документах.
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
cfg = json.loads(m.group(1)); ev = {}
for e, gs in cfg.get("hooks", {}).items():
    for g in gs:
        for h in g.get("hooks", []):
            for n in ("partial-read-guard.sh", "module-doc-check.sh"):
                if n in h.get("command", ""): ev.setdefault(n, set()).add(e)
ok = all(n in ev and "Stop" not in ev[n] for n in ("partial-read-guard.sh", "module-doc-check.sh"))
print("OK" if ok else "SKIP")
PY
)
[ "$premise" = "OK" ] || { echo "SKIP: посылка входа изменилась (хуки и Stop)"; exit 0; }

T="$(mktemp -d)"; P="$T/repo"
mkdir -p "$P/hooks/tests" "$P/.claude-docs/modules"
cp "$REPO/install.sh" "$P/install.sh"
cp "$GUARD_SRC" "$P/hooks/tests/guard.sh"

cat > "$P/.claude-docs/modules/spisok.md" <<'MD'
# Модуль: список файлов

**Файлы.**

- `hooks/partial-read-guard.sh` (Stop) — счётчик прочитанных строк.
- `hooks/module-doc-check.sh` (Stop) — страж модульных доков.

**Зависимости.** jq.
MD

out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
echo "код возврата стража: $rc"

fail=0
case "$out" in
    *"проверено: 0"*)
        echo "ПРОВАЛ: в документе два утверждения о регистрации, извлечено ноль — блок оборван пустой строкой после маркера"
        fail=1 ;;
esac
if [ "$rc" -eq 0 ]; then
    echo "ПРОВАЛ: оба утверждения ложны (хуки не на Stop), а код возврата 0"
    fail=1
fi
[ "$fail" -eq 0 ] && echo "OK: блок «Файлы» читается независимо от вёрстки списка"
exit "$fail"
