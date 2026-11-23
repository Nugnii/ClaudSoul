#!/usr/bin/env bash
# СУДИТ: hooks/tests/fixtures/probe_D1153.sh
# probe_D1156 — структурная нога D1153 опознаёт свою копию признака «запись user» у читателя реестра по устройству: каждая
# порча из повода (скептик opus по 9182f1d9, M1, M4) и откат каждой снятой копии краснят `probe_D1153` кодом 1. Порчи:
#   srr-var, srr-subscr, srr-get-default, srr-reversed, srr-in-tuple — брат `scripts/self-repeat-replay.py` судит запись
#       своей копией: через переменную `t`, `msg["role"]`, `.get("type", "")`, `"user" == …`, `in ("user",)`;
#   bco-dispatch  — `hooks/lib/backfill-compliance-one.py` снова диспетчер `rtype == "user"`;
#   ucg-copy      — медленный путь `hooks/user-correction-guard.sh` снова своя копия `.type == "user"`;
#   ucg-jq-in, ucg-jq-test — та же копия формами jq `IN("user")`, `test("^user$")`;
#   bro-role, bro-case — воркер `hooks/lib/backfill-replay-one.sh` снова судит роль оболочкой: `[ "$ROLE" = "user" ]`, `case`;
#   формы финального скептика по 5e64dfc3 (M1, M2): srr-const (`USER = "user"`), srr-param (параметр помощника),
#       srr-startswith, srr-dict-get (`{"user": …}.get(…)`), srr-in-dict (`in {"user": 1}`), bro-case-line (`case` в
#       строку), bro-var (`U=user`), ucg-jq-arg (`--arg u user`), ucg-jq-key (`{user: true}[.type]`).
# Красное засчитывается, только если его дала структурная нога (строка «своя проверка роли»), а не другая.
# Каждая порча кладётся в свою копию дерева (`hooks/*.sh`, `hooks/lib`, весь `scripts/` — что читает проба; копия
# только верхнего уровня `scripts/` судила меньше, чем проба на дереве), проба гоняется по копии параллельно. Контроль: копия без порчи — 0. Срок бьёт группу процессов TERM.
# 0 — все порчи красны; 1 — хоть одна проходит пробу (код не 1); 2 — рамка не собралась (нет пробы или питона,
# строка порчи не легла ровно раз, контроль не 0, срок вышел).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
P="$R/hooks/tests/fixtures/probe_D1153.sh"
[ -f "$P" ] && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base/hooks" "$T/base/scripts" && cp "$R"/hooks/*.sh "$T/base/hooks/" && cp -R "$R/hooks/lib" "$T/base/hooks/" \
    && cp -R "$R"/scripts/. "$T/base/scripts/" || exit 2
python3 - "$T" "$P" <<'PY'
import os, pathlib, shutil, signal, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
T, P = pathlib.Path(sys.argv[1]), sys.argv[2]
SRR, BCO = "scripts/self-repeat-replay.py", "hooks/lib/backfill-compliance-one.py"
UCG, BRO = "hooks/user-correction-guard.sh", "hooks/lib/backfill-replay-one.sh"
A = "if is_turn_user(rec) and is_live_user(msg):"
srr = lambda new, *more: [(A, new + " and is_live_user(msg):")] + list(more)
# Импорт стоит в блоке `try` (D1157): порча встаёт внутрь блока с его отступом, иначе файл не разбирается (D1209).
IMP = "    from transcript_window import is_turn_user  # noqa: E402\n"
BCO_A = "        # Границы хода (запись user) индекс не несёт: потребителя у неё не было с 25 июля 2026 (012c2f42) — `class_c` её\n"
UCG_A = '          | if owner_reply then "H"\n'
BRO_A = '    [ "$OWN" = true ] || continue\n'
M = [
    ("srr-var", SRR, srr('if t == "user"')),
    ("srr-subscr", SRR, srr('if msg["role"] == "user"')),
    ("srr-get-default", SRR, srr('if rec.get("type", "") == "user"')),
    ("srr-reversed", SRR, srr('if "user" == rec.get("type")')),
    ("srr-in-tuple", SRR, srr('if rec.get("type") in ("user",)')),
    ("srr-const", SRR, srr('if rec.get("type") == _U', (IMP, IMP + '    _U = "user"\n'))),
    ("srr-param", SRR, srr('if _isu(rec.get("type"))', (IMP, IMP + '    def _isu(k):\n        return k == "user"\n'))),
    ("srr-startswith", SRR, srr('if (rec.get("type") or "").startswith("user")')),
    ("srr-dict-get", SRR, srr('if {"user": True}.get(rec.get("type"))')),
    ("srr-in-dict", SRR, srr('if rec.get("type") in {"user": 1}')),
    ("bco-dispatch", BCO, [(BCO_A, '        elif rtype == "user":\n            events.append({"i": i, "kind": "user", "ts": ts})\n' + BCO_A)]),
    ("ucg-copy", UCG, [(UCG_A, '          | if .type == "user" and ((.isMeta // false) | not) then "H"\n')]),
    ("ucg-jq-in", UCG, [(UCG_A, '          | if (.type | IN("user")) then "H"\n')]),
    ("ucg-jq-test", UCG, [(UCG_A, '          | if (.message.role // "" | test("^user$")) then "H"\n')]),
    ("bro-role", BRO, [(BRO_A, BRO_A + '    [ "$(echo "$rec" | jq -r .role)" = "user" ] || continue\n')]),
    ("bro-case-line", BRO, [(BRO_A, BRO_A + '    case "$(echo "$rec" | jq -r .role)" in user) ;; *) continue ;; esac\n')]),
    ("bro-var", BRO, [(BRO_A, BRO_A + '    U=user; [ "$(echo "$rec" | jq -r .role)" = "$U" ] || continue\n')]),
    ("ucg-jq-arg", UCG, [('jq -rs --arg f "$FILE_PATH"', 'jq -rs --arg u user --arg f "$FILE_PATH"'),
                         (UCG_A, '          | if .type == $u then "H"\n')]),
    ("ucg-jq-key", UCG, [(UCG_A, '          | if ({user: true}[.type // ""] // false) then "H"\n')]),
    ("bro-case", BRO, [(BRO_A, BRO_A + '    case "$(echo "$rec" | jq -r .role)" in\n        user) ;;\n        *) continue ;;\n    esac\n')]),
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
    # ponytail: потолок 120 с на прогон — проба идёт ~3 с; зависшая копия иначе держала бы «Проверку» без срока.
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
green = [f"{n} (код {rc})" for n, rc, o in res[1:] if rc != 1 or not o[0].startswith("своя проверка роли")]
if green:
    print("структурная нога D1153 пропускает порчи:", "; ".join(green)); sys.exit(1)
print(f"структурная нога D1153 опознаёт свою копию по устройству: {len(M)} порч из {len(M)} красны ею")
PY
