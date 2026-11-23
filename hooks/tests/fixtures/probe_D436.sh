#!/usr/bin/env bash
# СУДИТ: scripts/ablation/parse-transcript.py
# probe_D436.sh — проба D436: стоимость прогона без result.json НЕИЗВЕСТНА, а не нулевая.
# Результат: запись arm_metrics прогона без result.json (или с повреждённым) несёт признак
#            неизвестности — tokens_in/tokens_out null и usage:"unknown" / "corrupt", — а не 0/0;
#            у прогона с исправным result.json числа те, что в файле.
# Проверка результата: bash hooks/tests/fixtures/probe_D436.sh даёт 0
#
# Корень берётся от своего пути, МЕХАНИЗМ — из CLAUDSOUL_REPO: зелёная сторона подставляет туда
# копию с починкой. Судится РЕЗУЛЬТАТ — запись, которую парсер кладёт в journal.jsonl (её и
# читает анализ плеч), а не текст механизма. Транскрипт песочницы несёт usage 777/888
# НАМЕРЕННО: восстанавливать стоимость из него документ аудита не требует (проба P2/P3), и
# «777» в записи было бы третьим состоянием, а не починкой — потому желаемое здесь null.
# Коды: 0 — желаемое соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась (нет механизма,
# нет python3, положительный контроль не прошёл), с сообщением в stderr.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
PARSER="$MECH/scripts/ablation/parse-transcript.py"
[ -f "$PARSER" ] || { echo "probe_D436: механизма нет: $PARSER" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D436: нет python3" >&2; exit 2; }

T=$(mktemp -d) || { echo "probe_D436: mktemp не удался" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" ABLATION_DIR="$T/abl"
mkdir -p "$HOME"

# Три прогона одного плеча: ok — исправный result.json (положительный контроль),
# none — файла нет, corrupt — файл оборван. Транскрипт у всех один и тот же, с usage 777/888.
for run in ok none corrupt; do
    mkdir -p "$ABLATION_DIR/runs/$run/full/home/.claude/projects/p" || exit 2
    printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":777,"output_tokens":888}}}' \
        > "$ABLATION_DIR/runs/$run/full/home/.claude/projects/p/s.jsonl"
done
printf '%s' '{"usage":{"input_tokens":100,"output_tokens":200},"num_turns":3,"duration_ms":10}' \
    > "$ABLATION_DIR/runs/ok/full/result.json"
printf '%s' '{"usage": {"input_tokens": 100, ' > "$ABLATION_DIR/runs/corrupt/full/result.json"

for run in ok none corrupt; do
    python3 "$PARSER" "$run" full >/dev/null 2>>"$T/parser.err" || true   # судится запись, не код
done

python3 - "$ABLATION_DIR/journal.jsonl" "$T/parser.err" <<'PY'
import json, os, sys
recs = {}
if os.path.isfile(sys.argv[1]):
    for line in open(sys.argv[1], encoding="utf-8"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("e") == "arm_metrics":
            recs[r.get("id")] = r
err = open(sys.argv[2], encoding="utf-8", errors="replace").read().strip()
ok = recs.get("ok")
if not ok or ok.get("tokens_in") != 100 or ok.get("tokens_out") != 200:
    sys.stderr.write("probe_D436: положительный контроль не прошёл — исправный result.json дал %r%s\n"
                     % (ok, (" / stderr парсера: " + err) if err else ""))
    sys.exit(2)
bad = []
for run, want in (("none", "unknown"), ("corrupt", "corrupt")):
    r = recs.get(run)
    if r is None:
        bad.append("%s: записи arm_metrics нет" % run)
        continue
    if r.get("tokens_in") is not None or r.get("tokens_out") is not None or r.get("usage") != want:
        bad.append("%s: tokens_in=%r tokens_out=%r usage=%r (нужно null / null / %r)"
                   % (run, r.get("tokens_in"), r.get("tokens_out"), r.get("usage"), want))
if bad:
    print("probe_D436: ДЕФЕКТ — " + "; ".join(bad))
    sys.exit(1)
print("probe_D436: незавершённый прогон помечен неизвестной стоимостью, исправный — числами из файла")
sys.exit(0)
PY
rc=$?
exit "$rc"
