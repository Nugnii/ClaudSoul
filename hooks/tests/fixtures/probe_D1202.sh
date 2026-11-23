#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_reply_readers_behavior.sh
# probe_D1202 — свидетель поведения читателей реплики (D1149) видит у читателя оба пути и все поля записи: подмена
# признака, которая меняет поведение только на запасном пути читателя или только на записи `isMeta`/`isSidechain`,
# краснит свидетеля. Повод — скептики opus по D1149 (круг 1: L1, L2; круг 2: L3; круг 4: L2; круг 5: M1): мутанты K1, K4, K5, K7, K8, K10, K14–K18
# в свидетеле зелёные (K19 — скептик opus D1202, L1), их ловят соседние тесты литералами, которые реестра не читают; K9 у стража поправок меняет только путь без
# помощника окна. Каждый мутант кладётся в копию рабочего дерева, свидетель гоняется по читателю этого признака.
# Красная (1), пока хоть один мутант проходит свидетеля зелёным; 2 — рамка не собралась (нет свидетеля, дерева, строки
# мутанта).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/tests/test_reply_readers_behavior.sh" ] || exit 2
command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
unset REPLY_READERS_OBS                  # память наблюдений из окружения судила бы старое (скептик D1149, круг 2)
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tree"
( cd "$R" && git ls-files -z -co --exclude-standard | tar --null -T - -cf - ) 2>/dev/null | tar -x -C "$T/tree" 2>/dev/null
[ -f "$T/tree/hooks/hook-input-lib.sh" ] || exit 2
python3 - "$T/tree" <<'PY'
import concurrent.futures, pathlib, queue, shutil, subprocess, sys
NW = 4
root = pathlib.Path(sys.argv[1])
W = root / "hooks/tests/test_reply_readers_behavior.sh"
M = [
    ("K1 owner_reply в jq без isSidechain", "hooks/hook-input-lib.sh",
     "and ((.isCompactSummary // false) | not) and ((.isSidechain // false) | not)\n        and (((.origin",
     "and ((.isCompactSummary // false) | not)\n        and (((.origin", "hooks/shared-language-lib.sh"),
    ("K4 is_turn_user в питоне без isMeta", "hooks/lib/transcript_window.py",
     "    if rec.get(\"isMeta\"):\n        return False\n    return len(_text(rec)) > 0", "    return len(_text(rec)) > 0",
     "scripts/self-repeat-replay.py"),  # прежний читатель backfill-compliance-one.py границу снял (D1156)
    ("K5 turn_user в jq без isMeta", "hooks/hook-input-lib.sh",
     "(($m.role // .role // \"\") == \"user\") and ((.isMeta // false) | not)", "(($m.role // .role // \"\") == \"user\")",
     "hooks/output-language-check.sh"),
    ("K7 образец «правка, затем реплика» без as_reply", "hooks/lib/transcript_window.py",
     "    return is_owner_speech(rec)\n\n\ndef _edits_file", "    return is_owner_reply(rec)\n\n\ndef _edits_file",
     "hooks/user-correction-guard.sh"),
    ("K8 запасной jq стража поправок без as_reply", "hooks/user-correction-guard.sh",
     "        [ .[] | as_reply\n", "        [ .[] | .\n", "hooks/user-correction-guard.sh"),
    ("K9 правило владельца в jq без автора по умолчанию (путь без помощника окна)", "hooks/hook-input-lib.sh",
     "(((.origin | if type == \"object\" then . else {} end).kind // \"human\") == \"human\");",
     "(((.origin | if type == \"object\" then . else {} end).kind) == \"human\");", "hooks/user-correction-guard.sh"),
    ("K10 правило владельца в jq без isSidechain", "hooks/hook-input-lib.sh",
     "and ((.isCompactSummary // false) | not) and ((.isSidechain // false) | not)\n        and (((.origin",
     "and ((.isCompactSummary // false) | not)\n        and (((.origin", "hooks/bulk-copy-guard.sh"),
    ("K14 приводилка as_reply в jq без commandMode", "hooks/hook-input-lib.sh",
     "and .attachment.type == \"queued_command\" and .attachment.commandMode == \"prompt\"",
     "and .attachment.type == \"queued_command\"", "hooks/shared-language-lib.sh"),
    ("K15 приводилка as_reply в питоне без commandMode", "hooks/lib/transcript_window.py",
     "if a.get(\"type\") != \"queued_command\" or a.get(\"commandMode\") != \"prompt\" or not _human_kind(kind):",
     "if a.get(\"type\") != \"queued_command\" or not _human_kind(kind):", "scripts/colon-lead-in-count.py"),
    ("K16 автор только явно human (питон)", "hooks/lib/transcript_window.py",
     "    return kind is None or kind is False or kind == \"human\"", "    return kind == \"human\"",
     "scripts/colon-lead-in-count.py"),
    ("K17 автор только явно human (jq, правило владельца)", "hooks/hook-input-lib.sh",
     "(((.origin | if type == \"object\" then . else {} end).kind // \"human\") == \"human\");",
     "(((.origin | if type == \"object\" then . else {} end).kind) == \"human\");", "hooks/shared-language-lib.sh"),
    ("K18 второй путь root-cause-lib (rc_outcome_observed) — граница узкая", "hooks/root-cause-lib.sh",
     "select($items[.] | turn_user)]",
     "select($items[.] | turn_user and ((.isCompactSummary // false) | not)"
     " and (((.origin | if type == \"object\" then . else {} end).kind // \"human\") == \"human\"))]",
     "hooks/root-cause-lib.sh"),
    # Скептик opus D1202 (один круг), L1 — вложение без поля автора (правило «не задан — человек»). Подмена автора в
    # приводилке (H1) — мутант эквивалентный: все 9 потребителей `as_reply` судят автора ещё раз (`owner_reply`,
    # `is_owner_reply`), поведение не меняется — в пробу не входит.
    ("K19 приводилка as_reply в jq: автор только явно human", "hooks/hook-input-lib.sh",
     "((.attachment.origin.kind // \"human\") == \"human\")\n", "(.attachment.origin.kind == \"human\")\n",
     "hooks/shared-language-lib.sh"),
]
# Мутанты — параллельно, каждый в своей копии дерева (свой `$T` у каждого прогона свидетеля): проба исполняется
# архиватором с пределом 120 с, а последовательный прогон под нагрузкой границы хода шёл 143 с (D1202, 4 ноября 2026).
for name, rel, old, new, reader in M:
    n = (root / rel).read_text(encoding="utf-8").count(old)
    if n != 1:
        print(f"рамка: строка мутанта {name} встречается {n} раз"); sys.exit(2)
