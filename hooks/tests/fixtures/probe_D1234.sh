#!/usr/bin/env bash
set -u
# СУДИТ: scripts/measurements.tsv scripts/activator-latency.sh hooks/tests/fixtures/probe_D488.sh
# probe_D1234 — у стенного времени хука знаний есть владелец со сроком: строка `activator-latency` в реестре замеров
#   зовёт `scripts/activator-latency.sh` (предел по нагрузке), прибор различает «в пределе / выше / не измерено» (его
#   свидетель зелен), а проба D488 судит свойство самой починки (коммит 199039cb), а не рабочее дерево.
#   Живой замер здесь не гоняется: под нагрузкой он идёт десятки секунд, а предмет пункта — что замер ЕСТЬ и исполним.
#   0 — всё так; 1 — строки нет, она зовёт не тот прибор, свидетель красен или проба D488 снова судит дерево; 2 — нет файлов.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in scripts/measurements.tsv scripts/activator-latency.sh hooks/tests/test_activator_latency.sh hooks/tests/fixtures/probe_D488.sh; do
    [ -f "$f" ] || exit 2
done
bad=0
awk -F'\t' '$1 == "activator-latency" && $3 ~ /^scripts\/activator-latency\.sh/ && $2 ~ /^[0-9]+c?$/ { f = 1 } END { exit !f }' \
    scripts/measurements.tsv || { echo "в реестре замеров нет строки activator-latency с прибором и сроком"; bad=1; }
bash -n scripts/activator-latency.sh 2>/dev/null || { echo "прибор не разбирается оболочкой"; bad=1; }
bash hooks/tests/test_activator_latency.sh >/dev/null 2>&1 || { echo "свидетель прибора красен"; bad=1; }
grep -q '^FIX_REV=199039cb' hooks/tests/fixtures/probe_D488.sh && grep -q 'archive "\$FIX_REV" hooks' hooks/tests/fixtures/probe_D488.sh \
    || { echo "проба D488 судит не коммит починки"; bad=1; }
# Мир пробы D488 — снимки, а не живое (скептик opus по 2f7b9d95, H1 и L): база знаний в песочном HOME и реестр сессий,
# без которого ветка дней опыта у обеих сторон не исполняется.
grep -q '^[^#]*HOME="\$W/home" FSRS_SESSION_REGISTRY="\$W/registry.jsonl"' hooks/tests/fixtures/probe_D488.sh \
    && grep -q '^[^#]*cp "\$REG" "\$W/registry.jsonl"' hooks/tests/fixtures/probe_D488.sh \
    || { echo "проба D488 идёт не на снимках базы знаний и реестра сессий"; bad=1; }
exit "$bad"
