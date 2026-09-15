#!/usr/bin/env bash
# test_adv_guard_second_files_block.sh — проверяется только ПЕРВЫЙ блок «Файлы» документа;
# утверждение во втором не сверяется ни с чем.
#
# Вход: модульный док с двумя блоками «Файлы» (модуль из двух частей — обычная форма):
#   первый — правдивый (`hooks/session-collector.sh` (Stop)), второй — ложный
#   (`hooks/partial-read-guard.sh` (Stop), в install.sh хук стоит на PostToolUse).
# Ожидание: расхождение названо, код 1.
# Факт: `claims()` берёт `text.find("**Файлы.**")` — первое вхождение — и режет блок до
#   первой пустой строки. Второй блок в предмет проверки не входит вовсе. Печатается
#   «утверждений о регистрации проверено: 1, расходятся: 0», код 0. Счётчик «проверено»
#   при этом сам сообщает, что проверено меньше, чем заявлено в документе, — но сравнивать
#   его не с чем: сколько утверждений в доке НА САМОМ ДЕЛЕ, страж не считает.
#
# Достижимость: маркер «**Файлы.**» ничем не ограничен в одном экземпляре на документ, а
#   структура «блок на каждую часть модуля» уже встречается в дереве (docs-audit.md несёт
#   слово «**Файлы.**» дважды: в блоке и в объяснении). Второй блок — вопрос времени, и
#   именно он окажется непроверенным молча.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_SRC="$REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD_SRC" ] || { echo "FAIL: нет $GUARD_SRC"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

# Посылка входа: partial-read-guard.sh НЕ зарегистрирован на Stop.
premise=$(python3 - "$REPO/install.sh" <<'PY'
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S)
if not m: print("SKIP"); raise SystemExit
cfg = json.loads(m.group(1)); evs = set()
for ev, gs in cfg.get("hooks", {}).items():
    for g in gs:
        for h in g.get("hooks", []):
            if "partial-read-guard.sh" in h.get("command", ""): evs.add(ev)
print("OK" if evs and "Stop" not in evs else "SKIP")
PY
)
[ "$premise" = "OK" ] || { echo "SKIP: посылка входа изменилась (partial-read-guard и Stop)"; exit 0; }

T="$(mktemp -d)"; P="$T/repo"
mkdir -p "$P/hooks/tests" "$P/.claude-docs/modules"
cp "$REPO/install.sh" "$P/install.sh"
cp "$GUARD_SRC" "$P/hooks/tests/guard.sh"

cat > "$P/.claude-docs/modules/two-blocks.md" <<'MD'
# Модуль: сборщик и счётчик

**Файлы.** `hooks/session-collector.sh` (Stop) — сборщик итога сессии.

**Зависимости.** jq.

## Вторая часть

**Файлы.** `hooks/partial-read-guard.sh` (Stop) — счётчик прочитанных строк.

**Зависимости.** jq.
MD

out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
echo "код возврата стража: $rc"

# Положительный контроль. Предполагалось: ненулевой код значит «расхождение второго блока
# названо». Ложно: тот же код даёт страж, упавший с трассировкой (прогон 7 сентября 2026 —
# исключение в `claims()`: код 1, вывод без строки «проверено», тест зелёный на ослепшем
# страже). Теперь держат две величины и адрес: осмотрено ≥ 2 (в документе два утверждения,
# по блоку на часть) и расхождение названо для хука ВТОРОГО блока. Счёт «проверено: 1»
# прежней ноги стал частным случаем условия «< 2».
checked=$(printf '%s\n' "$out" | sed -n 's/.*проверено: \([0-9][0-9]*\).*/\1/p' | head -1)
diverged=$(printf '%s\n' "$out" | sed -n 's/.*расходятся с install.sh: \([0-9][0-9]*\).*/\1/p' | head -1)
: "${checked:=-1}"
: "${diverged:=-1}"

named=0
case "$out" in *"two-blocks.md"*"partial-read-guard.sh"*"Stop"*) named=1 ;; esac

fail=0
if [ "$checked" -lt 2 ]; then
    echo "ПРОВАЛ: утверждений в документе два, осмотрено $checked — второй блок в предмет не попал"
    fail=1
fi
if [ "$rc" -eq 0 ] || [ "$diverged" -lt 1 ] || [ "$named" -eq 0 ]; then
    echo "ПРОВАЛ: во втором блоке заявлено событие Stop для хука, стоящего на PostToolUse, — расхождение не названо (код $rc, расхождений $diverged, адрес назван: $named)"
    fail=1
fi
[ "$fail" -eq 0 ] && echo "OK: сверяются все блоки «Файлы» документа"
exit "$fail"