trees = queue.Queue()                    # номера копий: копией владеет один поток, пока держит номер
for k in range(NW):
    if k:
        shutil.copytree(root, root.parent / f"tree{k}", symlinks=True)
    trees.put(k)
def run(m):
    name, rel, old, new, reader = m
    k = trees.get()
    # Копия — во временном каталоге пробы (`mktemp -d` оболочки выше, путь пришёл аргументом): писатель у файла один.
    t = pathlib.Path(sys.argv[1]).parent / (f"tree{k}" if k else root.name)
    try:
        f = t / rel
        src = f.read_text(encoding="utf-8")
        f.write_text(src.replace(old, new), encoding="utf-8")
        try:
            r = subprocess.run(["bash", str(t / W.relative_to(root)), "--only", reader], capture_output=True, text=True,
                               timeout=300)
        finally:
            f.write_text(src, encoding="utf-8")
        return None if r.returncode == 1 and f"FAIL: {reader}: объявлено" in r.stdout else f"{name} ({reader})"
    finally:
        trees.put(k)
with concurrent.futures.ThreadPoolExecutor(NW) as ex:
    green = [g for g in ex.map(run, M) if g]
if green:
    print("свидетель не видит подмену:", "; ".join(green)); sys.exit(1)
print(f"свидетель видит оба пути и все поля: {len(M)} мутантов из {len(M)} красны")
PY
