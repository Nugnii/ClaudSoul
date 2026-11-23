#!/usr/bin/env bash
# СУДИТ: scripts/ablation/parse-transcript.py
# probe_D437.sh — проба D437: ВСЕ числовые поля usage доходят до записи arm_metrics, а не перечень.
# Результат: у прогона, чей result.json несёт cache_read_input_tokens, cache_creation_input_tokens
#            и поле, которого нет ни в парсере, ни в аудите (service_tier_tokens), запись arm_metrics
#            несёт ВСЕ ТРИ числа порознь под именами источника (допустим префикс), а
#            tokens_in/tokens_out остаются 100/200 — ничего не сложено и ничего не потеряно;
#            прогон с двумя полями даёт те же 100/200.
# Проверка результата: bash hooks/tests/fixtures/probe_D437.sh даёт 0
#
# Корень берётся от своего пути, МЕХАНИЗМ — из CLAUDSOUL_REPO: зелёная сторона подставляет туда
# копию с починкой. Судится РЕЗУЛЬТАТ — запись в journal.jsonl, а не текст механизма. Складывать
# кеш с input нельзя по слову аудита (§3: у провайдеров это отдельные величины либо подмножества),
# поэтому желаемое — поля порознь, а tokens_in неизменён. Имя поля ищется по ХВОСТУ ключа: имя
# источника обязано сохраниться, префикс — на усмотрение починки. Третье поле — service_tier_tokens —
# выдумано: его нет ни в дереве, ни в аудите, и починка, лишь ДОПИСАВШАЯ в перечень два имени кеша,
# на нём краснеет (прожарка 17 сентября 2026: такой патч проходил редакцию с двумя известными
# именами). Судится вывод универсума, а не два конкретных поля. Коды: 0 — желаемое соблюдено;
# 1 — дефект наблюдён; 2 — рамка не собралась, с сообщением в stderr.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
PARSER="$MECH/scripts/ablation/parse-transcript.py"
[ -f "$PARSER" ] || { echo "probe_D437: механизма нет: $PARSER" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D437: нет python3" >&2; exit 2; }

T=$(mktemp -d) || { echo "probe_D437: mktemp не удался" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" ABLATION_DIR="$T/abl"
mkdir -p "$HOME" "$ABLATION_DIR/runs/plain/full" "$ABLATION_DIR/runs/cache/full" || exit 2
printf '%s' '{"usage":{"input_tokens":100,"output_tokens":200},"num_turns":3,"duration_ms":10}' \
    > "$ABLATION_DIR/runs/plain/full/result.json"
printf '%s' '{"usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":4000,"cache_creation_input_tokens":3000,"service_tier_tokens":7},"num_turns":3,"duration_ms":10}' \
    > "$ABLATION_DIR/runs/cache/full/result.json"

for run in plain cache; do
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
plain = recs.get("plain")
if not plain or plain.get("tokens_in") != 100 or plain.get("tokens_out") != 200:
    sys.stderr.write("probe_D437: положительный контроль не прошёл — result.json с двумя полями дал %r%s\n"
                     % (plain, (" / stderr парсера: " + err) if err else ""))
    sys.exit(2)
r = recs.get("cache")
if r is None:
    sys.stderr.write("probe_D437: записи arm_metrics для прогона с кешем нет%s\n" % ((" / " + err) if err else ""))
    sys.exit(2)
bad = []
if r.get("tokens_in") != 100 or r.get("tokens_out") != 200:
    bad.append("tokens_in/tokens_out = %r/%r — кеш сложили с input/output" % (r.get("tokens_in"), r.get("tokens_out")))
for src_name, want in (("cache_read_input_tokens", 4000), ("cache_creation_input_tokens", 3000),
                       ("service_tier_tokens", 7)):   # третье — нигде не названо: ловит патч-перечень
    hits = [k for k, v in r.items() if k.endswith(src_name) and v == want]
    if not hits:
        bad.append("%s=%d в записи нет (ключи: %s)" % (src_name, want, ", ".join(sorted(r))))
if bad:
    print("probe_D437: ДЕФЕКТ — " + "; ".join(bad))
    sys.exit(1)
print("probe_D437: все три поля usage в записи порознь, input/output не тронуты")
sys.exit(0)
PY
rc=$?
exit "$rc"
