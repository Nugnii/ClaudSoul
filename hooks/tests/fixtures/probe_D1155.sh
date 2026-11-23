#!/usr/bin/env bash
# СУДИТ: hooks/tests/fixtures/probe_D1150.sh
# probe_D1155 — ноги пробы D1150 держат обещания четвёртого круга D1150 и охрану детектора: каждая порча, которую
# называли скептики opus (по cdc955fb — M1–M6; по b74ce609 — L1), краснит `probe_D1150` кодом 1. Порчи:
#   bf-stderr-silenced     — массовый реплей снова глушит stderr воркера (`2>/dev/null` на xargs);
#   bf-stderr-prefix-filter — stderr воркера фильтруется по его префиксу «backfill-replay-one:» (финальный скептик
#                            D1155, M2: строку причины настоящего воркера проба не требовала);
#   bf-check-grep-rc       — итог массового реплея по коду grep, а не xargs;
#   bf-check-after-summary — отказ воркера проверяется после сводки (сводка печатается, потом код 2);
#   bf-digest-before-check — дайджест для calibrate.py собирается до проверки отказа (финальный скептик D1155, M1:
#                            ни одна нога не передавала `--digest`);
#   as_reply-old-rule      — `as_reply` судит автора прежним правилом («human» только на отсутствие поля);
#   owner_reply-old-rule   — `is_owner_reply` судит автора прежним `or "human"` (пустой автор — человек);
#   hk-in-tuple            — `_human_kind` через `kind in (None, False, "human")` (в питоне `0 == False`);
#   w1-msg-no-old-edition  — строка причины реплея без «старая редакция»;
#   det-guard-by-file      — охрана детектора по файлу библиотеки, а не по фильтру `is_non_user_turn`.
# Каждая порча кладётся в свою копию дерева (`hooks/*.sh`, `hooks/lib`, `scripts/stopper-effect.sh` — что читает
# проба), проба гоняется по копии параллельно. Контроль: копия без порчи — 0. Срок бьёт группу процессов сигналом
# TERM, а не одного bash: ловушка пробы D1150 убирает свой каталог, внуки не остаются (скептик D1155, L9).
# 0 — все порчи красны; 1 — хоть одна проходит пробу (код не 1); 2 — рамка не собралась (нет пробы или питона,
# строка порчи не легла ровно раз, контроль не 0).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
P="$R/hooks/tests/fixtures/probe_D1150.sh"
[ -f "$P" ] && [ -f "$R/scripts/stopper-effect.sh" ] && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base/hooks" "$T/base/scripts" && cp "$R"/hooks/*.sh "$T/base/hooks/" && cp -R "$R/hooks/lib" "$T/base/hooks/" \
    && cp "$R/scripts/stopper-effect.sh" "$T/base/scripts/" || exit 2
python3 - "$T" "$P" <<'PY'
import os, pathlib, shutil, signal, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
T, P = pathlib.Path(sys.argv[1]), sys.argv[2]
BF, TW = "hooks/backfill-intrusiveness.sh", "hooks/lib/transcript_window.py"
bf = (T / "base" / BF).read_text(encoding="utf-8")
CHECK = 'if [ "${_bf_rc[1]:-0}" -ne 0 ]; then'
DIGEST = 'if [ "$RUN_DIGEST" = "1" ]'
if bf.count(CHECK) != 1 or bf.count(DIGEST) != 1:
    print("рамка: проверка отказа воркера или выход на дайджест в массовом реплее не ровно по разу"); sys.exit(2)
i = bf.index(CHECK); blk = bf[i:bf.index("\nfi\n", i) + 4]
j = bf.index(DIGEST); dblk = bf[j:bf.index("\nfi\n", j) + 4]
TOTAL = 'TOTAL_EVENTS=$(wc -l < "$OUT_FILE" | tr -d \' \')\n'
M = [
    ("bf-stderr-silenced", BF, [('xargs -0 -n 1 -P "$PARALLEL" "$WORKER" \\', 'xargs -0 -n 1 -P "$PARALLEL" "$WORKER" 2>/dev/null \\')]),
    ("bf-stderr-prefix-filter", BF, [('xargs -0 -n 1 -P "$PARALLEL" "$WORKER" \\',
                                    'xargs -0 -n 1 -P "$PARALLEL" "$WORKER" 2> >(grep -v "^backfill-replay-one:" >&2) \\')]),
    ("bf-check-grep-rc", BF, [(CHECK, 'if [ "${_bf_rc[2]:-0}" -ne 0 ]; then')]),
    ("bf-check-after-summary", BF, [(blk, ""), (DIGEST, blk + DIGEST)]),
    ("bf-digest-before-check", BF, [(dblk, ""), (CHECK, TOTAL + dblk + CHECK)]),
    ("as_reply-old-rule", TW, [("or not _human_kind(kind):", 'or (kind if kind is not None else "human") != "human":')]),
    ("owner_reply-old-rule", TW, [('    return _human_kind(origin.get("kind"))\n', '    return (origin.get("kind") or "human") == "human"\n')]),
    ("hk-in-tuple", TW, [('    return kind is None or kind is False or kind == "human"', '    return kind in (None, False, "human")')]),
    ("w1-msg-no-old-edition", "hooks/lib/backfill-replay-one.sh",
     [("hook-input-lib.sh нет либо старая редакция — точки", "hook-input-lib.sh нет — точки")]),
    ("det-guard-by-file", "hooks/itr-event-detector.sh",
     [('command -v is_non_user_turn >/dev/null 2>&1 || exit 0', '[ -f "$INPUT_LIB" ] || exit 0')]),
]
def build(name, rel, subs):
    d = T / name
    shutil.copytree(T / "base", d)
    if rel:
        f = d / rel; src = f.read_text(encoding="utf-8")
        for old, new in subs:
            if src.count(old) != 1:
                return f"рамка: строка порчи {name} встречается {src.count(old)} раз"
            src = src.replace(old, new)
        f.write_text(src, encoding="utf-8")
    return d
def run(job):
    d = build(*job)
    if isinstance(d, str):
        return job[0], None, d
    # ponytail: потолок 120 с на прогон — проба идёт ~5 с; зависшая копия иначе держала бы «Проверку» без срока.
    p = subprocess.Popen(["bash", P], env=dict(os.environ, CLAUDSOUL_REPO=str(d)), stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=120)
        return job[0], p.returncode, out.strip().splitlines()[-1:] or [""]
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGTERM)
        try:
            p.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL); p.communicate()
        return job[0], None, "рамка: проба не уложилась в 120 с"
with ThreadPoolExecutor(max_workers=min(len(M) + 1, os.cpu_count() or 4)) as ex:
    res = list(ex.map(run, [("control", None, [])] + M))
frame = [f"{n}: {o}" for n, rc, o in res if rc is None]
if frame:
    print("; ".join(frame)); sys.exit(2)
ctl = res[0]
if ctl[1] != 0:
    print(f"рамка: проба на копии без порчи — код {ctl[1]}: {ctl[2][0]}"); sys.exit(2)
green = [f"{n} (код {rc})" for n, rc, _ in res[1:] if rc != 1]
if green:
    print("проба D1150 пропускает порчи:", "; ".join(green)); sys.exit(1)
print(f"ноги пробы D1150 держат обещания: {len(M)} порч из {len(M)} красны")
PY
