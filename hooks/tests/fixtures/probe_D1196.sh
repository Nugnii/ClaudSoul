#!/usr/bin/env bash
# СУДИТ: scripts/backlog-recheck.sh
# СУД: только в рабочем дереве
# (D1295, 15 ноября 2026) «Проверка» D474 читает журнал прибора свидетелей по пути РАБОЧЕГО дерева: в снимке строки нет, и
#  проба красна по построению, как только откат D474 перестаёт быть названным — прибор звал её «рамка не собралась».
# (предмет словами: BACKLOG-archive.md («Проверки» 15 закрытых пунктов) через scripts/backlog-recheck.sh --archive; в строке СУДИТ — только пути, иначе прибор свидетелей-атак читает слова путями — D1222)
# probe_D1196 — «Проверки» 15 закрытых пунктов, сгнивших после законных поздних решений (D305, D513, D1035, D1034,
# D1109, D474, D274, D1047, D519, D375, D360, D1002, D269, D291, D1041), исполняются на нынешнем дереве и держатся.
# Исполняет их ВЛАДЕЛЕЦ сверки архива — `scripts/backlog-recheck.sh --archive` над мини-архивом из блоков этих
# пунктов (`BACKLOG_RECHECK_ARCHIVE`), а не своя копия исполнителя: ограда кольца, срок и разбор кода — его.
# Маркер вложенности снимается только для этого вызова: мини-архив D1196 не содержит, кольца нет.
# Код: 0 — каждая держится либо её откат назван открытым пунктом («откат D<N>» в заголовке); 1 — красна хоть одна
# без такого пункта (названа); 2 — пункт не найден в архиве, исполнитель не ответил либо «Проверка» не измерила.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
ARCH="$R/BACKLOG-archive.md"; REC="$R/scripts/backlog-recheck.sh"
[ -f "$ARCH" ] && [ -f "$REC" ] || { echo "нет архива или исполнителя в $R"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3 — мини-архив собрать нечем"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# Перечень — ручка `PROBE_ARCHIVE_IDS`: тем же исполнителем судит свои 22 пункта `probe_D1197.sh`.
IDS="${PROBE_ARCHIVE_IDS:-D305 D513 D1035 D1034 D1109 D474 D274 D1047 D519 D375 D360 D1002 D269 D291 D1041}"
# Пункты режутся ПРАВИЛОМ ИСПОЛНИТЕЛЯ (D1283, скептик opus H1, корень R1): текст без огороженных блоков
# (`backlog_strip_fenced`), пункт — выражение `backlog_item_re` библиотеки бэклога (видит и заголовки старого вида
# `### D112 ☑ …`), закрытый — `backlog_item_re ☑`, номер — `BACKLOG_ID_TOKEN_RE`, граница — пункт или заголовок уровня
# 2–6, как у `scripts/backlog-recheck.sh --archive`. Своё выражение (только `- ☑ **D…**`) не находило пункты-заголовки,
# которые отбор после коммита берёт у исполнителя, и весь пакет выходил кодом 2 до исполнения (32 коммита из 400).
BL="$R/hooks/backlog-lib.sh"
[ -f "$BL" ] || { echo "нет hooks/backlog-lib.sh — правила пункта взять неоткуда"; exit 2; }
# shellcheck source=/dev/null
. "$BL"
backlog_strip_fenced < "$ARCH" > "$W/arch.txt" || exit 2
IDS="$IDS" AC_ITEM_RE="$(backlog_item_re)" AC_DONE_RE="$(backlog_item_re "$BACKLOG_MARK_DONE")" \
    AC_ID_RE="$BACKLOG_ID_TOKEN_RE" python3 - "$W/arch.txt" "$W/mini.md" <<'PY' || exit 2
import os, re, sys
ids = set(os.environ["IDS"].split())
item_re, done_re = re.compile(os.environ["AC_ITEM_RE"]), re.compile(os.environ["AC_DONE_RE"])
id_re = re.compile(os.environ["AC_ID_RE"])
out, keep, found = ["# mini", "", "## D1196", ""], False, set()
for ln in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    if item_re.match(ln) or re.match(r"#{2,6} ", ln):
        keep = False
        if item_re.match(ln) and done_re.match(ln):
            m = id_re.search(ln.replace("*", ""))
            if m and m.group(0) in ids:
                keep = True
                found.add(m.group(0))
    if keep:
        out.append(ln)
miss = ids - found
if miss:
    print("в архиве нет закрытых пунктов:", " ".join(sorted(miss)))
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
out=$(cd "$R" && env -u BACKLOG_CHECKS_NESTED BACKLOG_RECHECK_ARCHIVE="$W/mini.md" BACKLOG_RECHECK_VERBOSE=1 \
    bash "$REC" --archive 2>&1)
# Вторая ветка «Результата» D1196: красная «Проверка» засчитывается, только если откат назван своим пунктом — открытый
# (☐/◐) пункт BACKLOG.md несёт в заголовке «откат D<N>» (D474 → D1222, D375 → D1223; скептик opus по d271f058).
# Правило — у владельца, `backlog_revert_ids` (D1295, 15 ноября 2026): своя строчная копия не видела «Откат D474: …».
REV=$(backlog_revert_ids "$R/BACKLOG.md") || { echo "откаты в бэклоге не прочитаны"; exit 2; }
REV="$REV" IDS="$IDS" python3 -c '
import os, re, sys
ids, seen, red, unk, named = os.environ["IDS"].split(), {}, [], [], {}
for ln in sys.stdin:
    m = re.match(r"^\s*([✓✗?])\s+(D\d+)\b", ln)
    if m:
        seen.setdefault(m.group(2), set()).add(m.group(1))
for ln in os.environ["REV"].splitlines():
    r, _, h = ln.partition("\t")
    if r and h:
        named.setdefault(r, h)
for i in ids:
    s = seen.get(i, set())
    if "✗" in s and i not in named:
        red.append(i)
    elif "✗" not in s and ("?" in s or "✓" not in s):
        unk.append(i)
if red:
    print("красны:", " ".join(red)); sys.exit(1)
if unk:
    print("не измерено:", " ".join(unk)); sys.exit(2)
rb = [f"{i} ({named[i]})" for i in ids if "✗" in seen.get(i, set())]
print(f"держатся {len(ids) - len(rb)} из {len(ids)}" + (", откат назван: " + " ".join(rb) if rb else ""))
' "$R/BACKLOG.md" <<< "$out"
