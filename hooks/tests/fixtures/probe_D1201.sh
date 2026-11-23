#!/usr/bin/env bash
# СУДИТ: scripts/backlog-recheck.sh
# Проба D1201: промолчавшая красная «Проверка» архива несёт в итоге сверщика (`--archive`) подсказку, что именно не
# так, — повтор без глушения, с трассой. Две живые формы молчащих красных: значения в самой команде
# (`n=1; [ "$n" -eq 0 ]`, как у D477) и проба-файл под глушением (`bash probe.sh >/dev/null 2>&1`, как у D1147) — у
# второй трасса идёт в поток ошибок, и глушение в тексте команды съело бы её. Метка «без слов пробы» остаётся: её
# снимают только слова первого прогона (скептик opus D1201, H1). Итог: у обеих подсказка, исход не тронут.
# Код: 0 — подсказка у обеих, метки на месте; 1 — названо, что не так; 2 — не измерено.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
for f in scripts/backlog-recheck.sh hooks/backlog-lib.sh; do [ -f "$REPO/$f" ] || { echo "нет $f"; exit 2; }; done
command -v python3 >/dev/null 2>&1 || { echo "нет python3"; exit 2; }
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1201.XXXXXX") || exit 2
trap 'rm -rf "$S"' EXIT
F="$S/repo"; mkdir -p "$F/scripts" "$F/hooks/tests/fixtures" "$F/hooks/lib" "$S/state" || exit 2
cp "$REPO/scripts/backlog-recheck.sh" "$F/scripts/" && cp "$REPO/hooks/backlog-lib.sh" "$F/hooks/" || exit 2
[ -f "$REPO/hooks/lib/bounded_run.py" ] && cp "$REPO/hooks/lib/bounded_run.py" "$REPO/hooks/lib/backlog_cmd.py" "$REPO/hooks/lib/mktemp-shim.sh" "$F/hooks/lib/" 2>/dev/null
: > "$F/BACKLOG.md"
printf '#!/usr/bin/env bash\ngrep -q carrier-gone /dev/null\n' > "$F/hooks/tests/fixtures/probe_silent.sh"
{ printf -- '- ☑ **D901** значения\n'
  printf -- "  **Проверка.** \`bash -c 'n=1; [ \"\$n\" -eq 0 ]'\` → 0\n"
  printf -- '- ☑ **D902** проба под глушением\n'
  printf -- '  **Проверка.** `bash hooks/tests/fixtures/probe_silent.sh >/dev/null 2>&1` → 0\n'; } > "$S/arch.md"
# Дверь BACKLOG_CHECKS_NESTED снимается у вложенного сверщика, как у проб D1147 и D1196: архиватор и completion-gate
# исполняют эту «Проверку» с дверью, и без снятия сверщик отказывается (код 2 — отказ архиватора 3 ноября 2026).
out=$(cd "$F" && env -u BACKLOG_CHECKS_NESTED CLAUDSOUL_REPO="$F" STATE_DIR="$S/state" BACKLOG_RECHECK_ARCHIVE="$S/arch.md" BACKLOG_ARCHIVE_CHECK_TIMEOUT=20 \
    bash scripts/backlog-recheck.sh --archive 2>&1 < /dev/null)
grep -q 'Исполнено «Проверок»: 2 из 2' <<< "$out" || { echo "сверщик не исполнил обе «Проверки»: ${out:0:300}"; exit 2; }
bad=0
grep -qE '^  ✗ D901 +\[без слов пробы\] .*подсказка повтора без глушения, с трассой: .*n=1' <<< "$out" || { echo "D901: значения трассы не в подсказке либо снята метка"; bad=1; }
grep -qE '^  ✗ D902 +\[без слов пробы\] .*подсказка повтора.*⟪probe_silent\.sh:2⟫ grep -q carrier-gone' <<< "$out" || { echo "D902: проба под глушением не названа файлом и строкой"; bad=1; }
n_q=$(grep -c '^  ✗ D[0-9]* *\[без слов пробы\]' <<< "$out"); n_h=$(grep '^  ✗ D[0-9]* *\[без слов пробы\]' <<< "$out" | grep -c 'подсказка повтора')
[ "$n_q" -eq 2 ] && [ "$n_h" -eq "$n_q" ] || { echo "строк «без слов пробы»: $n_q, с подсказкой: $n_h"; bad=1; }
grep -q 'откатилось пунктов: 0' <<< "$out" || { echo "подсказка сменила исход: $(grep -o 'откатилось пунктов: [0-9]*' <<< "$out")"; bad=1; }
[ "$bad" -eq 0 ] && echo "промолчавшие красные несут подсказку повтора: значения и проба под глушением; метки на месте, откатов 0"
exit "$bad"
