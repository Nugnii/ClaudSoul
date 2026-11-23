#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# probe_D1130 — два хода с одинаковой репликой собеседника («продолжай») — разные ходы. Красная (1), пока ключ хода —
# cksum ТЕКСТА последней реплики (`rc_turn_key`): у таких ходов общий якорь исходов, общие строки живых поводов и общая
# пара журнала исходов (третий скептик, L4). Положительный контроль — разные реплики дают разные ключи. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/root-cause-lib.sh" ] && command -v jq >/dev/null 2>&1 || exit 2
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1130.XXXXXX") || exit 2
# Записи — в форме мира: у каждой записи расшифровки свой `uuid` (у фикстур без него ключ прежний, по тексту).
u() { jq -cn --arg t "$1" --arg id "$2" '{type:"user",uuid:$id,message:{role:"user",content:[{type:"text",text:$t}]}}'; }
a() { jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
{ u "продолжай" u-1; a "делаю раз"; } > "$S/t1.jsonl"; cp "$S/t1.jsonl" "$S/t2.jsonl"; { u "продолжай" u-2; a "делаю два"; } >> "$S/t2.jsonl"
cp "$S/t1.jsonl" "$S/t3.jsonl"; { u "дальше" u-3; a "делаю три"; } >> "$S/t3.jsonl"
# Процесс на расшифровку, как у стража: свёртка хода держит состояние на процесс, и три вызова в одном процессе
# отвечали бы прежним ключом.
key() { STATE_DIR="$S/st" bash -c '. "$1/hooks/root-cause-lib.sh" || exit 2; rc_turn_key "$2"' _ "$R" "$S/$1.jsonl"; }
k1=$(key t1); k2=$(key t2); k3=$(key t3)
[ -n "$k1" ] && [ -n "$k3" ] && [ "$k1" != "$k3" ] || exit 2
[ "$k1" != "$k2" ] || { echo "два хода с репликой «продолжай» получили один ключ ($k1)" >&2; exit 1; }
echo "одинаковая реплика — разные ходы"
exit 0
