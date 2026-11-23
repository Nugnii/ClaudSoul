#!/usr/bin/env bash
set -u
# СУДИТ: scripts/state-prune.sh scripts/state-size.sh
# probe_D1225 — каталог состояния после ближайшей плановой уборки (замер `state-prune`, `--apply` раз в неделю) — под
#   порогами замера `state-size`. Ничего не удаляет: число уборки берётся у её сухого прогона (сколько файлов и килобайт
#   уйдёт, сколько уедет в архив семейств), число каталога и пороги — у прибора размера; остаток сверяется с порогами.
#   0 — под обоими порогами; 1 — над (числа выведены); 2 — прибор не ответил.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in scripts/state-prune.sh scripts/state-size.sh; do [ -f "$f" ] || exit 2; done
sz=$(bash scripts/state-size.sh 2>/dev/null | head -1)
pr=$(bash scripts/state-prune.sh --dry-run 2>/dev/null)
python3 - "$sz" "$pr" <<'PY'
import re, sys
sz, pr = sys.argv[1], sys.argv[2]
m = re.search(r"(\d+) файлов, (\d+) МБ \(пороги: (\d+) / (\d+) МБ\)", sz)
d = re.search(r"посессионных файлов за окном хранения \([^)]*\): (\d+), (\d+) КБ", pr)
a = re.search(r"в архив семейства: (\d+)", pr)
if not (m and d and a):
    print("прибор не ответил: размер «%s», уборка %s" % (sz[:80], "есть" if pr else "пуста")); sys.exit(2)
files, mb, maxf, maxmb = map(int, m.groups())
gone, gone_kb, arch = int(d.group(1)), int(d.group(2)), int(a.group(1))
left_f, left_mb = files - gone - arch, mb - gone_kb / 1024
ok = left_f <= maxf and left_mb <= maxmb
print("после уборки: %d файлов (порог %d), %.0f МБ (порог %d) — сейчас %d и %d" % (left_f, maxf, left_mb, maxmb, files, mb))
sys.exit(0 if ok else 1)
PY
